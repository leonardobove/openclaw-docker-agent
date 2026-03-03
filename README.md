# openclaw-docker-agent

Self-hosted autonomous AI coding agent powered by [OpenClaw](https://openclaw.ai).
Controlled from your phone via Telegram. Runs entirely in Docker on Linux.

```
Telegram (phone) ↔ Telegram servers ↔ OpenClaw (Docker) ↔ Ollama sidecar / Anthropic API
```

---

## Architecture

Two Docker containers, one machine:

| Container | Role |
|---|---|
| `openclaw-agent` | Telegram bot, agent manager, self-edit capability |
| `ollama` | LLM sidecar — serves cloud and local models |

**Brain (chatbot):** Claude Sonnet 4.6 (Anthropic API) by default, switchable to any Ollama model at runtime.

**Coding agents:** Claude Pro (OAuth) or Ollama cloud/local models, spawned as background jobs with real-time Telegram updates.

---

## Prerequisites

- A Linux machine (or Windows with WSL2) with Docker + Docker Compose
- A Telegram account + bot token from [@BotFather](https://t.me/BotFather)
- An [Anthropic API key](https://console.anthropic.com/settings/keys) (powers the chatbot brain)

---

## Quick start

### 1. Clone and generate `.env`

```bash
git clone https://github.com/leonardobove/openclaw-docker-agent.git
cd openclaw-docker-agent
python3 scripts/gen-env.py
```

You'll be prompted for:
- Telegram bot token (from [@BotFather](https://t.me/BotFather) → `/newbot`)
- Anthropic API key
- Repo path (auto-detected)

### 2. Start the agent

```bash
make up
make logs    # watch startup
```

### 3. Pair your Telegram account (one time)

1. Open Telegram → find your bot → send `/start`
2. The bot replies with a pairing code (e.g. `BYGFKLR9`)
3. Send that code back to the bot (bot will be silent — expected)
4. Approve on the server:

```bash
docker compose exec openclaw openclaw pairing list
docker compose exec openclaw openclaw pairing approve BYGFKLR9
```

Send any message to the bot — it should respond.

### 4. Enable Claude Pro coding agents (optional but recommended)

```bash
make inject-claude-creds   # run on this machine after logging in with 'claude'
```

Or manually from another machine:
```bash
cat ~/.claude/.credentials.json | base64 -w0   # Linux
cat ~/.claude/.credentials.json | base64        # macOS
# paste the output to the Telegram bot
```

### 5. Enable Ollama cloud models (optional)

```bash
docker compose exec -it ollama ollama signin          # sign in to ollama.com (one time)
docker compose exec ollama ollama pull kimi-k2.5:cloud
docker compose exec ollama ollama pull glm-5:cloud
```

---

## Daily usage

```bash
make up          # Build image and start the agent
make down        # Stop the agent
make restart     # Restart without rebuilding
make logs        # Stream agent logs
make shell       # Bash shell inside the container
make status      # Show container and volume status
make build       # Force rebuild image (no cache)
make reset       # Wipe agent state volume and restart fresh (re-pairing required)
make upgrade     # Upgrade OpenClaw to latest and rebuild
make clean       # Remove containers, images, and volumes
```

---

## Switching the brain model

Switch at any time without rebuilding. The choice persists across restarts.

```bash
# From the server:
docker compose exec openclaw openclaw models set anthropic/claude-sonnet-4-6
docker compose exec openclaw openclaw models set anthropic/claude-haiku-4-5-20251001
docker compose exec openclaw openclaw models set ollama/kimi-k2.5:cloud
docker compose exec openclaw openclaw models set ollama/glm-5:cloud
docker compose exec openclaw openclaw models set ollama/qwen2.5-coder:7b

# Or just tell the bot: "switch to Kimi", "use Claude Haiku", etc.
```

To pull additional local Ollama models:
```bash
docker compose exec ollama ollama pull <model>
docker compose exec openclaw openclaw models set ollama/<model>
```

---

## Moving to a different machine

```bash
git clone https://github.com/leonardobove/openclaw-docker-agent.git
cd openclaw-docker-agent
bash scripts/install-claude-memory.sh   # restore session memory
python3 scripts/gen-env.py              # use the same TELEGRAM_BOT_TOKEN
make up
# Re-pair your Telegram account (step 3 above)
# Re-inject Claude Pro creds: make inject-claude-creds
# Re-sign in to Ollama: docker compose exec -it ollama ollama signin
```

---

## Project structure

```
openclaw-docker-agent/
├── config/
│   ├── openclaw.json          OpenClaw config — providers, gateway, Telegram
│   └── workspace/
│       ├── AGENTS.md          Agent behaviour instructions (seeded into workspace)
│       └── SOUL.md            Agent persona
├── scripts/
│   ├── entrypoint.sh          Container init — renders config, starts agent-manager + gateway
│   ├── agent-manager.py       Background agent spawner (port 3004); claude-pro + ollama backends
│   ├── gen-env.py             Interactive .env generator
│   ├── setup-claude.sh        Install Claude Code CLI on Linux
│   ├── install-claude-memory.sh  Restore session memory on a new machine
│   └── homeserver/            One-time Linux server setup (static IP, SSH, firewall, Tailscale)
├── .claude/
│   └── MEMORY.md              Portable session memory — committed and synced across machines
├── docker-compose.yml         Two services: openclaw-agent + ollama sidecar
├── Dockerfile                 Agent image (node:22-slim)
├── Makefile                   All operational commands
├── .env.example               Environment variable template
└── CLAUDE.md                  Full technical context (auto-loaded by Claude Code)
```

---

## .env variables

| Variable | Required | Description |
|---|---|---|
| `OPENCLAW_VERSION` | No | npm version — `latest` or pin e.g. `2026.2.26` |
| `OPENCLAW_GATEWAY_TOKEN` | Yes | ≥32 char secret. Generate: `openssl rand -hex 32` |
| `TELEGRAM_BOT_TOKEN` | Yes | From `@BotFather` |
| `ANTHROPIC_API_KEY` | Yes | Powers the chatbot brain (Claude Sonnet) |
| `REPO_HOST_PATH` | Yes | Absolute path to this repo on the host |
| `DOCKER_GID` | No | Docker group GID (default 999). Find: `getent group docker \| cut -d: -f3` |
| `OLLAMA_MODEL` | No | Default Ollama model for coding agents (default: `kimi-k2.5:cloud`) |

---

## Security

| Control | Implementation |
|---|---|
| Non-root container | UID 10001, `cap_drop: ALL` |
| Telegram auth | `dmPolicy: pairing` — explicit admin approval per user |
| No ports exposed | Gateway on loopback only — Telegram polls outbound |
| Resource limits | 4 CPU / 4 GB RAM max |

---

## License

MIT — see [LICENSE](LICENSE).
