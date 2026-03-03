# syntax=docker/dockerfile:1.7
# ─────────────────────────────────────────────────────────────────────────────
# OpenClaw Autonomous Coding Agent
# Base: node:22-slim  |  User: non-root (UID 10001)  |  No bind mounts
# ─────────────────────────────────────────────────────────────────────────────
FROM node:22-slim

ARG OPENCLAW_VERSION=latest
ARG UID=10001
ARG GID=10001

LABEL org.opencontainers.image.title="openclaw-agent" \
      org.opencontainers.image.description="Autonomous AI coding agent — OpenClaw + external Ollama (LAN)" \
      org.opencontainers.image.licenses="MIT"

# ── System dependencies ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        make \
        openssh-client \
        python3 \
        python3-pip \
        python3-venv \
        build-essential \
        unzip \
        wget \
    && rm -rf /var/lib/apt/lists/*

# ── Install OpenClaw globally ──────────────────────────────────────────────
RUN npm install -g openclaw@${OPENCLAW_VERSION} --omit=dev 2>&1 | tail -10

# ── Install Claude Code CLI ────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code --omit=dev 2>&1 | tail -10

# ── Docker CLI (for self-rebuild capability via mounted socket) ────────────
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ── Non-root user — GID 999 = host docker group (allows socket access) ────
RUN groupadd -g ${GID} openclaw \
    && groupadd -g 999 docker-host \
    && useradd -u ${UID} -g ${GID} -G docker-host -m -d /home/openclaw -s /bin/bash openclaw

# ── Directory structure ────────────────────────────────────────────────────
RUN mkdir -p /etc/openclaw/workspace \
    && mkdir -p /home/openclaw/.openclaw \
    && chown -R openclaw:openclaw /home/openclaw /etc/openclaw

# ── Config & scripts (copied from host at build time) ─────────────────────
COPY --chown=openclaw:openclaw config/openclaw.json       /etc/openclaw/openclaw.json
COPY --chown=openclaw:openclaw config/workspace/AGENTS.md /etc/openclaw/workspace/AGENTS.md
COPY --chown=openclaw:openclaw config/workspace/SOUL.md   /etc/openclaw/workspace/SOUL.md
COPY                           scripts/entrypoint.sh      /usr/local/bin/entrypoint.sh
COPY                           scripts/agent-manager.py   /usr/local/bin/agent-manager.py
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/agent-manager.py

# ── Runtime ────────────────────────────────────────────────────────────────
USER openclaw
WORKDIR /home/openclaw

ENV OPENCLAW_HOME=/home/openclaw/.openclaw \
    OPENCLAW_STATE_DIR=/home/openclaw/.openclaw \
    NODE_ENV=production \
    NO_UPDATE_NOTIFIER=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# Persistent state volume — declared here so docker-compose inherits it
VOLUME ["/home/openclaw/.openclaw"]

EXPOSE 18789

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -sf http://localhost:18789/ > /dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
