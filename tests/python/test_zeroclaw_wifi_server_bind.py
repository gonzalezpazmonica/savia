"""SE-442 alerta #25 (py/bind-socket-all-network-interfaces).

El servidor HTTP del firmware escuchaba en todas las interfaces sin
autenticación. Tras el arreglo: enlaza solo a la IP de la interfaz STA, no
arranca sin token y rechaza /status y /cmd sin la cabecera X-Zeroclaw-Token.

Ejecutar: python3 -m unittest tests/python/test_zeroclaw_wifi_server_bind.py
"""
import json
import socket
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "zeroclaw" / "firmware"))

STA_IP = "203.0.113.23"  # TEST-NET-3 (RFC 5737), solo documentación
ANY = ".".join(["0"] * 4)
TOKEN = "s3cret-token-0123"


class FakeWLAN:
    def __init__(self, _iface):
        pass

    def ifconfig(self):
        return (STA_IP, "255.255.255.0", "203.0.113.1", "203.0.113.53")


class FakeSocket:
    bound = None

    def __init__(self, *a, **k):
        pass

    def setsockopt(self, *a):
        pass

    def bind(self, addr):
        FakeSocket.bound = addr

    def listen(self, n):
        pass

    def setblocking(self, b):
        pass

    def close(self):
        pass


class Handler:
    def __init__(self):
        self.calls = []

    def process(self, cmd):
        self.calls.append(cmd)
        return {"ok": True, "cmd": cmd}


def _req(method, path, token=None, body=""):
    head = f"{method} {path} HTTP/1.0\r\n"
    if token is not None:
        head += f"X-Zeroclaw-Token: {token}\r\n"
    return head + "\r\n" + body


class WifiServerBindTest(unittest.TestCase):
    def setUp(self):
        net = types.ModuleType("network")
        net.STA_IF = 0
        net.WLAN = FakeWLAN
        self._mods = mock.patch.dict(sys.modules, {"network": net})
        self._mods.start()
        sys.modules.pop("lib.wifi_server", None)
        sys.modules.pop("lib", None)
        self._sock = mock.patch.object(socket, "socket", FakeSocket)
        self._sock.start()
        FakeSocket.bound = None
        from lib.wifi_server import MiniHTTPServer
        self.cls = MiniHTTPServer

    def tearDown(self):
        self._sock.stop()
        self._mods.stop()

    def _server(self, token=TOKEN):
        return self.cls(Handler(), port=8080, token=token)

    def test_bind_solo_a_la_ip_sta(self):
        srv = self._server()
        self.assertEqual(srv.start(), STA_IP)
        self.assertEqual(FakeSocket.bound, (STA_IP, 8080))
        self.assertNotEqual(FakeSocket.bound[0], ANY)

    def test_sin_token_no_arranca(self):
        for tok in (None, "", "corto"):
            with self.subTest(tok=tok):
                with self.assertRaises(ValueError):
                    self._server(tok).start()
        self.assertIsNone(FakeSocket.bound)

    def test_rutas_con_efecto_exigen_token(self):
        for path, method, body in (("/status", "GET", ""), ("/cmd", "POST", "info")):
            with self.subTest(path=path):
                srv = self._server()
                for tok in (None, "otro-token-cualquiera"):
                    out = json.loads(srv._handle(_req(method, path, tok, body)))
                    self.assertEqual(out, {"error": "unauthorized"})
                self.assertEqual(srv.handler.calls, [])
                out = json.loads(srv._handle(_req(method, path, TOKEN, body)))
                self.assertIs(out.get("ok"), True)

    def test_ping_sigue_abierto(self):
        srv = self._server()
        out = json.loads(srv._handle(_req("GET", "/ping")))
        self.assertEqual(out, {"pong": True, "ip": STA_IP})


if __name__ == "__main__":
    unittest.main()
