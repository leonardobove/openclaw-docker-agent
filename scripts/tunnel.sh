#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Ollama SSH Reverse Tunnel — macOS / Linux
#
# Opens a persistent reverse SSH tunnel so the OpenClaw agent on your VPS
# can reach Ollama running on this local machine.
#
# Usage:
#   ./scripts/tunnel.sh user@vps-ip
#   ./scripts/tunnel.sh ubuntu@192.168.1.100
#
# Keep this terminal open while using the agent.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VPS="${1:-}"
if [[ -z "$VPS" ]]; then
    echo "Usage: $0 user@vps-ip"
    echo "Example: $0 ubuntu@203.0.113.42"
    exit 1
fi

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
LOCAL_OLLAMA="http://localhost:${OLLAMA_PORT}"

# ── Check Ollama is running ────────────────────────────────────────────────
echo "[tunnel] Checking Ollama at ${LOCAL_OLLAMA}..."
if ! curl -sf --connect-timeout 3 "${LOCAL_OLLAMA}/api/tags" > /dev/null 2>&1; then
    echo "[tunnel] ERROR: Ollama is not running at ${LOCAL_OLLAMA}."
    echo "[tunnel] Start it with: ollama serve"
    exit 1
fi
echo "[tunnel] Ollama: reachable ✓"

# ── List available models ──────────────────────────────────────────────────
echo "[tunnel] Available models:"
curl -sf "${LOCAL_OLLAMA}/api/tags" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('models', []):
    size_gb = m.get('size', 0) / 1_000_000_000
    print(f\"  - {m['name']} ({size_gb:.1f} GB)\")
" 2>/dev/null || echo "  (could not list models)"

# ── Open tunnel ────────────────────────────────────────────────────────────
echo ""
echo "[tunnel] Opening SSH reverse tunnel:"
echo "[tunnel]   VPS port ${OLLAMA_PORT} → localhost:${OLLAMA_PORT}"
echo "[tunnel]   Target: ${VPS}"
echo "[tunnel] Press Ctrl-C to stop."
echo ""

exec ssh \
    -N \
    -R "0.0.0.0:${OLLAMA_PORT}:localhost:${OLLAMA_PORT}" \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=5 \
    -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    "${VPS}"
