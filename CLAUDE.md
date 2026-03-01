# OpenClaw Docker Agent — Claude Code Session Context

This file is auto-loaded by Claude Code. It gives you full context to continue
work on this project from any machine.

---

## What This Project Is

A containerized autonomous AI coding agent. Stack:
- **OpenClaw** — Node.js AI agent framework (npm), gateway on port 18789
- **Caddy** — HTTP reverse proxy with basicauth + rate limiting (port 8080)
- **cloudflared** — Exposes the agent to your phone via trycloudflare.com

LLM: **Google Gemini 2.0 Flash** (free, 1M context, no credit card)

---

## Deployment Machine

- Linux home server behind NAT router (not a VPS with direct public IP)
- Username: `leonardo`
- Repo: `/home/leonardo/openclaw-docker-agent`
- Docker is running here. Windows PC cannot run Docker (employer restriction).

---

## Current Status

Docker stack is UP and healthy. `make up` works.

**Remaining step**: User needs a free Gemini API key, then regenerate `.env`:
```bash
python3 scripts/gen-env.py   # prompts for GEMINI_API_KEY + Caddy password
docker compose down -v       # wipe old state volume
make up                      # start fresh
make url                     # get phone URL
```

Get free Gemini API key at: https://aistudio.google.com/apikey

---

## Credentials

| What | Value |
|------|-------|
| Web UI user | `agent` |
| Web UI password | `8L1Cy2HV5rWawHINVvze%1X#` |
| Gateway token | in `.env` on Linux (auto-generated) |
| Gemini API key | user must get from Google AI Studio |

---

## Key Commands

```bash
make up          # Build + start all containers, print tunnel URL
make url         # Print current phone URL (changes on each restart)
make down        # Stop all containers
make restart     # down + up
make reset       # Wipe state volume + restart (use after config changes)
make shell       # Shell into openclaw-agent container
make upgrade     # Rebuild with latest OpenClaw npm version
make status      # Show container health
docker logs -f openclaw-agent    # Stream agent logs
docker logs -f openclaw-cloudflared  # Stream tunnel logs
```

---

## Config Files

| File | Purpose |
|------|---------|
| `config/openclaw.json` | OpenClaw config — gemini provider, gateway settings |
| `Caddyfile` | Caddy proxy — basicauth, rate limit, reverse proxy |
| `docker-compose.yml` | All three services |
| `caddy/Dockerfile` | Custom Caddy build with caddy-ratelimit module |
| `scripts/entrypoint.sh` | Container startup — runs `openclaw gateway run` |
| `scripts/gen-env.py` | Interactive .env generator — always use this, not heredoc |

---

## Known Bugs Fixed (do not reintroduce)

1. `gateway.bind` — not a valid field, removed
2. `gateway.reload` — must be object `{}` not string
3. `gateway.mode: "local"` — **required** or gateway refuses to start
4. `env.shellEnv` — must be object `{}` not boolean
5. `agents.defaults.sandbox` — must be object `{}` not string
6. Model entries need both `"id"` AND `"name"` fields
7. `openclaw gateway start` — daemonizes and exits (wrong for Docker). Use `gateway run`
8. Caddy `environment:` block in compose — interpolates `$` in bcrypt hash. Use only `env_file:`
9. Heredoc with indented `EOF` — writes literal `EOF` into .env. Use `gen-env.py`
10. `caddy list-modules | grep rate_limit` (underscore) — not `ratelimit`

---

## Architecture Decisions

- **Ollama dropped**: Windows work PC could not tunnel to Linux home server.
  Corporate network blocked cloudflared quick tunnels. SSH to Linux blocked by home NAT.
  Switched to Google Gemini 2.0 Flash (free cloud API).
- **No Tailscale on Windows**: employer-restricted, requires kernel driver.
- **trycloudflare.com**: used for phone access — URL changes on every restart.
  Always run `make url` after `make up`.
- **HTTP-only Caddy**: Cloudflare handles TLS at the edge.
- **State volume**: `openclaw-state` — delete with `docker compose down -v` when config changes,
  so fresh config gets copied from image on next start.

---

## .env Variables Required

```
OPENCLAW_VERSION=latest
OPENCLAW_GATEWAY_TOKEN=<64 hex chars>
GEMINI_API_KEY=<from aistudio.google.com>
CADDY_AUTH_USER=agent
CADDY_AUTH_HASH=<bcrypt hash>
```

Generate with: `python3 scripts/gen-env.py`
