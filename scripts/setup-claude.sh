#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-claude.sh — Install Claude Code and open a session in this repo
#
# Run from the repo root on Linux:
#   bash scripts/setup-claude.sh
#
# What it does:
#   1. Installs Node.js 22 if not present (required by Claude Code)
#   2. Installs Claude Code (npm: @anthropic-ai/claude-code) globally
#   3. Opens a Claude Code session in the repo directory
#      Claude Code will auto-read CLAUDE.md and pick up the full session context
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Claude Code Setup ==="
echo "Repo: ${REPO_DIR}"
echo

# ── 1. Check / install Node.js 22 ─────────────────────────────────────────
if command -v node &>/dev/null; then
    NODE_VER=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
    echo "Node.js found: v$(node --version | tr -d 'v')"
    if [[ "${NODE_VER}" -lt 18 ]]; then
        echo "WARNING: Node.js ${NODE_VER} is too old. Claude Code requires Node.js 18+."
        echo "Installing Node.js 22 via NodeSource..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
else
    echo "Node.js not found. Installing Node.js 22 via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

echo "Node: $(node --version)  npm: $(npm --version)"
echo

# ── 2. Install Claude Code ─────────────────────────────────────────────────
if command -v claude &>/dev/null; then
    echo "Claude Code already installed: $(claude --version 2>/dev/null || echo 'unknown version')"
else
    echo "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    echo "Claude Code installed: $(claude --version 2>/dev/null || echo 'ok')"
fi
echo

# ── 3. Open session ────────────────────────────────────────────────────────
echo "Opening Claude Code session in: ${REPO_DIR}"
echo
echo "Claude Code will auto-read CLAUDE.md for full project context."
echo "To start, you can say:"
echo "  'Continue where we left off' or 'What is the current status?'"
echo
echo "Starting Claude Code..."
cd "${REPO_DIR}"
exec claude
