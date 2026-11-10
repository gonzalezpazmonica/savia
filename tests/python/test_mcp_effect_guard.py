"""Tests unitarios del núcleo del guard de efectos MCP/WebFetch/WebSearch (SE-508 S1).

El remoto se sustituye por un lector falso (`remote_reader`); el mecanismo git real, con un repositorio
bare de fixture, lo cubren los tests bats (tests/hooks/test-se508-mcp-effect-guard.bats).
Corre con `python3 -m unittest` o con pytest.
"""
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("mcp_effect_guard", ROOT / ".claude/hooks/lib/mcp_effect_guard.py")
g = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(g)

CATALOG = """# fixture
mcp__claude_ai_Gmail__send_message: write
mcp__claude_ai_Gmail__get_message: read_only
mcp__github__merge_pull_request: merge
mcp__github__create_pull_request: write
"""
HOSTS = "docs.ejemplo.org\n"
CORE_UNTIL = 'OBSERVE_UNTIL = "2026-11-24"\n'
TODAY_OBSERVE = "2026-11-10"
TODAY_AFTER = "2026-11-25"
SEND = "mcp__claude_ai_Gmail__send_message"
GET = "mcp__claude_ai_Gmail__get_message"
MERGE = "mcp__github__merge_pull_request"


def remote(catalog=CATALOG, hosts=HOSTS, core=CORE_UNTIL):
    return lambda url: {g.CATALOG_PATH: catalog, g.HOSTS_PATH: hosts, g.CORE_PATH: core}


def no_remote(url):
    return None


def env(**kw):
    base = {"SAVIA_MCP_GUARD_TEST": "1", "BATS_TEST_FILENAME": "x", "SAVIA_MCP_GUARD_TEST_TODAY": TODAY_OBSERVE}
    base.update(kw)
    return base


def after(**kw):
    return env(SAVIA_MCP_GUARD_TEST_TODAY=TODAY_AFTER, **kw)


def call(tool, args=None):
    return json.dumps({"tool_name": tool, "tool_input": args or {}}).encode()


