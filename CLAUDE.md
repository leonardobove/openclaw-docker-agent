# OpenClaw Docker Agent — Full Context

This file is the single source of truth for this project. It is auto-loaded by Claude Code
and seeded into the OpenClaw agent workspace, so the running bot can also read it.

---

## What This Project Is

A self-hosted autonomous AI coding agent running in Docker on a Linux home server.
Controlled via Telegram. No public URL. No reverse proxy. Single container.

```
Telegram app (phone)
       ↕  (HTTPS, Telegram's servers — bot polls outbound)
OpenClaw agent (Docker container, port 18789 on loopback only)
       ↓  (HTTP, Anthropic-compatible /v1/messages)
Ollama (Docker sidecar, port 11434)
       ├── kimi-k2.5:cloud  (default — cloud, no extra API key)
       └── <any ollama model>  (local or cloud, switchable at runtime)

Coding Agents (agent-manager.py, port 3004):
   ├── Ollama backend:   claude -p --model <model>
   │                     env: ANTHROPIC_BASE_URL=http://ollama:11434
   │                          ANTHROPIC_AUTH_TOKEN=ollama
   └── Claude Pro backend: claude -p  (real Anthropic API via OAuth credentials)
```

**Stack:**
- **OpenClaw** — Node.js AI agent framework (npm package `openclaw`), gateway on `ws://127.0.0.1:18789`
- **Telegram** — smartphone interface via outbound long-polling (no webhook, no exposed ports)
- **LLM** — Ollama with Anthropic-compatible `/v1/messages` API; models switchable at runtime:
  - `kimi-k2.5:cloud` — default (cloud model, no download needed)
  - `glm-5:cloud` — alternative cloud model
  - `qwen3:30b-a3b` — local model (must pull first)
  - `qwen2.5-coder:7b` — local coding model (must pull first)
- **Ollama** — Docker sidecar; serves Anthropic-compatible API at `http://ollama:11434/v1/messages`
  OpenClaw connects directly — no bridge process needed (Ollama ≥ 0.6)
- **Claude Code CLI** — used only for spawning coding agents (`agent-manager.py`)
  - Ollama backend: `ANTHROPIC_BASE_URL=http://ollama:11434` overrides the API endpoint
  - Claude Pro backend: uses OAuth credentials from `~/.claude/.credentials.json`

---

## Deployment Machine

Runs on **any machine with Docker** — Linux, Windows (WSL2), or macOS.
The containers are Linux regardless of the host OS.

**Current host:**
- **OS:** Linux home server (or Windows with WSL2)
- **Repo:** path set in `.env` as `REPO_HOST_PATH`
- **Git remote:** `git@github.com:leonardobove/openclaw-docker-agent.git`
- **Docker:** running, managed via `docker compose`

**Windows/WSL2 setup (one time):**
1. `wsl --install` in PowerShell (Admin) → reboot
2. Install Docker Desktop → enable WSL2 backend in settings
3. Open WSL2 terminal: `sudo apt install -y git make python3`
4. `git clone https://github.com/leonardobove/openclaw-docker-agent.git`
5. `cd openclaw-docker-agent && python3 scripts/gen-env.py && make up`

---

## Current Status

Stack is UP. Two containers: `openclaw-agent` + `ollama` sidecar.

- Telegram bot: `@openclaw_docker_agent_bot` — connected, user `leobove` is paired
- Active brain model: `ollama/kimi-k2.5:cloud`
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
│   └── homeserver/            One-time Linux server setup scripts
│       ├── setup.sh           Master script (runs all below in order)
│       ├── 01-static-ip.sh    Static LAN IP via netplan
│       ├── 02-ssh-hardening.sh  Key-only SSH + fail2ban
│       ├── 03-firewall.sh     ufw rules
│       └── 04-tailscale.sh    Tailscale for remote SSH
├── docker-compose.yml         Two-service stack: openclaw-agent + ollama sidecar
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

# Observability
make logs        # Stream container logs (tail 100)
make shell       # Bash shell inside the container
make status      # Show container + volume status

# Telegram pairing
docker compose exec openclaw openclaw pairing list
docker compose exec openclaw openclaw pairing approve <CODE>

# Model switching (no rebuild needed)
docker compose exec openclaw openclaw models list
docker compose exec openclaw openclaw models set ollama/kimi-k2.5:cloud
docker compose exec openclaw openclaw models set ollama/glm-5:cloud
docker compose exec openclaw openclaw models set ollama/qwen3:30b-a3b
docker compose exec openclaw openclaw models set ollama/qwen2.5-coder:7b

# Ollama model management
docker compose exec ollama ollama list                      # list downloaded models
docker compose exec ollama ollama pull qwen2.5-coder:7b    # pull a local model
docker compose exec ollama ollama pull <model>             # pull any Ollama model
docker compose exec ollama ollama --version                # check Ollama version

# Coding agent backend (agent-manager on port 3004)
# Switch to Ollama backend (default)
curl -s -X POST http://localhost:3004/backend \
  -H "Content-Type: application/json" \
  -d '{"backend": "ollama", "model": "kimi-k2.5:cloud"}'
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
                                         # on WSL2: Linux path inside WSL2
DOCKER_GID=999                           # docker group GID; getent group docker | cut -d: -f3
OLLAMA_MODEL=qwen2.5-coder:7b            # default model for coding agents
# ANTHROPIC_API_KEY=<optional>          # only needed for Claude Pro agents (API key auth)
                                         # prefer OAuth credential injection via Telegram
