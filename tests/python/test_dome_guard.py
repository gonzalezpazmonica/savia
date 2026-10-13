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
    for d in case.get("mkdirs", []):
        os.makedirs(os.path.join(ws, d), exist_ok=True)
    for link, target in case.get("links", []):
        os.symlink(sub(target, ws), os.path.join(ws, link))
    reg = table["registries"][case["registry"]]
    base = os.path.join(ws, "projects/savia-vaults/savia-vaults.domes.json")
    for key, path in (("base", base), ("local", dg.local_registry_path(base))):
        if key in reg:
            body = reg[key] if isinstance(reg[key], str) else json.dumps(sub(reg[key], ws))
            Path(path).write_text(body, encoding="utf-8")
    for rel, mode in case.get("chmod", []):
        os.chmod(os.path.join(ws, rel), int(mode, 8))
    return ws


def cleanup(ws: str) -> None:
    """Devuelve los permisos que quitó un caso (`chmod`) y borra el workspace."""
    for dirpath, dirnames, _files in os.walk(ws):
        for d in dirnames:
            p = os.path.join(dirpath, d)
            if not os.path.islink(p):
                os.chmod(p, 0o755)
    shutil.rmtree(ws, ignore_errors=True)


def payload_text(case: dict, ws: str) -> str:
    """Payload PreToolUse del caso: `raw` tal cual, o el JSON con `cwd` (relativo al workspace) y contexto."""
    if "raw" in case:
        return sub(case["raw"], ws)
    payload = {"hook_event_name": "PreToolUse", "tool_name": case["tool"], "tool_input": sub(case["input"], ws),
               "session_id": "s1", "cwd": os.path.join(ws, case["cwd"]) if "cwd" in case else ws}
    if "ctx" in case:
        payload["dome_context"] = case["ctx"]
    return json.dumps(payload)


def run_case(table: dict, case: dict) -> tuple[dict, str]:
    ws = build_workspace(table, case)
    try:
        env = {k: sub(v, ws) for k, v in case.get("env", {}).items()}
        out = io.StringIO()
        with mock.patch.dict(os.environ, env, clear=False), \
                mock.patch.object(sys, "stdin", io.TextIOWrapper(io.BytesIO(payload_text(case, ws).encode("utf-8", "surrogatepass")))), redirect_stdout(out):
            if "SAVIA_SPACE_DOMES_FILE" not in env:
                os.environ.pop("SAVIA_SPACE_DOMES_FILE", None)
            dg.main(["--root", ws])
        return json.loads(out.getvalue()), ws
    finally:
        cleanup(ws)


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
        self.assertGreaterEqual(len(table["cases"]), 500)
        failures = []
        for case in table["cases"]:
            got, _ws = run_case(table, case)
            failures += [f"{case['name']}: {e}" for e in check(table, case, got)]
        self.assertEqual(failures, [])


RANK = {"pass": 0, "ask": 1, "deny": 2}


def monotonic_pairs(spec: dict, registries: list | None = None) -> list[tuple[str, dict | None, str, dict, dict]]:
    """Pares (registro, contexto, etiqueta, payload, payload al menos igual de estricto) de la sección
    `monotonic` de la tabla: añadir claves a bash, quitar el cwd del payload o quitar la herramienta.
    `@WS@` queda sin sustituir. dome-guard.test.ts (monotonicPairs) los genera en el mismo orden."""
    pairs = []
    for reg, ctx in spec["registries"]:
        if registries is not None and reg not in registries:
            continue

        def payload(tool, tool_input, cwd=True):
            p = {} if tool is None else {"tool_name": tool}
            p["tool_input"] = tool_input
            if cwd:
                p["cwd"] = "@WS@"
            if ctx is not None:
                p["dome_context"] = ctx
            return p

        for cmd in spec["commands"]:
            for wd in spec["workdirs"]:
                base = {"command": cmd} if wd is None else {"command": cmd, "workdir": wd}
                weak = payload("bash", base)
                for extra in spec["extras"]:
                    if not set(extra) & set(base):
                        pairs.append((reg, ctx, f"+{json.dumps(extra)}: {cmd} (workdir {wd})", weak,
                                      payload("bash", {**base, **extra})))
                pairs.append((reg, ctx, f"sin cwd: {cmd} (workdir {wd})", weak, payload("bash", base, cwd=False)))
        for tool in spec["tools"]:
            for tool_input in spec["inputs"]:
                weak = payload(tool, tool_input)
                pairs.append((reg, ctx, f"sin herramienta ({tool}): {json.dumps(tool_input)}", weak, payload(None, tool_input)))
                pairs.append((reg, ctx, f"herramienta 42 ({tool}): {json.dumps(tool_input)}", weak, payload(42, tool_input)))
    return pairs


