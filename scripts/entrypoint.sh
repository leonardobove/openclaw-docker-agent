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

    chmod 700 "${OPENCLAW_HOME}/credentials"
    log "Initialization complete."
else
    log "Existing state found."
fi

# ── Always apply config from repo with env var substitution ───────────────
# OpenClaw does not interpolate env vars in provider baseUrl fields.
# We render the template on every start so OLLAMA_HOST (and others) are
# always current — no manual force-copy needed after changing .env.
CONFIG_SRC="/home/openclaw/repo/config/openclaw.json"
CONFIG_DEST="${OPENCLAW_HOME}/openclaw.json"
if [[ -f "${CONFIG_SRC}" ]]; then
    sed \
        -e "s|\${OLLAMA_HOST}|${OLLAMA_HOST:-}|g" \
        -e "s|\${BRAIN_MODEL}|${BRAIN_MODEL:-qwen3:8b}|g" \
        -e "s|\${OPENCLAW_GATEWAY_TOKEN}|${OPENCLAW_GATEWAY_TOKEN:-}|g" \
        -e "s|\${TELEGRAM_BOT_TOKEN}|${TELEGRAM_BOT_TOKEN:-}|g" \
        -e "s|\${OPENCLAW_HOME}|${OPENCLAW_HOME}|g" \
        "${CONFIG_SRC}" > "${CONFIG_DEST}"
    chmod 600 "${CONFIG_DEST}"
    log "Config rendered from repo (OLLAMA_HOST=${OLLAMA_HOST:-<unset>})."
else
    log "WARNING: repo config not found at ${CONFIG_SRC}, using cached version."
fi

# ── Patch OLLAMA_HOST in the models.json state file ───────────────────────
# OpenClaw writes a models.json with a cached baseUrl when 'models set' is used.
# This file takes precedence over openclaw.json, so we keep its baseUrl in sync.
MODELS_JSON="${OPENCLAW_HOME}/agents/main/agent/models.json"
if [[ -f "${MODELS_JSON}" && -n "${OLLAMA_HOST:-}" ]]; then
    sed -i "s|\"baseUrl\": \"[^\"]*\"|\"baseUrl\": \"${OLLAMA_HOST}\"|g" "${MODELS_JSON}"
    log "models.json baseUrl updated to ${OLLAMA_HOST}."
fi

# ── Always sync workspace instruction files ────────────────────────────────
# AGENTS.md and SOUL.md are instructions, not state — always keep them current.
mkdir -p "${OPENCLAW_HOME}/workspace"
[[ -f /etc/openclaw/workspace/AGENTS.md ]] \
    && cp /etc/openclaw/workspace/AGENTS.md "${OPENCLAW_HOME}/workspace/AGENTS.md"
[[ -f /etc/openclaw/workspace/SOUL.md ]] \
    && cp /etc/openclaw/workspace/SOUL.md "${OPENCLAW_HOME}/workspace/SOUL.md"

# ── SSH credentials for git push ──────────────────────────────────────────
# Source keys live in the repo bind-mount (.ssh/ is gitignored).
# We copy them to ~/.ssh so SSH sees the correct ownership (UID 10001).
SSH_SRC="/home/openclaw/repo/.ssh"
SSH_DEST="${HOME}/.ssh"
if [[ -d "${SSH_SRC}" ]]; then
    mkdir -p "${SSH_DEST}"
    chmod 700 "${SSH_DEST}"
    for f in id_ed25519 known_hosts config; do
        [[ -f "${SSH_SRC}/${f}" ]] && cp "${SSH_SRC}/${f}" "${SSH_DEST}/${f}" && chmod 600 "${SSH_DEST}/${f}"
    done
    [[ -f "${SSH_SRC}/id_ed25519.pub" ]] \
        && cp "${SSH_SRC}/id_ed25519.pub" "${SSH_DEST}/id_ed25519.pub" && chmod 644 "${SSH_DEST}/id_ed25519.pub"
    log "SSH credentials loaded."
fi

# ── Git configuration ──────────────────────────────────────────────────────
git config --global safe.directory /home/openclaw/repo
git config --global user.name  "OpenClaw Agent"
git config --global user.email "openclaw-agent@openclaw-docker-agent"

# ── Persist Claude Code credentials in state volume ────────────────────────
# ~/.claude/ is symlinked into the state volume so credentials survive rebuilds.
# Lost only on `make reset` / `make clean` (which wipe the volume).
CLAUDE_CREDS_DIR="${OPENCLAW_HOME}/claude-creds"
mkdir -p "${CLAUDE_CREDS_DIR}"
rm -rf "${HOME}/.claude"
ln -s "${CLAUDE_CREDS_DIR}" "${HOME}/.claude"
log "Claude Code credentials dir: ${CLAUDE_CREDS_DIR}"

# ── Start Agent Manager ─────────────────────────────────────────────────────
python3 /usr/local/bin/agent-manager.py &
log "Agent manager started (PID $!)"
sleep 1

# ── Start OpenClaw Gateway ─────────────────────────────────────────────────
log "Starting OpenClaw Gateway..."
exec openclaw gateway run
