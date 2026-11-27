"""Alerta #116: un `find -name 'a*a*…*b'` colgaba el guard de las dos CLI.

`_glob_regex` traducía cada `*` a `[^/]*` y `re` retrocede de forma exponencial contra un nombre
largo de `a`: denegación de servicio sobre la puerta. El matcher nuevo es lineal, da las mismas
respuestas que la regex anterior y coincide con el puerto de OpenCode en la misma batería.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "scripts/dual-cli"
LIB = ROOT / "scripts/opencode-plugin/savia-gates/lib/shell-targets.ts"
sys.path.insert(0, str(CORE))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gates
import shell_targets
from protocol import ProtocolError
from required_tools import needs


def old_glob_regex(pattern):
    """Copia literal de _glob_regex antes del arreglo: el oráculo de equivalencia."""
    out, i, n = "", 0, len(pattern)
    while i < n:
        c = pattern[i]
        if c == "*":
            out += "[^/]*"
        elif c == "?":
            out += "[^/]"
        elif c == "[":
            j = pattern.find("]", i + 2 if i + 1 < n and pattern[i + 1] in "!^" else i + 1)
            if j < 0:
                out += r"\["
            else:
                body = pattern[i + 1:j]
                neg = body[:1] in ("!", "^")
                body = body[1:] if neg else body
                out += "[" + ("^" if neg else "") + re.sub(r"([\\\]\[^])", r"\\\1", body) + "]"
                i = j
        else:
            out += re.escape(c)
        i += 1
    return out


PATTERNS = [
    "*", "**", "***", "?", "??", "*.sh", "*.json", "settings*", "settings.*", "*settings*", "s*t*n*s.json",
    "hooks", "HOOKS", "hook?", "[hH]ooks", "[!x]ooks", "[^x]ooks", "[a-z]*", "[a-z]ooks", "[!]", "[",
    "[abc", "a]b", "*[", "]", "\\", "\\*", ".claude", ".*", "*.", "a/b", "*/hooks", ".claude/*", ".claude/**",
    "*/*", "?/?", "[/]", "a[/]b", "[!a]", "x*y*z", "*.*.*", "opencode.json*", "*.jsonc", "$x", "(a)", "a|b",
    "a+", "a{1}", "^a", "a$", "-", "[a-]", "[-a]", "é*", "[é]", "dual-cli", "dual?cli",
]
NAMES = [
    "", "hooks", "HOOKS", "Hooks", "hook", "hooksx", "settings.json", "settings.local.json", "SETTINGS.JSON",
    ".claude", ".codex", "a/b", "a\\b", "ab", "a]b", "]", "[", "\\", "*", "a.b.c", "x/y/z", "xyz", "opencode.json",
    "opencode.jsonc", "dual-cli", "dual_cli", "dual/cli", "é", "éa", "x", "a", "-", "aa", "$x", "(a)",
    "a|b", "a+", "a{1}", "^a", "a$", "/", "//", ".", "..", "plugin", "scripts", "x.sh", "\n", "a\nb",
]


def python_child(code, timeout=5):
    t0 = time.monotonic()
    try:
        run = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=timeout,
                             cwd=str(ROOT))
    except subprocess.TimeoutExpired:
        return None, time.monotonic() - t0
    return run, time.monotonic() - t0


class GlobRedosTest(unittest.TestCase):
    def test_thirty_stars_against_five_thousand_chars_under_100_ms(self):
        code = (
            "import sys, time, json; sys.path.insert(0, 'scripts/dual-cli'); import shell_targets as s\n"
            "m = s._rx('a*' * 30 + 'b'); t0 = time.perf_counter(); r = m.fullmatch('a' * 5000)\n"
            "r2 = s._rx('*' * 30 + '?').fullmatch('a' * 5000)\n"
            "print(json.dumps({'r': bool(r), 'r2': bool(r2), 'ms': (time.perf_counter() - t0) * 1000}))\n"
        )
        run, _ = python_child(code)
        self.assertIsNotNone(run, "the matcher hung (timeout)")
        self.assertEqual(run.returncode, 0, run.stderr)
        got = json.loads(run.stdout)
        self.assertFalse(got["r"])
        self.assertTrue(got["r2"])
        self.assertLess(got["ms"], 100)

    def test_hostile_find_name_does_not_hang_the_guard(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, ".claude", "hooks"))
            Path(root, ".claude", "hooks", "a" * 250 + ".sh").write_text("")
            code = (
                "import sys, json; sys.path.insert(0, 'scripts/dual-cli'); import shell_targets as s, gates\n"
                f"root = {root!r}\n"
                "miss = s.protected_target(\"find .claude -name '\" + 'a*' * 30 + \"b' -delete\", root, root,"
                " gates.PROTECTED_PATHS)\n"
                "hit = s.protected_target(\"find .claude -name '\" + 'a*' * 30 + \".sh' -delete\", root, root,"
                " gates.PROTECTED_PATHS)\n"
                "print(json.dumps({'miss': miss, 'hit': hit}))\n"
            )
            run, elapsed = python_child(code)
            self.assertIsNotNone(run, "the guard hung (timeout)")
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertLess(elapsed, 3)
            self.assertEqual(json.loads(run.stdout), {"miss": None, "hit": ".claude"})

    def test_find_name_with_unknown_expansion_fails_closed(self):
        """Un patrón de `find -name` con $VAR, ${VAR} o $(cmd) no se conoce hasta ejecutar: no se puede
        descartar ninguna puerta y cuenta como «alcanza». Entre comillas simples el `$` es literal."""
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, ".claude", "hooks"))
            Path(root, ".claude", "hooks", "guard.sh").write_text("")

            def target(command):
                return shell_targets.protected_target(command, root, root, gates.PROTECTED_PATHS)

            for name in ('"$PATTERN"', "$PATTERN", "'*.'$EXT", '"${P}.sh"', '"$(cat p)"', "`cat p`"):
                for opt in ("-name", "-iname"):
                    self.assertEqual(target(f"find .claude {opt} {name} -delete"), ".claude", (opt, name))
            self.assertIsNone(target("find .claude -name '$PATTERN' -delete"))
            self.assertIsNone(target("find .claude -name '*.py' -delete"))
            self.assertIsNone(target('find .claude -name "$PATTERN" -print'))

    def test_same_answers_as_the_previous_regex(self):
        compared = 0
        for flags in (0, re.I):
            for p in PATTERNS:
                try:
                    ref = re.compile(old_glob_regex(p), re.S | flags)
                except re.error:
                    with self.assertRaises(ProtocolError):
                        shell_targets._rx(p, flags)
                    continue
                m = shell_targets._rx(p, flags)
                for n in NAMES:
                    self.assertEqual(bool(m.fullmatch(n)), bool(ref.fullmatch(n)), (p, flags, n))
                    compared += 1
        self.assertGreater(compared, 4000)

    def test_edge_cases(self):
        rx = shell_targets._rx
        self.assertFalse(rx("**").fullmatch("a/b"))
        self.assertTrue(rx("**").fullmatch("ab"))
        self.assertTrue(rx("**").fullmatch(""))
        self.assertTrue(rx("*/*").fullmatch("a/b"))
        self.assertFalse(rx("*/*").fullmatch("a/b/c"))
        self.assertFalse(rx("?").fullmatch("/"))
        self.assertTrue(rx("?").fullmatch("é"))
        self.assertTrue(rx("[/]").fullmatch("/"))
        self.assertTrue(rx("[!a]").fullmatch("/"))
        self.assertTrue(rx(".claude/*").fullmatch(".claude/hooks"))
        self.assertFalse(rx(".claude/*").fullmatch(".claude/hooks/x"))
        self.assertTrue(rx("HOOKS", re.I).fullmatch("hooks"))
        self.assertFalse(rx("HOOKS").fullmatch("hooks"))
        with self.assertRaises(ProtocolError):
            rx("[z-a]")

    @needs("bun")
    def test_same_answers_in_opencode(self):
        """Cada CLI da la misma respuesta sobre la batería. Fuera quedan `[]` y `[!]`, que ya divergían antes
        del arreglo: en JS `[]` no casa nada y `[^]` casa cualquier carácter; en Python los dos son re.error."""
        cases = [[p, ci] for ci in (False, True) for p in PATTERNS if p not in ("[]", "[!]")]
        code = (
            f"const {{ globMatcher }} = await import({json.dumps(str(LIB))})\n"
            "const { cases, names } = JSON.parse(await Bun.stdin.text())\n"
            "console.log(JSON.stringify(cases.map(([p, ci]) => {\n"
            "  try { const m = globMatcher(p, ci); return names.map((n) => m.test(n)) } catch { return null }\n"
            "})))\n"
        )
        run = subprocess.run(["bun", "-e", code], input=json.dumps({"cases": cases, "names": NAMES}),
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stderr)
        ts = json.loads(run.stdout)
        for (p, ci), got in zip(cases, ts):
            try:
                m = shell_targets._rx(p, re.I if ci else 0)
            except ProtocolError:
                self.assertIsNone(got, p)
                continue
            self.assertEqual(got, [bool(m.fullmatch(n)) for n in NAMES], (p, ci))


if __name__ == "__main__":
    unittest.main()
