#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# openclaw-docker-agent — Home Server Master Setup
#
# Turns a bare Ubuntu machine (on a home LAN behind a router) into a
# fully configured server running the OpenClaw agent stack.
#
# Run as a non-root user with sudo access:
#   bash scripts/homeserver/setup.sh
#
# What this does (in order):
#   1. Set a static local IP so your LAN address never changes
#   2. Harden SSH and install fail2ban
#   3. Configure ufw firewall for home server use
#   4. Install Tailscale for remote SSH access (no port forwarding needed)
#   5. Install Docker Engine + configure sshd for Ollama reverse tunnel
#
# After this script, run:
#   cp .env.example .env && nano .env
#   make up
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log()  { echo ""; echo "[setup] ══ $* ══"; echo ""; }
info() { echo "[setup] $*"; }
warn() { echo "[setup] WARNING: $*" >&2; }

[[ $(id -u) -ne 0 ]] || { echo "Run as a normal user with sudo, not as root."; exit 1; }

log "OpenClaw Home Server Setup"
info "This script will configure your Ubuntu machine step by step."
info "Each step asks for confirmation before making changes."
echo ""

# ── Step 1: Static IP ──────────────────────────────────────────────────────
log "Step 1 of 5 — Static local IP"
bash "$SCRIPT_DIR/01-static-ip.sh"

# ── Step 2: SSH hardening ──────────────────────────────────────────────────
log "Step 2 of 5 — SSH hardening + fail2ban"
bash "$SCRIPT_DIR/02-ssh-hardening.sh"

# ── Step 3: Firewall ───────────────────────────────────────────────────────
log "Step 3 of 5 — Firewall (ufw)"
bash "$SCRIPT_DIR/03-firewall.sh"

# ── Step 4: Tailscale ─────────────────────────────────────────────────────
log "Step 4 of 5 — Tailscale (remote access without port forwarding)"
bash "$SCRIPT_DIR/04-tailscale.sh"

# ── Step 5: Docker + sshd (reuses setup-vps.sh) ───────────────────────────
log "Step 5 of 5 — Docker Engine + sshd GatewayPorts"
bash "$SCRIPT_DIR/../setup-vps.sh"

# ── Done ──────────────────────────────────────────────────────────────────
log "Setup complete"
echo ""
info "Next steps:"
info "  1. Start a new shell (or run: exec newgrp docker) so Docker group takes effect"
info "  2. On your Windows machine, run the Ollama tunnel:"
info "       scripts\\tunnel.bat <your-tailscale-ip>      (from work / different network)"
info "       scripts\\tunnel.bat <your-local-ip>          (from home LAN)"
info "  3. Configure and start the agent:"
info "       cp .env.example .env"
info "       make gen-auth PASSWORD='your_password'  # paste into .env"
info "       make up"
info "  4. Get your phone URL:"
info "       make url"
echo ""
info "Tailscale IPs (for SSH tunnel and phone SSH access):"
tailscale ip 2>/dev/null || info "  Run 'tailscale ip' after reconnecting to see your Tailscale IP."
echo ""
