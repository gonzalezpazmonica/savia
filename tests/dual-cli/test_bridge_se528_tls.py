"""SE-528 S2b — el puente no arranca sin cifrar fuera de bucle local.

Si TLS no se puede preparar (falta openssl para generar el certificado, o el
certificado no carga) y la dirección de escucha no es de bucle local, el
puente se niega a arrancar con código 2 y un mensaje que dice cómo arreglarlo.
En bucle local sigue en HTTP con un aviso SECURITY bien visible. ``--no-tls``
explícito no cambia (modo sin sesión por cookie documentado en la spec).

Los tests de arranque lanzan el puente real con HOME temporal y un PATH que
solo contiene un ``claude`` falso (sin openssl): nunca se ejecuta un agente.
"""
import http.client
import importlib.util
import os
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

SPEC = importlib.util.spec_from_file_location(
    "savia_bridge_se528_tls", ROOT / "scripts" / "savia-bridge.py")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)

import bridge_auth  # noqa: E402

BRIDGE = ROOT / "scripts" / "savia-bridge.py"
OPENSSL = shutil.which("openssl")


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _missing_openssl(*_a, **_k):
    raise FileNotFoundError("openssl required for TLS certificate generation")


class TlsPolicyUnitTests(unittest.TestCase):
    def setUp(self):
        self.logs = []
        p = patch.object(bridge, "log", lambda m, level="INFO": self.logs.append((level, m)))
        p.start()
        self.addCleanup(p.stop)

    def test_prepare_tls_reports_missing_certificate_as_error(self):
        ctx, fp, err = bridge.prepare_tls(False, loader=_missing_openssl)
        self.assertIsNone(ctx)
        self.assertIsNone(fp)
        self.assertIn("openssl", err)

    def test_prepare_tls_reports_unloadable_certificate_as_error(self):
        with tempfile.TemporaryDirectory() as d:
            cert, key = Path(d, "cert.pem"), Path(d, "key.pem")
            cert.write_text("no es un certificado")
            key.write_text("no es una clave")
            ctx, _fp, err = bridge.prepare_tls(
                False, loader=lambda: (str(cert), str(key), "x"))
        self.assertIsNone(ctx)
        self.assertTrue(err)

    def test_prepare_tls_with_no_tls_is_not_an_error(self):
        called = []
        ctx, fp, err = bridge.prepare_tls(True, loader=lambda: called.append(1))
        self.assertEqual((ctx, fp, err), (None, None, None))
        self.assertEqual(called, [])

    def test_enforce_refuses_outside_loopback(self):
        for host in ("0.0.0.0", "::", "203.0.113.9"):
            with self.subTest(host=host), self.assertRaises(SystemExit) as cm:
                bridge.enforce_tls_policy(host, no_tls=False, tls_error="sin openssl")
            self.assertEqual(cm.exception.code, 2)
        self.assertTrue(any(lvl == "SECURITY" and "no arranca sin cifrar" in m
                            for lvl, m in self.logs))

    def test_enforce_refuses_name_resolving_outside_loopback(self):
        outside = lambda *_a: [(socket.AF_INET, 1, 6, "", ("203.0.113.9", 0))]
        with patch.object(bridge_auth.socket, "getaddrinfo", outside), \
                self.assertRaises(SystemExit):
            bridge.enforce_tls_policy("localhost", no_tls=False, tls_error="x")

    def test_enforce_allows_loopback_with_visible_warning(self):
        for host in ("127.0.0.1", "::1"):
            self.logs.clear()
            bridge.enforce_tls_policy(host, no_tls=False, tls_error="sin openssl")
            self.assertTrue(any(lvl == "SECURITY" and "SIN CIFRAR" in m
                                for lvl, m in self.logs), host)

    def test_enforce_is_noop_with_tls_or_explicit_no_tls(self):
        bridge.enforce_tls_policy("0.0.0.0", no_tls=False, tls_error=None)
        bridge.enforce_tls_policy("0.0.0.0", no_tls=True, tls_error=None)
        self.assertFalse(any(lvl == "SECURITY" for lvl, _ in self.logs))

    def test_refusal_message_says_how_to_fix(self):
        msg = bridge_auth.tls_refusal_message("0.0.0.0", "sin openssl", "/cfg")
        for hint in ("openssl", "cert.pem", "key.pem", "--host 127.0.0.1", "--no-tls"):
            self.assertIn(hint, msg)


class TlsStartupTests(unittest.TestCase):
    """Arranque real del puente (subproceso)."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name, "home")
        self.home.mkdir()
        self.bin = Path(tmp.name, "bin")
        self.bin.mkdir()
        fake = self.bin / "claude"
        fake.write_text("#!/bin/sh\nexit 0\n")
        fake.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin))
        self.port = _free_port()

    def _start(self, host):
        proc = subprocess.Popen(
            [sys.executable, str(BRIDGE), "--no-install-server", "--host", host,
             "--port", str(self.port), "--auth-token", "T" * 43],
            env=self.env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        def stop():
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            proc.stdout.close()
        self.addCleanup(stop)
        return proc

    def _wait_port(self, proc, timeout=20):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if proc.poll() is not None:
                self.fail(f"el puente salió con {proc.returncode}: {proc.stdout.read()}")
            with socket.socket() as c:
                if c.connect_ex(("127.0.0.1", self.port)) == 0:
                    return
            time.sleep(0.1)
        self.fail("el puente no abrió el puerto")

    def _bridge_log(self):
        log = self.home / ".savia" / "bridge" / "bridge.log"
        return log.read_text() if log.exists() else ""

    def test_missing_cert_on_all_interfaces_refuses_and_keeps_port_closed(self):
        proc = self._start("0.0.0.0")
        out, _ = proc.communicate(timeout=30)
        self.assertEqual(proc.returncode, 2, out)
        self.assertIn("no arranca sin cifrar", out)
        self.assertIn("--host 127.0.0.1", out)
        with socket.socket() as c:
            self.assertNotEqual(c.connect_ex(("127.0.0.1", self.port)), 0)

    def test_missing_cert_on_loopback_starts_http_with_warning(self):
        proc = self._start("127.0.0.1")
        self._wait_port(proc)
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("GET", "/health")
        self.assertEqual(conn.getresponse().status, 200)
        conn.close()
        self.assertIn("SIN CIFRAR", self._bridge_log())

    @unittest.skipUnless(OPENSSL, "openssl no disponible para crear el certificado de prueba")
    def test_valid_cert_starts_with_tls(self):
        cfg = self.home / ".savia" / "bridge"
        cfg.mkdir(parents=True)
        subprocess.run(
            [OPENSSL, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
             "-keyout", str(cfg / "key.pem"), "-out", str(cfg / "cert.pem"),
             "-subj", "/CN=localhost"], check=True, capture_output=True)
        proc = self._start("0.0.0.0")
        self._wait_port(proc)
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        conn = http.client.HTTPSConnection("127.0.0.1", self.port, timeout=10, context=ctx)
        conn.request("GET", "/health")
        self.assertEqual(conn.getresponse().status, 200)
        conn.close()
        self.assertIn("TLS: ENABLED", self._bridge_log())
        self.assertNotIn("SIN CIFRAR", self._bridge_log())


if __name__ == "__main__":
    unittest.main()
