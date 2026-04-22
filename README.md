# Claude Voice Integration

Android + PC relay for push-to-talk voice conversations with Claude.

## Components

- `android_app/`: Android client (STT + SSE streaming + incremental TTS).
- `pc_server/`: canonical Flask relay server (`/health`, `/claude`, `/claude/stream`, `/reset`, `/logs`).
- `packages/`: Termux + Linux package artifacts.

## Security defaults

- PC server defaults to `CLAUDE_VOICE_HOST=10.7.0.1` (WireGuard interface), not `0.0.0.0`.
- Bearer token is strongly recommended for any non-localhost bind.
- For local development only, you can bypass strict startup enforcement with:
  - `CLAUDE_VOICE_ALLOW_INSECURE_NO_TOKEN=1`

## Quick start

1. Install Python dependency:

```bash
pip install flask
```

2. Configure and run PC server:

```bash
cd pc_server
export CLAUDE_VOICE_HOST=10.7.0.1
export CLAUDE_VOICE_PORT=5000
export CLAUDE_VOICE_TOKEN='<your-random-token>'
python3 claude_webhook_server.py
```

3. Install Android APK from Releases:

- https://github.com/jerimie81/claude-voice-integration-apk/releases

4. In Android app Settings, set:
- PC IP (default WireGuard host: `10.7.0.1`)
- Port (`5000` by default)
- Bearer token (same as PC)
- Timeout seconds

## Legacy script notice

`termux/claude_relay.sh` is now a deprecated wrapper. Use `claude-voice` from the package as the supported path.

## License

MIT
