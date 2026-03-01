#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-vps.sh — Install Docker Engine and configure sshd
#
# Use this directly for a cloud VPS (DigitalOcean, Linode, Hetzner, etc.)
#
#   bash scripts/setup-vps.sh
#
# For a HOME SERVER behind a router, use the full setup instead:
#
#   bash scripts/homeserver/setup.sh
#
# This script is also called by scripts/homeserver/setup.sh as its final step.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

log()  { echo "[setup-vps] $*"; }
die()  { echo "[setup-vps] FATAL: $*" >&2; exit 1; }

[[ $(id -u) -ne 0 ]] || die "Do NOT run as root. Run as your normal user (with sudo access)."

# ── 1. Install Docker Engine (official Ubuntu method) ─────────────────────
if command -v docker &>/dev/null; then
    log "Docker already installed: $(docker --version)"
else
    log "Installing Docker Engine..."
    sudo apt-get update -q
    sudo apt-get install -yq ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -q
    sudo apt-get install -yq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        make curl git

    log "Adding $(whoami) to docker group..."
    sudo usermod -aG docker "$(whoami)"
    log "Docker installed. Group membership applies in a new shell."
fi

# ── 2. Configure sshd: GatewayPorts + AllowTcpForwarding ─────────────────
# GatewayPorts=yes : SSH reverse tunnel binds to 0.0.0.0 so Docker containers
#                    can reach it via host.docker.internal
# AllowTcpForwarding=yes : required for -R (reverse tunnel) to work
SSHD_CONF="/etc/ssh/sshd_config"

apply_sshd() {
    local key="$1" value="$2"
    if sudo grep -qE "^#?${key}" "$SSHD_CONF"; then
        sudo sed -i "s|^#*${key}.*|${key} ${value}|" "$SSHD_CONF"
    else
        echo "${key} ${value}" | sudo tee -a "$SSHD_CONF" > /dev/null
    fi
}

NEEDS_RESTART=false

if ! grep -q "^GatewayPorts yes" "$SSHD_CONF" 2>/dev/null; then
    apply_sshd "GatewayPorts"      "yes"
    NEEDS_RESTART=true
fi
if ! grep -q "^AllowTcpForwarding yes" "$SSHD_CONF" 2>/dev/null; then
    apply_sshd "AllowTcpForwarding" "yes"
    NEEDS_RESTART=true
fi

if $NEEDS_RESTART; then
    sudo sshd -t || die "sshd config test failed. Check $SSHD_CONF."
    sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd
    log "sshd configured: GatewayPorts=yes, AllowTcpForwarding=yes. ✓"
else
    log "sshd: already configured correctly."
fi

# ── 3. Firewall: deny Ollama port from external ───────────────────────────
# (For home servers, the full ufw setup is done in homeserver/03-firewall.sh)
# Here we only add the Ollama port deny rule if ufw is active but not yet set.
if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
    if ! sudo ufw status | grep -q "11434"; then
        sudo ufw deny 11434/tcp comment "Ollama SSH tunnel — internal only"
        log "ufw: port 11434 blocked externally. ✓"
    else
        log "ufw: port 11434 rule already present."
    fi
else
    log "INFO: ufw not active. Run homeserver/03-firewall.sh to configure, or:"
    log "  sudo ufw enable && sudo ufw deny 11434/tcp"
fi

# ── Done ──────────────────────────────────────────────────────────────────
log ""
log "=== setup-vps complete ==="
log ""
log "If Docker group was just added, activate it:"
log "  exec newgrp docker"
log "  (or log out and back in)"
log ""
log "Then:"
log "  cp .env.example .env"
log "  make gen-auth PASSWORD='your_password'   # paste result into CADDY_AUTH_HASH"
log "  make up"
log "  make url                                 # get your phone URL"
