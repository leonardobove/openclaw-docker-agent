# OpenClaw Docker Agent — Full Context

This file is the single source of truth for this project. It is auto-loaded by Claude Code
and seeded into the OpenClaw agent workspace, so the running bot can also read it.

---

## What This Project Is

A self-hosted autonomous AI coding agent running in Docker on a Linux machine.
Controlled via Telegram. The AI brain runs on a separate Windows machine (LAN) via Ollama.

```
Telegram app (phone)
       ↕  (HTTPS, Telegram's servers — bot polls outbound)
OpenClaw agent (Docker container on Linux, port 18789 on loopback only)
       ↓  (HTTP over LAN, Anthropic-compatible /v1/messages)
Ollama (native Windows — AMD GPU — port 11434, exposed on LAN)
       └── qwen2.5-coder:7b (default local), + kimi-k2.5:cloud, glm-5:cloud, qwen3:30b-a3b

Coding Agents (agent-manager.py, port 3004):
   ├── Ollama backend:   claude -p --model <model>
   │                     env: ANTHROPIC_BASE_URL=http://<win-ip>:11434
   │                          ANTHROPIC_AUTH_TOKEN=ollama
   └── Claude Pro backend: claude -p  (real Anthropic API via OAuth credentials)
```

**Stack:**
- **OpenClaw** — Node.js AI agent framework (npm package `openclaw`), gateway on `ws://127.0.0.1:18789`
- **Telegram** — smartphone interface via outbound long-polling (no webhook, no exposed ports)
- **LLM** — Ollama running natively on Windows (AMD GPU), exposed on LAN port 11434.
  Connected via `OLLAMA_HOST` env var. Anthropic-compatible `/v1/messages` API (Ollama ≥ 0.6).
- **Claude Code CLI** — used only for spawning coding agents (`agent-manager.py`)
  - Ollama backend: `ANTHROPIC_BASE_URL=<OLLAMA_HOST>` overrides the API endpoint
  - Claude Pro backend: uses OAuth credentials from `~/.claude/.credentials.json`

---

## Machines in This Setup

### Linux machine (OpenClaw host)
- Runs Docker with the `openclaw-agent` container
- No Ollama — connects to Windows machine over LAN
- Repo at path set in `.env` as `REPO_HOST_PATH`
- Git remote: `git@github.com:leonardobove/openclaw-docker-agent.git`

### Windows machine (Ollama host)
- Runs Ollama **natively** (not in Docker, not in WSL) for full AMD GPU access
- Ollama listens on `0.0.0.0:11434` (all interfaces, exposed on LAN)
- AMD GPU via Ollama's built-in ROCm support (RX 6000+ / RX 7000+ series)
- Windows Firewall: TCP 11434 allowed for Private networks

---

## Current Status

Stack is UP. One container: `openclaw-agent`.

- Telegram bot: `@openclaw_docker_agent_bot` — connected, user `leobove` is paired
- Active brain model: `ollama/qwen2.5-coder:7b` (on Windows Ollama)
- Coding agents: `ollama` backend (default), `claude-pro` backend available with OAuth creds

---

## Repository Structure

```
openclaw-docker-agent/
├── config/
│   ├── openclaw.json          LLM providers, gateway config, Telegram channel
│   └── workspace/
│       ├── AGENTS.md          Agent behaviour instructions (seeded into workspace)
│       └── SOUL.md            Agent persona
├── scripts/
│   ├── entrypoint.sh          Container init: seeds config on first run, starts agent-manager + gateway
│   ├── agent-manager.py       Background agent spawner on port 3004; supports ollama/claude-pro backends
│   ├── gen-env.py             Interactive .env generator (always use this, not heredoc)
│   ├── setup-claude.sh        Installs Claude Code CLI and opens a session in this repo
│   ├── install-claude-memory.sh  Installs committed memory file for cross-machine continuity
│   ├── windows/
│   │   └── setup-ollama.ps1   Run on Windows (Admin PowerShell) to configure Ollama for LAN + AMD GPU
│   ├── network/
│   │   └── test-ollama.sh     Test connectivity from Linux to Windows Ollama
│   └── homeserver/            One-time Linux server setup scripts
│       ├── setup.sh           Master script (runs all below in order)
│       ├── 01-static-ip.sh    Static LAN IP via netplan
│       ├── 02-ssh-hardening.sh  Key-only SSH + fail2ban
│       ├── 03-firewall.sh     ufw rules
│       └── 04-tailscale.sh    Tailscale for remote SSH
├── docker-compose.yml         Single-service stack: openclaw-agent only
├── Dockerfile                 Image: node:22-slim + openclaw npm + claude-code npm + non-root user
├── Makefile                   All operational commands
├── .env                       Secrets — gitignored, never commit
├── .env.example               Template for .env
└── CLAUDE.md                  This file
```

