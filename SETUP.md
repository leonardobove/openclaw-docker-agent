# Operations Reference

Detailed operational guide for `openclaw-docker-agent`.
For the initial setup walkthrough, see [README.md](README.md).

---

## Environment variables

All variables go in `.env` on the VPS. Copy from `.env.example`.

| Variable                  | Required | Description                                              |
|---------------------------|----------|----------------------------------------------------------|
| `OPENCLAW_VERSION`        | No       | npm package version. Default: `latest`                   |
| `OPENCLAW_GATEWAY_TOKEN`  | Yes      | ≥32 char random hex. `openssl rand -hex 32`             |
| `OLLAMA_API_KEY`          | No       | Any value activates Ollama provider. Default: `ollama-local` |
| `OLLAMA_BASE_URL`         | No       | Default: `http://host.docker.internal:11434`             |
| `CADDY_AUTH_USER`         | Yes      | Web UI login username                                    |
| `CADDY_AUTH_HASH`         | Yes      | bcrypt hash. Generate: `make gen-auth PASSWORD=...`      |

---

## Verify isolation

```bash
# 1. No host bind mounts — only named volumes
docker inspect openclaw-agent | python3 -c "
import sys, json
for m in json.load(sys.stdin)[0]['Mounts']:
    print(m['Type'], m.get('Source',''), '->', m['Destination'])
"
# Expected: one 'volume' entry for /home/openclaw/.openclaw — no 'bind' entries

# 2. Non-root user
docker exec openclaw-agent id
# Expected: uid=10001(openclaw) gid=10001(openclaw)

# 3. No Linux capabilities
docker exec openclaw-agent cat /proc/1/status | grep CapEff
# Expected: CapEff: 0000000000000000

# 4. Port 18789 not published to host
ss -tlnp | grep 18789
# Expected: no output

# 5. Port 11434 blocked from internet (on VPS)
sudo ufw status | grep 11434
# Expected: 11434/tcp DENY IN Anywhere

# 6. Caddy auth enforced
curl -I http://localhost:8080
# Expected: 401 Unauthorized (from inside VPS — proves basicauth is active)
```

---

## Changing the Ollama model

1. Pull the new model on your local machine:
   ```bash
   ollama pull qwen2.5-coder:14b
   ```

2. Edit `config/openclaw.json` — update `models` list and `agents.defaults.model.primary`.

3. Push to VPS and restart:
   ```bash
   make deploy VPS_USER=ubuntu VPS_HOST=your.vps.ip
   ssh ubuntu@your.vps.ip "cd ~/openclaw-docker-agent && make restart"
   ```

---

## Revoking remote access

```bash
# Immediately — take down the stack (public URL disappears instantly)
make down

# Firewall only — stack keeps running locally but is unreachable remotely
sudo ufw deny 443/tcp

# Rotate web UI password
make gen-auth PASSWORD=new_password
# Update CADDY_AUTH_HASH in .env, then:
make down && make up

# Rotate gateway token (invalidates all active WebSocket sessions)
openssl rand -hex 32
# Update OPENCLAW_GATEWAY_TOKEN in .env, then:
make restart
```

---

## Reset agent state

Wipes the agent's workspace, session history, and memory. Config and models are unaffected.

```bash
make reset
# Prompts: "Type 'yes' to confirm"
```

Equivalent manual steps:
```bash
docker compose down -v          # removes openclaw-state volume
docker compose up -d --build    # recreates everything fresh
```

---

## Upgrade OpenClaw

```bash
make upgrade
# Pulls latest OpenClaw npm package, rebuilds image, restarts
```

To pin to a specific version:
```bash
# Edit .env: OPENCLAW_VERSION=2026.2.26
make down
make build
make up
```

---

## SSH tunnel — tips

### Keep the tunnel alive automatically (macOS / Linux)

Add to your shell profile (`~/.bashrc`, `~/.zshrc`):
```bash
alias start-agent-tunnel='./scripts/tunnel.sh ubuntu@YOUR_VPS_IP'
```

Or use `autossh` for automatic reconnection:
```bash
# macOS: brew install autossh
# Linux: sudo apt install autossh
autossh -M 0 -N \
    -R 0.0.0.0:11434:localhost:11434 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=5 \
    ubuntu@YOUR_VPS_IP
```

### Windows — run tunnel at login (Task Scheduler)

1. Open Task Scheduler → Create Task
2. Trigger: At log on
3. Action: Start a program
   - Program: `cmd.exe`
   - Arguments: `/c "C:\path\to\openclaw-docker-agent\scripts\tunnel.bat ubuntu@YOUR_VPS_IP"`
4. Settings: ☑ Restart if the task fails, retry every 1 minute

### Verify the tunnel is working

From the VPS (after tunnel is open):
```bash
curl -s http://localhost:11434/api/tags | python3 -c "
import sys, json
for m in json.load(sys.stdin)['models']:
    print(m['name'])
"
# Should list your local Ollama models
```

---

## Log locations

| Service     | Command                  | Location inside container                |
|-------------|--------------------------|------------------------------------------|
| OpenClaw    | `make logs`              | stdout / stderr                          |
| Caddy       | `make logs-caddy`        | stdout / stderr (JSON format)            |
| cloudflared | `make logs-tunnel`       | stdout / stderr                          |
| OpenClaw    | `make shell` then ls     | `/tmp/openclaw/openclaw-*.log`           |

---

## Deploying to a new VPS from scratch

```bash
# 1. On your new VPS — clone the repo
git clone https://github.com/YOUR_USERNAME/openclaw-docker-agent.git
cd openclaw-docker-agent

# 2. Run one-time setup
bash scripts/setup-vps.sh
exec newgrp docker   # apply docker group

# 3. Configure
cp .env.example .env
openssl rand -hex 32   # → OPENCLAW_GATEWAY_TOKEN
make gen-auth PASSWORD='your_password'  # → CADDY_AUTH_HASH
nano .env

# 4. Start
make up

# 5. On local machine — start Ollama tunnel
./scripts/tunnel.sh ubuntu@NEW_VPS_IP   # Linux/macOS
# or: scripts\tunnel.bat ubuntu@NEW_VPS_IP   (Windows)
```

---

## Cloudflare Tunnel URL management

The trycloudflare.com URL is **random and changes on every `make up`**.

```bash
make url          # show current URL
make logs-tunnel  # stream tunnel logs (URL appears near the top)
```

If you want a **stable URL** (requires a free Cloudflare account):
1. Sign up at cloudflare.com (free, no credit card)
2. Run `cloudflared login` on the VPS
3. Replace the cloudflared service command in `docker-compose.yml`:
   ```yaml
   command: tunnel run --token ${CF_TUNNEL_TOKEN}
   ```
4. Add `CF_TUNNEL_TOKEN` to `.env`

This gives you a permanent `https://something.cfargotunnel.com` URL.
