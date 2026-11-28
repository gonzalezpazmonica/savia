"""PUT /git-config: credential.helper solo admite helpers conocidos.

Barrido Python 2026-11-27 (hallazgo fuera de clase): la expresión anterior
admitía «/», así que una ruta absoluta (/tmp/x) o un nombre con «../» quedaba
como credential.helper global y git ejecutaba ese binario en cada operación
con credenciales. Ahora es una lista cerrada.
"""
import http.client
import http.server
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

SPEC = importlib.util.spec_from_file_location(
    "savia_bridge_credhelper", ROOT / "scripts" / "savia-bridge.py"
)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class CredentialHelperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.gitconfig = self.home / "gitconfig"
        self.gitconfig.write_text("")
        env = {"HOME": str(self.home), "GIT_CONFIG_GLOBAL": str(self.gitconfig),
               "GIT_CONFIG_NOSYSTEM": "1"}
        self.patches = [
            patch.dict(os.environ, env),
            patch.object(bridge.SaviaBridgeHandler, "_check_auth", lambda self: True),
            patch.object(bridge.SaviaBridgeHandler, "log_message", lambda *a: None),
        ]
        for p in self.patches:
            p.start()
        self.server = http.server.HTTPServer(("127.0.0.1", 0), bridge.SaviaBridgeHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def _put(self, body):
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=10)
        conn.request("PUT", "/git-config", body=json.dumps(body).encode(),
                     headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        status = resp.status
        resp.read()
        conn.close()
        return status

    def _helper(self):
        r = subprocess.run(["git", "config", "--global", "credential.helper"],
                           capture_output=True, text=True)
        return r.stdout.strip()

    def test_absolute_path_is_rejected(self):
        self.assertEqual(self._put({"credential_helper": "/tmp/evil-helper"}), 400)
        self.assertEqual(self._helper(), "")

    def test_relative_traversal_is_rejected(self):
        for val in ("../../tmp/evil", "store/../../x", "./evil", "evil-helper"):
            with self.subTest(val=val):
                self.assertEqual(self._put({"credential_helper": val}), 400)
                self.assertEqual(self._helper(), "")

    def test_non_string_is_rejected(self):
        self.assertEqual(self._put({"credential_helper": ["store"]}), 400)
        self.assertEqual(self._helper(), "")

    def test_known_helpers_are_accepted(self):
        for val in ("store", "cache", "manager", "manager-core", "osxkeychain",
                    "libsecret", "wincred"):
            with self.subTest(val=val):
                self.assertEqual(self._put({"credential_helper": val}), 200)
                self.assertEqual(self._helper(), val)

    def test_empty_unsets(self):
        self.assertEqual(self._put({"credential_helper": "store"}), 200)
        self.assertEqual(self._put({"credential_helper": ""}), 200)
        self.assertEqual(self._helper(), "")


if __name__ == "__main__":
    unittest.main()
