#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 02-ssh-hardening.sh — Harden SSH and install fail2ban
#
# Changes made to /etc/ssh/sshd_config:
#   - PasswordAuthentication no    (key-based auth only)
#   - PermitRootLogin no
#   - MaxAuthTries 3
#   - LoginGraceTime 30
#   - AllowTcpForwarding yes       (needed for SSH reverse tunnel)
#   - GatewayPorts yes             (needed so Docker containers reach tunnel)
#   - X11Forwarding no
#   - PrintLastLog yes
#
# IMPORTANT: This script checks that you have at least one authorized SSH key
# before disabling password authentication. If no key is found, it will guide
# you through adding one before locking down access.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

log()  { echo "[ssh-hardening] $*"; }
warn() { echo "[ssh-hardening] WARNING: $*" >&2; }
die()  { echo "[ssh-hardening] FATAL: $*" >&2; exit 1; }

SSHD_CONF="/etc/ssh/sshd_config"
AUTH_KEYS="$HOME/.ssh/authorized_keys"

# ── Check for authorized key ───────────────────────────────────────────────
log "Checking for authorized SSH keys..."
KEY_COUNT=0
if [[ -f "$AUTH_KEYS" ]]; then
    KEY_COUNT=$(grep -c "^ssh-" "$AUTH_KEYS" 2>/dev/null || echo 0)
fi

if [[ "$KEY_COUNT" -eq 0 ]]; then
    echo ""
    warn "No authorized SSH keys found in $AUTH_KEYS."
    warn "Disabling password auth without a key will lock you out!"
    echo ""
    echo "  Add your public key first. From your OTHER machine, run:"
    echo "    ssh-copy-id $(whoami)@$(hostname -I | awk '{print $1}')"
    echo "  Or paste your public key manually:"
    echo "    mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    echo "    echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys"
    echo "    chmod 600 ~/.ssh/authorized_keys"
    echo ""
    printf "  Have you added your key and want to continue anyway? [y/N] "
    read -r confirm
    [[ "${confirm,,}" == "y" ]] || { log "Aborted. Re-run after adding SSH key."; exit 0; }
else
    log "Found $KEY_COUNT authorized key(s). Safe to disable password auth."
fi

# ── Backup sshd_config ────────────────────────────────────────────────────
BACKUP="${SSHD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
sudo cp "$SSHD_CONF" "$BACKUP"
log "Backed up sshd_config to $BACKUP"

# ── Apply settings via sed ────────────────────────────────────────────────
apply_setting() {
    local key="$1"
    local value="$2"
    # Replace existing (commented or not), or append
    if sudo grep -qE "^#?${key}" "$SSHD_CONF"; then
        sudo sed -i "s|^#*${key}.*|${key} ${value}|" "$SSHD_CONF"
    else
        echo "${key} ${value}" | sudo tee -a "$SSHD_CONF" > /dev/null
    fi
    log "  ${key} ${value}"
}

echo ""
log "Applying sshd_config settings:"
apply_setting "PasswordAuthentication"   "no"
apply_setting "PermitRootLogin"          "no"
apply_setting "MaxAuthTries"             "3"
apply_setting "LoginGraceTime"           "30"
apply_setting "AllowTcpForwarding"       "yes"
apply_setting "GatewayPorts"             "yes"
apply_setting "X11Forwarding"            "no"
apply_setting "PrintLastLog"             "yes"
apply_setting "ClientAliveInterval"      "60"
apply_setting "ClientAliveCountMax"      "5"

# ── Test config before restarting ─────────────────────────────────────────
log "Validating sshd config..."
sudo sshd -t || {
    warn "sshd config test failed! Restoring backup."
    sudo cp "$BACKUP" "$SSHD_CONF"
    die "Restored original config. Check $BACKUP for what failed."
}

# ── Restart sshd ──────────────────────────────────────────────────────────
sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd
log "sshd restarted. ✓"

# ── Install fail2ban ──────────────────────────────────────────────────────
echo ""
log "Installing fail2ban..."
sudo apt-get update -q
sudo apt-get install -yq fail2ban

# Write a local jail config for SSH
sudo tee /etc/fail2ban/jail.d/openclaw-ssh.conf > /dev/null << 'EOF'
[sshd]
enabled  = true
port     = ssh
maxretry = 5
findtime = 10m
bantime  = 1h
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
log "fail2ban configured: 5 failed attempts → 1h ban on SSH port ✓"

echo ""
log "SSH hardening complete."
log "  Password auth : disabled (key-based only)"
log "  Root login    : disabled"
log "  fail2ban      : active"
log "  GatewayPorts  : yes (required for Ollama SSH tunnel)"