class GuardTest(unittest.TestCase):
    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self.tmp = pathlib.Path(self._d.name)

    def tearDown(self):
        self._d.cleanup()

    def tree(self, catalog=CATALOG, hosts=HOSTS, core=CORE_UNTIL):
        (self.tmp / "config").mkdir(exist_ok=True)
        for rel, text in (("config/mcp-effect-catalog.yaml", catalog), ("config/webfetch-allow-hosts", hosts),
                          (".claude/hooks/lib/mcp_effect_guard.py", core)):
            p = self.tmp / rel
            if text is None:
                if p.exists():
                    p.unlink()
                continue
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        return str(self.tmp)

    def run_guard(self, payload, e=None, rr=None, tree=None, **kw):
        return g.decide(payload, tree or self.tree(), e or env(), remote_reader=rr or remote(), **kw)

    # AC-1
    def test_read_only_passes_without_decision(self):
        v = self.run_guard(call(GET))
        self.assertEqual(v.decision, "pass")
        self.assertIsNone(v.log)

    # AC-2
    def test_write_asks_with_destination_and_effect(self):
        v = self.run_guard(call(SEND, {"to": ["a@x.test", "b@x.test"], "cc": ["c@x.test"], "subject": "Plan de la semana"}))
        self.assertEqual(v.decision, "ask")
        self.assertIn('Savia quiere enviar un correo a 3 personas (asunto: "Plan de la semana"). ¿Lo envío?', v.reason)
        self.assertIn("destino: 3 personas", v.reason)
        self.assertIn("efecto: enviar un correo", v.reason)

    # AC-2b
    def test_loosened_tree_catalog_still_asks(self):
        loose = CATALOG.replace("send_message: write", "send_message: read_only")
        self.assertEqual(self.run_guard(call(SEND), tree=self.tree(catalog=loose)).decision, "ask")

    def test_hardened_tree_catalog_applies(self):
        hard = CATALOG.replace("get_message: read_only", "get_message: write")
        self.assertEqual(self.run_guard(call(GET), tree=self.tree(catalog=hard)).decision, "ask")

    # AC-2d
    def test_no_remote_turns_read_only_into_ask(self):
        self.assertEqual(self.run_guard(call(GET), rr=no_remote).decision, "ask")

    def test_no_remote_autonomous_denies(self):
        self.assertEqual(self.run_guard(call(GET), e=env(SAVIA_AUTONOMOUS_RUN="1"), rr=no_remote).decision, "deny")

    def test_no_remote_allows_no_host(self):
        v = self.run_guard(call("WebFetch", {"url": "https://docs.ejemplo.org/guia"}), rr=no_remote)
        self.assertEqual(v.decision, "ask")

    def test_remote_until_earlier_wins(self):
        v = self.run_guard(call("WebFetch", {"url": "https://otro.test/"}),
                           tree=self.tree(core='OBSERVE_UNTIL = "2027-01-01"\n'),
                           rr=remote(core='OBSERVE_UNTIL = "2026-11-01"\n'))
        self.assertEqual(v.decision, "ask")  # el remoto ya caducó: enforce

    # AC-3
    def test_merge_denied_citing_se343(self):
        v = self.run_guard(call(MERGE, {"pull_number": 1}))
        self.assertEqual(v.decision, "deny")
        self.assertIn("SE-343", v.reason)

    def test_merge_in_remote_only_is_denied(self):
        loose = CATALOG.replace("merge_pull_request: merge", "merge_pull_request: read_only")
        self.assertEqual(self.run_guard(call(MERGE), tree=self.tree(catalog=loose)).decision, "deny")

    # AC-4
    def test_uncatalogued_asks(self):
        v = self.run_guard(call("mcp__claude_ai_Nuevo__hacer_algo"))
        self.assertEqual(v.decision, "ask")
        self.assertIn("sin clasificar", v.reason)

    def test_missing_from_remote_counts_as_uncatalogued(self):
        self.assertEqual(self.run_guard(call(GET), rr=remote(catalog=None)).decision, "ask")

    # AC-5
    def test_bad_stdin_asks(self):
        for raw in (b"", b"   ", b"{no json", b"[]", b'{"tool_input":{}}', b"\xff\xfe",
                    b'{"tool_name":"mcp__claude_ai_Gmail__get_message","tool_input":"x"}'):
            with self.subTest(raw=raw):
                self.assertEqual(self.run_guard(raw).decision, "ask")

    def test_webfetch_without_url_asks(self):
        self.assertEqual(self.run_guard(call("WebFetch", {})).decision, "ask")

    def test_missing_or_bad_catalog_asks(self):
        for catalog in (None, "mcp__x__y: escribe\n", "a: write\na: read_only\n", ""):
            for tool, args in ((GET, {}), ("WebFetch", {"url": "https://docs.ejemplo.org/"}), ("WebSearch", {"query": "x"})):
                with self.subTest(catalog=catalog, tool=tool):
                    self.assertEqual(self.run_guard(call(tool, args), tree=self.tree(catalog=catalog)).decision, "ask")

    def test_tool_out_of_scope_not_decided(self):
        self.assertEqual(self.run_guard(call("Bash", {"command": "ls"})).decision, "pass")

    # AC-6
    def test_webfetch_allowed_host_passes(self):
        v = self.run_guard(call("WebFetch", {"url": "https://docs.ejemplo.org/guia/instalar"}), e=after())
        self.assertEqual(v.decision, "pass")

    def test_webfetch_enforce_asks(self):
        for url in ("https://docs.ejemplo.org/api?token=abc123", "https://docs.ejemplo.org/a#frag",
                    "https://docs.ejemplo.org/" + "a/" * 100, "https://docs.ejemplo.org/" + "b" * 65,
                    "https://otro.test/limpio"):
            with self.subTest(url=url):
                self.assertEqual(self.run_guard(call("WebFetch", {"url": url}), e=after()).decision, "ask")

    def test_webfetch_observe_logs_instead_of_asking(self):
        v = self.run_guard(call("WebFetch", {"url": "https://otro.test/x?q=1"}))
        self.assertEqual(v.decision, "pass")
        self.assertEqual(v.log["decision"], "would_ask")

    def test_path_limit_200(self):
        path = "/" + "/".join(["c" * 49] * 4)
        self.assertEqual(len(path), 200)
        ok = self.run_guard(call("WebFetch", {"url": "https://docs.ejemplo.org" + path}), e=after())
        over = self.run_guard(call("WebFetch", {"url": "https://docs.ejemplo.org" + path + "c"}), e=after())
        self.assertEqual((ok.decision, over.decision), ("pass", "ask"))

    def test_prototype_message_for_unknown_site(self):
        v = self.run_guard(call("WebFetch", {"url": "https://datos-ejemplo.test/x?" + "q" * 142}), e=after())
        self.assertIn("Savia quiere abrir una web que no está en tu lista. Sitio: datos-ejemplo.test.", v.reason)
        self.assertIn("La dirección lleva 142 caracteres de más (datos después del ?).", v.reason)

    # AC-7
    def test_host_boundaries(self):
        for url in ("https://docs.ejemplo.org.atacante.net/", "https://atacante.net/docs.ejemplo.org",
                    "https://docs.ejemplo.org@atacante.test/", "https://docs.ejemplo.org:8443/", "http://docs.ejemplo.org/"):
            with self.subTest(url=url):
                self.assertEqual(self.run_guard(call("WebFetch", {"url": url}), e=after()).decision, "ask")

    def test_host_normalization_allows_case_and_trailing_dot(self):
        v = self.run_guard(call("WebFetch", {"url": "https://DOCS.Ejemplo.org./guia"}), e=after())
        self.assertEqual(v.decision, "pass")

    def test_host_needs_both_lists(self):
        v = self.run_guard(call("WebFetch", {"url": "https://nuevo.test/"}), e=after(),
                           tree=self.tree(hosts="docs.ejemplo.org\nnuevo.test\n"))
        self.assertEqual(v.decision, "ask")

    # AC-8
    def test_claude_never_delegates(self):
        for var in ({"SAVIA_GATES_PIN": "1"}, {"SAVIA_MCP_GUARD": "space"}):
            with self.subTest(var=var):
                v = self.run_guard(call(SEND), e=env(**var), frontend="claude", pin_fixed=True)
                self.assertEqual(v.decision, "ask")

    def test_opencode_pinned_delegates_with_log(self):
        v = self.run_guard(call(SEND), e=env(SAVIA_GATES_PIN="1"), frontend="opencode", pin_fixed=True)
        self.assertEqual(v.decision, "pass")
        self.assertEqual(v.log["decision"], "delegated")

    def test_opencode_space_var_without_pin_asks(self):
        v = self.run_guard(call(SEND), e=env(SAVIA_MCP_GUARD="space"), frontend="opencode", pin_fixed=False)
        self.assertEqual(v.decision, "ask")

    def test_merge_never_delegated(self):
        v = self.run_guard(call(MERGE), e=env(SAVIA_GATES_PIN="1", SAVIA_MCP_GUARD="space"), frontend="opencode", pin_fixed=True)
        self.assertEqual(v.decision, "deny")

    # AC-8b
    def test_autonomous_denies_before_observe_until(self):
        for payload in (call(SEND), call("mcp__claude_ai_Nuevo__x"), b"{malo", call("WebFetch", {"url": "https://otro.test/"})):
            with self.subTest(payload=payload):
                self.assertEqual(self.run_guard(payload, e=env(SAVIA_AUTONOMOUS_RUN="1")).decision, "deny")

    def test_run_id_counts_as_autonomous(self):
        self.assertEqual(self.run_guard(call(SEND), e=env(SAVIA_RUN_ID="r1")).decision, "deny")

    def test_autonomous_websearch_observed(self):
        v = self.run_guard(call("WebSearch", {"query": "algo"}), e=env(SAVIA_AUTONOMOUS_RUN="1"))
        self.assertEqual(v.decision, "pass")
        self.assertEqual(v.log["decision"], "observed")

    def test_autonomous_never_delegates(self):
        v = self.run_guard(call(SEND), e=env(SAVIA_AUTONOMOUS_RUN="1", SAVIA_GATES_PIN="1"), frontend="opencode", pin_fixed=True)
        self.assertEqual(v.decision, "deny")

    # AC-8c
    def test_until_yesterday_enforces(self):
        v = self.run_guard(call("WebSearch", {"query": "x"}), e=env(SAVIA_MCP_GUARD_TEST_TODAY="2026-11-25"))
        self.assertEqual(v.decision, "ask")

    def test_until_today_still_observes(self):
        v = self.run_guard(call("WebSearch", {"query": "x"}), e=env(SAVIA_MCP_GUARD_TEST_TODAY="2026-11-24"))
        self.assertEqual(v.decision, "pass")

    def test_unreadable_tree_constant_enforces(self):
        v = self.run_guard(call("WebSearch", {"query": "x"}), tree=self.tree(core="OBSERVE_UNTIL = mañana\n"))
        self.assertEqual(v.decision, "ask")

    def test_remote_without_core_uses_tree(self):
        self.assertEqual(self.run_guard(call("WebSearch", {"query": "x"}), rr=remote(core=None)).decision, "pass")

    def test_remote_core_without_constant_enforces(self):
        v = self.run_guard(call("WebSearch", {"query": "x"}), rr=remote(core="# sin constante\n"))
        self.assertEqual(v.decision, "ask")

    # Inyección de pruebas solo dentro de bats
    def test_injection_requires_bats(self):
        e = {"SAVIA_MCP_GUARD_TEST": "1", "SAVIA_MCP_GUARD_TEST_REMOTE": "/tmp/x"}
        self.assertEqual(g.remote_url(e), g.CANONICAL_REMOTE)
        e["BATS_TEST_FILENAME"] = "t.bats"
        self.assertEqual(g.remote_url(e), "/tmp/x")

    def test_real_constant_is_a_date(self):
        text = (ROOT / ".claude/hooks/lib/mcp_effect_guard.py").read_text(encoding="utf-8")
        self.assertIsNotNone(g.parse_until(text))


if __name__ == "__main__":
    unittest.main()