---

## Key Commands

```bash
# Stack management
make up          # Build image + start container (requires .env)
make down        # Stop and remove container
make restart     # Restart container without rebuild
make build       # Force rebuild image (no cache)
make reset       # Wipe state volume + restart fresh (use after major config changes)
make upgrade     # Rebuild with latest OpenClaw npm version
make clean       # Remove container, image, AND state volume (destructive)

# Network
make test-ollama # Verify connectivity from Linux to Windows Ollama

# Observability
make logs        # Stream container logs (tail 100)
make shell       # Bash shell inside the container
make status      # Show container + volume status

# Telegram pairing
docker compose exec openclaw openclaw pairing list
docker compose exec openclaw openclaw pairing approve <CODE>

# Model switching (no rebuild needed)
docker compose exec openclaw openclaw models list
docker compose exec openclaw openclaw models set ollama/qwen2.5-coder:7b
docker compose exec openclaw openclaw models set ollama/qwen3:30b-a3b
docker compose exec openclaw openclaw models set ollama/kimi-k2.5:cloud
docker compose exec openclaw openclaw models set ollama/glm-5:cloud

# Ollama model management (run on Windows machine)
ollama list                      # list downloaded models
ollama pull qwen2.5-coder:7b     # pull a local model
ollama pull qwen3:30b-a3b        # pull Qwen3 MoE
ollama pull kimi-k2.5:cloud      # cloud model (no download, requires internet)
ollama --version                 # check Ollama version

# Coding agent backend (agent-manager on port 3004)
# Switch to Ollama backend (default)
curl -s -X POST http://localhost:3004/backend \
  -H "Content-Type: application/json" \
  -d '{"backend": "ollama", "model": "qwen2.5-coder:7b"}'
# Switch to Claude Pro backend
curl -s -X POST http://localhost:3004/backend \
  -H "Content-Type: application/json" \
  -d '{"backend": "claude-pro"}'

# Claude Code OAuth credential injection (run on LOCAL machine, paste blob to Telegram)
cat ~/.claude/.credentials.json | base64 -w0   # Linux
cat ~/.claude/.credentials.json | base64        # macOS
```

---

## .env Variables

```
OPENCLAW_VERSION=latest                  # npm package version, pin or use latest
OPENCLAW_GATEWAY_TOKEN=<64 hex chars>    # openssl rand -hex 32
TELEGRAM_BOT_TOKEN=<from @BotFather>
REPO_HOST_PATH=<absolute path to repo>   # e.g. /home/leonardo/openclaw-docker-agent
DOCKER_GID=999                           # docker group GID; getent group docker | cut -d: -f3
OLLAMA_HOST=http://<windows-ip>:11434    # Windows machine LAN URL — required
OLLAMA_MODEL=qwen2.5-coder:7b            # default model for coding agents
# ANTHROPIC_API_KEY=<optional>          # only needed for Claude Pro agents (API key auth)
                                         # prefer OAuth credential injection via Telegram
```

Generate with: `python3 scripts/gen-env.py`

---

## Windows Ollama Setup (One Time)

Run the following on the **Windows machine** (PowerShell as Administrator):

```powershell
# 1. Install Ollama from https://ollama.com/download/windows (if not installed)

# 2. Run the setup script from this repo (cloned or copied to Windows)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\setup-ollama.ps1

# 3. Restart Ollama (right-click tray icon → Quit → relaunch)
```

The script:
- Sets `OLLAMA_HOST=0.0.0.0:11434` system-wide (Ollama listens on all interfaces)
- Adds a Windows Firewall inbound rule for TCP 11434 (Private networks)
- Detects AMD GPU
- Pulls `qwen2.5-coder:7b`
- Prints the LAN IP to paste into your Linux `.env`

**AMD GPU notes:**
- Ollama on Windows supports AMD GPUs via ROCm — RX 6000+ and RX 7000+ series
- Keep Radeon Software / AMDGPU drivers up to date
- No extra configuration needed — Ollama auto-detects the GPU on Windows
- Older AMD cards may fall back to CPU. Check with: `ollama run qwen2.5-coder:7b`
  and watch Task Manager → Performance → GPU to confirm GPU utilization.

