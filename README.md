# openclaw-docker-agent

Self-hosted autonomous AI coding agent powered by [OpenClaw](https://openclaw.ai) and a local [Ollama](https://ollama.ai) model. Runs in Docker on a personal Linux VPS. Accessible from anywhere via a secure Cloudflare Tunnel.

```
Your Phone
    │ HTTPS (trycloudflare.com — no account needed)
    ▼
Cloudflare Edge
    │
    ▼
cloudflared  ──►  Caddy :8080  ──►  OpenClaw :18789
(VPS, Docker)     (auth + rate      (VPS, Docker)
                   limiting)              │
                                          │ Ollama API
                                          ▼
                              SSH Reverse Tunnel
                                          │
                                          ▼
                              Ollama :11434 (your local machine)
                              Windows / macOS / Linux
```

---

## What runs where

| Component     | Location          | Notes                                  |
|---------------|-------------------|----------------------------------------|
| Ollama        | Your local machine | Windows, macOS, or Linux              |
| Models        | Your local machine | qwen3-coder, llama3.1:8b, etc.        |
| OpenClaw      | VPS (Docker)      | The AI agent runtime                  |
| Caddy         | VPS (Docker)      | Reverse proxy — auth + rate limiting  |
| cloudflared   | VPS (Docker)      | Public HTTPS URL for phone access     |
| SSH tunnel    | Your local machine | Built-in SSH — nothing to install    |

---

## Prerequisites

### VPS (Linux only)
- Ubuntu 20.04 LTS or later (Debian also works)
- 8 GB+ RAM (16 GB recommended for large models)
- SSH access with `sudo` rights
- Outbound internet access

### Local machine (any OS — Ollama host)
- [Ollama](https://ollama.ai) installed and running
- SSH client (built into Windows 10+, macOS, and all Linux distros)
- At least one model pulled — see [Recommended models](#recommended-models)
- Git (to clone this repo)

---

## Quick start

### 1. Clone on both machines

```bash
# On VPS and on your local machine:
git clone https://github.com/YOUR_USERNAME/openclaw-docker-agent.git
cd openclaw-docker-agent
```

### 2. VPS — one-time setup

```bash
bash scripts/setup-vps.sh
```

Installs Docker Engine, sets `GatewayPorts yes` in sshd, configures firewall.
If Docker group was just added, run `exec newgrp docker` before continuing.

### 3. VPS — configure environment

```bash
cp .env.example .env

# Generate gateway token
openssl rand -hex 32
# Paste into OPENCLAW_GATEWAY_TOKEN= in .env

# Generate Caddy password hash (choose any password)
make gen-auth PASSWORD='your_strong_password'
# Paste the $2a$... output into CADDY_AUTH_HASH= in .env

# Set your username
# CADDY_AUTH_USER=agent   (or whatever you prefer)
```

### 4. VPS — start the stack

```bash
make up
# Prints your phone URL after ~15 seconds, e.g.:
# https://some-random-words.trycloudflare.com
```

Run `make url` any time to see the current URL.

### 5. Local machine — start the Ollama tunnel

**Windows** (CMD or PowerShell — built-in SSH, no install):
```bat
scripts\tunnel.bat ubuntu@YOUR_VPS_IP
```

**macOS / Linux**:
```bash
./scripts/tunnel.sh ubuntu@YOUR_VPS_IP
```

Keep this terminal open. The agent needs the tunnel running to reach Ollama.

### 6. Open on your phone

Visit the URL from step 4.
Login with the username/password you set in `.env`.

---

## Home server setup (behind a home router)

If your Linux machine is on a home LAN behind a NAT router, use the dedicated
home server setup instead of the generic VPS setup. It handles everything the
cloud VPS setup does, plus the home-specific requirements.

```
Your Router (NAT)
    │
    └── Linux Home Server  ←── this machine
            │
            ├── Docker (OpenClaw + Caddy + cloudflared)
            ├── Static LAN IP  (no address changes on reboot)
            ├── Hardened SSH   (key-based only + fail2ban)
            ├── ufw firewall   (LAN SSH only, all else blocked)
            └── Tailscale      (remote SSH from anywhere, no port forwarding)
```

**No router port forwarding is required.** Everything uses outbound connections:
- cloudflared makes outbound connections to Cloudflare → phone access works
- Tailscale makes outbound connections → remote SSH works
- SSH reverse tunnel from your Windows PC is outbound → Ollama access works

### Home server quick start

```bash
# Clone on your Linux home server
git clone https://github.com/YOUR_USERNAME/openclaw-docker-agent.git
cd openclaw-docker-agent

# Run the master setup script — walks through each step with confirmation
bash scripts/homeserver/setup.sh
```

The master script runs these in order:

| Script | What it does |
|---|---|
| `homeserver/01-static-ip.sh` | Reads your current LAN IP, writes a static netplan config |
| `homeserver/02-ssh-hardening.sh` | Disables password auth, enables key-only, installs fail2ban |
| `homeserver/03-firewall.sh` | Sets ufw rules for home server (LAN SSH only, Ollama blocked) |
| `homeserver/04-tailscale.sh` | Installs Tailscale for remote SSH without port forwarding |
| `setup-vps.sh` | Installs Docker Engine, sets sshd GatewayPorts |

Each step asks for confirmation before making changes and is safe to re-run.

### After home server setup

```bash
# Apply docker group (no full logout needed)
exec newgrp docker

# Configure and start the stack
cp .env.example .env
make gen-auth PASSWORD='your_password'   # paste into CADDY_AUTH_HASH in .env
nano .env                                # also fill OPENCLAW_GATEWAY_TOKEN
make up
make url                                 # get your phone URL
```

### Ollama tunnel — home vs. away

| Location | Tunnel command |
|---|---|
| Home LAN (Windows) | `scripts\tunnel.bat user@192.168.x.x` (local IP) |
| Away from home (Windows) | `scripts\tunnel.bat user@100.x.x.x` (Tailscale IP) |
| Home LAN (macOS/Linux) | `./scripts/tunnel.sh user@192.168.x.x` |
| Away from home (macOS/Linux) | `./scripts/tunnel.sh user@100.x.x.x` |

Find your Tailscale IP on the server: `tailscale ip -4`

### Add your SSH key before running setup

The SSH hardening script disables password authentication. Make sure your
public key is on the server first:

```bash
# From your local machine (Windows PowerShell, macOS Terminal, or Linux):
ssh-copy-id user@192.168.x.x

# Or manually on the server:
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## Recommended models

Pull on your local machine before starting the tunnel:

```bash
# Best — strongest coding model (~19 GB download)
ollama pull qwen3-coder

# Good — solid coding ability, lighter weight (~9 GB)
ollama pull qwen2.5-coder:14b

# Smallest — use for testing the setup (~5 GB)
ollama pull llama3.1:8b
```

To add more models, update `config/openclaw.json` and run `make restart`.

---

## Daily usage

### VPS commands

```bash
make up           # Start stack + print tunnel URL
make down         # Stop everything
make url          # Show current phone URL
make logs         # Stream agent logs
make logs-caddy   # Stream Caddy logs
make logs-tunnel  # Stream cloudflared logs
make shell        # Open bash inside the agent container
make status       # Show container and volume status
make restart      # Restart agent only (without rebuilding)
```

### Local machine commands

```bash
# Linux / macOS
./scripts/tunnel.sh ubuntu@YOUR_VPS_IP

# Windows
scripts\tunnel.bat ubuntu@YOUR_VPS_IP

# Push updated files to VPS after local edits
make deploy VPS_USER=ubuntu VPS_HOST=YOUR_VPS_IP
```

---

## Resetting and upgrading

```bash
# Wipe all agent state (workspace, sessions, memory) and restart fresh
make reset

# Upgrade OpenClaw to the latest release
make upgrade

# Force rebuild all Docker images from scratch
make build
```

---

## Revoking remote access

```bash
# Stop everything (stack + public URL immediately gone)
make down

# Rotate the web UI password
make gen-auth PASSWORD='new_password'
# Update CADDY_AUTH_HASH in .env, then:
make down && make up

# Rotate the gateway token (invalidates all active API sessions)
openssl rand -hex 32
# Update OPENCLAW_GATEWAY_TOKEN in .env, then: make restart
```

---

## Security model

| Control                  | Implementation                                  |
|--------------------------|-------------------------------------------------|
| Non-root container       | UID 10001, no capability grants                 |
| No host filesystem       | Named Docker volume only                        |
| No Docker socket         | Never mounted                                   |
| No --privileged          | Never used                                      |
| Port 18789 not exposed   | Only reachable via Caddy on internal network    |
| Port 11434 not exposed   | SSH tunnel only — blocked by ufw externally     |
| Authentication layer 1   | Caddy basicauth (bcrypt password)               |
| Authentication layer 2   | `OPENCLAW_GATEWAY_TOKEN` header                 |
| Rate limiting            | 60 req/min per IP (caddy-ratelimit module)      |
| Request size cap         | 10 MB max body                                  |
| TLS                      | Cloudflare edge (automatic, no config needed)   |
| Resource limits          | 2 CPU / 2 GB RAM max (OpenClaw container)       |

---

## Deploying to a new VPS

```bash
# From your local machine (once repo is cloned there):
make deploy VPS_USER=ubuntu VPS_HOST=new.vps.ip

# Then on the new VPS:
ssh ubuntu@new.vps.ip
cd openclaw-docker-agent
bash scripts/setup-vps.sh
cp .env.example .env
# fill in .env values...
make up
```

---

## Project structure

```
openclaw-docker-agent/
├── README.md                     This file
├── LICENSE                       MIT
├── .env.example                  Environment variable template
├── .gitignore
├── Dockerfile                    OpenClaw agent image (node:22-slim)
├── docker-compose.yml            Stack: openclaw + caddy + cloudflared
├── Caddyfile                     HTTP-only reverse proxy config
├── Makefile                      All operational commands
├── SETUP.md                      Detailed operations reference
├── caddy/
│   └── Dockerfile                Custom Caddy + caddy-ratelimit module
├── config/
│   ├── openclaw.json             OpenClaw gateway + model config
│   └── workspace/
│       ├── AGENTS.md             Agent behavior instructions
│       └── SOUL.md               Agent persona
└── scripts/
    ├── entrypoint.sh             Docker container init + startup
    ├── setup-vps.sh              One-time VPS setup (run as normal user with sudo)
    ├── tunnel.sh                 Ollama SSH tunnel — macOS / Linux
    ├── tunnel.bat                Ollama SSH tunnel — Windows (CMD)
    └── tunnel.ps1                Ollama SSH tunnel — Windows (PowerShell)
```

---

## License

MIT — see [LICENSE](LICENSE).
