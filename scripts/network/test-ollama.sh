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
#   3. Lists available models; warns if OLLAMA_MODEL isn't pulled
#   4. Anthropic-compatible API (/v1/messages) using whatever model is available
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# ── Load .env ────────────────────────────────────────────────────────────────
if [[ -f "${ENV_FILE}" ]]; then
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
    echo "  WARNING: Could not list models"
    MODELS=""
}

FIRST_MODEL=""
if [[ -n "${MODELS}" ]]; then
    if command -v jq &>/dev/null; then
        echo "${MODELS}" | jq -r '.models[].name' | while read -r m; do
            echo "    - ${m}"
        done
        FIRST_MODEL=$(echo "${MODELS}" | jq -r '.models[0].name // empty' 2>/dev/null || true)
    else
        echo "  ${MODELS}"
    fi
fi

OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:7b}"
echo ""
echo "  Configured OLLAMA_MODEL: ${OLLAMA_MODEL}"
if command -v jq &>/dev/null && [[ -n "${MODELS}" ]]; then
    MODEL_PRESENT=$(echo "${MODELS}" | jq -r --arg m "${OLLAMA_MODEL}" '.models[].name | select(. == $m)' 2>/dev/null || true)
    if [[ -z "${MODEL_PRESENT}" ]]; then
        echo "  WARNING: '${OLLAMA_MODEL}' is not pulled on the Windows machine."
        if [[ -n "${FIRST_MODEL}" ]]; then
            echo "  Will use '${FIRST_MODEL}' for the API test instead."
            echo "  To use '${OLLAMA_MODEL}': run  ollama pull ${OLLAMA_MODEL}  on Windows,"
            echo "  then set OLLAMA_MODEL=${OLLAMA_MODEL} in .env"
            OLLAMA_MODEL="${FIRST_MODEL}"
        else
            echo "  No models are pulled at all. Pull one on Windows: ollama pull qwen2.5-coder:7b"
            exit 1
        fi
    else
        echo "  Model '${OLLAMA_MODEL}' is available."
    fi
fi

# ── 4. Test Anthropic-compatible API ─────────────────────────────────────────
echo ""
echo "[4/4] Testing Anthropic-compatible /v1/messages API (model: ${OLLAMA_MODEL})..."
API_RESPONSE=$(curl -sf --connect-timeout 30 \
    -X POST "${OLLAMA_HOST}/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ollama" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"${OLLAMA_MODEL}\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the word OK only.\"}]}" \
    2>&1) || {
    echo "  FAILED: /v1/messages API not responding."
    echo ""
    echo "  Possible causes:"
    echo "    - Ollama version too old (need >= 0.6): run  ollama --version  on Windows"
    echo "    - Model '${OLLAMA_MODEL}' is not pulled: run  ollama pull ${OLLAMA_MODEL}  on Windows"
    echo "    - Ollama not restarted after OLLAMA_HOST change (restart from tray)"
    exit 1
}
if command -v jq &>/dev/null; then
    REPLY=$(echo "${API_RESPONSE}" | jq -r '.content[0].text // .error.message // empty' 2>/dev/null || echo "${API_RESPONSE}")
    echo "  API response: ${REPLY}"
else
    echo "  API responded OK."
fi

echo ""
echo "All checks passed. Ollama is reachable and working."
echo ""
echo "Next steps:"
echo "  - Make sure OLLAMA_MODEL in .env matches a pulled model: ${OLLAMA_MODEL}"
echo "  - make up    (start or rebuild the agent)"
echo ""
