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
      org.opencontainers.image.description="Autonomous AI coding agent — OpenClaw + Ollama" \
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

# ── Non-root user ──────────────────────────────────────────────────────────
RUN groupadd -g ${GID} openclaw \
    && useradd -u ${UID} -g ${GID} -m -d /home/openclaw -s /bin/bash openclaw

# ── Directory structure ────────────────────────────────────────────────────
RUN mkdir -p /etc/openclaw/workspace \
    && mkdir -p /home/openclaw/.openclaw \
    && chown -R openclaw:openclaw /home/openclaw /etc/openclaw

# ── Config & scripts (copied from host at build time) ─────────────────────
COPY --chown=openclaw:openclaw config/openclaw.json       /etc/openclaw/openclaw.json
COPY --chown=openclaw:openclaw config/workspace/AGENTS.md /etc/openclaw/workspace/AGENTS.md
COPY --chown=openclaw:openclaw config/workspace/SOUL.md   /etc/openclaw/workspace/SOUL.md
COPY                           scripts/entrypoint.sh      /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

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
