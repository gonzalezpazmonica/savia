#!/usr/bin/env python3
"""Servidor local de pruebas para hooks con red (tests bats).

Uso: server.py MODE PORTFILE
  ok         HTTP 200 a todo. GET devuelve {"models": []}. POST guarda el cuerpo
             en $MOCK_LOG (si existe) y responde con $MOCK_BODY (o {}).
  blackhole  Acepta conexiones TCP y nunca responde (servicio colgado).
Escribe el puerto elegido en PORTFILE cuando ya escucha. Solo 127.0.0.1.
"""
import os
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def _send(self, body):
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._send('{"models": [], "status": "ok"}')

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace")
        log = os.environ.get("MOCK_LOG")
        if log:
            with open(log, "a", encoding="utf-8") as f:
                f.write(body + "\n")
        self._send(os.environ.get("MOCK_BODY", "{}"))

    def log_message(self, *args):
        return


def write_port(path, port):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(str(port))
    os.replace(tmp, path)


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("ok", "blackhole"):
        print(__doc__, file=sys.stderr)
        return 2
    mode, portfile = sys.argv[1], sys.argv[2]
    if mode == "ok":
        srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        write_port(portfile, srv.server_address[1])
        srv.serve_forever()
        return 0
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    sock.listen(64)
    write_port(portfile, sock.getsockname()[1])
    held = []
    while True:
        conn, _ = sock.accept()
        held.append(conn)  # se retiene abierta sin responder nunca


if __name__ == "__main__":
    sys.exit(main())
