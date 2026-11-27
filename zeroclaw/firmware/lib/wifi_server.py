# ZeroClaw WiFi HTTP server — enables wireless Savia↔ESP32 comms
# Runs a minimal HTTP server on the ESP32 for receiving commands
# and sending responses over WiFi instead of serial USB.
import json
import socket
import gc


class MiniHTTPServer:
    """Tiny HTTP server for ESP32 — handles JSON commands over WiFi.

    Endpoints:
      GET  /ping           → {"pong": true, "ip": "..."}
      POST /cmd            → execute command, return JSON   (token)
      GET  /status         → device info                    (token)

    SE-442 #25: binds only to the STA interface address (not every
    interface) and refuses to start without a shared token of
    MIN_TOKEN_LEN+ chars; /cmd and /status need header X-Zeroclaw-Token.
    """
    MIN_TOKEN_LEN = 16

    def __init__(self, handler, port=80, token=None):
        self.handler = handler
        self.port = port
        self.token = token or ""
        self.sock = None

    def start(self):
        """Start listening on the STA IP. Non-blocking via poll()."""
        if len(self.token) < self.MIN_TOKEN_LEN:
            raise ValueError("http_token missing or shorter than %d chars" % self.MIN_TOKEN_LEN)
        import network
        ip = network.WLAN(network.STA_IF).ifconfig()[0]
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((ip, self.port))
        self.sock.listen(2)
        self.sock.setblocking(False)
        print(f"HTTP server on {ip}:{self.port}")
        return ip

    def _authorized(self, lines):
        """Constant-time compare of X-Zeroclaw-Token (no hmac in MicroPython)."""
        got = ""
        for ln in lines[1:]:
            if not ln:
                break
            if ':' in ln and ln.split(':', 1)[0].strip().lower() == 'x-zeroclaw-token':
                got = ln.split(':', 1)[1].strip()
        want = self.token
        if not want or len(got) != len(want):
            return False
        diff = 0
        for a, b in zip(got, want):
            diff |= ord(a) ^ ord(b)
        return diff == 0

    def poll(self):
        """Check for incoming requests. Non-blocking."""
        if not self.sock:
            return
        try:
            cl, addr = self.sock.accept()
        except OSError:
            return  # No connection waiting
        try:
            cl.settimeout(2)
            request = cl.recv(2048).decode('utf-8', 'ignore')
            response = self._handle(request)
            cl.send("HTTP/1.0 200 OK\r\n")
            cl.send("Content-Type: application/json\r\n")
            cl.send("Access-Control-Allow-Origin: *\r\n")
            cl.send(f"Content-Length: {len(response)}\r\n")
            cl.send("\r\n")
            cl.send(response)
        except Exception as e:
            try:
                err = json.dumps({"error": str(e)})
                cl.send(f"HTTP/1.0 500 Error\r\n\r\n{err}")
            except Exception:
                pass
        finally:
            cl.close()
            gc.collect()

    def _handle(self, request):
        """Route request to handler."""
        lines = request.split('\r\n')
        if not lines:
            return json.dumps({"error": "empty request"})
        method, path = "GET", "/"
        parts = lines[0].split(' ')
        if len(parts) >= 2:
            method, path = parts[0], parts[1]

        if path == "/ping":
            import network
            ip = network.WLAN(network.STA_IF).ifconfig()[0]
            return json.dumps({"pong": True, "ip": ip})

        if path in ("/status", "/cmd") and not self._authorized(lines):
            return json.dumps({"error": "unauthorized"})

        if path == "/status":
            return json.dumps(self.handler.process("info"))

        if path == "/cmd" and method == "POST":
            # Extract body
            body = ""
            if '\r\n\r\n' in request:
                body = request.split('\r\n\r\n', 1)[1]
            if body:
                result = self.handler.process(body)
                return json.dumps(result)
            return json.dumps({"error": "no body"})

        return json.dumps({"error": f"unknown: {method} {path}",
                           "routes": ["/ping", "/status", "/cmd"]})

    def stop(self):
        if self.sock:
            self.sock.close()
            self.sock = None
