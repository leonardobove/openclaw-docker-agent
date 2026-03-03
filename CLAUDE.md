# OpenClaw Docker Agent — Full Context

This file is the single source of truth for this project. It is auto-loaded by Claude Code
and seeded into the OpenClaw agent workspace, so the running bot can also read it.

---

## What This Project Is

A self-hosted autonomous AI coding agent running in Docker on a Linux home server.
Controlled via Telegram. No public URL. No reverse proxy. Two containers.

```
Telegram app (phone)
       ↕  (HTTPS, Telegram's servers — bot polls outbound)
OpenClaw agent (Docker container, port 18789 on loopback only)
   Brain: Claude Sonnet 4.6 (Anthropic API, ANTHROPIC_API_KEY)
       ↓  (HTTP, Anthropic-compatible /v1/messages — fallback/alternative)
Ollama sidecar (Docker container, port 11434 on Docker network)
       └── kimi-k2.5:cloud  (cloud model — no download needed)
           glm-5:cloud      (alternative cloud model)

Coding Agents (agent-manager.py, port 3004):
   ├── Claude Pro backend: claude -p  (real Anthropic API via OAuth credentials)
   └── Ollama backend:   claude -p --model <model>
                          env: ANTHROPIC_BASE_URL=http://ollama:11434
                               ANTHROPIC_AUTH_TOKEN=ollama
```

**Stack:**
- **OpenClaw** — Node.js AI agent framework (npm package `openclaw`), gateway on `ws://127.0.0.1:18789`
- **Telegram** — smartphone interface via outbound long-polling (no webhook, no exposed ports)
- **Brain LLM** — Claude Sonnet 4.6 via Anthropic API (`ANTHROPIC_API_KEY`)
  - Fallback: Ollama cloud models (`kimi-k2.5:cloud`, `glm-5:cloud`)
- **Ollama** — Docker sidecar; serves Anthropic-compatible API at `http://ollama:11434`
  OpenClaw connects directly — no bridge process needed (Ollama ≥ 0.6)
- **Claude Code CLI** — used only for spawning coding agents (`agent-manager.py`)
  - Claude Pro backend: uses OAuth credentials from `~/.claude/.credentials.json`
  - Ollama backend: `ANTHROPIC_BASE_URL=http://ollama:11434` overrides the API endpoint

---

## Deployment Machine

Runs on **any machine with Docker** — Linux, Windows (WSL2), or macOS.
The containers are Linux regardless of the host OS.

**Current host:**
- **OS:** Linux home server
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
- Active brain model: `anthropic/claude-sonnet-4-6`
- Coding agents: `claude-pro` backend (OAuth) preferred; `ollama` backend available

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
│   ├── entrypoint.sh          Container init: seeds config, starts agent-manager + gateway
│   ├── agent-manager.py       Background agent spawner on port 3004; claude-pro + ollama backends
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
make up          # Build image + start containers (requires .env)
make down        # Stop and remove containers
make restart     # Restart openclaw container without rebuild
make build       # Force rebuild image (no cache)
make reset       # Wipe state volume + restart fresh (use after major config changes)
make upgrade     # Rebuild with latest OpenClaw npm version
make clean       # Remove containers, images, AND state volume (destructive)

# Observability
make logs        # Stream container logs (tail 100)
make shell       # Bash shell inside the openclaw container
make status      # Show container + volume status

# Telegram pairing
docker compose exec openclaw openclaw pairing list
docker compose exec openclaw openclaw pairing approve <CODE>

# Model switching (no rebuild needed)
docker compose exec openclaw openclaw models list
docker compose exec openclaw openclaw models set anthropic/claude-sonnet-4-6
docker compose exec openclaw openclaw models set anthropic/claude-haiku-4-5-20251001
docker compose exec openclaw openclaw models set ollama/kimi-k2.5:cloud
docker compose exec openclaw openclaw models set ollama/glm-5:cloud

# Ollama model management (sidecar)
docker compose exec ollama ollama list                      # list downloaded models
docker compose exec ollama ollama pull qwen2.5-coder:7b    # pull a local model
docker compose exec ollama ollama --version                # check Ollama version

# Coding agent backend (agent-manager on port 3004)
# Switch to Claude Pro backend (OAuth — preferred)
docker compose exec -T openclaw curl -s -X POST http://localhost:3004/backend \
  -H "Content-Type: application/json" \
  -d '{"backend": "claude-pro"}'
