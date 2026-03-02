# openclaw-docker-agent

Self-hosted autonomous AI coding agent powered by [OpenClaw](https://openclaw.ai).
Controlled from your phone via Telegram. Runs in Docker. No public URL required.

```
Telegram app (phone) ↔ Telegram servers ↔ OpenClaw (Docker) → Ollama (LLM)
```

---

## Prerequisites

- **Docker Desktop** (Windows/macOS) or **Docker + Docker Compose** (Linux)
- A Telegram account
- Git

---

## Quick start — Windows (WSL2) or Linux

> **Windows users:** All commands run inside a **WSL2 terminal** (Ubuntu or Debian).
> Install WSL2 first if you haven't: open PowerShell as Admin and run `wsl --install`, then reboot.
> Install Docker Desktop and enable the WSL2 backend in its settings.

### 1. Install dependencies (WSL2 / Linux only, one time)

```bash
sudo apt update && sudo apt install -y git make python3
```

### 2. Clone the repo

```bash
git clone https://github.com/leonardobove/openclaw-docker-agent.git
cd openclaw-docker-agent
```

### 3. Generate your `.env`

```bash
python3 scripts/gen-env.py
```

This prompts for your Telegram bot token, auto-detects your repo path, and writes a clean `.env`.

> **Need a bot?** Open Telegram → search `@BotFather` → send `/newbot` → follow the prompts → copy the token.

### 4. Start the agent

```bash
make up          # CPU only
make gpu-up      # NVIDIA GPU acceleration (see GPU section below)
```

### 5. Pair your Telegram account (one time)

1. Open Telegram → find your bot → send `/start`
2. The bot replies with a pairing code (e.g. `BYGFKLR9`)
3. Send that code back to the bot
4. Approve it on the server:

```bash
docker compose exec openclaw openclaw pairing list
docker compose exec openclaw openclaw pairing approve BYGFKLR9
```

Send any message to the bot — it should respond.

---

## Daily usage

```bash
make up        # Build image and start the agent
make down      # Stop the agent
make restart   # Restart without rebuilding
make logs      # Stream agent logs
make shell     # Bash shell inside the container
make status    # Show container and volume status
make build     # Force rebuild image (no cache)
make reset     # Wipe agent state volume and restart fresh (re-pairing required)
make upgrade   # Upgrade OpenClaw to latest and rebuild
make clean     # Remove container, image, and volume
```

---

## GPU acceleration (NVIDIA)

Run Ollama with your NVIDIA GPU for much faster inference:

**Windows (Docker Desktop + WSL2):**
1. Install the [NVIDIA driver for WSL2](https://docs.nvidia.com/cuda/wsl-user-guide/)
2. Enable GPU in Docker Desktop → Settings → Resources → GPU
3. Run: `make gpu-up`

**Linux:**
1. Install [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
2. Run: `make gpu-up`

---

## Ollama models

The default model is `qwen2.5-coder:7b`. Pull it on first run:

```bash
docker compose exec ollama ollama pull qwen2.5-coder:7b
```

Switch the bot brain to a different model (no rebuild needed):

```bash
docker compose exec ollama ollama pull llama3.2:3b          # pull first
docker compose exec openclaw openclaw models set ollama/llama3.2:3b
```

List available models:
```bash
docker compose exec ollama ollama list
```

---

## Moving to a different machine

1. Clone the repo on the new machine
2. Run `python3 scripts/gen-env.py` — use the **same `TELEGRAM_BOT_TOKEN`** to keep the same bot
3. Run `make up`
4. Re-pair your Telegram account (send `/start` → code → approve)

The bot identity is determined by the token — same token, same bot. The pairing step takes ~30 seconds.

---

## Project structure

```
openclaw-docker-agent/
├── config/
│   ├── openclaw.json          OpenClaw config — Ollama provider, gateway, Telegram channel
│   └── workspace/
│       ├── AGENTS.md          Agent behaviour instructions (seeded into agent workspace)
│       └── SOUL.md            Agent persona
├── scripts/
│   ├── entrypoint.sh          Container init — seeds config, starts agent-manager + gateway
│   ├── agent-manager.py       Background agent spawner (port 3004)
│   ├── gen-env.py             Interactive .env generator
│   └── homeserver/            Linux home server one-time setup scripts
├── docker-compose.yml         Stack definition (openclaw-agent + ollama)
├── docker-compose.gpu.yml     GPU override for Ollama (NVIDIA)
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
| `REPO_HOST_PATH` | Yes | Absolute path to this repo on the host (e.g. `/home/user/openclaw-docker-agent`) |
| `DOCKER_GID` | No | Docker group GID (default 999). Find yours: `getent group docker \| cut -d: -f3` |
| `OLLAMA_MODEL` | No | Default Ollama model for coding agents (default: `qwen2.5-coder:7b`) |
| `ANTHROPIC_API_KEY` | No | Only needed for Claude Pro coding agents |

---

## Security

| Control | Implementation |
|---|---|
| Non-root container | UID 10001, `cap_drop: ALL` |
| Repo bind-mount | Read/write access to repo only |
| Telegram auth | `dmPolicy: pairing` — explicit admin approval per user |
| No ports exposed | Gateway on loopback only — Telegram polls outbound |
| Resource limits | 4 CPU / 4 GB RAM max |

---

## License

MIT — see [LICENSE](LICENSE).
