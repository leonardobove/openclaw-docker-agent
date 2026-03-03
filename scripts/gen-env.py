#!/usr/bin/env python3
"""
gen-env.py — Generate a clean .env file for openclaw-docker-agent

Run from the repo root:
    python3 scripts/gen-env.py

What it does:
  - Generates a random 64-hex-char OPENCLAW_GATEWAY_TOKEN
  - Prompts for TELEGRAM_BOT_TOKEN (from @BotFather)
  - Prompts for ANTHROPIC_API_KEY (required — powers the chatbot brain)
  - Auto-detects REPO_HOST_PATH (asks to confirm)
  - Optionally prompts for OLLAMA_MODEL (default: kimi-k2.5:cloud)
  - Writes a clean .env with no trailing whitespace or encoding issues
"""

import subprocess
import sys
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE  = os.path.join(REPO_ROOT, ".env")

DEFAULTS = {
    "OPENCLAW_VERSION": "latest",
    "OLLAMA_MODEL":     "kimi-k2.5:cloud",
    "DOCKER_GID":       "999",
}


def run(cmd, description):
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.PIPE)
        return result.decode().strip()
    except subprocess.CalledProcessError as e:
        print(f"ERROR: {description} failed.")
        print(e.stderr.decode().strip())
        sys.exit(1)
    except FileNotFoundError:
        print(f"ERROR: command not found: {cmd[0]}")
        sys.exit(1)


def detect_docker_gid():
    """Try to detect the docker group GID on the current system."""
    try:
        out = subprocess.check_output(
            ["getent", "group", "docker"], stderr=subprocess.DEVNULL
        ).decode().strip()
        return out.split(":")[2]
    except Exception:
        return DEFAULTS["DOCKER_GID"]


def main():
    print("openclaw-docker-agent — .env generator")
    print("=" * 40)

    # Gateway token
    print("Generating gateway token...")
    token = run(["openssl", "rand", "-hex", "32"], "openssl rand")
    print(f"  Token: {token[:8]}...{token[-4:]}")

    # Telegram bot token
    print()
    print("Get a bot token from @BotFather on Telegram (/newbot)")
    telegram_token = input("Paste your TELEGRAM_BOT_TOKEN: ").strip()
    if not telegram_token:
        print("ERROR: TELEGRAM_BOT_TOKEN cannot be empty.")
        sys.exit(1)

    # Anthropic API key — required (powers the chatbot brain)
    print()
    print("ANTHROPIC_API_KEY is required — it powers the chatbot brain (Claude Sonnet).")
    print("Get it at: https://console.anthropic.com/settings/keys")
    anthropic_key = input("Paste your ANTHROPIC_API_KEY: ").strip()
    if not anthropic_key:
        print("ERROR: ANTHROPIC_API_KEY cannot be empty.")
        sys.exit(1)

    # REPO_HOST_PATH — auto-detect, let user confirm or override
    print()
    detected_path = REPO_ROOT
    print(f"Detected repo path: {detected_path}")
    print("This is the absolute host path Docker uses to find the repo.")
    repo_path = input(f"REPO_HOST_PATH [{detected_path}]: ").strip()
    if not repo_path:
        repo_path = detected_path

    # Docker GID
    print()
    detected_gid = detect_docker_gid()
    print(f"Detected docker group GID: {detected_gid}")
    docker_gid = input(f"DOCKER_GID [{detected_gid}]: ").strip()
    if not docker_gid:
        docker_gid = detected_gid

    # Ollama model for coding agents
    print()
    print("OLLAMA_MODEL is the Ollama cloud model used for spawned coding agents.")
    print("Cloud models work without pulling locally (kimi-k2.5:cloud, glm-5:cloud).")
    print(f"Default: {DEFAULTS['OLLAMA_MODEL']}")
    ollama_model = input(f"OLLAMA_MODEL [{DEFAULTS['OLLAMA_MODEL']}]: ").strip()
    if not ollama_model:
        ollama_model = DEFAULTS["OLLAMA_MODEL"]

    # Write .env
    lines = [
        f"OPENCLAW_VERSION={DEFAULTS['OPENCLAW_VERSION']}",
        f"OPENCLAW_GATEWAY_TOKEN={token}",
        f"TELEGRAM_BOT_TOKEN={telegram_token}",
        f"ANTHROPIC_API_KEY={anthropic_key}",
        f"REPO_HOST_PATH={repo_path}",
        f"DOCKER_GID={docker_gid}",
        f"OLLAMA_MODEL={ollama_model}",
    ]

    with open(ENV_FILE, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print()
    print(f"Written: {ENV_FILE}")
    print()
    print("Next steps:")
    print("  1. Start the agent:   make up")
    print("  2. Stream logs:       make logs")
    print("  3. Pair Telegram:     send /start to your bot, follow pairing prompt")
    print()
    print("To use Claude Pro OAuth for coding agents (instead of API key):")
    print("  make inject-claude-creds   # run on this machine after logging in with 'claude'")


if __name__ == "__main__":
    main()
