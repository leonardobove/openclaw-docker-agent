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
       ↓  (HTTPS)
Anthropic Claude API  /  Google Gemini API
```

**Stack:**
- **OpenClaw** — Node.js AI agent framework (npm package `openclaw`), gateway on `ws://127.0.0.1:18789`
- **Telegram** — smartphone interface via outbound long-polling (no webhook, no exposed ports)
- **LLM** — Anthropic Claude Sonnet 4.6 (default), switchable to Gemini 2.0 Flash without rebuild

---

## Deployment Machine

- **OS:** Linux home server behind NAT router (not a VPS)
- **User:** `leonardo`
- **Repo:** `/home/leonardo/openclaw-docker-agent`
- **Git remote:** `git@github.com:leonardobove/openclaw-docker-agent.git`
- **Docker:** running, managed via `docker compose`

---

## Current Status

Stack is UP. Single container `openclaw-agent` is healthy.

- Telegram bot: `@openclaw_docker_agent_bot` — connected, user `leobove` is paired
- Active model: `anthropic/claude-sonnet-4-6`
- Both Anthropic and Google providers are configured — switch without rebuild

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
│   ├── entrypoint.sh          Container init: seeds config on first run, starts gateway
│   ├── gen-env.py             Interactive .env generator (always use this, not heredoc)
│   ├── setup-claude.sh        Installs Claude Code CLI and opens a session in this repo
│   └── homeserver/            One-time Linux server setup scripts
│       ├── setup.sh           Master script (runs all below in order)
│       ├── 01-static-ip.sh    Static LAN IP via netplan
│       ├── 02-ssh-hardening.sh  Key-only SSH + fail2ban
│       ├── 03-firewall.sh     ufw rules
│       └── 04-tailscale.sh    Tailscale for remote SSH
├── docker-compose.yml         Single-service stack definition
├── Dockerfile                 Image: node:22-slim + openclaw npm + non-root user
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
docker compose exec openclaw openclaw models set google/gemini-2.0-flash
docker compose exec openclaw openclaw models set anthropic/claude-sonnet-4-6
docker compose exec openclaw openclaw models set anthropic/claude-haiku-4-5-20251001
```

---

## .env Variables

```
OPENCLAW_VERSION=latest                  # npm package version, pin or use latest
OPENCLAW_GATEWAY_TOKEN=<64 hex chars>    # openssl rand -hex 32
TELEGRAM_BOT_TOKEN=<from @BotFather>
ANTHROPIC_API_KEY=<from console.anthropic.com>
GEMINI_API_KEY=<from aistudio.google.com/apikey>   # free tier available
```

Generate with: `python3 scripts/gen-env.py`

---

## Config Files in Detail

### `config/openclaw.json`

This is the **source of truth** for the agent config. It lives in the repo and is baked into
the Docker image at `/etc/openclaw/openclaw.json`.

On **first container start**, `scripts/entrypoint.sh` copies it to the state volume at
`/home/openclaw/.openclaw/openclaw.json`. On subsequent starts the entrypoint skips this copy
(state already exists), but OpenClaw's gateway may auto-overwrite it if the image config differs.

**If a config change isn't being picked up**, force-copy and restart:
```bash
docker compose exec openclaw cp /etc/openclaw/openclaw.json /home/openclaw/.openclaw/openclaw.json
docker compose restart openclaw
```

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

Both providers are pre-configured. Switch at any time **without rebuilding**:

```bash
# Switch to Gemini (free)
docker compose exec openclaw openclaw models set google/gemini-2.0-flash

# Switch back to Claude (default)
docker compose exec openclaw openclaw models set anthropic/claude-sonnet-4-6

# Cheaper/faster Claude
docker compose exec openclaw openclaw models set anthropic/claude-haiku-4-5-20251001
```

Or ask the bot directly: *"switch to Gemini 2.0 Flash"*

`models set` updates `/home/openclaw/.openclaw/agents/main/agent/models.json` live — no restart needed.

**Verify:** `make logs | grep "agent model"` or ask the bot what model it's using.

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

**To install a new system package:**
1. Edit `/home/openclaw/repo/Dockerfile` — add to the apt-get install list
2. Commit: `git -C /home/openclaw/repo commit -am "Add <pkg> to Dockerfile"`
3. Warn the user, then rebuild

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

4. **Anthropic provider** — needs `"api": "anthropic-messages"` set on the provider object AND
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

---

## Architecture Decisions

- **Telegram over web UI**: works behind NAT with no port forwarding, no public URL,
  persistent pairing, accessible from any phone worldwide.
- **Single container**: removed Caddy and cloudflared (3-container stack). No reverse proxy
  needed since there's no web UI to serve.
- **Both LLM providers pre-configured**: Anthropic (paid, strong) + Google (free, 1M context).
  Switch at runtime with `openclaw models set` — no image rebuild required.
- **State volume**: named volume `openclaw-state` persists everything across restarts.
  Delete with `docker compose down -v` to start completely fresh (re-pairing required).
- **Loopback-only gateway**: port 18789 is not published to the host. Telegram uses
  outbound HTTP long-polling — nothing needs to reach in from outside.
- **Non-root container**: runs as UID 10001, `cap_drop: ALL`, `no-new-privileges: true`.
