#!/usr/bin/env python3
"""
agent-manager.py — Background agent spawner with real-time Telegram updates

Listens on 127.0.0.1:3004.

Endpoints:
  POST   /spawn          Start a Claude Code agent in the background
  GET    /status         List all agents (running, completed, failed, cancelled)
  DELETE /agent/<id>     Cancel a running agent
  POST   /logging        Toggle progress logging ({"enabled": true/false})

The agent runs `claude -p --output-format stream-json`, parses NDJSON events,
and sends real-time tool-call progress + final result to Telegram via the Bot API.

Config via environment variables:
  TELEGRAM_BOT_TOKEN   — Telegram bot token (required for Telegram updates)
  ANTHROPIC_API_KEY    — Anthropic API key (used unless OAuth token is present)
  AGENT_MANAGER_PORT   — port to listen on (default: 3004)
"""

import json
import os
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

# ── Config ──────────────────────────────────────────────────────────────────
MANAGER_PORT       = int(os.environ.get("AGENT_MANAGER_PORT", 3004))
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CREDENTIALS_FILE   = os.path.expanduser("~/.claude/.credentials.json")
ALLOWFROM_FILE     = os.path.expanduser("~/.openclaw/credentials/telegram-default-allowFrom.json")
LOGGING_FLAG       = os.path.expanduser("~/.openclaw/agent-logging-enabled")
CLAUDE_TOOLS       = "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch"
CLAUDE_TIMEOUT     = 600   # seconds per agent
MAX_MSG_LEN        = 4000  # Telegram character limit

# ── Global job registry ─────────────────────────────────────────────────────
_jobs      = {}             # job_id → {status, task, start_time, end_time, proc}
_jobs_lock = threading.Lock()


# ── OAuth helpers (mirrors claude-bridge.py) ─────────────────────────────────

def _get_access_token():
    """Return a valid OAuth access token, or None (fall back to ANTHROPIC_API_KEY)."""
    try:
        with open(CREDENTIALS_FILE) as f:
            creds = json.load(f)
    except Exception:
        return None

    if "claudeAiOauth" not in creds:
        return None

    oauth       = creds["claudeAiOauth"]
    expires_ms  = oauth.get("expiresAt", 0)
    now_ms      = int(time.time() * 1000)

    if now_ms >= expires_ms:
        return None   # expired — fall back to API key

    return oauth.get("accessToken")


def _build_env():
    """Build subprocess env: prefer OAuth token over ANTHROPIC_API_KEY."""
    env   = os.environ.copy()
    token = _get_access_token()
    if token:
        env["CLAUDE_CODE_OAUTH_TOKEN"] = token
        env.pop("ANTHROPIC_API_KEY", None)
    return env


# ── Telegram helpers ─────────────────────────────────────────────────────────

def _get_default_chat_id():
    """Read the first paired Telegram user ID from the allowFrom credentials file."""
    try:
        with open(ALLOWFROM_FILE) as f:
            data = json.load(f)
        # Format: {"version": 1, "allowFrom": ["123456789"]}
        if isinstance(data, dict) and "allowFrom" in data:
            return int(data["allowFrom"][0])
        # Fallback: plain list ["123456789"]
        if isinstance(data, list) and data:
            return int(data[0])
    except Exception as e:
        print(f"[agent-manager] Cannot read default chat_id: {e}", flush=True)
    return None


def send_telegram(chat_id, text):
    """Send a Telegram message. Silently truncates to MAX_MSG_LEN chars."""
    if not TELEGRAM_BOT_TOKEN or not chat_id:
        return
    if len(text) > MAX_MSG_LEN:
        text = text[:MAX_MSG_LEN - 3] + "..."
    payload = json.dumps({
        "chat_id":    chat_id,
        "text":       text,
        "parse_mode": "Markdown",
    }).encode()
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    try:
        req = urllib.request.Request(
            url, data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=15)
    except Exception as e:
        print(f"[agent-manager] Telegram send failed: {e}", flush=True)


