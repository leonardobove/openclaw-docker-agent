#!/usr/bin/env python3
"""
gen-env.py — Generate a clean .env file for openclaw-docker-agent

Run from the repo root:
    python3 scripts/gen-env.py

What it does:
  - Generates a random 64-hex-char OPENCLAW_GATEWAY_TOKEN
  - Hashes your Caddy web UI password via Docker (bcrypt)
  - Writes a clean .env with no trailing whitespace or encoding issues

Requirements: Docker must be running (used only to hash the password).
"""

import subprocess
import sys
import os
import getpass

ENV_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")

DEFAULTS = {
    "OPENCLAW_VERSION": "latest",
    "CADDY_AUTH_USER": "agent",
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

    # Gemini API key
    print()
    print("Get a free Gemini API key at: https://aistudio.google.com/apikey")
    gemini_key = input("Paste your GEMINI_API_KEY: ").strip()
    if not gemini_key:
        print("ERROR: GEMINI_API_KEY cannot be empty.")
        sys.exit(1)

    # Caddy password
    print()
    print(f"Caddy web UI user: {DEFAULTS['CADDY_AUTH_USER']}")
    password = getpass.getpass("Enter Caddy web UI password (input hidden): ").strip()
    if not password:
        print("ERROR: password cannot be empty.")
        sys.exit(1)

    print("Hashing password via Docker (caddy:2-alpine)...")
    caddy_hash = run(
        ["docker", "run", "--rm", "caddy:2-alpine", "caddy", "hash-password", "--plaintext", password],
        "caddy hash-password",
    )
    print("  Hash generated.")

    # Write .env
    lines = [
        f"OPENCLAW_VERSION={DEFAULTS['OPENCLAW_VERSION']}",
        f"OPENCLAW_GATEWAY_TOKEN={token}",
        f"GEMINI_API_KEY={gemini_key}",
        f"CADDY_AUTH_USER={DEFAULTS['CADDY_AUTH_USER']}",
        f"CADDY_AUTH_HASH={caddy_hash}",
    ]

    with open(ENV_FILE, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print()
    print(f"Written: {ENV_FILE}")
    print()
    print("Next steps:")
    print("  docker compose down -v   # remove old state volume")
    print("  make up                  # rebuild and start")


if __name__ == "__main__":
    main()
