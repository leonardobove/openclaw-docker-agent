.PHONY: help up down restart logs logs-caddy logs-tunnel shell url \
        tunnel gen-auth status build reset upgrade clean deploy

COMPOSE      := docker compose
AGENT        := openclaw-agent
CADDY_SVC    := openclaw-caddy
TUNNEL_SVC   := openclaw-cloudflared
MODEL        ?= qwen3-coder:latest

# ── VPS deploy / tunnel settings ──────────────────────────────────────────
VPS_USER     ?= ubuntu
VPS_HOST     ?= YOUR_VPS_IP
VPS_DIR      ?= ~/openclaw-docker-agent

# ─────────────────────────────────────────────────────────────────────────────
help:
	@printf '\033[1mOpenClaw Agent — Makefile\033[0m\n\n'
	@printf '  \033[36m%-20s\033[0m %s\n' "up"            "Build images and start all services"
	@printf '  \033[36m%-20s\033[0m %s\n' "down"          "Stop and remove containers"
	@printf '  \033[36m%-20s\033[0m %s\n' "restart"       "Restart the OpenClaw agent container"
	@printf '  \033[36m%-20s\033[0m %s\n' "url"           "Show current Cloudflare Tunnel URL"
	@printf '  \033[36m%-20s\033[0m %s\n' "logs"          "Stream agent logs"
	@printf '  \033[36m%-20s\033[0m %s\n' "logs-caddy"    "Stream Caddy logs"
	@printf '  \033[36m%-20s\033[0m %s\n' "logs-tunnel"   "Stream cloudflared tunnel logs"
	@printf '  \033[36m%-20s\033[0m %s\n' "shell"         "Open bash shell in agent container"
	@printf '  \033[36m%-20s\033[0m %s\n' "pull-model"    "Pull MODEL from Ollama on VPS (if applicable)"
	@printf '  \033[36m%-20s\033[0m %s\n' "gen-auth"      "Generate bcrypt hash: make gen-auth PASSWORD=secret"
	@printf '  \033[36m%-20s\033[0m %s\n' "status"        "Show container and volume status"
	@printf '  \033[36m%-20s\033[0m %s\n' "build"         "Force rebuild all images (no cache)"
	@printf '  \033[36m%-20s\033[0m %s\n' "reset"         "Wipe agent state volume and restart clean"
	@printf '  \033[36m%-20s\033[0m %s\n' "upgrade"       "Upgrade OpenClaw to latest and rebuild"
	@printf '  \033[36m%-20s\033[0m %s\n' "clean"         "Remove all containers, images, and volumes"
	@printf '  \033[36m%-20s\033[0m %s\n' "tunnel"        "Start Ollama SSH tunnel to VPS (Linux/macOS only)"
	@printf '  \033[36m%-20s\033[0m %s\n' "deploy"        "Sync project files to VPS via scp"
	@printf '\n'
	@printf '  Windows tunnel:  scripts\\tunnel.bat ubuntu@VPS_IP\n'
	@printf '  Deploy:          make deploy VPS_USER=ubuntu VPS_HOST=1.2.3.4\n\n'

# ─────────────────────────────────────────────────────────────────────────────
up: .env
	$(COMPOSE) up -d --build
	@echo ""
	@echo "Stack started. Waiting for tunnel URL (15s)..."
	@sleep 15
	@$(MAKE) url

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart $(AGENT)

# ─────────────────────────────────────────────────────────────────────────────
url:
	@echo ""
	@echo "=== Cloudflare Tunnel URL (for phone) ==="
	@docker logs $(TUNNEL_SVC) 2>&1 \
	    | grep -o 'https://[^ ]*\.trycloudflare\.com' \
	    | tail -1 \
	    || echo "  (not yet available — try: make logs-tunnel)"
	@echo ""

logs:
	$(COMPOSE) logs -f --tail=100 $(AGENT)

logs-caddy:
	$(COMPOSE) logs -f --tail=100 $(CADDY_SVC)

logs-tunnel:
	$(COMPOSE) logs -f --tail=100 $(TUNNEL_SVC)

shell:
	$(COMPOSE) exec -it $(AGENT) bash

# ── SSH Ollama tunnel (Linux/macOS — for Windows use scripts/tunnel.bat) ──
tunnel:
ifeq ($(VPS_HOST),YOUR_VPS_IP)
	$(error Set VPS_HOST: make tunnel VPS_USER=ubuntu VPS_HOST=1.2.3.4)
endif
	bash scripts/tunnel.sh $(VPS_USER)@$(VPS_HOST)

# ─────────────────────────────────────────────────────────────────────────────
gen-auth:
ifndef PASSWORD
	$(error Usage: make gen-auth PASSWORD=your_password)
endif
	@docker run --rm caddy:2-alpine caddy hash-password --plaintext "$(PASSWORD)"

status:
	@echo "=== Containers ==="
	@$(COMPOSE) ps
	@echo ""
	@echo "=== Volumes ==="
	@docker volume ls --filter "name=openclaw"

build:
	$(COMPOSE) build --no-cache

# ─────────────────────────────────────────────────────────────────────────────
reset: .env
	@echo "WARNING: This will permanently delete all agent state (workspace, sessions, memory)."
	@printf "Type 'yes' to confirm: "; read confirm; [ "$$confirm" = "yes" ] || (echo "Aborted."; exit 1)
	$(COMPOSE) down -v
	$(COMPOSE) up -d --build
	@sleep 15
	@$(MAKE) url

upgrade: .env
	$(COMPOSE) down
	$(COMPOSE) build --no-cache --build-arg OPENCLAW_VERSION=latest
	$(COMPOSE) up -d
	@echo "OpenClaw upgraded to latest."

clean:
	@echo "WARNING: Removes all containers, images, and volumes for this project."
	@printf "Type 'yes' to confirm: "; read confirm; [ "$$confirm" = "yes" ] || (echo "Aborted."; exit 1)
	$(COMPOSE) down -v --rmi all --remove-orphans

# ─────────────────────────────────────────────────────────────────────────────
# Deploy: copy project from Windows to VPS using built-in Windows SSH/SCP
# Usage: make deploy VPS_USER=ubuntu VPS_HOST=1.2.3.4
deploy:
ifeq ($(VPS_HOST),YOUR_VPS_IP)
	$(error Set VPS_HOST: make deploy VPS_USER=ubuntu VPS_HOST=1.2.3.4)
endif
	@echo "Copying project to $(VPS_USER)@$(VPS_HOST):$(VPS_DIR) ..."
	ssh $(VPS_USER)@$(VPS_HOST) "mkdir -p $(VPS_DIR)"
	scp -r \
	    Dockerfile \
	    docker-compose.yml \
	    Caddyfile \
	    Makefile \
	    .env.example \
	    .gitignore \
	    caddy/ \
	    config/ \
	    scripts/ \
	    $(VPS_USER)@$(VPS_HOST):$(VPS_DIR)/
	@echo ""
	@echo "Files copied. Now run on the VPS:"
	@echo "  ssh $(VPS_USER)@$(VPS_HOST)"
	@echo "  bash $(VPS_DIR)/scripts/setup-vps.sh"

# ─────────────────────────────────────────────────────────────────────────────
.env:
	$(error .env not found. Copy .env.example to .env and fill in values.)
