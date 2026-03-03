#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test-ollama.sh — Verify connectivity from Linux to Windows Ollama (LAN)
#
# Run from the repo root:
#   bash scripts/network/test-ollama.sh
#   or: make test-ollama
#
# What it checks:
#   1. OLLAMA_HOST is set in .env
#   2. HTTP reachability (curl to /api/version)
#   3. Anthropic-compatible API (/v1/messages endpoint)
#   4. Lists available models
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# ── Load .env ────────────────────────────────────────────────────────────────
if [[ -f "${ENV_FILE}" ]]; then
    # Export only OLLAMA_HOST and OLLAMA_MODEL lines (avoid overwriting current shell)
    while IFS='=' read -r key val; do
        [[ "${key}" =~ ^# ]] && continue
        [[ -z "${key}" ]] && continue
        key="${key// /}"
        val="${val// /}"
        if [[ "${key}" == "OLLAMA_HOST" || "${key}" == "OLLAMA_MODEL" ]]; then
            export "${key}=${val}"
        fi
    done < "${ENV_FILE}"
fi

OLLAMA_HOST="${OLLAMA_HOST:-}"

echo ""
echo "OpenClaw — Ollama Connectivity Test"
echo "===================================="
echo ""

# ── 1. Check OLLAMA_HOST is set ─────────────────────────────────────────────
echo "[1/4] Checking OLLAMA_HOST..."
if [[ -z "${OLLAMA_HOST}" ]]; then
    echo "  ERROR: OLLAMA_HOST is not set in .env"
    echo "  Add it: OLLAMA_HOST=http://192.168.x.x:11434"
    exit 1
fi
echo "  OLLAMA_HOST=${OLLAMA_HOST}"

# ── 2. Basic HTTP reachability ───────────────────────────────────────────────
echo ""
echo "[2/4] Testing HTTP reachability (${OLLAMA_HOST}/api/version)..."
RESPONSE=$(curl -sf --connect-timeout 5 "${OLLAMA_HOST}/api/version" 2>&1) || {
    echo "  FAILED: Could not reach ${OLLAMA_HOST}"
    echo ""
    echo "  Troubleshooting:"
    echo "    - Is Ollama running on the Windows machine?"
    echo "    - Did you run scripts/windows/setup-ollama.ps1 on Windows?"
    echo "    - Is OLLAMA_HOST set to the correct Windows LAN IP?"
    echo "    - Windows Firewall: allow TCP 11434 on Private profile"
    echo "    - Ping test: ping $(echo "${OLLAMA_HOST}" | sed 's|http://||' | cut -d: -f1)"
    exit 1
}
echo "  OK — Ollama responded: ${RESPONSE}"

# ── 3. List models ───────────────────────────────────────────────────────────
echo ""
echo "[3/4] Listing available models..."
MODELS=$(curl -sf --connect-timeout 5 "${OLLAMA_HOST}/api/tags" 2>&1) || {
    echo "  WARNING: Could not list models (${OLLAMA_HOST}/api/tags)"
}
if [[ -n "${MODELS}" ]]; then
    # Pretty-print model names if jq is available
    if command -v jq &>/dev/null; then
        echo "${MODELS}" | jq -r '.models[].name' | while read -r m; do
            echo "    - ${m}"
        done
    else
        echo "  ${MODELS}"
    fi
fi

OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:7b}"
echo ""
echo "  Default model for coding agents: ${OLLAMA_MODEL}"
if command -v jq &>/dev/null; then
    MODEL_PRESENT=$(echo "${MODELS}" | jq -r --arg m "${OLLAMA_MODEL}" '.models[].name | select(. == $m)' 2>/dev/null || true)
    if [[ -z "${MODEL_PRESENT}" ]]; then
        echo "  WARNING: Model '${OLLAMA_MODEL}' is NOT pulled yet on the Windows machine."
        echo "  Pull it: open a terminal on Windows and run: ollama pull ${OLLAMA_MODEL}"
    else
        echo "  Model '${OLLAMA_MODEL}' is available."
    fi
fi

# ── 4. Test Anthropic-compatible API ─────────────────────────────────────────
echo ""
echo "[4/4] Testing Anthropic-compatible /v1/messages API..."
API_RESPONSE=$(curl -sf --connect-timeout 10 \
    -X POST "${OLLAMA_HOST}/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ollama" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"${OLLAMA_MODEL}\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the word OK only.\"}]}" \
    2>&1) || {
    echo "  FAILED: /v1/messages API not responding."
    echo "  Make sure Ollama version is >= 0.6 (run: ollama --version on Windows)."
    exit 1
}
if command -v jq &>/dev/null; then
    REPLY=$(echo "${API_RESPONSE}" | jq -r '.content[0].text' 2>/dev/null || echo "${API_RESPONSE}")
    echo "  API response: ${REPLY}"
else
    echo "  API responded OK."
fi

echo ""
echo "All checks passed. Ollama is reachable from this machine."
echo ""
echo "Next step: make up"
echo ""
