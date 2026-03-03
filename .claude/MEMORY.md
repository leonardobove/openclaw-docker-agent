# OpenClaw Docker Agent — Session Memory

## Status (last updated: 2026-03-03)
Stack is TWO containers: openclaw-agent + ollama sidecar.
- Brain model: ollama/kimi-k2.5:cloud (user-selected, persists across restarts)
- Anthropic API (claude-sonnet-4-6) available as alternative brain
- Ollama sidecar: cloud models (kimi-k2.5:cloud, glm-5:cloud) + local qwen2.5-coder:7b
- Coding agents: claude-pro (OAuth, default) + ollama backend
- Telegram bot: @openclaw_docker_agent_bot — connected, user leobove paired
- No Windows scripts, no LAN setup, no bridge scripts

## Architecture
```
Telegram (phone) ↔ Telegram servers ↔ OpenClaw (Docker)
                                          Brain: kimi-k2.5:cloud (via Ollama sidecar)
                                            OR: claude-sonnet-4-6 (Anthropic API)
                                            ↓ http://ollama:11434/v1/messages
                                       Ollama sidecar (Docker, port 11434)
                                            ├── kimi-k2.5:cloud  (cloud, signed in)
                                            ├── glm-5:cloud      (cloud, signed in)
                                            └── qwen2.5-coder:7b (local, pulled)
Coding Agents (agent-manager.py :3004):
   ├── claude-pro backend: reads ~/.claude/.credentials.json, auto-refreshes token
   └── ollama backend: ANTHROPIC_BASE_URL=http://ollama:11434, ANTHROPIC_AUTH_TOKEN=ollama
```

## Credentials / .env Variables
- TELEGRAM_BOT_TOKEN: in .env
- OPENCLAW_GATEWAY_TOKEN: in .env (≥32 chars)
- ANTHROPIC_API_KEY: in .env — REQUIRED (brain fallback + potential coding agents)
- REPO_HOST_PATH: in .env (absolute host path to repo on Linux)
- DOCKER_GID: in .env (docker group GID, default 999)
- OLLAMA_MODEL: in .env (default Ollama coding agent model, kimi-k2.5:cloud)

## Key Config Files
- config/openclaw.json: two providers — anthropic (claude-sonnet-4-6) + ollama (cloud + local models)
  Default brain: anthropic/claude-sonnet-4-6 in template; restored from state on restart
- docker-compose.yml: two services (openclaw-agent + ollama); ollama-data volume
- scripts/entrypoint.sh: renders openclaw.json via sed, restores persisted brain model,
  patches models.json Ollama baseUrl (Python JSON), syncs AGENTS.md, starts agent-manager + gateway
- scripts/agent-manager.py: port 3004; /spawn /status /cancel /logging /backend
- Makefile: inject-claude-creds target uses docker compose exec -T (port 3004 is inside container only)

## Brain Model Persistence
entrypoint.sh saves the primary model from state openclaw.json BEFORE rendering the template,
then re-applies it if it differs from the template default (anthropic/claude-sonnet-4-6).
So `openclaw models set <model>` persists across restarts automatically.
Bot can switch its own brain: `openclaw models set ollama/kimi-k2.5:cloud` then restart.

## Ollama Cloud Models
Cloud models (kimi-k2.5:cloud, glm-5:cloud) require:
1. ollama signin (run once: `docker compose exec -it ollama ollama signin`)
2. ollama pull kimi-k2.5:cloud (just downloads a 340B manifest — pointer to cloud)
Credentials stored in ollama-data volume (/root/.ollama/) — persists across restarts.
Lost only on `docker compose down -v` or `make reset`/`make clean`.
After make reset: re-run ollama signin + ollama pull kimi-k2.5:cloud + ollama pull glm-5:cloud.

## Config Rendering (entrypoint.sh)
entrypoint.sh uses sed to substitute env vars in openclaw.json EVERY start:
- ${ANTHROPIC_API_KEY} → actual API key
- ${OPENCLAW_GATEWAY_TOKEN} → token
- ${TELEGRAM_BOT_TOKEN} → bot token
- ${OPENCLAW_HOME} → /home/openclaw/.openclaw
Then restores persisted primary model if different from template default.

## agent-manager.py — Backend Switching
Backend state persisted to disk:
- ~/.openclaw/agent-backend → "ollama" or "claude-pro"
- ~/.openclaw/agent-model → default Ollama model name

Endpoints (all via docker compose exec -T openclaw curl ... from host):
- POST /spawn: {"task": "...", "backend": "ollama|claude-pro", "model": "..."}
- GET /status: jobs + _config with default_backend/default_model
- DELETE /agent/<id>: cancel
- POST /logging: {"enabled": true/false}
- POST /backend: {"backend": "ollama|claude-pro", "model": "..."}

## Claude Pro Credential Injection
OAuth credentials at ~/.claude/.credentials.json (symlinked to state volume ~/.openclaw/claude-creds/)
- From Linux host: make inject-claude-creds
- Manual: base64-encode credentials, paste to Telegram, bot decodes and writes file
Access token expires ~8h; refresh token is long-lived (months). Claude Code handles refresh automatically.
agent-manager does NOT inject CLAUDE_CODE_OAUTH_TOKEN — lets Claude Code read file + auto-refresh.

## Known Bugs (do not reintroduce)
1. gateway.bind:"lan" only needed with reverse proxy — omit for Telegram-only.
2. ModelProviderSchema requires BOTH baseUrl AND models array for every provider.
3. Ollama provider needs "api":"anthropic-messages" on provider AND each model entry.
4. gateway.reload must be {} not a string.
5. gateway.mode:"local" is required.
6. agents.defaults.sandbox must be {} not a string.
7. openclaw gateway start daemonizes — use gateway run.
8. dmPolicy:"pairing" requires admin approval via `openclaw pairing approve <CODE>`.
9. Ollama ≥ 0.6 required for /v1/messages endpoint.
10. models.json (written by 'openclaw models set') caches provider state (baseUrl, models).
    entrypoint patches ollama baseUrl via Python JSON (handles any URL format).
11. AGENTS.md must be copied from repo bind-mount (entrypoint does this). Never use sessions_spawn.
12. Claude Pro OAuth: agent-manager clears API env vars, lets claude read .credentials.json for auto-refresh.
13. Ollama cloud models need `ollama signin` + `ollama pull <model>:cloud` in the ollama container.
    Docker Ollama (0.17.5) supports cloud models after signin — only 340B manifest downloaded.
14. Brain model choice persists: entrypoint saves/restores primary from state openclaw.json.

## Telegram Pairing (TWO-STEP)
1. User sends /start to bot → bot sends pairing code
2. User sends code back to bot (bot says nothing)
3. Admin MUST run: `docker compose exec openclaw openclaw pairing approve <CODE>`
4. Run: `docker compose exec openclaw openclaw pairing list` to see pending

# currentDate
Today's date is 2026-03-03.
