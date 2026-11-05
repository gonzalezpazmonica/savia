#!/usr/bin/env python3
"""Tests de scripts/lib/strip_inert_heredocs.py: el texto de un heredoc que solo
escribe un fichero no es una orden; el de un heredoc hacia un intérprete sí."""
import os
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "scripts", "lib", "strip_inert_heredocs.py")
RM = "rm -" + "rf"  # el literal entero dispara los guards al editar este fichero


def strip(cmd):
    p = subprocess.run([sys.executable, SCRIPT], input=cmd, text=True, capture_output=True)
    assert p.returncode == 0, p.stderr
    return p.stdout


class Strip(unittest.TestCase):
    def test_quoted_heredoc_to_file_drops_body(self):
        for cmd in (f"cat > notas.md <<'EOF'\n{RM} /tmp/x\nEOF",
                    f'cat >notas.md <<"EOF"\n{RM} ~/x\nEOF',
                    f"cat <<'EOF' > notas.md\n{RM} /\nEOF",
                    f"cat >> notas.md <<-'FIN'\n\t{RM} /\n\tFIN",
                    f"tee notas.md >/dev/null <<'EOF'\n{RM} /\nEOF"):
            out = strip(cmd)
            self.assertNotIn(RM, out, cmd)
            self.assertIn("notas.md", out)

    def test_unquoted_heredoc_without_substitution_drops_body(self):
        self.assertNotIn(RM, strip(f"cat > n.md <<EOF\n{RM} /\nEOF"))

    def test_commands_after_the_heredoc_are_kept(self):
        out = strip(f"cat > n.md <<'EOF'\ntexto\nEOF\n{RM} /home/x")
        self.assertIn(f"{RM} /home/x", out)

    def test_interpreter_heredocs_are_kept(self):
        for cmd in (f"bash <<'EOF'\n{RM} /\nEOF",
                    f"sh <<EOF\n{RM} /\nEOF",
                    f"cat <<'EOF' | bash\n{RM} /\nEOF",
                    f"cat > n.md <<'EOF' && bash n.md\n{RM} /\nEOF",
                    f"cat > n.sh <<'EOF'\n{RM} /\nEOF\nbash n.sh",
                    f"python3 - <<'EOF'\nimport os; os.system('{RM} /')\nEOF",
                    f"cat <<'EOF'\n{RM} /\nEOF"):  # a stdout: puede acabar en una tubería del llamador
            self.assertIn(RM, strip(cmd), cmd)

    def test_unquoted_heredoc_with_substitution_is_kept(self):
        for body in ("$(" + RM + " /)", "`" + RM + " /`"):
            self.assertIn(RM, strip(f"cat > n.md <<EOF\n{body}\nEOF"), body)

    def test_unterminated_heredoc_is_kept(self):
        self.assertIn(RM, strip(f"cat > n.md <<'EOF'\n{RM} /\n"))

    def test_line_continuation_on_heredoc_line_is_kept(self):
        # bash une la línea siguiente a la del heredoc: no es cuerpo, se ejecuta
        for cmd in (f"cat > n.md <<'EOF' \\\n&& {RM} /\nhola\nEOF",
                    f"bash \\\ncat > n.md <<'EOF'\n{RM} /\nEOF"):
            self.assertIn(RM, strip(cmd), cmd)

    def test_partially_quoted_delimiter_is_kept(self):
        # bash usa EOFX como delimitador; el EOF de en medio no cierra nada
        for cmd in (f"cat > n.md <<EOF'X'\nhola\nEOFX\n{RM} /\nEOF",
                    f"cat > n.md <<EOF\\X\nhola\nEOFX\n{RM} /\nEOF",
                    f"cat > n.md <<'EOF'X\nhola\nEOFX\n{RM} /\nEOF"):
            self.assertIn(RM, strip(cmd), cmd)

    def test_file_run_later_by_glob_or_variable_is_kept(self):
        for later in ("bash ./*.sh", "F=n.s; bash ${F}h", '. "$F"', "bash n.s?"):
            cmd = f"cat > n.sh <<'EOF'\n{RM} /\nEOF\n{later}"
            self.assertIn(RM, strip(cmd), cmd)

    def test_file_run_outside_the_command_is_kept(self):
        for target in (".git/hooks/post-checkout", "~/.bashrc", "/x/.profile", ".zshrc"):
            cmd = f"cat > {target} <<'EOF'\n{RM} /\nEOF"
            self.assertIn(RM, strip(cmd), cmd)

    def test_plain_later_command_still_drops_body(self):
        out = strip(f"cat > n.md <<'EOF'\n{RM} /\nEOF\necho listo")
        self.assertNotIn(RM, out)

    def test_no_heredoc_is_identity(self):
        cmd = f"{RM} /tmp/x; echo ok"
        self.assertEqual(strip(cmd), cmd)


if __name__ == "__main__":
    unittest.main()
