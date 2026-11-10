#!/usr/bin/env python3
"""Servidor MCP falso por stdio para tests/test-mcp-tool-design.bats.

FAKE_MCP_MODE: paginate (catálogo de catalog-ok.json en una herramienta por página),
silent (lee y no contesta), exit (sale sin responder), error (tools/list devuelve error),
initerror (initialize devuelve error), burst (cada respuesta va precedida de una
notificación en la misma escritura), partial (escribe media línea sin \\n y calla),
endless (nextCursor infinito).
"""
import json, os, sys

mode = os.environ.get("FAKE_MCP_MODE", "paginate")
here = os.path.dirname(os.path.abspath(__file__))
tools = json.load(open(os.path.join(here, "catalog-ok.json"), encoding="utf-8"))["tools"]
out = sys.stdout.buffer


def emit(obj):
    data = json.dumps(obj) + "\n"
    if mode == "burst":
        note = json.dumps({"jsonrpc": "2.0", "method": "notifications/message",
                           "params": {"level": "info", "data": "hola"}}) + "\n"
        data = note + data
    out.write(data.encode()); out.flush()


if mode == "exit":
    sys.exit(0)
for line in sys.stdin:
    msg = json.loads(line)
    if mode == "silent":
        continue
    mid, method = msg.get("id"), msg.get("method")
    if mid is None:
        continue
    if mode == "partial":
        out.write(b'{"jsonrpc": "2.0", "id": '); out.flush()
        continue
    if method == "initialize" and mode == "initerror":
        emit({"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": "version"}})
        continue
    if method == "initialize":
        res = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
               "serverInfo": {"name": "fake", "version": "0"}}
    elif method == "tools/list" and mode == "error":
        emit({"jsonrpc": "2.0", "id": mid, "error": {"code": -32603, "message": "boom"}})
        continue
    elif method == "tools/list" and mode == "endless":
        res = {"tools": [], "nextCursor": "otra"}
    elif method == "tools/list":
        i = int((msg.get("params") or {}).get("cursor") or 0)
        res = {"tools": tools[i:i + 1]}
        if i + 1 < len(tools):
            res["nextCursor"] = str(i + 1)
    else:
        res = {}
    emit({"jsonrpc": "2.0", "id": mid, "result": res})
