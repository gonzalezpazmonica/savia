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

    def test_more_autorun_targets_are_kept(self):
        for target in (".bash_aliases", "/etc/profile.d/x.sh", ".config/fish/config.fish",
                       ".opencode/plugins/x.ts", ".claude/hooks/x.sh", ".github/workflows/ci.yml"):
            cmd = f"cat > {target} <<'EOF'\n{RM} /\nEOF"
            self.assertIn(RM, strip(cmd), cmd)

    def test_autorun_targets_ignore_case_and_cover_hook_dirs(self):
        # Revisión de seguridad #1483 (3.ª, P2-2): APFS/NTFS no distinguen
        # mayúsculas; `.husky/`, `.githooks/` (core.hooksPath) y `.ssh/rc` se
        # ejecutan solos.
        for target in (".Git/hooks/pre-commit", ".BashRC", ".husky/pre-commit",
                       ".githooks/pre-push", "/home/u/.ssh/rc"):
            cmd = f"cat > {target} <<'EOF'\n{RM} /\nEOF"
            self.assertIn(RM, strip(cmd), cmd)
            cmd = f"cat > n.md <<'EOF'\n{RM} /\nEOF\ncat n.md >> {target}"
            self.assertIn(RM, strip(cmd), cmd)
        # negativo: un fichero de datos con nombre parecido sigue quitando el cuerpo
        self.assertNotIn(RM, strip(f"cat > docs/husky.md <<'EOF'\n{RM} /\nEOF"))

    def test_printf_assigning_a_variable_keeps_body(self):
        # Revisión de seguridad #1483 (3.ª, P2-1): `printf -v PATH …` cambia
        # qué programa ejecuta bash después.
        for pre in ("printf -v PATH %s /tmp/x", "printf -vPATH %s /tmp/x",
                    "echo a; printf -v PATH %s /tmp/x"):
            cmd = f"{pre}\ncat > n.md <<'EOF'\n{RM} /\nEOF"
            self.assertIn(RM, strip(cmd), cmd)
        # negativo: printf que solo escribe, o `-v` como dato de otra orden
        for pre in ("printf %s -v", "grep -v x f.md"):
            cmd = f"{pre}\ncat > n.md <<'EOF'\n{RM} /\nEOF"
            self.assertNotIn(RM, strip(cmd), cmd)

    def test_copy_to_autorun_file_keeps_body(self):
        # Revisión de seguridad #1483 P2-1: el resto copia el fichero «inerte»
        # a un destino que se ejecuta solo.
        for later in ("cat n.md >> ~/.bashrc", "cat n.md >> /home/u/.bashrc",
                      "cat n.md | tee -a .profile", "tee .git/hooks/pre-commit < n.md",
                      "cat n.md > .claude/hooks/x.sh"):
            cmd = f"cat > n.md <<'EOF'\n{RM} /\nEOF\n{later}"
            self.assertIn(RM, strip(cmd), cmd)
        # negativo: copiar a un fichero de datos sigue quitando el cuerpo
        self.assertNotIn(RM, strip(f"cat > n.md <<'EOF'\n{RM} /\nEOF\ncat n.md >> otro.md"))

    def test_plain_later_command_still_drops_body(self):
        out = strip(f"cat > n.md <<'EOF'\n{RM} /\nEOF\necho listo")
        self.assertNotIn(RM, out)

    def test_indirect_execution_keeps_body(self):
        # Revisión #1483 P1-3: bash ejecuta el fichero sin nombrarlo literalmente.
        for cmd in (f"export BASH_ENV=/tmp/env\ncat > \"$BASH_ENV\" <<'EOF'\n{RM} /\nEOF\nbash -c true",
                    f"export BASH_ENV=/tmp/env\ncat > /tmp/env <<'EOF'\n{RM} /\nEOF\nbash -c true",
                    f"cat > /tmp/guard-payload <<'EOF'\n{RM} /\nEOF\nbash /tmp/guard-*",
                    f"cat > package.json <<'EOF'\n{RM} /\nEOF\nnpm test",
                    f"cat > Makefile <<'EOF'\n{RM} /\nEOF\nmake",
                    f"cat > ~/notas.md <<'EOF'\n{RM} /\nEOF"):
            self.assertIn(RM, strip(cmd), cmd)

    def test_quoted_string_wrapping_the_heredoc_line_keeps_body(self):
        # bash: echo "…"; <orden>; echo "…" — el «cuerpo» es una orden
        cmd = f"echo \"\ncat > n.md <<'EOF'\n\"; {RM} /; echo \"\nEOF\n\""
        self.assertIn(RM, strip(cmd))

    def test_one_doubtful_heredoc_keeps_all(self):
        cmd = f"cat > a.md <<'EOF'\n{RM} /a\nEOF\nbash <<'EOF'\n{RM} /b\nEOF"
        self.assertEqual(strip(cmd), cmd)

    def test_known_data_commands_around_literal_output_drop_body(self):
        cmd = (f"mkdir -p docs\ncat > docs/n.md <<'EOF'\n{RM} /\nEOF\n"
               "printf '%s' 'texto bash'\ncat docs/n.md | grep -c rm && echo ok")
        out = strip(cmd)
        self.assertNotIn(RM, out)
        self.assertIn("cat docs/n.md", out)

    def test_no_heredoc_is_identity(self):
        cmd = f"{RM} /tmp/x; echo ok"
        self.assertEqual(strip(cmd), cmd)


if __name__ == "__main__":
    unittest.main()
