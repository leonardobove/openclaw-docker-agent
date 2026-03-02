#!/usr/bin/env python3
"""
gen-env.py — Generate a clean .env file for openclaw-docker-agent

Run from the repo root:
    python3 scripts/gen-env.py

What it does:
  - Generates a random 64-hex-char OPENCLAW_GATEWAY_TOKEN
  - Prompts for TELEGRAM_BOT_TOKEN (from @BotFather)
  - Auto-detects REPO_HOST_PATH (asks to confirm)
  - Optionally prompts for ANTHROPIC_API_KEY (for Claude Pro agents)
  - Writes a clean .env with no trailing whitespace or encoding issues
"""

import subprocess
import sys
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE  = os.path.join(REPO_ROOT, ".env")

DEFAULTS = {
    "OPENCLAW_VERSION": "latest",
    "OLLAMA_MODEL":     "qwen2.5-coder:7b",
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

    # REPO_HOST_PATH — auto-detect, let user confirm or override
    print()
    detected_path = REPO_ROOT
    print(f"Detected repo path: {detected_path}")
    print("This is the absolute host path Docker uses to find the repo.")
    print("On WSL2: use the Linux path (e.g. /home/youruser/openclaw-docker-agent)")
    repo_path = input(f"REPO_HOST_PATH [{detected_path}]: ").strip()
    if not repo_path:
        repo_path = detected_path

    # Docker GID
    print()
    detected_gid = detect_docker_gid()
    print(f"Detected docker group GID: {detected_gid}")
    print("(On Docker Desktop for Windows/macOS, 999 usually works fine)")
    docker_gid = input(f"DOCKER_GID [{detected_gid}]: ").strip()
    if not docker_gid:
        docker_gid = detected_gid

    # Anthropic API key (optional — for Claude Pro coding agents)
    print()
    print("ANTHROPIC_API_KEY is optional.")
    print("Only needed if you want coding agents to use Claude Pro (API key auth).")
    print("You can also inject OAuth credentials later via Telegram (recommended).")
    anthropic_key = input("Paste your ANTHROPIC_API_KEY (or press Enter to skip): ").strip()

    # Write .env
    lines = [
        f"OPENCLAW_VERSION={DEFAULTS['OPENCLAW_VERSION']}",
        f"OPENCLAW_GATEWAY_TOKEN={token}",
        f"TELEGRAM_BOT_TOKEN={telegram_token}",
        f"REPO_HOST_PATH={repo_path}",
        f"DOCKER_GID={docker_gid}",
        f"OLLAMA_MODEL={DEFAULTS['OLLAMA_MODEL']}",
    ]
    if anthropic_key:
        lines.append(f"ANTHROPIC_API_KEY={anthropic_key}")

    with open(ENV_FILE, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print()
    print(f"Written: {ENV_FILE}")
    print()
    print("Next steps:")
    print("  make up      # build image and start the stack")
    print("  make logs    # watch startup, then pair Telegram (/start)")
    print()
    print("GPU (NVIDIA):")
    print("  make gpu-up  # start with GPU acceleration for Ollama")


if __name__ == "__main__":
    main()
