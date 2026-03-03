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
# OpenClaw does not interpolate env vars natively (except apiKey/token fields).
# We render the template on every start so secrets are always current.
CONFIG_SRC="/home/openclaw/repo/config/openclaw.json"
CONFIG_DEST="${OPENCLAW_HOME}/openclaw.json"

# Save the primary model from state before overwriting — 'openclaw models set'
# writes the choice into openclaw.json, which the template render would reset.
SAVED_PRIMARY=""
if [[ -f "${CONFIG_DEST}" ]]; then
    SAVED_PRIMARY=$(python3 -c "
import json, sys
try:
    with open('${CONFIG_DEST}') as f:
        d = json.load(f)
    print(d['agents']['defaults']['model']['primary'])
except Exception:
    pass
" 2>/dev/null || true)
fi

if [[ -f "${CONFIG_SRC}" ]]; then
    sed \
        -e "s|\${ANTHROPIC_API_KEY}|${ANTHROPIC_API_KEY:-}|g" \
        -e "s|\${OPENCLAW_GATEWAY_TOKEN}|${OPENCLAW_GATEWAY_TOKEN:-}|g" \
        -e "s|\${TELEGRAM_BOT_TOKEN}|${TELEGRAM_BOT_TOKEN:-}|g" \
        -e "s|\${OPENCLAW_HOME}|${OPENCLAW_HOME}|g" \
        "${CONFIG_SRC}" > "${CONFIG_DEST}"
    chmod 600 "${CONFIG_DEST}"
    log "Config rendered from repo."
else
    log "WARNING: repo config not found at ${CONFIG_SRC}, using cached version."
fi

# Restore the primary model if it was changed from the template default.
TEMPLATE_PRIMARY="anthropic/claude-sonnet-4-6"
if [[ -n "${SAVED_PRIMARY}" && "${SAVED_PRIMARY}" != "${TEMPLATE_PRIMARY}" ]]; then
    python3 -c "
import json
with open('${CONFIG_DEST}') as f:
    config = json.load(f)
config['agents']['defaults']['model']['primary'] = '${SAVED_PRIMARY}'
with open('${CONFIG_DEST}', 'w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null
    log "Primary model restored: ${SAVED_PRIMARY}"
fi

# ── Patch Ollama baseUrl in the models.json state file ────────────────────
# OpenClaw writes a models.json with a cached baseUrl when 'models set' is used.
# This file takes precedence over openclaw.json, so we keep its Ollama URL correct.
MODELS_JSON="${OPENCLAW_HOME}/agents/main/agent/models.json"
if [[ -f "${MODELS_JSON}" ]]; then
    # Normalise any Ollama baseUrl (covers docker service name, LAN IPs, etc.)
    python3 -c "
import json, re
with open('${MODELS_JSON}') as f:
    raw = f.read()
# Replace baseUrl for the ollama provider entry
data = json.loads(raw)
if 'providers' in data and 'ollama' in data['providers']:
    data['providers']['ollama']['baseUrl'] = 'http://ollama:11434'
with open('${MODELS_JSON}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null && log "models.json Ollama baseUrl normalised to http://ollama:11434." || true
fi

# ── Always sync workspace instruction files ────────────────────────────────
# Prefer the live repo bind-mount so edits take effect on restart without rebuild.
# Fall back to the image-baked copy if the repo isn't mounted yet.
mkdir -p "${OPENCLAW_HOME}/workspace"
REPO_WORKSPACE="/home/openclaw/repo/config/workspace"
IMG_WORKSPACE="/etc/openclaw/workspace"
for f in AGENTS.md SOUL.md; do
    if [[ -f "${REPO_WORKSPACE}/${f}" ]]; then
        cp "${REPO_WORKSPACE}/${f}" "${OPENCLAW_HOME}/workspace/${f}"
    elif [[ -f "${IMG_WORKSPACE}/${f}" ]]; then
        cp "${IMG_WORKSPACE}/${f}" "${OPENCLAW_HOME}/workspace/${f}"
    fi
done

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

# ── Start cron for scheduled tasks ────────────────────────────────────────
/usr/local/bin/setup-cron.sh 2>/dev/null || true
log "Cron setup complete (Gmail alerts daily at 08:00)."

# ── Start Agent Manager ─────────────────────────────────────────────────────
python3 /usr/local/bin/agent-manager.py &
log "Agent manager started (PID $!)"
sleep 1

# ── Start OpenClaw Gateway ─────────────────────────────────────────────────
log "Starting OpenClaw Gateway..."
exec openclaw gateway run
