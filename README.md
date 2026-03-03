# openclaw-docker-agent

Self-hosted autonomous AI coding agent powered by [OpenClaw](https://openclaw.ai).
Controlled from your phone via Telegram. Runs in Docker on Linux. AI brain on Windows (AMD GPU).

```
Telegram app (phone) ↔ Telegram servers ↔ OpenClaw (Docker, Linux) → Ollama (Windows, LAN, AMD GPU)
```

---

## Architecture

| Machine | Role |
|---|---|
| **Linux** | Runs the `openclaw-agent` Docker container (Telegram bot, agent manager, self-edit) |
| **Windows** | Runs Ollama natively with AMD GPU — exposes LLM API on LAN port 11434 |

The two machines communicate over your local network. No cloud services, no public URLs required.

---

## Prerequisites

- **Linux machine** with Docker + Docker Compose
- **Windows machine** with an AMD GPU (RX 6000+ or RX 7000+ recommended)
- Both machines on the same LAN
- A Telegram account + bot token from [@BotFather](https://t.me/BotFather)

---

## Step 1 — Set up Ollama on Windows

Run the setup script **once** on the Windows machine (PowerShell as Administrator):

```powershell
# If you haven't installed Ollama yet, download from: https://ollama.com/download/windows

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\setup-ollama.ps1
```

This script:
- Configures Ollama to listen on all interfaces (`0.0.0.0:11434`)
- Adds a Windows Firewall rule (TCP 11434, Private network)
- Detects your AMD GPU
- Pulls `qwen2.5-coder:7b`
- Prints the LAN IP you'll need in the next step

Then **restart Ollama** (right-click tray icon → Quit → relaunch).

---

## Step 2 — Set up the Linux machine

### Install dependencies (one time)

```bash
sudo apt update && sudo apt install -y git make python3 docker.io docker-compose-plugin
sudo usermod -aG docker $USER   # log out and back in after this
```

### Clone the repo

```bash
git clone https://github.com/leonardobove/openclaw-docker-agent.git
cd openclaw-docker-agent
```

### Generate `.env`

```bash
python3 scripts/gen-env.py
```

You'll be prompted for:
- Your Telegram bot token (from [@BotFather](https://t.me/BotFather) → `/newbot`)
- Your repo path (auto-detected)
- **`OLLAMA_HOST`** — the Windows machine's URL, e.g. `http://192.168.1.100:11434`

### Verify connectivity to Windows Ollama

```bash
make test-ollama
```

### Start the agent

```bash
make up
make logs    # watch startup
```

---

## Step 3 — Pair your Telegram account (one time)

1. Open Telegram → find your bot → send `/start`
2. The bot replies with a pairing code (e.g. `BYGFKLR9`)
3. Send that code back to the bot (bot will be silent — this is expected)
4. Approve it on the Linux server:

```bash
docker compose exec openclaw openclaw pairing list
docker compose exec openclaw openclaw pairing approve BYGFKLR9
```

Send any message to the bot — it should respond.

---

## Step 4 — Enable Claude Pro coding agents (optional)

To spawn Claude Code sessions using your Claude Pro subscription:

```bash
# On your local machine (where you're logged into Claude Code):
cat ~/.claude/.credentials.json | base64 -w0   # Linux
cat ~/.claude/.credentials.json | base64        # macOS
```

Paste the output to the Telegram bot. The bot saves the credentials and can switch
to the `claude-pro` backend for coding tasks.

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
make clean       # Remove container, image, and volume
make test-ollama # Verify connectivity to Windows Ollama
```

---

## Ollama models

Switch the bot's brain model at any time without rebuilding.
Models must be pulled on the **Windows machine** first (local models only):

```powershell
# On Windows:
ollama pull qwen2.5-coder:7b    # default (already pulled by setup script)
ollama pull qwen3:30b-a3b       # Qwen3 MoE — good reasoning
ollama list                     # show pulled models
# Cloud models need no pull — they stream from ollama.com:
# kimi-k2.5:cloud, glm-5:cloud
```

Then switch from the Linux machine:

```bash
docker compose exec openclaw openclaw models set ollama/qwen3:30b-a3b
docker compose exec openclaw openclaw models set ollama/kimi-k2.5:cloud
docker compose exec openclaw openclaw models set ollama/qwen2.5-coder:7b
```

Or just tell the bot: *"switch to Qwen3"*, *"use Kimi"*, etc.

---

## Moving to a different machine

1. Clone the repo on the new machine
2. Install Claude Code memory (preserves session context across machines):
   ```bash
   bash scripts/install-claude-memory.sh
   ```
3. Run `python3 scripts/gen-env.py` — use the **same `TELEGRAM_BOT_TOKEN`** to keep the same bot
4. Run `make up`
5. Re-pair your Telegram account

---

## Project structure

```
openclaw-docker-agent/
├── config/
│   ├── openclaw.json          OpenClaw config — Ollama provider, gateway, Telegram
│   └── workspace/
│       ├── AGENTS.md          Agent behaviour instructions (seeded into workspace)
│       └── SOUL.md            Agent persona
├── scripts/
│   ├── entrypoint.sh          Container init — seeds config, starts agent-manager + gateway
│   ├── agent-manager.py       Background agent spawner (port 3004); Ollama + Claude Pro backends
│   ├── gen-env.py             Interactive .env generator
│   ├── setup-claude.sh        Install Claude Code CLI on Linux
│   ├── install-claude-memory.sh  Sync memory file for cross-machine continuity
│   ├── windows/
│   │   └── setup-ollama.ps1   Configure Ollama for LAN + AMD GPU (run on Windows)
│   ├── network/
│   │   └── test-ollama.sh     Test Linux → Windows Ollama connectivity
│   └── homeserver/            One-time Linux server setup (static IP, SSH, firewall, Tailscale)
├── docker-compose.yml         Single openclaw-agent service
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
| `REPO_HOST_PATH` | Yes | Absolute path to this repo on the Linux host |
| `DOCKER_GID` | No | Docker group GID (default 999). Find: `getent group docker \| cut -d: -f3` |
| `OLLAMA_HOST` | Yes | Full URL to Windows Ollama, e.g. `http://192.168.1.100:11434` |
| `OLLAMA_MODEL` | No | Default model for coding agents (default: `qwen2.5-coder:7b`) |
| `ANTHROPIC_API_KEY` | No | Only for Claude Pro coding agents (API key auth) |

---

## Security

| Control | Implementation |
|---|---|
| Non-root container | UID 10001, `cap_drop: ALL` |
| Repo bind-mount | Read/write access to repo only |
| Telegram auth | `dmPolicy: pairing` — explicit admin approval per user |
| No ports exposed | Gateway on loopback only — Telegram polls outbound |
| Ollama LAN only | Windows Firewall restricts port 11434 to Private network profile |
| Resource limits | 4 CPU / 4 GB RAM max |

---

## License

MIT — see [LICENSE](LICENSE).