# Switch to Ollama backend
docker compose exec -T openclaw curl -s -X POST http://localhost:3004/backend \
  -H "Content-Type: application/json" \
  -d '{"backend": "ollama", "model": "kimi-k2.5:cloud"}'

# Claude Code OAuth credential injection (run on this Linux machine)
make inject-claude-creds
# Or manually from another machine:
cat ~/.claude/.credentials.json | base64 -w0   # Linux
cat ~/.claude/.credentials.json | base64        # macOS
```

---

## .env Variables

```
OPENCLAW_VERSION=latest                  # npm package version, pin or use latest
OPENCLAW_GATEWAY_TOKEN=<64 hex chars>    # openssl rand -hex 32
TELEGRAM_BOT_TOKEN=<from @BotFather>
ANTHROPIC_API_KEY=<from console.anthropic.com>  # REQUIRED — powers the chatbot brain
REPO_HOST_PATH=<absolute path to repo>   # e.g. /home/leonardo/openclaw-docker-agent
DOCKER_GID=999                           # docker group GID; getent group docker | cut -d: -f3
OLLAMA_MODEL=kimi-k2.5:cloud             # Ollama model for coding agents
```

Generate with: `python3 scripts/gen-env.py`

---

## Config Files in Detail

### `config/openclaw.json`

This is the **source of truth** for the agent config. It lives in the repo and is rendered
on every container start by `scripts/entrypoint.sh` (via `sed` for env var substitution).

Two providers:
- **anthropic** — native Anthropic API; `ANTHROPIC_API_KEY` required; `claude-sonnet-4-6` is default brain
- **ollama** — Anthropic-compatible sidecar at `http://ollama:11434`; cloud models (no download needed)

On every container start, `scripts/entrypoint.sh` renders it to the state volume at
`/home/openclaw/.openclaw/openclaw.json`. The `sed` substitution handles `ANTHROPIC_API_KEY`,
`OPENCLAW_GATEWAY_TOKEN`, and `TELEGRAM_BOT_TOKEN`.

**If a config change isn't being picked up**, force-copy from the repo bind-mount and restart:
```bash
docker compose exec openclaw cp /home/openclaw/repo/config/openclaw.json /home/openclaw/.openclaw/openclaw.json
docker compose restart openclaw
```

Or wipe the state entirely:
```bash
make reset   # prompts for confirmation
```

### State Volume

Named volume `openclaw-state` is mounted at `/home/openclaw/.openclaw` inside the container.
It persists across restarts: workspace files, sessions, memory, credentials, paired users.

Key paths inside the volume:
- `openclaw.json` — active config (rendered from repo on every start)
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

### Brain model (chatbot)

```bash
# Switch to Claude Haiku (faster, cheaper)
docker compose exec openclaw openclaw models set anthropic/claude-haiku-4-5-20251001

# Switch to Kimi K2.5 (Ollama cloud — no API key needed)
docker compose exec openclaw openclaw models set ollama/kimi-k2.5:cloud

# Switch back to Claude Sonnet (default)
docker compose exec openclaw openclaw models set anthropic/claude-sonnet-4-6
```

### Ollama models (sidecar)

Cloud models work without downloading anything. Local models require pulling first:

```bash
# Use a local model
docker compose exec ollama ollama pull qwen2.5-coder:7b
docker compose exec openclaw openclaw models set ollama/qwen2.5-coder:7b
```

**Adding a new model:** add an entry to the `models` array in `config/openclaw.json`,
then rebuild (`make up`) and the config will be re-rendered on next start.

---

## Coding Agents — agent-manager (port 3004)

The agent manager runs `claude -p` in the background and sends real-time Telegram updates.

Two backends:

### Claude Pro backend (preferred)
Uses OAuth credentials from `~/.claude/.credentials.json`.
Talks to the real Anthropic API with the user's Claude Pro subscription.
Token auto-refreshes via the refresh token (no re-login needed day-to-day).

### Ollama backend
Sets `ANTHROPIC_BASE_URL=http://ollama:11434` and `ANTHROPIC_AUTH_TOKEN=ollama`.
The Claude CLI sends requests to Ollama instead of Anthropic.

**Inject Claude Pro credentials (from this Linux machine):**
```bash
make inject-claude-creds
```