# ── Logging toggle ───────────────────────────────────────────────────────────

def logging_enabled():
    return os.path.exists(LOGGING_FLAG)


# ── Tool input summariser ────────────────────────────────────────────────────

def _summarize_input(inp):
    """Return a short readable summary of a tool's input dict."""
    if not inp:
        return ""
    # Show the most informative field if present
    for key in ("command", "file_path", "pattern", "query", "url", "path", "old_string"):
        if key in inp:
            val = str(inp[key])
            return val[:120] + ("..." if len(val) > 120 else "")
    # Fall back to raw JSON, trimmed
    raw = json.dumps(inp)
    return raw[:120] + ("..." if len(raw) > 120 else "")


# ── Agent runner (background thread) ─────────────────────────────────────────

def _run_agent(job_id, task, chat_id):
    cmd = [
        "claude", "-p", task,
        "--output-format", "stream-json",
        "--dangerously-skip-permissions",
        "--allowedTools", CLAUDE_TOOLS,
        "--max-turns", "30",
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
        print(f"[agent-manager] Failed to start claude: {e}", flush=True)
        send_telegram(chat_id, f"❌ Agent `{job_id}` failed to start:\n`{e}`")
        with _jobs_lock:
            _jobs[job_id]["status"]   = "failed"
            _jobs[job_id]["end_time"] = time.time()
        return

    with _jobs_lock:
        _jobs[job_id]["proc"] = proc

    deadline    = time.time() + CLAUDE_TIMEOUT
    result_sent = False

    try:
        for raw_line in proc.stdout:
            # Check cancellation
            with _jobs_lock:
                if _jobs[job_id]["status"] == "cancelled":
                    proc.kill()
                    return

            # Check timeout
            if time.time() > deadline:
                proc.kill()
                send_telegram(chat_id, f"⏰ Agent `{job_id}` timed out after {CLAUDE_TIMEOUT}s.")
                with _jobs_lock:
                    _jobs[job_id]["status"]   = "failed"
                    _jobs[job_id]["end_time"] = time.time()
                return

            raw_line = raw_line.strip()
            if not raw_line:
                continue

            try:
                event = json.loads(raw_line)
            except json.JSONDecodeError:
                continue

            etype = event.get("type")

            if etype == "assistant" and logging_enabled():
                content = event.get("message", {}).get("content", [])
                for block in content:
                    if block.get("type") == "tool_use":
                        name    = block.get("name", "?")
                        summary = _summarize_input(block.get("input", {}))
                        msg     = f"🔧 `{name}`"
                        if summary:
                            msg += f": {summary}"
                        send_telegram(chat_id, msg)

            elif etype == "result":
                is_error    = event.get("is_error", False)
                result_text = event.get("result", "(no output)")
                if is_error:
                    send_telegram(chat_id, f"❌ Agent `{job_id}` error:\n{result_text}")
                else:
                    send_telegram(chat_id, f"✅ Agent `{job_id}` done:\n{result_text}")
                result_sent = True
                with _jobs_lock:
                    _jobs[job_id]["status"]   = "completed"
                    _jobs[job_id]["end_time"] = time.time()

    except Exception as e:
        print(f"[agent-manager] Error reading agent stream for {job_id}: {e}", flush=True)

    proc.wait()

    if not result_sent:
        # No result event received — report based on exit code
        stderr = ""
        if proc.stderr:
            try:
                stderr = proc.stderr.read()
            except Exception:
                pass
        if proc.returncode != 0:
            send_telegram(chat_id, f"❌ Agent `{job_id}` exited (code {proc.returncode}):\n{stderr[:500]}")
        else:
            send_telegram(chat_id, f"✅ Agent `{job_id}` completed.")
        with _jobs_lock:
            _jobs[job_id]["status"]   = "completed" if proc.returncode == 0 else "failed"
            _jobs[job_id]["end_time"] = time.time()


# ── HTTP handler ─────────────────────────────────────────────────────────────

class ManagerHandler(BaseHTTPRequestHandler):

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body   = json.loads(self.rfile.read(length)) if length else {}

        if self.path == "/spawn":
            self._handle_spawn(body)
        elif self.path == "/logging":
            self._handle_logging(body)
        else:
            self.send_error(404, "Not Found")

    def do_GET(self):
        if self.path == "/status":
            self._handle_status()
        else:
            self.send_error(404, "Not Found")

    def do_DELETE(self):
        if self.path.startswith("/agent/"):
            job_id = self.path[len("/agent/"):]
            self._handle_cancel(job_id)
        else:
            self.send_error(404, "Not Found")

    # ── Endpoint handlers ─────────────────────────────────────────────────────

    def _handle_spawn(self, body):
        task = body.get("task", "").strip()
        if not task:
            self._send_json(400, {"error": "Missing 'task' field"})
            return

        chat_id = body.get("chat_id") or _get_default_chat_id()
        job_id  = f"agent_{int(time.time())}"

        with _jobs_lock:
            _jobs[job_id] = {
                "status":     "running",
                "task":       task,
                "start_time": time.time(),
                "end_time":   None,
                "proc":       None,
            }

        # Notify user immediately before the agent does any work
        task_summary = task[:100] + ("..." if len(task) > 100 else "")
        send_telegram(chat_id, f"🤖 Agent `{job_id}` started:\n_{task_summary}_")

        # Launch background thread — returns control to caller immediately
        t = threading.Thread(target=_run_agent, args=(job_id, task, chat_id), daemon=True)
        t.start()

        self._send_json(200, {"job_id": job_id, "status": "started"})
        print(f"[agent-manager] Spawned {job_id}: {task_summary}", flush=True)

    def _handle_status(self):
        with _jobs_lock:
            snapshot = {
                jid: {k: v for k, v in info.items() if k != "proc"}
                for jid, info in _jobs.items()
            }
        self._send_json(200, snapshot)

    def _handle_cancel(self, job_id):
        with _jobs_lock:
            if job_id not in _jobs:
                self._send_json(404, {"error": "Job not found"})
                return
            job = _jobs[job_id]
            if job["status"] != "running":
                self._send_json(400, {"error": f"Job is already {job['status']}"})
                return
            job["status"]   = "cancelled"
            job["end_time"] = time.time()
            proc            = job.get("proc")
        if proc:
            try:
                proc.kill()
            except Exception:
                pass
        self._send_json(200, {"job_id": job_id, "status": "cancelled"})
        print(f"[agent-manager] Cancelled {job_id}", flush=True)

    def _handle_logging(self, body):
        enabled = body.get("enabled", True)
        if enabled:
            open(LOGGING_FLAG, "w").close()
            msg = "Logging enabled — tool calls will appear in Telegram."
        else:
            try:
                os.remove(LOGGING_FLAG)
            except FileNotFoundError:
                pass
            msg = "Logging disabled — only final results will appear in Telegram."
        self._send_json(200, {"logging": enabled, "message": msg})
        print(f"[agent-manager] {msg}", flush=True)

    # ── Utility ───────────────────────────────────────────────────────────────

    def _send_json(self, code, data):
        body = json.dumps(data, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[agent-manager] {fmt % args}", flush=True)


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


# ── Entrypoint ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if not TELEGRAM_BOT_TOKEN:
        print("[agent-manager] WARNING: TELEGRAM_BOT_TOKEN not set — Telegram updates disabled", flush=True)
    server = ThreadingHTTPServer(("127.0.0.1", MANAGER_PORT), ManagerHandler)
    print(f"[agent-manager] Listening on 127.0.0.1:{MANAGER_PORT}", flush=True)
    server.serve_forever()
