#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 04-tailscale.sh — Install Tailscale for remote access without port forwarding
#
# Tailscale creates an encrypted WireGuard mesh between your devices.
# Once installed on both this server and your phone/Windows machine:
#
#   - SSH into this server from anywhere (no port forwarding, no dynamic DNS)
#   - Run the Ollama SSH tunnel to this server from your Windows PC at work
#   - Access this server from your phone for management
#
# The Tailscale IP (100.x.x.x) is stable even when your home IP changes.
#
# Free tier: up to 100 devices. No credit card required.
#
# After this script:
#   - Install Tailscale on your Windows PC:  https://tailscale.com/download/windows
#   - Install Tailscale on your phone:       https://tailscale.com/download
#   - Then use the Tailscale IP instead of your local LAN IP for the SSH tunnel
#     when you are away from home.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

log()  { echo "[tailscale] $*"; }
warn() { echo "[tailscale] WARNING: $*" >&2; }

# ── Check if already installed ─────────────────────────────────────────────
if command -v tailscale &>/dev/null && tailscale status &>/dev/null 2>&1; then
    log "Tailscale is already installed and connected."
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
    log "  Tailscale IPv4: $TAILSCALE_IP"
    log "  Use this IP in your tunnel command when off your home LAN."
    exit 0
fi

# ── Preview ────────────────────────────────────────────────────────────────
echo ""
echo "  Tailscale will be installed from the official Tailscale apt repository."
echo "  You will be prompted to authenticate via a browser link."
echo "  A free account at tailscale.com is required (no credit card)."
echo ""
printf "  Install Tailscale? [y/N] "; read -r confirm
[[ "${confirm,,}" == "y" ]] || { log "Skipped. You can run this script again later to add Tailscale."; exit 0; }

# ── Install ────────────────────────────────────────────────────────────────
log "Adding Tailscale apt repository..."
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").noarmor.gpg \
    | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null

curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").tailscale-keyring.list" \
    | sudo tee /etc/apt/sources.list.d/tailscale.list > /dev/null

sudo apt-get update -q
sudo apt-get install -yq tailscale
log "Tailscale installed."

# ── Enable IP forwarding (needed for subnet routing if desired later) ──────
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
    echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl -p -q
    log "IP forwarding enabled."
fi

# ── Connect ────────────────────────────────────────────────────────────────
log "Connecting to Tailscale..."
log "A browser authentication link will appear below."
log "Open it on any browser — you only need to do this once."
echo ""
sudo tailscale up --accept-routes

# ── Get IP ─────────────────────────────────────────────────────────────────
sleep 2
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "pending")

echo ""
log "Tailscale connected. ✓"
log ""
log "  This server's Tailscale IP: $TAILSCALE_IP"
log ""
log "Next steps for remote access:"
log "  1. Install Tailscale on your Windows PC:"
log "       https://tailscale.com/download/windows"
log "  2. Install Tailscale on your phone:"
log "       iOS:     https://tailscale.com/download/ios"
log "       Android: https://tailscale.com/download/android"
log "  3. Sign in to the same Tailscale account on all devices."
log ""
log "SSH into this server from anywhere (once Tailscale is on your client):"
log "  ssh $(whoami)@$TAILSCALE_IP"
log ""
log "Ollama tunnel from Windows when NOT on home LAN (using Tailscale IP):"
log "  scripts\\tunnel.bat $(whoami)@$TAILSCALE_IP"
log ""
log "Ollama tunnel from Linux/macOS when NOT on home LAN:"
log "  ./scripts/tunnel.sh $(whoami)@$TAILSCALE_IP"

# ── Allow Tailscale through ufw (if active) ───────────────────────────────
if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow in on tailscale0 comment "Tailscale" 2>/dev/null || true
    sudo ufw allow out on tailscale0 comment "Tailscale" 2>/dev/null || true
    log "Tailscale allowed through ufw. ✓"
fi
