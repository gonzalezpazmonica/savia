"""Tests del núcleo Python del guard de cúpulas (SE-436 S5, .claude/hooks/lib/dome_guard.py).

Ejecuta la tabla compartida tests/hooks/fixtures/dome-guard-cases.json (la misma que usan la regla de
savia-gates y la prueba de paridad) más comprobaciones del analizador de órdenes y del registro.
"""
from __future__ import annotations

import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
CASES = ROOT / "tests/hooks/fixtures/dome-guard-cases.json"
SPEC = importlib.util.spec_from_file_location("dome_guard", ROOT / ".claude/hooks/lib/dome_guard.py")
dg = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dg)


def sub(value, ws: str):
    if isinstance(value, str):
        return value.replace("@WS@", ws)
    if isinstance(value, list):
        return [sub(v, ws) for v in value]
    if isinstance(value, dict):
        return {k: sub(v, ws) for k, v in value.items()}
    return value


def build_workspace(table: dict, case: dict) -> str:
    ws = os.path.realpath(tempfile.mkdtemp(prefix="dome-guard-"))
    for d in table["dirs"]:
        os.makedirs(os.path.join(ws, d), exist_ok=True)
    for f in table["files"]:
        Path(ws, f).write_text("x", encoding="utf-8")
    for link, target in case.get("links", []):
        os.symlink(sub(target, ws), os.path.join(ws, link))
    reg = table["registries"][case["registry"]]
    base = os.path.join(ws, "projects/savia-vaults/savia-vaults.domes.json")
    for key, path in (("base", base), ("local", dg.local_registry_path(base))):
        if key in reg:
            body = reg[key] if isinstance(reg[key], str) else json.dumps(sub(reg[key], ws))
            Path(path).write_text(body, encoding="utf-8")
    return ws


def run_case(table: dict, case: dict) -> tuple[dict, str]:
    ws = build_workspace(table, case)
    try:
        payload = {"hook_event_name": "PreToolUse", "tool_name": case["tool"],
                   "tool_input": sub(case["input"], ws), "session_id": "s1", "cwd": ws}
        if "ctx" in case:
            payload["dome_context"] = case["ctx"]
        env = {k: sub(v, ws) for k, v in case.get("env", {}).items()}
        out = io.StringIO()
        with mock.patch.dict(os.environ, env, clear=False), \
                mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), redirect_stdout(out):
            if "SAVIA_SPACE_DOMES_FILE" not in env:
                os.environ.pop("SAVIA_SPACE_DOMES_FILE", None)
            dg.main(["--root", ws])
        return json.loads(out.getvalue()), ws
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def check(table: dict, case: dict, got: dict) -> list[str]:
    errors = []
    notices = {f"@{k}@": v for k, v in table["notices"].items()}
    if got["decision"] != case["expect"]:
        errors.append(f"decisión {got['decision']!r} != {case['expect']!r} ({got['reason']})")
    if "reason" in case and got["reason"] != notices.get(case["reason"], case["reason"]):
        errors.append(f"motivo {got['reason']!r}")
    if "reason_has" in case and case["reason_has"] not in got["reason"]:
        errors.append(f"motivo sin {case['reason_has']!r}: {got['reason']!r}")
    if "reason_lacks" in case and case["reason_lacks"] in got["reason"]:
        errors.append(f"motivo con {case['reason_lacks']!r}: {got['reason']!r}")
    return errors


class SharedCases(unittest.TestCase):
    def test_every_shared_case(self):
        table = json.loads(CASES.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(table["cases"]), 100)
        failures = []
        for case in table["cases"]:
            got, _ws = run_case(table, case)
            failures += [f"{case['name']}: {e}" for e in check(table, case, got)]
        self.assertEqual(failures, [])


class ShellParse(unittest.TestCase):
    def ro(self, cmd: str) -> bool:
        try:
            return dg.bash_reads_only(dg.parse(cmd))
        except dg.ParseError:
            return False

    def test_read_only_detection_is_conservative(self):
        for cmd in ("cat a.md", "ls -la /x | head -5", "/usr/bin/grep -r foo .", "cat a | grep x | wc -l",
                    "ls; cat a"):
            self.assertTrue(self.ro(cmd), cmd)
        for cmd in ("cat a > b", "cat a; rm b", "cat a && touch b", "cat <(echo x)", "cat $(echo a)",
                    "python3 -c 1", "cat a\nrm b", "", "cat a | tee b", "cat a & touch b", "ls; cp a b",
                    "tree x", "less x", "rg x", "file x"):
            self.assertFalse(self.ro(cmd), cmd)

    def test_unterminated_constructs_are_errors(self):
        for cmd in ("echo 'x", 'echo "x', "echo $(x", "echo `x", "echo ${x", "cat <(x"):
            with self.assertRaises(dg.ParseError, msg=cmd):
                dg.parse(cmd)

    def test_quotes_are_removed_and_dynamic_parts_kept(self):
        script = dg.parse("echo x > vaults/gal''linero/a.md; cat \"$HOME\"/b")
        self.assertEqual(dg.unquoted(script), "echo x vaults/gallinero/a.md ; cat $HOME/b")
        self.assertIsNone(dg.literal(script[1]["words"][1]))

    def test_reserved_words_and_assignments(self):
        script = dg.parse("if true; then LANG=C cat a; fi")
        self.assertEqual([dg.lit_or_dollar(c["words"][0]) for c in script], ["true", "cat"])
        self.assertEqual(script[1]["assigns"][0][0], "LANG")

    def test_too_long_is_an_error(self):
        with self.assertRaises(dg.ParseError):
            dg.parse("a" * (32 * 1024 + 1))


class Registry(unittest.TestCase):
    def test_local_and_base_paths(self):
        self.assertEqual(dg.local_registry_path("/x/savia-vaults.domes.json"), "/x/savia-vaults.domes.local.json")
        self.assertEqual(dg.local_registry_path("/x/domes"), "/x/domes.local")
        self.assertEqual(dg.base_registry_path("/x/a.domes.local.json"), "/x/a.domes.json")
        self.assertEqual(dg.base_registry_path("/x/a.domes.json"), "/x/a.domes.json")

    def test_level_parsing_matches_savia_vaults(self):
        self.assertEqual(dg.parse_level(""), 2)
        self.assertEqual(dg.parse_level(" n1 "), 1)
        self.assertEqual(dg.parse_level("N4b"), 4)
        self.assertIsNone(dg.parse_level("N5"))

    def test_missing_registry_is_empty_unless_required(self):
        self.assertEqual(dg.load_registry("/nonexistent/x.json", False), {"domes": []})
        self.assertIn("no existe", dg.load_registry("/nonexistent/x.json", True)["error"])


if __name__ == "__main__":
    unittest.main()
