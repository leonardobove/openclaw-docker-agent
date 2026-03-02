#!/usr/bin/env python3
"""
claude-bridge.py — Local HTTP bridge: OpenClaw → Claude Code CLI

Listens on 127.0.0.1:3001.
Accepts POST /v1/messages in Anthropic Messages API format.
Translates to `claude -p` subprocess calls.
Manages OAuth token refresh automatically.
Falls back to ANTHROPIC_API_KEY if no OAuth credentials are present.

Streaming note: SSE headers and initial events are sent IMMEDIATELY so the
client doesn't time out. Pings are emitted every 5 s while claude runs.
Content is streamed when claude exits.
"""

import json
import os
import subprocess
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

# ── Config ─────────────────────────────────────────────────────────────────
BRIDGE_PORT = int(os.environ.get("BRIDGE_PORT", 3001))
CREDENTIALS_FILE = os.path.expanduser("~/.claude/.credentials.json")
OAUTH_TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_REFRESH_BUFFER_MS = 10 * 60 * 1000  # refresh if < 10 min remaining
CLAUDE_TOOLS = "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch"
CLAUDE_TIMEOUT = 600  # seconds
PING_INTERVAL = 5     # SSE ping every N seconds while claude runs


# ── OAuth token management ──────────────────────────────────────────────────

def _read_credentials():
    try:
        with open(CREDENTIALS_FILE) as f:
            return json.load(f)
    except Exception:
        return None


def _write_credentials(creds):
    os.makedirs(os.path.dirname(CREDENTIALS_FILE), exist_ok=True)
    with open(CREDENTIALS_FILE, "w") as f:
        json.dump(creds, f, indent=2)
    os.chmod(CREDENTIALS_FILE, 0o600)


def _do_refresh(refresh_token_val):
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token_val,
        "client_id": OAUTH_CLIENT_ID,
    }).encode()
    req = urllib.request.Request(
        OAUTH_TOKEN_URL,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def get_access_token():
    """
    Return a valid OAuth access token, refreshing if needed.
    Returns None if no credentials file exists (fall back to ANTHROPIC_API_KEY).
    """
    creds = _read_credentials()
    if not creds or "claudeAiOauth" not in creds:
        return None

    oauth = creds["claudeAiOauth"]
    expires_at_ms = oauth.get("expiresAt", 0)
    now_ms = int(time.time() * 1000)

    if now_ms + TOKEN_REFRESH_BUFFER_MS >= expires_at_ms:
        print("[bridge] OAuth token expiring soon — refreshing...", flush=True)
        try:
            resp = _do_refresh(oauth["refreshToken"])
            new_oauth = {
                "accessToken": resp["access_token"],
                "refreshToken": resp["refresh_token"],
                "expiresAt": int(time.time() * 1000) + resp["expires_in"] * 1000,
                "scopes": resp.get("scope", "").split(),
            }
            _write_credentials({"claudeAiOauth": new_oauth})
            print("[bridge] Token refreshed successfully.", flush=True)
            return new_oauth["accessToken"]
        except Exception as e:
            print(f"[bridge] Token refresh failed: {e}", flush=True)
            # If the token is already expired, fall back to ANTHROPIC_API_KEY rather
            # than passing an expired OAuth token to claude (which causes a 401).
            if now_ms >= expires_at_ms:
                print("[bridge] Token is expired and refresh failed — falling back to ANTHROPIC_API_KEY.", flush=True)
                return None

    return oauth.get("accessToken")


def _build_env():
    """Build subprocess env: set OAuth token or fall back to ANTHROPIC_API_KEY."""
    env = os.environ.copy()
    token = get_access_token()
    if token:
        env["CLAUDE_CODE_OAUTH_TOKEN"] = token
        env.pop("ANTHROPIC_API_KEY", None)
    return env


# ── Conversation formatting ─────────────────────────────────────────────────

def _extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        )
    return str(content)


def format_prompt(system, messages):
    parts = []
    if system:
        parts.append(f"<system>\n{system}\n</system>")
    for msg in messages:
        role = msg.get("role", "user")
        text = _extract_text(msg.get("content", ""))
        if role == "user":
            parts.append(f"<user>\n{text}\n</user>")
        elif role == "assistant":
            parts.append(f"<assistant>\n{text}\n</assistant>")
    return "\n".join(parts)


# ── HTTP handler ────────────────────────────────────────────────────────────

