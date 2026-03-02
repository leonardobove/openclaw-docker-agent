#!/usr/bin/env python3
"""
groq-bridge.py — HTTP bridge: OpenClaw → Groq API

Listens on 127.0.0.1:3003.
Accepts POST /v1/messages in Anthropic Messages API format.
Translates to Groq's OpenAI-compatible /openai/v1/chat/completions API.
Returns Anthropic-compatible SSE or JSON responses.

Config via environment variables:
  GROQ_API_KEY  — Groq API key (required)
  GROQ_MODEL    — model to use (default: qwen-qwq-32b)
  BRIDGE_PORT   — port to listen on (default: 3003)
"""

import json
import os
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

# ── Config ─────────────────────────────────────────────────────────────────
BRIDGE_PORT  = int(os.environ.get("BRIDGE_PORT", 3003))
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
GROQ_MODEL   = os.environ.get("GROQ_MODEL", "qwen/qwen3-32b")
GROQ_BASE    = "https://api.groq.com/openai/v1"
REQUEST_TIMEOUT = 120  # seconds


# ── Helpers ─────────────────────────────────────────────────────────────────

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


def _build_openai_messages(system, messages):
    """Convert Anthropic message list + system prompt → OpenAI message list."""
    result = []
    if system:
        result.append({"role": "system", "content": system})
    for msg in messages:
        role    = msg.get("role", "user")
        content = _extract_text(msg.get("content", ""))
        result.append({"role": role, "content": content})
    return result


def _approx_tokens(messages):
    return max(1, sum(len(m.get("content", "")) for m in messages) // 4)


# ── HTTP handler ─────────────────────────────────────────────────────────────

class BridgeHandler(BaseHTTPRequestHandler):

    def do_POST(self):
        if self.path != "/v1/messages":
            self.send_error(404, "Not Found")
            return

        length = int(self.headers.get("Content-Length", 0))
        body   = json.loads(self.rfile.read(length))

        streaming  = body.get("stream", False)
        model      = body.get("model", GROQ_MODEL)
        system_raw = body.get("system", "")
        system     = _extract_text(system_raw) if isinstance(system_raw, list) else system_raw
        messages   = body.get("messages", [])
        max_tokens = body.get("max_tokens", 8192)

        openai_messages = _build_openai_messages(system, messages)
        print(f"[groq-bridge] Request: model={model} stream={streaming} msgs={len(messages)}", flush=True)

        if not GROQ_API_KEY:
            self._send_error_response("GROQ_API_KEY is not set")
            return

        if streaming:
            self._handle_streaming(model, openai_messages, max_tokens)
        else:
            response_text = self._call_groq_sync(model, openai_messages, max_tokens)
            in_tok  = _approx_tokens(openai_messages)
            out_tok = max(1, len(response_text) // 4)
            self._send_json(model, response_text, in_tok, out_tok)

    # ── Streaming path ────────────────────────────────────────────────────────

    def _handle_streaming(self, model, messages, max_tokens):
        in_tok = _approx_tokens(messages)
        msg_id = f"msg_groq_{int(time.time())}"

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

        total_text = ""
        payload = json.dumps({
            "model":            model,
            "messages":         messages,
            "max_tokens":       max_tokens,
            "stream":           True,
            "reasoning_effort": "default",
        }).encode()

        try:
            req = urllib.request.Request(
                f"{GROQ_BASE}/chat/completions",
                data=payload,
                headers={
                    "Content-Type":  "application/json",
                    "Authorization": f"Bearer {GROQ_API_KEY}",
                    "User-Agent":    "groq-bridge/1.0",
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                for raw_line in resp:
                    raw_line = raw_line.decode("utf-8").strip()
                    if not raw_line or not raw_line.startswith("data: "):
                        continue
                    data_str = raw_line[6:]
                    if data_str == "[DONE]":
                        break
                    try:
                        chunk = json.loads(data_str)
                    except json.JSONDecodeError:
                        continue
                    delta = chunk.get("choices", [{}])[0].get("delta", {}).get("content", "")
                    if delta:
                        total_text += delta
                        try:
                            emit("content_block_delta", {
                                "type": "content_block_delta", "index": 0,
                                "delta": {"type": "text_delta", "text": delta},
                            })
                        except Exception:
                            return  # client disconnected
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8", errors="replace")
            error_text = f"[groq-bridge] HTTP {e.code} from Groq: {error_body}"
            total_text += error_text
            try:
                emit("content_block_delta", {
                    "type": "content_block_delta", "index": 0,
                    "delta": {"type": "text_delta", "text": error_text},
                })
            except Exception:
                return
        except Exception as e:
            error_text = f"[groq-bridge] Error calling Groq: {e}"
            total_text += error_text
            try:
                emit("content_block_delta", {
                    "type": "content_block_delta", "index": 0,
                    "delta": {"type": "text_delta", "text": error_text},
                })
            except Exception:
                return

        out_tok = max(1, len(total_text) // 4)
        emit("content_block_stop", {"type": "content_block_stop", "index": 0})
        emit("message_delta", {
            "type": "message_delta",
            "delta": {"stop_reason": "end_turn", "stop_sequence": None},
            "usage": {"output_tokens": out_tok},
        })
        emit("message_stop", {"type": "message_stop"})

    # ── Non-streaming path ────────────────────────────────────────────────────

    def _call_groq_sync(self, model, messages, max_tokens):
        payload = json.dumps({
            "model":            model,
            "messages":         messages,
            "max_tokens":       max_tokens,
            "stream":           False,
            "reasoning_effort": "default",
        }).encode()
        try:
            req = urllib.request.Request(
                f"{GROQ_BASE}/chat/completions",
                data=payload,
                headers={
                    "Content-Type":  "application/json",
                    "Authorization": f"Bearer {GROQ_API_KEY}",
                    "User-Agent":    "groq-bridge/1.0",
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                data = json.loads(resp.read())
                return data.get("choices", [{}])[0].get("message", {}).get("content", "(no output)")
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8", errors="replace")
            return f"[groq-bridge] HTTP {e.code} from Groq: {error_body}"
        except Exception as e:
            return f"[groq-bridge] Error calling Groq: {e}"

    def _send_json(self, model, text, in_tok, out_tok):
        resp = {
            "id":            f"msg_groq_{int(time.time())}",
            "type":          "message",
            "role":          "assistant",
            "content":       [{"type": "text", "text": text}],
            "model":         model,
            "stop_reason":   "end_turn",
            "stop_sequence": None,
            "usage":         {"input_tokens": in_tok, "output_tokens": out_tok},
        }
        body = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error_response(self, message):
        self._send_json("error", f"[groq-bridge] {message}", 0, 0)

    def log_message(self, fmt, *args):
        print(f"[groq-bridge] {fmt % args}", flush=True)


# ── Entrypoint ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if not GROQ_API_KEY:
        print("[groq-bridge] WARNING: GROQ_API_KEY is not set — requests will fail", flush=True)
    server = HTTPServer(("127.0.0.1", BRIDGE_PORT), BridgeHandler)
    print(f"[groq-bridge] Groq bridge listening on 127.0.0.1:{BRIDGE_PORT} "
          f"(model={GROQ_MODEL}, base={GROQ_BASE})", flush=True)
    server.serve_forever()
