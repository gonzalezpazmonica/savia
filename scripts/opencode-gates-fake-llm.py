#!/usr/bin/env python3
"""Fake OpenAI-compatible chat server for scripts/opencode-gates-v2-real.sh.

It makes a real OpenCode engine issue a real tool call without any model or network:
the user prompt carries a directive, the server answers with the matching tool call,
and when the tool result comes back it answers "ok" and appends the result to the log.

  RUN: <command>     -> tool call  <shell_tool>{command}
  READ: <path>       -> tool call  read{<path_key>: path}
  WRITE: <path>      -> tool call  write{<path_key>: path, content}
  anything else      -> plain text "ok"

Tool names and the path key differ between OpenCode 1 (bash, filePath) and 2 (shell, path).
The port is chosen by the OS and written to <port-file> once the server listens.
Every request is logged (one JSON line) with the last user text, all message text and the tool results.
"""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ap = argparse.ArgumentParser()
ap.add_argument("port_file")
ap.add_argument("log_file")
ap.add_argument("--shell-tool", default="shell")
ap.add_argument("--path-key", default="path")
ARGS = ap.parse_args()
PORT_FILE, LOG_FILE, SHELL_TOOL, PATH_KEY = ARGS.port_file, ARGS.log_file, ARGS.shell_tool, ARGS.path_key


def log(entry):
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(p.get("text", "") for p in content if isinstance(p, dict))
    return ""


def directive(messages):
    for m in reversed(messages):
        if m.get("role") == "user":
            t = text_of(m.get("content"))
            for key, tool in (("RUN:", SHELL_TOOL), ("READ:", "read"), ("WRITE:", "write")):
                if key in t:
                    arg = t.split(key, 1)[1].strip().splitlines()[0].strip()
                    if tool == "read":
                        return tool, {PATH_KEY: arg}
                    if tool == "write":
                        return tool, {PATH_KEY: arg, "content": "x"}
                    return tool, {"command": arg}
            return None
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
        messages = body.get("messages", [])
        tool_results = [text_of(m.get("content")) for m in messages if m.get("role") == "tool"]
        wanted = None if tool_results else directive(messages)
        users = [text_of(m.get("content")) for m in messages if m.get("role") == "user"]
        log({"path": self.path, "tools_offered": [t["function"]["name"] for t in body.get("tools", [])],
             "user": users[-1] if users else "", "text": "\n".join(text_of(m.get("content")) for m in messages),
             "tool_results": tool_results, "directive": wanted})
        if not body.get("stream"):
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.end_headers()

        def chunk(delta, finish=None):
            payload = {"id": "c1", "object": "chat.completion.chunk", "created": 0, "model": "m",
                       "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            self.wfile.write(f"data: {json.dumps(payload)}\n\n".encode())
            self.wfile.flush()

        if wanted:
            name, args = wanted
            chunk({"role": "assistant", "tool_calls": [{"index": 0, "id": "call_1", "type": "function",
                                                         "function": {"name": name, "arguments": json.dumps(args)}}]})
            chunk({}, "tool_calls")
        else:
            chunk({"role": "assistant", "content": "ok"})
            chunk({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
