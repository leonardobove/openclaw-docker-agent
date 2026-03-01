#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OpenClaw Agent — Container Entrypoint
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-/home/openclaw/.openclaw}"
LOG_PREFIX="[entrypoint]"

log() { echo "${LOG_PREFIX} $*" >&2; }
die() { echo "${LOG_PREFIX} FATAL: $*" >&2; exit 1; }

# ── Validate required environment variables ────────────────────────────────
[[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]] \
    || die "OPENCLAW_GATEWAY_TOKEN is not set."
[[ ${#OPENCLAW_GATEWAY_TOKEN} -ge 32 ]] \
    || die "OPENCLAW_GATEWAY_TOKEN must be at least 32 characters long."

# ── First-run initialization ───────────────────────────────────────────────
if [[ ! -f "${OPENCLAW_HOME}/openclaw.json" ]]; then
    log "First run: initializing OpenClaw home at ${OPENCLAW_HOME}"

    mkdir -p "${OPENCLAW_HOME}/workspace"
    mkdir -p "${OPENCLAW_HOME}/memory"
    mkdir -p "${OPENCLAW_HOME}/credentials"

    # Seed config from the image's bundled default
    cp /etc/openclaw/openclaw.json "${OPENCLAW_HOME}/openclaw.json"
    chmod 600 "${OPENCLAW_HOME}/openclaw.json"
    chmod 700 "${OPENCLAW_HOME}/credentials"

    # Seed workspace instruction files
    [[ -f /etc/openclaw/workspace/AGENTS.md ]] \
        && cp /etc/openclaw/workspace/AGENTS.md "${OPENCLAW_HOME}/workspace/AGENTS.md"
    [[ -f /etc/openclaw/workspace/SOUL.md ]] \
        && cp /etc/openclaw/workspace/SOUL.md "${OPENCLAW_HOME}/workspace/SOUL.md"

    log "Initialization complete."
else
    log "Existing state found — skipping initialization."
fi

# ── Ollama connectivity check ──────────────────────────────────────────────
OLLAMA_URL="${OLLAMA_BASE_URL:-http://host.docker.internal:11434}"
log "Checking Ollama at ${OLLAMA_URL}..."
if curl -sf --connect-timeout 5 "${OLLAMA_URL}/api/tags" > /dev/null 2>&1; then
    log "Ollama: reachable ✓"
else
    log "WARNING: Ollama not reachable at ${OLLAMA_URL}. Agent will start but LLM calls will fail until Ollama is available."
fi

# ── Start OpenClaw Gateway ─────────────────────────────────────────────────
log "Starting OpenClaw Gateway on 0.0.0.0:18789..."
exec openclaw gateway start
