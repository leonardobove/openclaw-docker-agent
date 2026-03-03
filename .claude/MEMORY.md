# OpenClaw Docker Agent — Session Memory

## Status (last updated: 2026-03-03)
Stack is ONE container: openclaw-agent only. Ollama runs on Windows (native, AMD GPU).
- Brain model: ollama/qwen2.5-coder:7b (on Windows Ollama)
- Telegram bot: @openclaw_docker_agent_bot — connected
- No Caddy, no cloudflared, no public URL
- NO bridge scripts, NO Ollama sidecar on Linux
- OLLAMA_HOST env var points to Windows machine LAN URL

## Architecture
```
Telegram (phone) ↔ Telegram servers ↔ OpenClaw (Docker, Linux)
                                            ↓ Anthropic-compatible /v1/messages over LAN
                                       Ollama (native Windows, AMD GPU, port 11434)
                                            └── qwen2.5-coder:7b (default, local)
Coding Agents (agent-manager.py :3004):
   ├── ollama backend: ANTHROPIC_BASE_URL=<OLLAMA_HOST>, ANTHROPIC_AUTH_TOKEN=ollama
   └── claude-pro backend: CLAUDE_CODE_OAUTH_TOKEN from ~/.claude/.credentials.json
```

## Credentials / .env Variables
- TELEGRAM_BOT_TOKEN: in .env
- OPENCLAW_GATEWAY_TOKEN: in .env (≥32 chars)
- REPO_HOST_PATH: in .env (absolute host path to repo on Linux)
- DOCKER_GID: in .env (docker group GID, default 999)
- OLLAMA_HOST: in .env — full URL to Windows Ollama (e.g. http://192.168.1.100:11434) — REQUIRED
- OLLAMA_MODEL: in .env (default coding agent model, default qwen2.5-coder:7b)
- ANTHROPIC_API_KEY: optional (Claude Pro agents via API key)

## Key Config Files
- config/openclaw.json: Single Ollama provider; baseUrl="${OLLAMA_HOST}"; 4 models listed
- docker-compose.yml: single openclaw-agent service; OLLAMA_HOST from .env
- scripts/entrypoint.sh: state init, workspace sync, SSH keys, git config, claude-creds symlink, agent-manager, gateway run
- scripts/agent-manager.py: port 3004; /spawn /status /cancel /logging /backend; ollama+claude-pro backends
- scripts/windows/setup-ollama.ps1: run on Windows (Admin PS) to configure Ollama for LAN + AMD GPU
- scripts/network/test-ollama.sh: verify Linux→Windows Ollama connectivity (make test-ollama)

## Windows Ollama Setup
Run scripts/windows/setup-ollama.ps1 in PowerShell as Admin:
- Sets OLLAMA_HOST=0.0.0.0:11434 system-wide
- Adds Windows Firewall rule (TCP 11434, Private)
- Detects AMD GPU
- Pulls qwen2.5-coder:7b
- Prints LAN IPs to use in Linux .env
MUST restart Ollama after running (tray icon → Quit → relaunch).

## Ollama Direct Connection (No Bridge)
Ollama ≥ 0.6 serves Anthropic-compatible /v1/messages.
OpenClaw provider: apiKey="ollama", baseUrl="${OLLAMA_HOST}", api="anthropic-messages"
No bridge process needed.
Cloud models (kimi-k2.5:cloud, glm-5:cloud) require Windows machine to reach ollama.com.

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
11. OLLAMA_HOST must be full URL (http://ip:11434) — no trailing slash. Set in .env.
12. Windows Ollama must restart after setting OLLAMA_HOST env var — right-click tray → Quit → relaunch.
13. REPO_HOST_PATH must be in .env (absolute host path). To copy edited config: `cp /home/openclaw/repo/config/openclaw.json ...`

## Telegram Pairing (TWO-STEP)
1. User sends /start to bot → bot sends pairing code
2. User sends code back to bot (bot says nothing)
3. Admin MUST run: `docker compose exec openclaw openclaw pairing approve <CODE>`
4. Run: `docker compose exec openclaw openclaw pairing list` to see pending

# currentDate
Today's date is 2026-03-03.
