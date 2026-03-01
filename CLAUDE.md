# OpenClaw Docker Agent — Claude Code Session Context

This file is auto-loaded by Claude Code. It gives you full context to continue
work on this project from any machine.

---

## What This Project Is

A containerized autonomous AI coding agent controlled via Telegram.
Single container, no public URL needed.

- **OpenClaw** — Node.js AI agent framework (npm), gateway on port 18789 (loopback only)
- **Telegram** — smartphone interface (DM the bot, pairing-code auth)
- **LLM** — Anthropic Claude Sonnet 4.6 (primary), Claude Haiku 4.5 (fallback)

---

## Deployment Machine

- Linux home server behind NAT router (not a VPS with direct public IP)
- Username: `leonardo`
- Repo: `/home/leonardo/openclaw-docker-agent`
- Docker is running here.

---

## Current Status

Stack is a single container. `make up` builds and starts it.

**First-time Telegram pairing (TWO steps):**
1. Open Telegram → find your bot → send `/start`
2. Bot replies with a pairing code
3. Send the code back to the bot
4. On the server, approve it: `docker compose exec openclaw openclaw pairing approve <CODE>`

Without step 4 the user is permanently blocked — the bot stays silent after receiving the code.
List pending requests: `docker compose exec openclaw openclaw pairing list`

---

## Credentials

| What | Value |
|------|-------|
| Telegram bot token | in `.env` as `TELEGRAM_BOT_TOKEN` |
| Anthropic API key | in `.env` as `ANTHROPIC_API_KEY` |
| Gateway token | in `.env` as `OPENCLAW_GATEWAY_TOKEN` (internal only) |

---

## Key Commands

```bash
make up          # Build + start agent
make down        # Stop agent
make restart     # Restart agent
make reset       # Wipe state volume + restart (use after config changes)
make logs        # Stream agent logs (watch for Telegram connect + pairing code)
make shell       # Shell into the container
make upgrade     # Rebuild with latest OpenClaw npm version
make status      # Show container health

docker logs -f openclaw-agent   # Alias for make logs
```

---

## Config Files

| File | Purpose |
|------|---------|
| `config/openclaw.json` | OpenClaw config — Anthropic provider, Telegram channel, gateway |
| `docker-compose.yml` | Single-service stack |
| `scripts/entrypoint.sh` | Container startup — runs `openclaw gateway run` |
| `scripts/gen-env.py` | Interactive .env generator |

---

## Known Issues / Do Not Reintroduce

1. `gateway.bind: "lan"` is only needed when a reverse proxy (Caddy) or other container
   needs to reach the gateway. With Telegram only, omit it (defaults to loopback).
2. `gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback` — only needed with `bind: lan`.
3. `ModelProviderSchema` requires both `baseUrl` (string) AND `models` (array) for every provider.
4. Anthropic provider must have `"api": "anthropic-messages"` on both provider and each model entry.
5. `openclaw gateway start` daemonizes and exits (wrong for Docker). Use `gateway run`.
6. `gateway.reload` must be `{}` not a string.
7. `gateway.mode: "local"` is required or gateway refuses to start.
8. `agents.defaults.sandbox` must be `{}` not a string.
9. State volume (`openclaw-state`) caches `openclaw.json`. After config changes, run
   `docker compose down -v` before `make up` so the fresh config is copied from the image.
10. trycloudflare.com rate-limits IPs that create too many tunnels rapidly (error 1045).
    The old cloudflared approach has been removed — Telegram has no such issue.
11. `dmPolicy: "pairing"` requires explicit admin approval via `openclaw pairing approve <CODE>`.
    The bot does NOT auto-admit users after they send the code back.

---

## .env Variables Required

```
OPENCLAW_VERSION=latest
OPENCLAW_GATEWAY_TOKEN=<64 hex chars>
TELEGRAM_BOT_TOKEN=<from @BotFather>
ANTHROPIC_API_KEY=<from console.anthropic.com>
```

Generate with: `python3 scripts/gen-env.py`

---

## Switching LLMs

### Claude → Gemini (free)

1. Add `GEMINI_API_KEY=<key>` to `.env` (get free key at aistudio.google.com/apikey)
2. Edit `config/openclaw.json` — replace provider + agent model:
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
   }
   ```
   Update `agents.defaults.model.primary` → `"google/gemini-2.0-flash"`.
3. Rebuild: `make build && docker compose up -d`
4. Verify: `make logs | grep "agent model"` → should show `google/gemini-2.0-flash`

### Gemini → Claude

Reverse the above. Provider key is `anthropic`, requires `"api": "anthropic-messages"` on
the provider AND on each model entry, plus `baseUrl: "https://api.anthropic.com"`.

---

## Architecture

```
Telegram app (phone)
       ↕  (HTTPS, Telegram's servers)
OpenClaw agent (Docker container)
       ↓  (HTTPS)
Anthropic Claude API
```

No ports exposed to the host. No public URL. No reverse proxy.
The agent polls Telegram's bot API outbound — nothing needs to reach in.
