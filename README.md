# openclaw-docker-agent

Self-hosted autonomous AI coding agent powered by [OpenClaw](https://openclaw.ai).
Controlled from your phone via Telegram. Runs in a single Docker container. No public URL required.

```
Telegram app (phone) ↔ Telegram servers ↔ OpenClaw (Docker) → Anthropic Claude API
```

---

## Prerequisites

- Linux machine with Docker and Docker Compose installed
- A Telegram account
- An [Anthropic API key](https://console.anthropic.com) (Claude)
- Git

If you need to set up Docker on a fresh Linux machine, run:

```bash
bash scripts/homeserver/setup.sh
```

This handles static IP, SSH hardening, firewall, Tailscale, and Docker in one go.

---

## Quick start

### 1. Clone the repo

```bash
git clone https://github.com/YOUR_USERNAME/openclaw-docker-agent.git
cd openclaw-docker-agent
```

### 2. Create a Telegram bot

Open Telegram → search for `@BotFather` → send `/newbot` → follow the prompts.
Copy the bot token (looks like `1234567890:AAH-...`).

### 3. Generate your `.env`

```bash
python3 scripts/gen-env.py
```

This prompts for your Telegram bot token and Anthropic API key, and writes a clean `.env`.

### 4. Start the agent

```bash
make up
```

### 5. Pair your Telegram account (one time)

1. Open Telegram → find your bot → send `/start`
2. The bot replies with a pairing code (e.g. `BYGFKLR9`)
3. Send that code back to the bot
4. On the server, approve it:

```bash
docker compose exec openclaw openclaw pairing approve <CODE>
```

You can list pending requests with:

```bash
docker compose exec openclaw openclaw pairing list
```

That's it — send a message to your bot and Claude responds.

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
make reset     # Wipe agent state volume and restart fresh
make upgrade   # Upgrade OpenClaw to latest and rebuild
make clean     # Remove container, image, and volume
```

---

## Switching the LLM

### Switch to Google Gemini (free)

Get a free API key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey).

1. Add to `.env`:
   ```
   GEMINI_API_KEY=AIzaSy...
   ```

2. Edit `config/openclaw.json` — replace the `models` block:
   ```json
   "models": {
     "providers": {
       "google": {
         "apiKey": "${GEMINI_API_KEY}",
         "baseUrl": "https://generativelanguage.googleapis.com/v1beta",
         "models": [
           { "id": "gemini-2.0-flash", "name": "Gemini 2.0 Flash", "contextWindow": 1000000, "maxTokens": 8192 },
           { "id": "gemini-1.5-flash", "name": "Gemini 1.5 Flash", "contextWindow": 1000000, "maxTokens": 8192 }
         ]
       }
     }
   },
   "agents": {
     "defaults": {
       "model": {
         "primary": "google/gemini-2.0-flash",
         "fallbacks": ["google/gemini-1.5-flash"]
       }
     }
   }
   ```

3. Rebuild and restart:
   ```bash
   make build && docker compose up -d
   ```

4. Verify — check the logs:
   ```bash
   make logs | grep "agent model"
   # Expected: [gateway] agent model: google/gemini-2.0-flash
   ```
   Or ask the bot: *"what model are you?"*

### Switch back to Anthropic Claude

Default config uses `anthropic/claude-sonnet-4-6`. It's already in `config/openclaw.json`.
Make sure `ANTHROPIC_API_KEY` is set in `.env`, rebuild if you changed providers.

---

## Project structure

```
openclaw-docker-agent/
├── config/
│   ├── openclaw.json          OpenClaw config — model provider, gateway, Telegram channel
│   └── workspace/
│       ├── AGENTS.md          Agent behaviour instructions (seeded into agent workspace)
│       └── SOUL.md            Agent persona
├── scripts/
│   ├── entrypoint.sh          Container init — seeds config on first run, starts gateway
│   ├── gen-env.py             Interactive .env generator
│   ├── setup-claude.sh        Install Claude Code CLI and open a session in this repo
│   └── homeserver/            Linux home server one-time setup scripts
│       ├── setup.sh           Master script — runs all steps below
│       ├── 01-static-ip.sh    Assign static LAN IP via netplan
│       ├── 02-ssh-hardening.sh  Key-only SSH + fail2ban
│       ├── 03-firewall.sh     ufw rules
│       └── 04-tailscale.sh    Tailscale for remote SSH
├── docker-compose.yml         Single-container stack
├── Dockerfile                 OpenClaw agent image (node:22-slim)
├── Makefile                   All operational commands
├── .env.example               Environment variable template
└── .gitignore
```

---

## .env variables

| Variable | Required | Description |
|---|---|---|
| `OPENCLAW_VERSION` | No | npm version — `latest` or pin e.g. `2026.2.26` |
| `OPENCLAW_GATEWAY_TOKEN` | Yes | ≥32 char secret. Generate: `openssl rand -hex 32` |
| `TELEGRAM_BOT_TOKEN` | Yes | From `@BotFather` |
| `ANTHROPIC_API_KEY` | Yes* | From [console.anthropic.com](https://console.anthropic.com) |
| `GEMINI_API_KEY` | Yes* | From [aistudio.google.com](https://aistudio.google.com/apikey) — free |

*One LLM API key required (Anthropic or Google).

---

## Security

| Control | Implementation |
|---|---|
| Non-root container | UID 10001, `cap_drop: ALL` |
| No host filesystem | Named Docker volume only |
| No Docker socket | Never mounted |
| No ports exposed | Gateway on loopback only — Telegram polls outbound |
| Telegram auth | `dmPolicy: pairing` — explicit admin approval per user |
| Resource limits | 2 CPU / 2 GB RAM max |

---

## License

MIT — see [LICENSE](LICENSE).
