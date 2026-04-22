#!/data/data/com.termux/files/usr/bin/bash
# Deprecated compatibility wrapper.
# Prefer: $PREFIX/bin/claude-voice

set -euo pipefail

echo "[DEPRECATED] termux/claude_relay.sh is legacy. Forwarding to claude-voice..." >&2
exec "${PREFIX:-/data/data/com.termux/files/usr}/bin/claude-voice" "$@"
