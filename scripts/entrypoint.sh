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

    log "Initialization complete."
else
    log "Existing state found — skipping initialization."
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

# ── Start OpenClaw Gateway ─────────────────────────────────────────────────
log "Starting OpenClaw Gateway..."
exec openclaw gateway run
