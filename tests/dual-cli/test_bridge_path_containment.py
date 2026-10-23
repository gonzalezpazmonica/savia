"""CodeQL py/path-injection: Savia Bridge must keep client paths inside the workspace."""
import http.client
import http.server
import importlib.util
import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

SPEC = importlib.util.spec_from_file_location(
    "savia_bridge_pathinj", ROOT / "scripts" / "savia-bridge.py"
)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class ContainPathTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.root = self.base / "savia"
        (self.root / "docs").mkdir(parents=True)
        (self.root / "docs" / "a.md").write_text("ok")
        self.sibling = self.base / "savia-other"
        self.sibling.mkdir()
        (self.sibling / "secret.txt").write_text("secret")

    def tearDown(self):
        self.tmp.cleanup()

    def test_relative_inside_is_allowed(self):
        target = bridge._contain_path(self.root, "docs/a.md")
        self.assertEqual(target, Path(os.path.realpath(self.root / "docs" / "a.md")))

    def test_empty_is_the_root(self):
        self.assertEqual(bridge._contain_path(self.root, ""), Path(os.path.realpath(self.root)))

    def test_dotdot_is_rejected(self):
        self.assertIsNone(bridge._contain_path(self.root, "../../etc/passwd"))
        self.assertIsNone(bridge._contain_path(self.root, "docs/../../x"))

    def test_sibling_with_same_prefix_is_rejected(self):
        # The old check was startswith(str(workspace)) without separator.
        self.assertIsNone(bridge._contain_path(self.root, "../savia-other/secret.txt"))

    def test_absolute_path_is_rejected(self):
        self.assertIsNone(bridge._contain_path(self.root, "/etc/passwd"))
        self.assertIsNone(bridge._contain_path(self.root, str(self.root / "docs" / "a.md")))

    def test_nul_byte_is_rejected(self):
        self.assertIsNone(bridge._contain_path(self.root, "docs/a.md\x00.txt"))

    def test_symlink_escaping_root_is_rejected(self):
        os.symlink(self.sibling, self.root / "out")
        self.assertIsNone(bridge._contain_path(self.root, "out/secret.txt"))
        self.assertIsNone(bridge._contain_path(self.root, "out"))

    def test_symlink_staying_inside_is_allowed(self):
        os.symlink(self.root / "docs", self.root / "alias")
        target = bridge._contain_path(self.root, "alias/a.md")
        self.assertEqual(target, Path(os.path.realpath(self.root / "docs" / "a.md")))

    def test_root_itself_behind_symlink_still_contains(self):
        link = self.base / "link-to-savia"
        os.symlink(self.root, link)
        self.assertIsNotNone(bridge._contain_path(link, "docs/a.md"))
        self.assertIsNone(bridge._contain_path(link, "../savia-other/secret.txt"))


class ProjectDirTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ws = Path(self.tmp.name) / "savia"
        (self.ws / "projects" / "alpha").mkdir(parents=True)
        self.outside = Path(self.tmp.name) / "outside"
        self.outside.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def test_valid_id_resolves_under_projects(self):
        self.assertEqual(
            bridge._project_dir(self.ws, "alpha"),
            Path(os.path.realpath(self.ws / "projects" / "alpha")),
        )
        self.assertIsNotNone(bridge._project_dir(self.ws, "new-project_2.v1"))

    def test_traversal_and_separators_are_rejected(self):
        for bad in ("..", ".", "...", "../outside", "../../x", "a/b", "/etc", "", "-x", "a\x00b"):
            with self.subTest(bad=bad):
                self.assertIsNone(bridge._project_dir(self.ws, bad))

    def test_non_string_is_rejected(self):
        self.assertIsNone(bridge._project_dir(self.ws, None))

    def test_project_symlink_escaping_is_rejected(self):
        os.symlink(self.outside, self.ws / "projects" / "evil")
        self.assertIsNone(bridge._project_dir(self.ws, "evil"))


class HandlerContainmentTests(unittest.TestCase):
    """End to end through SaviaBridgeHandler with auth bypassed."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.ws = self.home / "savia"
        (self.ws / "projects" / "alpha").mkdir(parents=True)
        (self.ws / "notes").mkdir()
        self.sibling = self.home / "savia-other"
        self.sibling.mkdir()
        self.patches = [
            patch.dict(os.environ, {"HOME": str(self.home), "SAVIA_WORKSPACE": str(self.ws)}),
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

    def _req(self, method, path, body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=10)
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Content-Type": "application/json"} if data else {}
        conn.request(method, path, body=data, headers=headers)
        resp = conn.getresponse()
        status, payload = resp.status, resp.read()
        conn.close()
        return status, payload

    def test_put_file_into_sibling_prefix_dir_is_blocked(self):
        status, _ = self._req("PUT", "/files/content",
                              {"path": "../savia-other/evil.sh", "content": "x"})
        self.assertEqual(status, 403)
        self.assertFalse((self.sibling / "evil.sh").exists())

    def test_put_file_with_absolute_path_is_blocked(self):
        target = self.home / "abs.txt"
        status, _ = self._req("PUT", "/files/content", {"path": str(target), "content": "x"})
        self.assertEqual(status, 403)
        self.assertFalse(target.exists())

    def test_put_file_through_escaping_symlink_is_blocked(self):
        os.symlink(self.sibling, self.ws / "notes" / "out")
        status, _ = self._req("PUT", "/files/content", {"path": "notes/out/evil.txt", "content": "x"})
        self.assertEqual(status, 403)
        self.assertFalse((self.sibling / "evil.txt").exists())

    def test_put_file_inside_workspace_is_saved(self):
        status, _ = self._req("PUT", "/files/content", {"path": "notes/ok.md", "content": "hola"})
        self.assertEqual(status, 200)
        self.assertEqual((self.ws / "notes" / "ok.md").read_text(), "hola")

    def test_get_file_from_sibling_prefix_dir_is_blocked(self):
        (self.sibling / "secret.md").write_text("secret")
        status, payload = self._req("GET", "/files/content?path=../savia-other/secret.md")
        self.assertEqual(status, 403)
        self.assertNotIn(b"secret\"", payload)

    def test_get_file_inside_workspace_is_served(self):
        (self.ws / "notes" / "r.md").write_text("leeme")
        status, payload = self._req("GET", "/files/content?path=notes/r.md")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(payload)["content"], "leeme")

    def test_list_sibling_prefix_dir_is_blocked(self):
        status, _ = self._req("GET", "/files?path=../savia-other")
        self.assertEqual(status, 403)

    def test_create_project_with_traversal_slug_is_rejected(self):
        status, _ = self._req("POST", "/projects", {"slug": "../../escaped"})
        self.assertEqual(status, 400)
        self.assertFalse((self.home / "escaped").exists())
        self.assertFalse((self.ws / "escaped").exists())

    def test_create_project_with_valid_slug_scaffolds(self):
        status, _ = self._req("POST", "/projects", {"slug": "beta"})
        self.assertEqual(status, 200)
        self.assertTrue((self.ws / "projects" / "beta" / "backlog" / "pbi").is_dir())

    def test_kanban_and_backlog_reject_traversal_project(self):
        for route in ("/kanban", "/timelog", "/approvals", "/backlog"):
            with self.subTest(route=route):
                status, _ = self._req("GET", f"{route}?project=../../savia-other")
                self.assertEqual(status, 400)

    def test_kanban_known_project_still_resolves(self):
        status, payload = self._req("GET", "/kanban?project=alpha")
        self.assertEqual(status, 404)
        self.assertIn(b"Mock data not found", payload)


if __name__ == "__main__":
    unittest.main()
