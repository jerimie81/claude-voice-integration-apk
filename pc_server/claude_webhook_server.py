"""
claude_webhook_server.py — PC-side Flask server for claude-voice.

Endpoints:
  GET  /health
  POST /claude
  POST /claude/stream   (SSE)
  POST /reset
  GET  /logs
"""

import datetime
import hmac
import os
import subprocess
from functools import wraps

from flask import Flask, Response, request

app = Flask(__name__)

CLAUDE_BIN = os.environ.get("CLAUDE_VOICE_CLAUDE_BIN", os.path.expanduser("~/.local/bin/claude"))
PORT = int(os.environ.get("CLAUDE_VOICE_PORT", "5000"))
HOST = os.environ.get("CLAUDE_VOICE_HOST", "10.7.0.1")
TOKEN = os.environ.get("CLAUDE_VOICE_TOKEN", "")
ALLOW_INSECURE_NO_TOKEN = os.environ.get("CLAUDE_VOICE_ALLOW_INSECURE_NO_TOKEN", "0") == "1"
LOG_FILE = os.path.expanduser(os.environ.get("CLAUDE_VOICE_LOG", "~/.claude-voice-server.log"))
TIMEOUT = int(os.environ.get("CLAUDE_VOICE_TIMEOUT", "300"))

session_history: list[dict] = []
MAX_HISTORY = 10


def build_prompt(query: str) -> str:
    if not session_history:
        return query
    lines = ["[Prior conversation]"]
    for turn in session_history[-MAX_HISTORY:]:
        lines.append(f"User: {turn['query']}")
        lines.append(f"Claude: {turn['response']}")
    lines.append(f"\nUser: {query}")
    return "\n".join(lines)


def _append_history(query: str, response: str) -> None:
    session_history.append({"query": query, "response": response})
    if len(session_history) > MAX_HISTORY:
        session_history.pop(0)


def require_token(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not TOKEN:
            return Response("Server misconfigured: missing CLAUDE_VOICE_TOKEN", status=503, mimetype="text/plain")
        header = request.headers.get("Authorization", "")
        prefix = "Bearer "
        if not header.startswith(prefix) or not hmac.compare_digest(header[len(prefix):], TOKEN):
            return Response("Unauthorized: missing or invalid bearer token", status=401, mimetype="text/plain")
        return view(*args, **kwargs)

    return wrapper


def log(text: str) -> None:
    ts = datetime.datetime.now().strftime("[%Y-%m-%d %H:%M:%S]")
    line = f"{ts} {text}\n"
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line)
    print(line, end="", flush=True)


def _extract_query() -> str | None:
    if request.is_json:
        return request.json.get("query") or None
    if request.content_type and "text/plain" in request.content_type:
        return request.get_data(as_text=True).strip() or None
    return request.form.get("query") or None


@app.route("/health", methods=["GET"])
def health():
    return Response("OK", status=200, mimetype="text/plain")


@app.route("/reset", methods=["POST"])
@require_token
def reset_history():
    session_history.clear()
    log("RESET: conversation history cleared")
    return Response("OK", status=200, mimetype="text/plain")


@app.route("/claude", methods=["POST"])
@require_token
def handle_claude_command():
    query = _extract_query()
    if not query:
        return Response("Error: missing 'query' parameter", status=400, mimetype="text/plain")

    log(f"QUERY: {query}")

    if not os.path.isfile(CLAUDE_BIN):
        msg = f"claude binary not found at {CLAUDE_BIN}. Set CLAUDE_VOICE_CLAUDE_BIN."
        log(f"ERROR: {msg}")
        return Response(msg, status=500, mimetype="text/plain")

    full_prompt = build_prompt(query)

    try:
        result = subprocess.run(
            [CLAUDE_BIN, "-p", full_prompt],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            env=os.environ.copy(),
        )

        stdout = result.stdout.strip()
        stderr = result.stderr.strip()

        log(f"EXIT: {result.returncode}")
        if stdout:
            log(f"STDOUT: {stdout[:500]}")
        if stderr:
            log(f"STDERR: {stderr[:200]}")

        if result.returncode != 0:
            return Response(stderr or f"claude exited with code {result.returncode}", status=500, mimetype="text/plain")

        _append_history(query, stdout)
        return Response(stdout, status=200, mimetype="text/plain")

    except subprocess.TimeoutExpired:
        log(f"ERROR: claude timed out after {TIMEOUT}s")
        return Response(f"Error: claude timed out after {TIMEOUT}s", status=504, mimetype="text/plain")
    except Exception as exc:
        log(f"ERROR: {exc}")
        return Response(f"Error: {exc}", status=500, mimetype="text/plain")


@app.route("/claude/stream", methods=["POST"])
@require_token
def stream_claude():
    query = _extract_query()
    if not query:
        return Response("Error: missing 'query' parameter", status=400, mimetype="text/plain")

    if not os.path.isfile(CLAUDE_BIN):
        msg = f"claude binary not found at {CLAUDE_BIN}. Set CLAUDE_VOICE_CLAUDE_BIN."
        log(f"ERROR: {msg}")
        return Response(msg, status=500, mimetype="text/plain")

    full_prompt = build_prompt(query)
    log(f"STREAM QUERY: {query}")

    def generate():
        accumulated: list[str] = []
        try:
            proc = subprocess.Popen(
                [CLAUDE_BIN, "-p", full_prompt],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=os.environ.copy(),
            )
            assert proc.stdout is not None
            for line in proc.stdout:
                accumulated.append(line)
                yield f"data: {line.rstrip()}\n\n"
            proc.wait(timeout=TIMEOUT)
            full_response = "".join(accumulated).strip()
            if proc.returncode == 0 and full_response:
                _append_history(query, full_response)
                log(f"STREAM EXIT: 0, {len(full_response)} chars")
            else:
                stderr_out = proc.stderr.read().strip() if proc.stderr else ""
                log(f"STREAM EXIT: {proc.returncode}, stderr: {stderr_out[:200]}")
        except Exception as exc:
            log(f"STREAM ERROR: {exc}")
            yield f"data: Error: {exc}\n\n"
        finally:
            yield "data: [DONE]\n\n"

    return Response(generate(), mimetype="text/event-stream")


@app.route("/logs", methods=["GET"])
@require_token
def get_logs():
    if not os.path.exists(LOG_FILE):
        return Response("No logs yet.", status=404, mimetype="text/plain")
    with open(LOG_FILE, encoding="utf-8") as f:
        return Response(f.read(), status=200, mimetype="text/plain")


if __name__ == "__main__":
    os.makedirs(os.path.dirname(LOG_FILE) or ".", exist_ok=True)
    if not os.path.exists(LOG_FILE):
        with open(LOG_FILE, "w", encoding="utf-8") as f:
            f.write("=== claude-voice server log ===\n")

    if not TOKEN and not ALLOW_INSECURE_NO_TOKEN:
        raise SystemExit(
            "Refusing to start without CLAUDE_VOICE_TOKEN. Set CLAUDE_VOICE_TOKEN or override with CLAUDE_VOICE_ALLOW_INSECURE_NO_TOKEN=1 for local development only."
        )

    log(f"Starting claude-voice server on {HOST}:{PORT}")
    log(f"Claude binary: {CLAUDE_BIN}")
    log(f"Log file: {LOG_FILE}")
    log(f"Subprocess timeout: {TIMEOUT}s")
    log(f"Bearer auth: {'enabled' if TOKEN else 'DISABLED (insecure override)'}")

    app.run(host=HOST, port=PORT)