---

## LAN Network Setup

### Verify connectivity from Linux to Windows

```bash
# From the Linux machine (repo root):
make test-ollama

# Or manually:
curl http://<windows-ip>:11434/api/version
```

### Troubleshooting LAN issues

| Symptom | Fix |
|---|---|
| `Connection refused` | Ollama not running, or OLLAMA_HOST not set to 0.0.0.0 — restart Ollama after setting env var |
| `No route to host` | Windows Firewall blocking — run setup-ollama.ps1 or add rule manually |
| `Connection timed out` | Wrong IP in OLLAMA_HOST, or machines on different subnets |
| `Models not found` | Pull models on Windows first: `ollama pull <model>` |

### Static IPs (recommended)

Assign static LAN IPs to both machines so `OLLAMA_HOST` never changes:
- **Linux:** use `scripts/homeserver/01-static-ip.sh` (netplan)
- **Windows:** Control Panel → Network → adapter → IPv4 properties → Use the following IP address

### Tailscale (optional, for remote access)

If you want to reach Ollama from outside the LAN (or from any machine securely):
- Install Tailscale on both machines (`scripts/homeserver/04-tailscale.sh` for Linux)
- Use the Tailscale IP as `OLLAMA_HOST`

---

## Config Files in Detail

### `config/openclaw.json`

This is the **source of truth** for the agent config. It lives in the repo and is baked into
the Docker image at `/etc/openclaw/openclaw.json`.

The Ollama provider uses `"api": "anthropic-messages"` and reads the base URL from the
`${OLLAMA_HOST}` environment variable — no bridge process needed (Ollama ≥ 0.6 serves `/v1/messages`).

On **first container start**, `scripts/entrypoint.sh` copies it to the state volume at
`/home/openclaw/.openclaw/openclaw.json`. On subsequent starts the entrypoint skips this copy
(state already exists).

**If a config change isn't being picked up**, force-copy from the repo bind-mount and restart:
```bash
docker compose exec openclaw cp /home/openclaw/repo/config/openclaw.json /home/openclaw/.openclaw/openclaw.json
docker compose restart openclaw
```

Or wipe the state entirely for a clean slate:
```bash
make reset
```

### State Volume

Named volume `openclaw-state` is mounted at `/home/openclaw/.openclaw` inside the container.
It persists across restarts: workspace files, sessions, memory, credentials, paired users.