```

Generate with: `python3 scripts/gen-env.py`

---

## Config Files in Detail

### `config/openclaw.json`

This is the **source of truth** for the agent config. It lives in the repo and is baked into
the Docker image at `/etc/openclaw/openclaw.json`.

The Ollama provider uses `"api": "anthropic-messages"` and points directly to
`http://ollama:11434` — no bridge process is needed (Ollama ≥ 0.6 serves `/v1/messages`).

On **first container start**, `scripts/entrypoint.sh` copies it to the state volume at
`/home/openclaw/.openclaw/openclaw.json`. On subsequent starts the entrypoint skips this copy
(state already exists), but OpenClaw's gateway may auto-overwrite it if the image config differs.

**If a config change isn't being picked up**, force-copy from the repo bind-mount and restart:
```bash
docker compose exec openclaw cp /home/openclaw/repo/config/openclaw.json /home/openclaw/.openclaw/openclaw.json
docker compose restart openclaw
```
Note: `/etc/openclaw/openclaw.json` is baked into the image at build time — use the repo path above
to pick up edits without rebuilding.

Or wipe the state entirely for a clean slate:
```bash
make reset   # prompts for confirmation
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

All Ollama models are pre-configured. Switch at any time **without rebuilding**:

```bash
# Switch to GLM-5 (cloud)
docker compose exec openclaw openclaw models set ollama/glm-5:cloud

# Switch back to default (Kimi K2.5 cloud)
docker compose exec openclaw openclaw models set ollama/kimi-k2.5:cloud

# Switch to a local model (pull it first if not already downloaded)
docker compose exec ollama ollama pull qwen2.5-coder:7b
docker compose exec openclaw openclaw models set ollama/qwen2.5-coder:7b
```

Or ask the bot directly: *"switch to GLM-5"*, *"switch to Qwen2.5 Coder"*, etc.

**Adding a new model:** add an entry to the `models` array in `config/openclaw.json`,
then rebuild (`make up`) and force-copy the config if needed.

**Cloud vs local models:**
- Cloud models (e.g. `kimi-k2.5:cloud`, `glm-5:cloud`): served by Ollama's cloud
  infrastructure. Ollama container must reach `ollama.com`. No extra API key needed.
- Local models (e.g. `qwen2.5-coder:7b`): pulled to the `ollama-data` volume. Require
  disk space but work fully offline.

`models set` updates `/home/openclaw/.openclaw/agents/main/agent/models.json` live — no restart needed.

**Verify:** `make logs | grep "agent model"` or ask the bot what model it's using.

---

## Coding Agents — agent-manager (port 3004)

The agent manager runs `claude -p` in the background and sends real-time Telegram updates.

Two backends:

### Ollama backend (default)
Sets `ANTHROPIC_BASE_URL=http://ollama:11434` and `ANTHROPIC_AUTH_TOKEN=ollama`.
The Claude CLI sends requests to Ollama instead of Anthropic.

### Claude Pro backend
Uses OAuth credentials from `~/.claude/.credentials.json`.
Sets `CLAUDE_CODE_OAUTH_TOKEN` from the credentials file.
Talks to the real Anthropic API.

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
If deploying to a new machine where the docker group has a different GID, update the GID in
the Dockerfile (`groupadd -g 999 docker-host`) and `docker-compose.yml` (`group_add: ["999"]`).
Check with: `getent group docker | cut -d: -f3`

---

## Making Changes to This Repo

The bot can modify this repository directly. The repo is at `/home/leonardo/openclaw-docker-agent`.

**Workflow for config changes** (e.g. editing `config/openclaw.json`):
```bash
# 1. Edit the file
# 2. Rebuild image
docker compose up -d --build
# 3. If the new config isn't picked up from the state cache, force-copy:
docker compose exec openclaw cp /etc/openclaw/openclaw.json /home/openclaw/.openclaw/openclaw.json
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
    endpoint. If the `ollama/ollama:latest` image is older, the bot will fail to get responses.
    Verify with: `docker compose exec ollama ollama --version`

14. **Cloud model availability** — `kimi-k2.5:cloud` and `glm-5:cloud` require the Ollama
    container to reach `ollama.com`. Check connectivity if these models fail.

---

## Architecture Decisions

- **Telegram over web UI**: works behind NAT with no port forwarding, no public URL,
  persistent pairing, accessible from any phone worldwide.
- **Single brain provider (Ollama)**: removed Anthropic, Gemini, Groq providers. Ollama
  serves an Anthropic-compatible API at `/v1/messages` — no bridge process needed.
  Cloud models (kimi-k2.5:cloud, glm-5:cloud) require no extra API key.
- **No LLM bridges**: removed `claude-bridge.py`, `ollama-bridge.py`, `groq-bridge.py`.
  Simpler stack, fewer processes, no bridge failures.
- **Dual coding agent backends**: agent-manager supports Ollama (via `ANTHROPIC_BASE_URL`
  override) and Claude Pro (via OAuth credentials) — switch at runtime without rebuild.
- **State volume**: named volume `openclaw-state` persists everything across restarts.
  Delete with `docker compose down -v` to start completely fresh (re-pairing required).
- **Loopback-only gateway**: port 18789 is not published to the host. Telegram uses
  outbound HTTP long-polling — nothing needs to reach in from outside.
- **Non-root container**: runs as UID 10001, `cap_drop: ALL`, `no-new-privileges: true`.