def decide_text(text: str, ws: str) -> tuple[str, str]:
    with mock.patch.dict(os.environ, {}, clear=False):
        for k in ("SAVIA_SPACE_DOMES_FILE", "SAVIA_DOME_GUARD", "SAVIA_GATES_PIN"):
            os.environ.pop(k, None)
        return dg.decide_payload(text, ws)


class Monotonic(unittest.TestCase):
    def test_extra_keys_missing_cwd_or_missing_tool_never_loosen_the_verdict(self):
        table = json.loads(CASES.read_text(encoding="utf-8"))
        pairs = monotonic_pairs(table["monotonic"])
        self.assertGreaterEqual(len(pairs), 400)
        failures, workspaces = [], {}
        try:
            for reg, _ctx, label, weak, strong in pairs:
                if reg not in workspaces:
                    workspaces[reg] = build_workspace(table, {"registry": reg})
                ws = workspaces[reg]
                a = decide_text(json.dumps(sub(weak, ws)), ws)
                b = decide_text(json.dumps(sub(strong, ws)), ws)
                if RANK[b[0]] < RANK[a[0]]:
                    failures.append(f"{reg} {label}: {a[0]} -> {b[0]} ({b[1][:60]})")
                # Ronda 8: el segundo de un par de bash tiene el cwd desconocido, y eso nunca es pass.
                if not label.startswith(("sin herramienta", "herramienta 42")) and b[0] == "pass":
                    failures.append(f"{reg} {label}: cwd desconocido y pass")
        finally:
            for ws in workspaces.values():
                cleanup(ws)
        self.assertEqual(failures, [])

    def test_the_property_is_not_vacuous(self):
        """Algún par sube de verdad (ask -> deny y alguno desde pass): si no, la propiedad no prueba nada."""
        table = json.loads(CASES.read_text(encoding="utf-8"))
        ws = build_workspace(table, {"registry": "std-pb"})
        try:
            ups = set()
            for _reg, _ctx, _label, weak, strong in monotonic_pairs(table["monotonic"], ["std-pb"]):
                a = decide_text(json.dumps(sub(weak, ws)), ws)[0]
                b = decide_text(json.dumps(sub(strong, ws)), ws)[0]
                if a != b:
                    ups.add((a, b))
        finally:
            cleanup(ws)
        # Con una N3 en nube (std-pb) el cwd desconocido sube a deny desde pass o desde ask (ronda 9).
        self.assertIn(("ask", "deny"), ups)
        self.assertTrue(any(a == "pass" for a, _b in ups), ups)

    def test_strictest_keeps_the_first_reason_on_ties(self):
        self.assertEqual(dg.strictest([("ask", "a"), ("ask", "b"), ("pass", "")]), ("ask", "a"))
        self.assertEqual(dg.strictest([("ask", "a"), ("deny", "d")]), ("deny", "d"))
        self.assertEqual(dg.strictest([]), ("pass", ""))


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
        self.assertEqual(dg.load_registry("/nonexistent/x.json", False),
                         {"domes": [], "files": ["/nonexistent/x.json", "/nonexistent/x.local.json"]})
        self.assertIn("no existe", dg.load_registry("/nonexistent/x.json", True)["error"])


if __name__ == "__main__":
    unittest.main()
