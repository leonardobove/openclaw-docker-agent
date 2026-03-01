#!/usr/bin/env python3
"""
gen-env.py — Generate a clean .env file for openclaw-docker-agent

Run from the repo root:
    python3 scripts/gen-env.py

What it does:
  - Generates a random 64-hex-char OPENCLAW_GATEWAY_TOKEN
  - Prompts for TELEGRAM_BOT_TOKEN (from @BotFather)
  - Prompts for ANTHROPIC_API_KEY (from console.anthropic.com)
  - Writes a clean .env with no trailing whitespace or encoding issues
"""

import subprocess
import sys
import os

ENV_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")

DEFAULTS = {
    "OPENCLAW_VERSION": "latest",
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

    # Anthropic API key
    print()
    print("Get an API key from https://console.anthropic.com")
    anthropic_key = input("Paste your ANTHROPIC_API_KEY: ").strip()
    if not anthropic_key:
        print("ERROR: ANTHROPIC_API_KEY cannot be empty.")
        sys.exit(1)

    # Write .env
    lines = [
        f"OPENCLAW_VERSION={DEFAULTS['OPENCLAW_VERSION']}",
        f"OPENCLAW_GATEWAY_TOKEN={token}",
        f"TELEGRAM_BOT_TOKEN={telegram_token}",
        f"ANTHROPIC_API_KEY={anthropic_key}",
    ]

    with open(ENV_FILE, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print()
    print(f"Written: {ENV_FILE}")
    print()
    print("Next steps:")
    print("  docker compose down -v   # remove old state volume")
    print("  make up                  # build and start")
    print("  make logs                # watch startup, then pair Telegram")


if __name__ == "__main__":
    main()
