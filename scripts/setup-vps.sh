#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OpenClaw VPS Setup Script
# Run once on the Ubuntu VPS as a non-root user with sudo access:
#   bash ~/openclaw/scripts/setup-vps.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

log()  { echo "[setup] $*"; }
die()  { echo "[setup] FATAL: $*" >&2; exit 1; }

[[ $(id -u) -ne 0 ]] || die "Do NOT run as root. Run as your normal user (with sudo access)."

# ── 1. Install Docker Engine (official method, Ubuntu) ────────────────────
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
    sudo apt-get install -yq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin make

    log "Adding $(whoami) to docker group..."
    sudo usermod -aG docker "$(whoami)"
    log "Docker installed. Group membership will apply in new shell."
fi

# ── 2. Configure sshd for reverse tunnel ─────────────────────────────────
SSHD_CONF="/etc/ssh/sshd_config"
if grep -q "^GatewayPorts yes" "$SSHD_CONF" 2>/dev/null; then
    log "sshd: GatewayPorts already set."
else
    log "Configuring sshd GatewayPorts for reverse tunnel..."
    sudo sed -i 's/^#*GatewayPorts.*/GatewayPorts yes/' "$SSHD_CONF"
    # If the line doesn't exist at all, append it
    grep -q "^GatewayPorts" "$SSHD_CONF" || echo "GatewayPorts yes" | sudo tee -a "$SSHD_CONF"
    sudo systemctl restart ssh || sudo systemctl restart sshd
    log "sshd restarted with GatewayPorts yes."
fi

# ── 3. Firewall: block external access to Ollama tunnel port ─────────────
if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
    log "Configuring ufw: block port 11434 from external, allow 80/443..."
    sudo ufw deny 11434/tcp comment "Ollama SSH tunnel — internal only"
    sudo ufw allow 80/tcp  comment "Caddy HTTP (Cloudflare redirect)"
    sudo ufw allow 443/tcp comment "Caddy HTTPS"
    sudo ufw allow 443/udp comment "Caddy HTTP/3"
    log "ufw rules updated."
else
    log "WARNING: ufw not active. Manually ensure port 11434 is not exposed externally."
    log "  sudo ufw enable && sudo ufw deny 11434/tcp"
fi

# ── 4. Verify ──────────────────────────────────────────────────────────────
log ""
log "=== Setup complete ==="
log ""
log "IMPORTANT: If Docker group was just added, start a new shell before running 'make up':"
log "  exec newgrp docker"
log "  OR log out and back in."
log ""
log "Next steps:"
log "  cd ~/openclaw"
log "  cp .env.example .env       # skip if .env already exists"
log "  make gen-auth PASSWORD='your_password'  # then paste hash into .env"
log "  make up"
log ""
log "Then on your WINDOWS machine, run this to tunnel Ollama to the VPS:"
log "  ssh -N -R 0.0.0.0:11434:localhost:11434 $(whoami)@\$(hostname -I | awk '{print \$1}') -o ServerAliveInterval=60 -o ServerAliveCountMax=5"
log ""
log "After make up, get your phone URL:"
log "  make url"
