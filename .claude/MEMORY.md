# OpenClaw Docker Agent — Session Memory

## Status (last updated: 2026-03-02)
Stack is TWO containers: openclaw-agent + ollama sidecar.
- Brain model: ollama/qwen2.5-coder:7b (pulled, working)
- Telegram bot: @openclaw_docker_agent_bot — connected
- No Caddy, no cloudflared, no public URL
- NO bridge scripts (removed: claude-bridge.py, ollama-bridge.py, groq-bridge.py)
- Repo is portable — works on Linux, Windows/WSL2, macOS

## Architecture
```
Telegram (phone) ↔ Telegram servers ↔ OpenClaw (Docker)
                                            ↓ Anthropic-compatible /v1/messages
                                       Ollama sidecar (port 11434)
                                            └── qwen2.5-coder:7b (default, local)
Coding Agents (agent-manager.py :3004):
   ├── ollama backend: ANTHROPIC_BASE_URL=http://ollama:11434, ANTHROPIC_AUTH_TOKEN=ollama
   └── claude-pro backend: CLAUDE_CODE_OAUTH_TOKEN from ~/.claude/.credentials.json
```

## Credentials
- Telegram bot token: in .env as TELEGRAM_BOT_TOKEN
- Gateway token: in .env as OPENCLAW_GATEWAY_TOKEN
- REPO_HOST_PATH: in .env (absolute host path to repo) — machine-specific, NOT committed
- DOCKER_GID: in .env (docker group GID, default 999) — machine-specific, NOT committed
- ANTHROPIC_API_KEY: optional (only for Claude Pro coding agents with API key auth)

## Key Config Files
- config/openclaw.json: Single Ollama provider; qwen2.5-coder:7b default; 4 models listed
- docker-compose.yml: relative bind mount (.:/home/openclaw/repo); REPO_HOST_PATH from .env
- docker-compose.gpu.yml: NVIDIA GPU override for Ollama (use with make gpu-up)
- scripts/entrypoint.sh: state init, workspace sync, SSH keys, git config, claude-creds symlink, agent-manager, gateway run
- scripts/agent-manager.py: port 3004; /spawn /status /cancel /logging /backend; ollama+claude-pro backends

## Portability (Windows/WSL2)
- REPO_HOST_PATH is now in .env (was hardcoded to /home/leonardo/...)
- Bind mount uses relative path .:/home/openclaw/repo (works everywhere)
- DOCKER_GID is in .env (default 999, Docker Desktop usually fine)
- GPU: make gpu-up uses docker-compose.gpu.yml (NVIDIA, requires Container Toolkit or Docker Desktop GPU)
- Windows setup: WSL2 + Docker Desktop; run all commands from WSL2 terminal
- gen-env.py auto-detects REPO_HOST_PATH and DOCKER_GID

## Ollama Direct Connection (No Bridge)
Ollama ≥ 0.6 serves Anthropic-compatible /v1/messages.
OpenClaw provider: apiKey="ollama", baseUrl="http://ollama:11434", api="anthropic-messages"
No bridge process needed — direct HTTP connection works.
Cloud models (kimi-k2.5:cloud, glm-5:cloud) require newer Ollama than 0.17.x — use local models.

## agent-manager.py — Backend Switching
Backend state persisted to disk:
- ~/.openclaw/agent-backend → "ollama" or "claude-pro"
- ~/.openclaw/agent-model → default Ollama model name

Endpoints:
- POST /spawn: {"task": "...", "backend": "ollama|claude-pro", "model": "..."}
- GET /status: jobs + _config with default_backend/default_model
- DELETE /agent/<id>: cancel
- POST /logging: {"enabled": true/false}
- POST /backend: {"backend": "ollama|claude-pro", "model": "..."}

## Claude Pro Credential Injection
OAuth credentials at ~/.claude/.credentials.json (symlinked to state volume ~/.openclaw/claude-creds/)
1. User: cat ~/.claude/.credentials.json | base64 -w0  (Linux) or base64 (macOS)
2. User pastes to Telegram
3. Bot: echo "<blob>" | base64 -d > ~/.claude/.credentials.json && chmod 600 ...
4. Switch backend: curl -X POST localhost:3004/backend -d '{"backend":"claude-pro"}'

## Known Bugs (do not reintroduce)
1. gateway.bind:"lan" only needed with reverse proxy — omit for Telegram-only.
2. ModelProviderSchema requires BOTH baseUrl AND models array.
3. Ollama provider needs "api":"anthropic-messages" on provider AND each model entry.
4. gateway.reload must be {} not a string.
5. gateway.mode:"local" is required.
6. agents.defaults.sandbox must be {} not a string.
7. State volume caches openclaw.json — force-copy after config changes.
8. openclaw gateway start daemonizes — use gateway run.
9. dmPolicy:"pairing" requires admin approval via `openclaw pairing approve <CODE>`.
10. Ollama ≥ 0.6 required for /v1/messages endpoint.
11. Cloud models (kimi-k2.5:cloud, glm-5:cloud) need Ollama internet access AND recent version.
    Ollama 0.17.x does NOT support :cloud models. Use local models instead.
12. REPO_HOST_PATH must be in .env (absolute host path). The cp command in CLAUDE.md
    that says `cp /etc/openclaw/openclaw.json` copies the baked IMAGE config, not the
    edited repo file. To copy the edited file: `cp /home/openclaw/repo/config/openclaw.json ...`

## Telegram Pairing (TWO-STEP)
1. User sends /start to bot → bot sends pairing code
2. User sends code back to bot (bot says nothing)
3. Admin MUST run: `docker compose exec openclaw openclaw pairing approve <CODE>`
4. Run: `docker compose exec openclaw openclaw pairing list` to see pending

# currentDate
Today's date is 2026-03-02.
