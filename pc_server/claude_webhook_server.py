"""
claude_webhook_server.py — PC-side Flask server for claude-voice Termux package.

Receives query POSTs from Termux, runs `claude -p <query>`, and returns
Claude's response in the HTTP body so the phone can display/speak it.

Configuration via environment variables:
  CLAUDE_VOICE_CLAUDE_BIN  Path to the claude CLI binary
                           (default: ~/.local/bin/claude)
  CLAUDE_VOICE_PORT        Port to listen on (default: 5000)
  CLAUDE_VOICE_LOG         Log file path (default: ~/.claude-voice-server.log)
  CLAUDE_VOICE_HOST        Bind address (default: 10.7.0.1, the WireGuard tunnel IP)
  CLAUDE_VOICE_TOKEN       Bearer token required on /claude and /logs.
                           Empty disables auth (development only — emits a warning).
"""

import hmac
import os
import subprocess
import datetime
from functools import wraps
from flask import Flask, request, Response

app = Flask(__name__)

# ── Config from environment ───────────────────────────────────────────────────
CLAUDE_BIN = os.environ.get(
    "CLAUDE_VOICE_CLAUDE_BIN",
    os.path.expanduser("~/.local/bin/claude"),
)
PORT = int(os.environ.get("CLAUDE_VOICE_PORT", "5000"))
HOST = os.environ.get("CLAUDE_VOICE_HOST", "10.7.0.1")
TOKEN = os.environ.get("CLAUDE_VOICE_TOKEN", "")
LOG_FILE = os.path.expanduser(
    os.environ.get("CLAUDE_VOICE_LOG", "~/.claude-voice-server.log")
)


# ── Auth ──────────────────────────────────────────────────────────────────────
def require_token(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not TOKEN:
            return view(*args, **kwargs)
        header = request.headers.get("Authorization", "")
        prefix = "Bearer "
        if not header.startswith(prefix) or not hmac.compare_digest(
            header[len(prefix):], TOKEN
        ):
            return Response(
                "Unauthorized: missing or invalid bearer token",
                status=401,
                mimetype="text/plain",
            )
        return view(*args, **kwargs)
    return wrapper


# ── Helpers ───────────────────────────────────────────────────────────────────
def log(text: str) -> None:
    ts = datetime.datetime.now().strftime("[%Y-%m-%d %H:%M:%S]")
    line = f"{ts} {text}\n"
    with open(LOG_FILE, "a") as f:
        f.write(line)
    print(line, end="", flush=True)


# ── Routes ────────────────────────────────────────────────────────────────────
@app.route("/health", methods=["GET"])
def health():
    """Liveness probe used by `claude-voice --status`."""
    return Response("OK", status=200, mimetype="text/plain")


@app.route("/claude", methods=["POST"])
@require_token
def handle_claude_command():
    query = None
    if request.is_json:
        query = request.json.get("query")
    elif request.content_type and "text/plain" in request.content_type:
        query = request.get_data(as_text=True).strip()
    else:
        query = request.form.get("query")
    if not query:
        return Response("Error: missing 'query' parameter", status=400, mimetype="text/plain")

    log(f"QUERY: {query}")

    if not os.path.isfile(CLAUDE_BIN):
        msg = f"claude binary not found at {CLAUDE_BIN}. Set CLAUDE_VOICE_CLAUDE_BIN."
        log(f"ERROR: {msg}")
        return Response(msg, status=500, mimetype="text/plain")

    try:
        env = os.environ.copy()
        result = subprocess.run(
            [CLAUDE_BIN, "-p", query],
            capture_output=True,
            text=True,
            timeout=120,
            env=env,
        )

        stdout = result.stdout.strip()
        stderr = result.stderr.strip()

        log(f"EXIT: {result.returncode}")
        if stdout:
            log(f"STDOUT: {stdout[:500]}")
        if stderr:
            log(f"STDERR: {stderr[:200]}")

        if result.returncode != 0:
            error_body = stderr or f"claude exited with code {result.returncode}"
            return Response(error_body, status=500, mimetype="text/plain")

        # Return Claude's actual response so the phone can receive and display it
        return Response(stdout, status=200, mimetype="text/plain")

    except subprocess.TimeoutExpired:
        log("ERROR: claude timed out after 120s")
        return Response("Error: claude timed out", status=504, mimetype="text/plain")
    except Exception as exc:
        log(f"ERROR: {exc}")
        return Response(f"Error: {exc}", status=500, mimetype="text/plain")


@app.route("/logs", methods=["GET"])
@require_token
def get_logs():
    if not os.path.exists(LOG_FILE):
        return Response("No logs yet.", status=404, mimetype="text/plain")
    with open(LOG_FILE) as f:
        return Response(f.read(), status=200, mimetype="text/plain")


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    os.makedirs(os.path.dirname(LOG_FILE) or ".", exist_ok=True)
    if not os.path.exists(LOG_FILE):
        with open(LOG_FILE, "w") as f:
            f.write("=== claude-voice server log ===\n")

    log(f"Starting claude-voice server on {HOST}:{PORT}")
    log(f"Claude binary: {CLAUDE_BIN}")
    log(f"Log file: {LOG_FILE}")
    if TOKEN:
        log(f"Bearer auth: enabled (token length {len(TOKEN)})")
    else:
        log("WARNING: CLAUDE_VOICE_TOKEN is empty — bearer auth DISABLED")

    app.run(host=HOST, port=PORT)
