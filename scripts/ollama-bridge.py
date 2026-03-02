#!/usr/bin/env python3
"""
ollama-bridge.py — Local HTTP bridge: OpenClaw → Ollama

Listens on 127.0.0.1:3002.
Accepts POST /v1/messages in Anthropic Messages API format.
Translates to Ollama /api/chat calls (streaming NDJSON).
Returns Anthropic-compatible SSE or JSON responses.

Config via environment variables:
  OLLAMA_HOST   — Ollama base URL (default: http://ollama:11434)
  OLLAMA_MODEL  — model to use (default: qwen2.5-coder:7b)
  BRIDGE_PORT   — port to listen on (default: 3002)
"""

import json
import os
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

# ── Config ─────────────────────────────────────────────────────────────────
BRIDGE_PORT  = int(os.environ.get("BRIDGE_PORT", 3002))
OLLAMA_HOST  = os.environ.get("OLLAMA_HOST", "http://ollama:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5-coder:7b")
REQUEST_TIMEOUT = 300  # seconds


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


def _build_ollama_messages(system, messages):
    """Convert Anthropic message list + system prompt → Ollama message list."""
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
        model      = body.get("model", OLLAMA_MODEL)
        system_raw = body.get("system", "")
        system     = _extract_text(system_raw) if isinstance(system_raw, list) else system_raw
        messages   = body.get("messages", [])

        ollama_messages = _build_ollama_messages(system, messages)
        print(f"[ollama-bridge] Request: model={model} stream={streaming} msgs={len(messages)}", flush=True)

        if streaming:
            self._handle_streaming(model, ollama_messages)
        else:
            response_text = self._call_ollama_sync(model, ollama_messages)
            in_tok  = _approx_tokens(ollama_messages)
            out_tok = max(1, len(response_text) // 4)
            self._send_json(model, response_text, in_tok, out_tok)

    # ── Streaming path ────────────────────────────────────────────────────────

    def _handle_streaming(self, model, messages):
        in_tok = _approx_tokens(messages)
        msg_id = f"msg_ollama_{int(time.time())}"

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
            "model":    model,
            "messages": messages,
            "stream":   True,
        }).encode()

        try:
            req = urllib.request.Request(
                f"{OLLAMA_HOST}/api/chat",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                for raw_line in resp:
                    raw_line = raw_line.strip()
                    if not raw_line:
                        continue
                    try:
                        chunk = json.loads(raw_line)
                    except json.JSONDecodeError:
                        continue
                    delta = chunk.get("message", {}).get("content", "")
                    if delta:
                        total_text += delta
                        try:
                            emit("content_block_delta", {
                                "type": "content_block_delta", "index": 0,
                                "delta": {"type": "text_delta", "text": delta},
                            })
                        except Exception:
                            return  # client disconnected
                    if chunk.get("done"):
                        break
        except Exception as e:
            error_text = f"[ollama-bridge] Error calling Ollama: {e}"
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

    def _call_ollama_sync(self, model, messages):
        payload = json.dumps({
            "model":    model,
            "messages": messages,
            "stream":   False,
        }).encode()
        try:
            req = urllib.request.Request(
                f"{OLLAMA_HOST}/api/chat",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                data = json.loads(resp.read())
                return data.get("message", {}).get("content", "(no output)")
        except Exception as e:
            return f"[ollama-bridge] Error calling Ollama: {e}"

    def _send_json(self, model, text, in_tok, out_tok):
        resp = {
            "id":            f"msg_ollama_{int(time.time())}",
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

    def log_message(self, fmt, *args):
        print(f"[ollama-bridge] {fmt % args}", flush=True)


# ── Entrypoint ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", BRIDGE_PORT), BridgeHandler)
    print(f"[ollama-bridge] Ollama bridge listening on 127.0.0.1:{BRIDGE_PORT} "
          f"(model={OLLAMA_MODEL}, host={OLLAMA_HOST})", flush=True)
    server.serve_forever()
