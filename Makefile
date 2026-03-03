.PHONY: help up down restart logs shell status build reset upgrade clean setup-homeserver test-ollama inject-claude-creds

COMPOSE  := docker compose
SERVICE  := openclaw
AGENT    := openclaw-agent

# ─────────────────────────────────────────────────────────────────────────────
help:
	@printf '\033[1mOpenClaw Agent — Makefile\033[0m\n\n'
	@printf '  \033[36m%-22s\033[0m %s\n' "up"               "Build image and start the agent"
	@printf '  \033[36m%-22s\033[0m %s\n' "down"             "Stop and remove the container"
	@printf '  \033[36m%-22s\033[0m %s\n' "restart"          "Restart the agent container"
	@printf '  \033[36m%-22s\033[0m %s\n' "logs"             "Stream agent logs"
	@printf '  \033[36m%-22s\033[0m %s\n' "shell"            "Open bash shell in agent container"
	@printf '  \033[36m%-22s\033[0m %s\n' "status"           "Show container and volume status"
	@printf '  \033[36m%-22s\033[0m %s\n' "build"            "Force rebuild image (no cache)"
	@printf '  \033[36m%-22s\033[0m %s\n' "reset"            "Wipe agent state volume and restart clean"
	@printf '  \033[36m%-22s\033[0m %s\n' "upgrade"          "Upgrade OpenClaw to latest and rebuild"
	@printf '  \033[36m%-22s\033[0m %s\n' "clean"            "Remove container, image, and volume"
	@printf '  \033[36m%-22s\033[0m %s\n' "test-ollama"      "Test connectivity to Windows Ollama"
	@printf '  \033[36m%-22s\033[0m %s\n' "inject-claude-creds" "Copy local Claude Pro OAuth creds into container"
	@printf '\n'
	@printf '\033[1m  Server setup (run on Linux server):\033[0m\n'
	@printf '  \033[36m%-22s\033[0m %s\n' "setup-homeserver" "Full home server setup (static IP, SSH, firewall, Tailscale, Docker)"
	@printf '\n'
	@printf '  Telegram: send /start to your bot, follow pairing prompt.\n\n'

# ─────────────────────────────────────────────────────────────────────────────
up: .env
	$(COMPOSE) up -d --build
	@echo ""
	@echo "Agent started. Stream logs with:  make logs"
	@echo "Telegram: open your bot and send /start to pair."
	@echo ""

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart $(SERVICE)

# ─────────────────────────────────────────────────────────────────────────────
logs:
	$(COMPOSE) logs -f --tail=100 $(SERVICE)

shell:
	$(COMPOSE) exec -it $(SERVICE) bash

status:
	@echo "=== Container ==="
	@$(COMPOSE) ps
	@echo ""
	@echo "=== Volume ==="
	@docker volume ls --filter "name=openclaw"

build:
	$(COMPOSE) build --no-cache

# ─────────────────────────────────────────────────────────────────────────────
reset: .env
	@echo "WARNING: This will permanently delete all agent state (workspace, sessions, memory)."
	@printf "Type 'yes' to confirm: "; read confirm; [ "$$confirm" = "yes" ] || (echo "Aborted."; exit 1)
	$(COMPOSE) down -v
	$(COMPOSE) up -d --build
	@echo ""
	@echo "Agent reset. Stream logs with:  make logs"

upgrade: .env
	$(COMPOSE) down
	$(COMPOSE) build --no-cache --build-arg OPENCLAW_VERSION=latest
	$(COMPOSE) up -d
	@echo "OpenClaw upgraded to latest."

clean:
	@echo "WARNING: Removes the container, image, and state volume."
	@printf "Type 'yes' to confirm: "; read confirm; [ "$$confirm" = "yes" ] || (echo "Aborted."; exit 1)
	$(COMPOSE) down -v --rmi all --remove-orphans

# ── Network ───────────────────────────────────────────────────────────────────
test-ollama:
	bash scripts/network/test-ollama.sh

# ── Claude Pro credentials ─────────────────────────────────────────────────────
inject-claude-creds:
	@test -f ~/.claude/.credentials.json \
	  || (echo "ERROR: ~/.claude/.credentials.json not found. Run 'claude' first to log in."; exit 1)
	@echo "Injecting Claude Pro credentials into container..."
	@cat ~/.claude/.credentials.json | $(COMPOSE) exec -T $(SERVICE) \
	  bash -c 'mkdir -p ~/.claude && cat > ~/.claude/.credentials.json && chmod 600 ~/.claude/.credentials.json'
	@echo "Switching coding agents to claude-pro backend..."
	@curl -sf -X POST http://localhost:3004/backend \
	  -H "Content-Type: application/json" \
	  -d '{"backend":"claude-pro"}' | python3 -m json.tool
	@echo ""
	@echo "Done. Coding agents now use Claude Pro (OAuth). To revert: curl -X POST http://localhost:3004/backend -d '{\"backend\":\"ollama\"}'"

# ── Server setup ──────────────────────────────────────────────────────────────
setup-homeserver:
	bash scripts/homeserver/setup.sh

# ─────────────────────────────────────────────────────────────────────────────
.env:
	$(error .env not found. Run: python3 scripts/gen-env.py)
