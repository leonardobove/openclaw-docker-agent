#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 03-firewall.sh — ufw firewall rules for a home server behind NAT
#
# Philosophy:
#   Your router's NAT already blocks all unsolicited inbound traffic from the
#   internet. ufw provides a second layer for LAN-level control and covers the
#   case where someone else on your network tries to reach this machine.
#
# Rules applied:
#   - Default: deny incoming, allow outgoing
#   - SSH from your LAN subnet only (not from internet — use Tailscale for that)
#   - Tailscale interface: fully allowed (Tailscale handles its own encryption)
#   - Port 11434 (Ollama SSH tunnel): denied externally, Docker bypasses ufw
#   - Ports 80/443: not opened (cloudflared uses outbound only — no inbound needed)
#
# Note: Docker manages its own iptables rules and bypasses ufw for container
#       traffic. This is expected and required for the agent to work.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

log()  { echo "[firewall] $*"; }
warn() { echo "[firewall] WARNING: $*" >&2; }

# ── Detect LAN subnet ──────────────────────────────────────────────────────
IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
LAN_SUBNET=$(ip route show dev "$IFACE" | awk '/scope link/ {print $1}' | head -1)

if [[ -z "$LAN_SUBNET" ]]; then
    warn "Could not auto-detect LAN subnet. Defaulting to 192.168.0.0/16."
    LAN_SUBNET="192.168.0.0/16"
fi
log "Detected LAN subnet: $LAN_SUBNET (interface: $IFACE)"

# ── Preview ────────────────────────────────────────────────────────────────
echo ""
echo "  Firewall rules to be applied:"
echo "    DEFAULT incoming : DENY"
echo "    DEFAULT outgoing : ALLOW"
echo "    SSH (22)         : ALLOW from $LAN_SUBNET (LAN only)"
echo "    Tailscale (if present): ALLOW on tailscale0"
echo "    Port 11434       : DENY from internet (Docker containers bypass via iptables)"
echo "    Everything else  : DENY inbound"
echo ""
printf "  Apply these rules? [y/N] "; read -r confirm
[[ "${confirm,,}" == "y" ]] || { log "Skipped."; exit 0; }

# ── Install ufw if missing ─────────────────────────────────────────────────
if ! command -v ufw &>/dev/null; then
    log "Installing ufw..."
    sudo apt-get update -q && sudo apt-get install -yq ufw
fi

# ── Reset and apply ────────────────────────────────────────────────────────
sudo ufw --force reset

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed     # no IP forwarding by default

# SSH: LAN only
sudo ufw allow from "$LAN_SUBNET" to any port 22 proto tcp \
    comment "SSH from LAN"

# Tailscale: allow all traffic on the Tailscale interface
if ip link show tailscale0 &>/dev/null 2>&1; then
    sudo ufw allow in on tailscale0 comment "Tailscale"
    sudo ufw allow out on tailscale0 comment "Tailscale"
    log "Tailscale interface detected and allowed."
else
    log "Tailscale interface not yet present — will be allowed after step 4."
    # Pre-add the rule so it activates once Tailscale is installed
    sudo ufw allow in on tailscale0 comment "Tailscale (added pre-install)"
    sudo ufw allow out on tailscale0 comment "Tailscale (added pre-install)"
fi

# Block Ollama port from external (Docker containers bypass this via iptables)
sudo ufw deny 11434/tcp comment "Ollama SSH tunnel — internal only"

# Enable
sudo ufw --force enable
log "ufw enabled."

# ── Status ─────────────────────────────────────────────────────────────────
echo ""
sudo ufw status verbose
echo ""
log "Firewall configured. ✓"
log ""
log "Note: Docker containers can reach host port 11434 despite the ufw rule."
log "This is expected — Docker manages its own iptables rules independently."
log "The ufw rule blocks internet and LAN devices from reaching Ollama directly."
