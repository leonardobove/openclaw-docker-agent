#!/usr/bin/env bash
# install-claude-memory.sh
# Installs the committed Claude Code memory file into the correct local path
# so Claude Code picks it up automatically when opening this project.
#
# Run once after cloning on a new machine:
#   bash scripts/install-claude-memory.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${REPO_ROOT}/.claude/MEMORY.md"

# Claude Code derives the project key from the absolute repo path
# Format: ~/.claude/projects/<path-with-slashes-as-dashes>/memory/MEMORY.md
ENCODED="$(echo "${REPO_ROOT}" | sed 's|/|-|g')"
DEST_DIR="${HOME}/.claude/projects/${ENCODED}/memory"
DEST="${DEST_DIR}/MEMORY.md"

if [[ ! -f "${SRC}" ]]; then
    echo "ERROR: ${SRC} not found — are you in the repo root?"
    exit 1
fi

mkdir -p "${DEST_DIR}"
cp "${SRC}" "${DEST}"
echo "Memory installed → ${DEST}"
echo "Claude Code will load it automatically when you open this project."
