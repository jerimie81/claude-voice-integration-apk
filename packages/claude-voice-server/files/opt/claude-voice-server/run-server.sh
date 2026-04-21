#!/usr/bin/env bash
cd /opt/claude-voice-server
[ -f "$HOME/.config/claude-voice/server.env" ] && { set -a; source "$HOME/.config/claude-voice/server.env"; set +a; }
exec python3 claude_webhook_server.py
