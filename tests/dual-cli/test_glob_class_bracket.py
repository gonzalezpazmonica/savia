"""P2 de la revisión de la PR #1672: `]` justo tras `[` (o `[!`, `[^`) es literal en POSIX y en fnmatch.

El gemelo de OpenCode generaba la clase vacía `[]` y dejaba pasar `find . -name '[]h]ooks' -delete`;
este lado daba INVALID_EVENT con el mismo patrón. Ahora los dos siguen a fnmatch y coinciden con find.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/dual-cli"))
import shell_targets

NAMES = ["hooks", "]ooks", "xooks", "[]", "[!]", "!ooks", "^ooks"]
PATTERNS = ["[]h]ooks", "[!]x]ooks", "[^]x]ooks", "[]x]ooks", "[!]h]ooks", "[]", "[!]", "[]!]ooks", "[]^]ooks"]


class GlobClassBracketTest(unittest.TestCase):
    def test_find_delete_with_leading_bracket_reaches_gate(self):
        with tempfile.TemporaryDirectory() as root:
            os.mkdir(os.path.join(root, "hooks"))
            for cmd in ("find . -name '[]h]ooks' -delete", "find . -name '[!]x]ooks' -delete",
                        "find . -iname '[]H]OOKS' -delete"):
                self.assertEqual(shell_targets.protected_target(cmd, root, root, ["hooks"]), ".", cmd)

    def test_control_class_without_h_does_not_reach(self):
        with tempfile.TemporaryDirectory() as root:
            os.mkdir(os.path.join(root, "hooks"))
            for cmd in ("find . -name '[]x]ooks' -delete", "find . -name '[!]h]ooks' -delete"):
                self.assertIsNone(shell_targets.protected_target(cmd, root, root, ["hooks"]), cmd)

    def test_matcher_literal_bracket(self):
        rx = shell_targets._rx
        self.assertTrue(rx("[]h]ooks").fullmatch("hooks"))
        self.assertTrue(rx("[]h]ooks").fullmatch("]ooks"))
        self.assertFalse(rx("[]h]ooks").fullmatch("xooks"))
        self.assertTrue(rx("[!]x]ooks").fullmatch("hooks"))
        self.assertFalse(rx("[!]x]ooks").fullmatch("]ooks"))
        self.assertTrue(rx("[]").fullmatch("[]"))
        self.assertTrue(rx("[!]").fullmatch("[!]"))

    @unittest.skipUnless(shutil.which("find"), "sin find no hay oráculo")
    def test_parity_with_real_find(self):
        with tempfile.TemporaryDirectory() as root:
            for n in NAMES:
                os.mkdir(os.path.join(root, n))
            for p in PATTERNS:
                run = subprocess.run(["find", root, "-mindepth", "1", "-maxdepth", "1", "-name", p,
                                      "-printf", "%f\n"], capture_output=True, text=True, check=True)
                real = sorted(x for x in run.stdout.split("\n") if x)
                ours = sorted(n for n in NAMES if shell_targets._rx(p).fullmatch(n))
                self.assertEqual(ours, real, p)


if __name__ == "__main__":
    unittest.main()