class BridgeHandler(BaseHTTPRequestHandler):

    def do_POST(self):
        if self.path != "/v1/messages":
            self.send_error(404, "Not Found")
            return

        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))

        streaming = body.get("stream", False)
        model = body.get("model", "claude-code")

        system_raw = body.get("system", "")
        system = _extract_text(system_raw) if isinstance(system_raw, list) else system_raw
        messages = body.get("messages", [])
        prompt = format_prompt(system, messages)

        print(f"[bridge] Request: model={model} stream={streaming} msgs={len(messages)}", flush=True)

        if streaming:
            self._handle_streaming(prompt, model)
        else:
            response_text = self._run_claude_sync(prompt)
            in_tok = max(1, len(prompt) // 4)
            out_tok = max(1, len(response_text) // 4)
            self._send_json(model, response_text, in_tok, out_tok)

    # ── Streaming path ───────────────────────────────────────────────────────

    def _handle_streaming(self, prompt, model):
        in_tok = max(1, len(prompt) // 4)
        msg_id = f"msg_bridge_{int(time.time())}"

        # Send headers + initial SSE events IMMEDIATELY — prevents client timeout
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        def emit(event, data):
            line = f"event: {event}\ndata: {json.dumps(data)}\n\n"
            self.wfile.write(line.encode())
            self.wfile.flush()

        emit("message_start", {
            "type": "message_start",
            "message": {
                "id": msg_id, "type": "message", "role": "assistant",
                "content": [], "model": model,
                "stop_reason": None, "stop_sequence": None,
                "usage": {"input_tokens": in_tok, "output_tokens": 0},
            },
        })
        emit("content_block_start", {
            "type": "content_block_start", "index": 0,
            "content_block": {"type": "text", "text": ""},
        })

        # Launch claude as a non-blocking subprocess
        cmd = [
            "claude", "-p", prompt,
            "--output-format", "json",
            "--dangerously-skip-permissions",
            "--allowedTools", CLAUDE_TOOLS,
            "--max-turns", "20",
        ]
        env = _build_env()

        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                cwd=os.path.expanduser("~"),
            )
        except Exception as e:
            response_text = f"[bridge] Failed to start claude: {e}"
            self._emit_content_and_close(emit, response_text, in_tok)
            return

        # Poll the process, sending SSE pings to keep the connection alive
        deadline = time.time() + CLAUDE_TIMEOUT
        while proc.poll() is None:
            if time.time() > deadline:
                proc.kill()
                response_text = f"[bridge] Claude timed out after {CLAUDE_TIMEOUT}s."
                self._emit_content_and_close(emit, response_text, in_tok)
                return
            try:
                emit("ping", {"type": "ping"})
            except Exception:
                # Client disconnected — kill subprocess and bail
                proc.kill()
                return
            time.sleep(PING_INTERVAL)

        stdout, stderr = proc.communicate()

        if proc.returncode == 0:
            try:
                out = json.loads(stdout)
                response_text = out.get("result") or out.get("message") or "(no output)"
            except json.JSONDecodeError:
                response_text = stdout.strip() or "(no output)"
        else:
            err = (stderr or stdout or "unknown error").strip()
            response_text = f"[claude error (exit {proc.returncode})] {err}"

        self._emit_content_and_close(emit, response_text, in_tok)

    def _emit_content_and_close(self, emit, text, in_tok):
        out_tok = max(1, len(text) // 4)
        emit("content_block_delta", {
            "type": "content_block_delta", "index": 0,
            "delta": {"type": "text_delta", "text": text},
        })
        emit("content_block_stop", {"type": "content_block_stop", "index": 0})
        emit("message_delta", {
            "type": "message_delta",
            "delta": {"stop_reason": "end_turn", "stop_sequence": None},
            "usage": {"output_tokens": out_tok},
        })
        emit("message_stop", {"type": "message_stop"})

    # ── Non-streaming path ───────────────────────────────────────────────────

    def _run_claude_sync(self, prompt):
        cmd = [
            "claude", "-p", prompt,
            "--output-format", "json",
            "--dangerously-skip-permissions",
            "--allowedTools", CLAUDE_TOOLS,
            "--max-turns", "20",
        ]
        env = _build_env()
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=CLAUDE_TIMEOUT,
                env=env,
                cwd=os.path.expanduser("~"),
            )
            if result.returncode == 0:
                out = json.loads(result.stdout)
                return out.get("result") or out.get("message") or "(no output)"
            else:
                err = (result.stderr or result.stdout or "unknown error").strip()
                return f"[claude error (exit {result.returncode})] {err}"
        except subprocess.TimeoutExpired:
            return f"[bridge] Claude timed out after {CLAUDE_TIMEOUT}s."
        except Exception as e:
            return f"[bridge] Unexpected error: {e}"

    def _send_json(self, model, text, in_tok, out_tok):
        resp = {
            "id": f"msg_bridge_{int(time.time())}",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": text}],
            "model": model,
            "stop_reason": "end_turn",
            "stop_sequence": None,
            "usage": {"input_tokens": in_tok, "output_tokens": out_tok},
        }
        body = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[bridge] {fmt % args}", flush=True)


# ── Entrypoint ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", BRIDGE_PORT), BridgeHandler)
    print(f"[bridge] Claude Code bridge listening on 127.0.0.1:{BRIDGE_PORT}", flush=True)
    server.serve_forever()