**Manual injection (from another machine):**
```bash
# On the machine where you're logged into Claude Code:
cat ~/.claude/.credentials.json | base64 -w0    # Linux
cat ~/.claude/.credentials.json | base64         # macOS
# Paste the output to the Telegram bot
```

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
If deploying to a new machine where the docker group has a different GID, update `DOCKER_GID`
in `.env` (or when running `gen-env.py`).
Check with: `getent group docker | cut -d: -f3`

---

## Making Changes to This Repo

The bot can modify this repository directly. The repo is at `/home/leonardo/openclaw-docker-agent`
on the host (inside the container: `/home/openclaw/repo`).

**Workflow for config changes** (e.g. editing `config/openclaw.json`):
```bash
# 1. Edit the file
# 2. Restart (config is re-rendered from repo on every start)
docker compose restart openclaw
# 3. Or rebuild if Dockerfile changed:
docker compose up -d --build
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

9. **Config rendered on every start** — `entrypoint.sh` renders `openclaw.json` from the repo
   on every container start via `sed`. After changing `config/openclaw.json`, just restart.

10. **`openclaw gateway start` vs `run`** — `start` forks to background and the container exits.
    The entrypoint uses `exec openclaw gateway run` (foreground, PID 1).

11. **`dmPolicy: "pairing"`** — does NOT auto-approve. Admin must run
    `openclaw pairing approve <CODE>` after the user sends the code back. Without this,
    the bot is permanently silent to that user.

12. **AGENTS.md live updates** — entrypoint copies `AGENTS.md` from the repo bind-mount
    (`/home/openclaw/repo/config/workspace/AGENTS.md`) on every start. Edits take effect
    after a container restart.

13. **Ollama version** — Ollama ≥ 0.6 is required for the Anthropic-compatible `/v1/messages`
    endpoint. Verify with: `docker compose exec ollama ollama --version`

14. **Cloud model availability** — `kimi-k2.5:cloud` and `glm-5:cloud` require the Ollama
    container to reach `ollama.com`. Check connectivity if these models fail.

15. **models.json stale Ollama baseUrl** — entrypoint patches any URL containing `ollama`
    in models.json back to `http://ollama:11434`. If models.json is corrupted:
    ```bash
    docker compose exec openclaw rm ~/.openclaw/agents/main/agent/models.json
    docker compose restart openclaw
    ```

16. **agent-manager port 3004** — binds to `127.0.0.1` INSIDE the container. Not reachable
    from the host directly. Use `docker compose exec -T openclaw curl ...` to call it from
    the host (as in the `inject-claude-creds` Makefile target).

17. **Claude Pro OAuth token refresh** — agent-manager does NOT inject `CLAUDE_CODE_OAUTH_TOKEN`.
    It clears API env vars and lets Claude Code read `~/.claude/.credentials.json` directly,
    enabling automatic token refresh via the refresh token. Access tokens expire in ~8h;
    refresh tokens are long-lived (months). No re-login needed day-to-day.

---

## Architecture Decisions

- **Telegram over web UI**: works behind NAT with no port forwarding, no public URL,
  persistent pairing, accessible from any phone worldwide.
- **Anthropic API as brain**: Claude Sonnet 4.6 provides high-quality chatbot responses.
  `ANTHROPIC_API_KEY` required. Ollama cloud models available as free fallback.
- **Ollama sidecar**: cloud models (kimi-k2.5:cloud, glm-5:cloud) work without downloading
  anything. Serves as both fallback brain and Ollama coding agent backend.
- **Dual coding agent backends**: agent-manager supports Claude Pro (OAuth, preferred) and
  Ollama — switch at runtime without rebuild.
- **No LLM bridges**: Ollama serves the Anthropic-compatible `/v1/messages` API directly
  (Ollama ≥ 0.6). No bridge processes, no extra ports.
- **State volume**: named volume `openclaw-state` persists everything across restarts.
  Delete with `docker compose down -v` to start completely fresh (re-pairing required).
- **Loopback-only gateway**: port 18789 is not published to the host.
- **Non-root container**: runs as UID 10001, `cap_drop: ALL`, `no-new-privileges: true`.
- **Config rendered on every start**: entrypoint.sh uses `sed` to substitute env vars
  into `openclaw.json` on every container start. No manual force-copy needed.