Key paths inside the volume:
- `openclaw.json` — active config (may differ from image if `models set` was used)
- `agents/main/agent/models.json` — per-agent model overrides (updated by `models set`)
- `credentials/telegram-default-allowFrom.json` — list of paired Telegram user IDs
- `credentials/telegram-pairing.json` — pending pairing requests
- `telegram/update-offset-default.json` — Telegram polling offset (don't delete while running)
- `claude-creds/` — Claude Code OAuth credentials (symlinked to `~/.claude/`)
- `agent-backend` — default coding agent backend (`ollama` or `claude-pro`)
- `agent-model` — default coding agent Ollama model

---

## Telegram Pairing — Two-Step Process

`dmPolicy: "pairing"` means **the bot does NOT auto-admit users**. Admin approval is required.

1. User sends `/start` to `@openclaw_docker_agent_bot` on Telegram
2. Bot replies with a one-time code (e.g. `BYGFKLR9`)
3. User sends the code back to the bot (bot stays silent — this is expected)
4. **Admin runs on the server:**
   ```bash
   docker compose exec openclaw openclaw pairing list       # see pending
   docker compose exec openclaw openclaw pairing approve BYGFKLR9
   ```
5. User is now admitted permanently — no re-pairing needed across restarts

Paired user IDs are stored in:
`/home/openclaw/.openclaw/credentials/telegram-default-allowFrom.json`

---

## Switching LLMs

All Ollama models are pre-configured in `config/openclaw.json`. Switch at any time **without rebuilding**:

```bash
# Switch to Qwen3 MoE (local, pull first on Windows)
docker compose exec openclaw openclaw models set ollama/qwen3:30b-a3b

# Switch to Kimi K2.5 (cloud — requires Windows machine to have internet)
docker compose exec openclaw openclaw models set ollama/kimi-k2.5:cloud

# Switch back to default
docker compose exec openclaw openclaw models set ollama/qwen2.5-coder:7b
```

Or ask the bot directly: *"switch to Qwen3"*, *"use Kimi"*, etc.

**Adding a new model:**
1. Pull it on the Windows machine: `ollama pull <model>`
2. Add an entry to the `models` array in `config/openclaw.json`
3. Rebuild (`make up`) and force-copy the config if needed

**Cloud vs local models:**
- Cloud models (e.g. `kimi-k2.5:cloud`, `glm-5:cloud`): served via Ollama's cloud proxy.
  The Windows Ollama container must reach `ollama.com`. No extra API key needed.
- Local models (e.g. `qwen2.5-coder:7b`, `qwen3:30b-a3b`): stored on Windows disk.
  Use AMD GPU for fast inference. No internet needed after pull.

`models set` updates `/home/openclaw/.openclaw/agents/main/agent/models.json` live — no restart needed.

**Verify:** `make logs | grep "agent model"` or ask the bot what model it's using.

---

## Coding Agents — agent-manager (port 3004)

The agent manager runs `claude -p` in the background and sends real-time Telegram updates.

Two backends:

### Ollama backend (default)
Sets `ANTHROPIC_BASE_URL=<OLLAMA_HOST>` and `ANTHROPIC_AUTH_TOKEN=ollama`.
The Claude CLI sends requests to Windows Ollama instead of Anthropic.

### Claude Pro backend
Uses OAuth credentials from `~/.claude/.credentials.json`.
Sets `CLAUDE_CODE_OAUTH_TOKEN` from the credentials file.
Talks to the real Anthropic API (your Claude Pro subscription).

**Inject Claude Pro credentials:**
```bash
# On local machine (where you're logged into Claude Code):
cat ~/.claude/.credentials.json | base64 -w0    # Linux
cat ~/.claude/.credentials.json | base64         # macOS
# Paste the output to the Telegram bot
```
The bot writes the credentials to `~/.claude/.credentials.json` in the container (symlinked
to the state volume — persists across rebuilds, lost only on `make reset`/`make clean`).

**agent-manager endpoints:**
- `POST /spawn` — `{"task": "...", "backend": "ollama|claude-pro", "model": "..."}`
- `GET /status` — list jobs + current default backend/model
- `DELETE /agent/<id>` — cancel a running job
- `POST /logging` — `{"enabled": true/false}` — toggle tool-call updates in Telegram
- `POST /backend` — `{"backend": "ollama|claude-pro", "model": "..."}` — set default

---

## Docker Self-Rebuild Capability

The container has the Docker socket mounted and the Docker CLI installed. OpenClaw can
manage Docker directly — including rebuilding and restarting itself.

**Key env var:** `REPO_HOST_PATH=/home/leonardo/openclaw-docker-agent`
This is the HOST path to the repo. Docker commands must use this path (not `/home/openclaw/repo`)
because the Docker daemon resolves paths from the host's perspective, not the container's.

**Rebuild command (from inside the container):**
```bash
docker compose -f "$REPO_HOST_PATH/docker-compose.yml" up -d --build
```

⚠️ Running this kills the current container (and the active agent session). Always warn the
user before triggering a rebuild.

**Docker group:** container user (UID 10001) is in group `docker-host` (GID 999 = host docker group).
If deploying to a new machine where the docker group has a different GID, set `DOCKER_GID` in `.env`.

---

## Making Changes to This Repo

The bot can modify this repository directly. The repo is at `/home/leonardo/openclaw-docker-agent`.

**Workflow for config changes** (e.g. editing `config/openclaw.json`):
```bash
# 1. Edit the file
# 2. Rebuild image
docker compose up -d --build
# 3. If the new config isn't picked up from the state cache, force-copy:
docker compose exec openclaw cp /home/openclaw/repo/config/openclaw.json /home/openclaw/.openclaw/openclaw.json
docker compose restart openclaw
# 4. Commit and push
git add config/openclaw.json
git commit -m "..."
git push
```

**Workflow for non-config changes** (scripts, Makefile, Dockerfile, docs):
```bash
# Edit files, then:
git add <files>
git commit -m "..."
git push
# Rebuild if Dockerfile or entrypoint changed:
docker compose up -d --build
```

**Never commit `.env`** — it is gitignored and contains secrets.

---

## Known Bugs — Do Not Reintroduce

1. **`gateway.bind: "lan"`** — only needed when a reverse proxy needs to reach the gateway.
   With Telegram-only, omit it. Default is loopback (`127.0.0.1`), which is correct.

2. **`gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback`** — only needed with `bind: lan`. Remove if not using a reverse proxy.

3. **`ModelProviderSchema`** — requires BOTH `baseUrl` (non-empty string) AND `models` (array)
   for every provider entry. Missing either causes a Zod validation error at startup.

4. **Ollama provider** — needs `"api": "anthropic-messages"` set on the provider object AND
   on each individual model entry. Omitting it causes silent model failures.

5. **`openclaw gateway start`** — daemonizes and exits immediately. Wrong for Docker.
   Always use `openclaw gateway run` in `entrypoint.sh`.

6. **`gateway.reload`** — must be `{}` (empty object), not a string.

7. **`gateway.mode: "local"`** — required. Without it the gateway refuses to start.

8. **`agents.defaults.sandbox`** — must be `{}` (empty object), not a string.

9. **State volume config cache** — `openclaw.json` in the state volume is not automatically
   overwritten on every restart. After changing `config/openclaw.json`, force-copy or `make reset`.

10. **`openclaw gateway start` vs `run`** — `start` forks to background and the container exits.
    The entrypoint uses `exec openclaw gateway run` (foreground, PID 1).

11. **`dmPolicy: "pairing"`** — does NOT auto-approve. Admin must run
    `openclaw pairing approve <CODE>` after the user sends the code back. Without this,
    the bot is permanently silent to that user.

12. **Entrypoint first-run only** — `scripts/entrypoint.sh` only copies config files from
    `/etc/openclaw/` to the state volume when `openclaw.json` does not already exist.
    Subsequent container starts skip this entirely.

13. **Ollama version** — Ollama ≥ 0.6 is required for the Anthropic-compatible `/v1/messages`
    endpoint. Verify with: `ollama --version` on the Windows machine.

14. **`OLLAMA_HOST` must be the full URL** — e.g. `http://192.168.1.100:11434`.
    Do NOT include a trailing slash. The env var is used directly in `config/openclaw.json`
    via `${OLLAMA_HOST}` substitution.

15. **Windows Ollama must restart after setting `OLLAMA_HOST`** — the system env var
    (`OLLAMA_HOST=0.0.0.0:11434`) is only read on Ollama startup. Quit and relaunch Ollama
    from the system tray after running `setup-ollama.ps1`.

16. **OpenClaw does NOT substitute `${OLLAMA_HOST}` in provider `baseUrl`** — env var
    interpolation works for gateway token, telegram token, and workspace path, but NOT for
    `models.providers.*.baseUrl`. The entrypoint uses `sed` to render the config template
    on every start, so this is handled automatically. Do not bypass the entrypoint.

17. **Cloud models on Windows** — `kimi-k2.5:cloud` and `glm-5:cloud` require the Windows
    machine to reach `ollama.com`. Check internet connectivity if these models fail.

---

## Architecture Decisions

- **Telegram over web UI**: works behind NAT with no port forwarding, no public URL,
  persistent pairing, accessible from any phone worldwide.
- **Ollama on Windows (native)**: AMD GPU works fully on Windows with Ollama's ROCm support.
  Running Ollama in Docker or WSL would lose GPU access (AMD ROCm in Docker on Windows is
  not supported). Native Windows Ollama is the simplest path.
- **No Ollama sidecar on Linux**: removed the `ollama` Docker service. All LLM traffic goes
  over LAN to the Windows machine. Single container on Linux — simpler, fewer moving parts.
- **Single brain provider (Ollama)**: removed Anthropic, Gemini, Groq providers.
  Ollama serves an Anthropic-compatible API at `/v1/messages` — no bridge process needed.
- **Dual coding agent backends**: agent-manager supports Ollama (via `ANTHROPIC_BASE_URL`
  override pointing to Windows) and Claude Pro (via OAuth credentials) — switch at runtime.
- **State volume**: named volume `openclaw-state` persists everything across restarts.
  Delete with `docker compose down -v` to start completely fresh (re-pairing required).
- **Loopback-only gateway**: port 18789 is not published to the host. Telegram uses
  outbound HTTP long-polling — nothing needs to reach in from outside.
- **Non-root container**: runs as UID 10001, `cap_drop: ALL`, `no-new-privileges: true`.
