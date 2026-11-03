#!/usr/bin/env python3
"""Tests de scripts/lib/git_op_targets.py: destino real de cada git commit/add de una orden."""
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "scripts", "lib", "git_op_targets.py")


class Targets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = os.path.realpath(cls.tmp.name)
        cls.home = os.path.join(root, "home")
        cls.base = os.path.join(cls.home, "repo-main")
        cls.wt = os.path.join(cls.home, "wt-x")
        for d in (cls.base, cls.wt):
            os.makedirs(d)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_(self, cmd, base=None):
        env = dict(os.environ, HOME=self.home)
        p = subprocess.run([sys.executable, SCRIPT, base or self.base], input=cmd,
                           text=True, capture_output=True, env=env)
        self.assertEqual(p.returncode, 0, p.stderr)
        return [tuple(line.split("\t")) for line in p.stdout.splitlines()]

    # ── destino resuelto ──
    def test_git_C_with_literal_var(self):
        out = self.run_(f"W={self.wt}; git -C $W add f && git -C $W commit -q --no-edit")
        self.assertEqual(out, [("add", self.wt), ("commit", self.wt)])

    def test_git_C_quoted(self):
        self.assertEqual(self.run_(f'git -C "{self.wt}" commit -m x'), [("commit", self.wt)])
        self.assertEqual(self.run_(f"git -C '{self.wt}' commit -m x"), [("commit", self.wt)])
        self.assertEqual(self.run_(f'W={self.wt}; git -C "${{W}}" commit'), [("commit", self.wt)])

    def test_git_C_relative_and_multiple(self):
        self.assertEqual(self.run_("git -C .. -C wt-x commit"), [("commit", self.wt)])

    def test_cd_tilde_unquoted_semicolon(self):
        out = self.run_("cd ~/wt-x && git merge origin/main ; git commit -m y")
        self.assertEqual(out, [("commit", self.wt)])

    def test_cd_back_to_main_after_worktree(self):
        out = self.run_(f"cd {self.wt} && git add . ; cd {self.base} && git commit -m z")
        self.assertEqual(out, [("add", self.wt), ("commit", self.base)])

    def test_git_C_to_main_from_worktree(self):
        out = self.run_(f"git -C {self.base} commit -m x", base=self.wt)
        self.assertEqual(out, [("commit", self.base)])

    def test_subshell_cd_does_not_leak(self):
        out = self.run_(f"(cd {self.wt} && git add f); git commit -m x")
        self.assertEqual(out, [("add", self.wt), ("commit", self.base)])

    def test_cd_in_pipeline_or_background_does_not_persist(self):
        self.assertEqual(self.run_(f"cd {self.wt} | true; git commit -m x"), [("commit", self.base)])
        self.assertEqual(self.run_(f"cd {self.wt} & git commit -m x"), [("commit", self.base)])

    def test_cd_to_missing_dir_keeps_cwd(self):
        out = self.run_(f"cd {self.home}/no-existe; git commit -m x")
        self.assertEqual(out, [("commit", self.base)])

    # ── cd condicional: puede no ejecutarse ──
    def test_conditional_cd_keeps_previous_cwd_possible(self):
        out = self.run_(f"false && cd {self.wt}; git commit -m x")
        self.assertEqual(sorted(out), sorted([("commit", self.base), ("commit", self.wt)]))
        out = self.run_(f"true || cd {self.wt}; git commit -m x")
        self.assertIn(("commit", self.base), out)

    def test_commit_after_or_may_run_without_cd(self):
        out = self.run_(f"cd {self.wt} || git commit -m x")
        self.assertIn(("commit", self.base), out)

    def test_and_chain_after_cd_is_exact(self):
        out = self.run_(f"git status && cd {self.wt} && git commit -m x")
        self.assertEqual(out, [("commit", self.wt)])
        out = self.run_(f"cd {self.wt} || exit 1; git commit -m x")
        self.assertEqual(out, [("commit", self.wt)])

    def test_failed_cd_makes_and_chain_unreachable(self):
        self.assertEqual(self.run_(f'cd "{self.home}/no-existe" && git commit -m x'), [])
        out = self.run_(f"cd {self.home}/no-existe && git commit; git commit -m y")
        self.assertEqual(out, [("commit", self.base)])
        out = self.run_(f"cd {self.home}/no-existe || git commit -m y")
        self.assertEqual(out, [("commit", self.base)])

    def test_cd_to_dir_created_in_same_command_is_unresolved(self):
        # mkdir puede crearlo: no se da por fallido (sería un rodeo)
        self.assertEqual(self.run_("mkdir -p d && cd d && git commit -m x"), [("commit", "")])

    def test_reassigned_var_uses_latest_value(self):
        out = self.run_(f"W={self.wt}; W={self.base}; git -C $W commit", base=self.wt)
        self.assertEqual(out, [("commit", self.base)])

    def test_tilde_in_assignment_expands(self):
        out = self.run_("W=~/repo-main; git -C $W commit", base=self.wt)
        self.assertEqual(out, [("commit", self.base)])

    def test_bash_c_recursion(self):
        out = self.run_(f"bash -c 'cd {self.wt} && git commit -m x'")
        self.assertEqual(out, [("commit", self.wt)])

    def test_wrappers(self):
        out = self.run_(f"env FOO=1 nohup git -C {self.wt} commit -m x; command git commit")
        self.assertEqual(out, [("commit", self.wt), ("commit", self.base)])

    def test_odd_quotes_split_word(self):
        out = self.run_(f'cd "{self.home}"/\'wt-x\' && g"it" com\'mit\' -m x')
        self.assertEqual(out, [("commit", self.wt)])

    def test_command_substitution_is_analyzed(self):
        out = self.run_("echo $(git commit -m x)")
        self.assertEqual(out, [("commit", self.base)])

    # ── destino no resoluble: vacío ──
    def test_unknown_var_is_unresolved(self):
        self.assertEqual(self.run_("git -C $NOPE commit -m x"), [("commit", "")])

    def test_git_dir_env_is_unresolved(self):
        self.assertEqual(self.run_(f"GIT_DIR={self.base}/.git git commit"), [("commit", "")])
        self.assertEqual(self.run_("git --git-dir=/x/.git commit"), [("commit", "")])
        self.assertEqual(self.run_("export GIT_DIR=/x/.git; git commit"), [("commit", "")])

    def test_cd_command_substitution_is_unresolved(self):
        self.assertEqual(self.run_("cd $(pwd) && git commit"), [("commit", "")])
        self.assertEqual(self.run_("cd - && git commit"), [("commit", "")])

    def test_unbalanced_quotes_fall_back_to_text(self):
        self.assertEqual(self.run_("git commit -m 'sin cerrar"), [("commit", "")])

    # ── texto, no órdenes ──
    def test_heredoc_text_is_not_a_command(self):
        cmd = "cat > notas.md <<'EOF'\nhay que commitear; git commit -m x\nlos commits\nEOF\necho ok"
        self.assertEqual(self.run_(cmd), [])

    def test_string_text_is_not_a_command(self):
        self.assertEqual(self.run_('echo "luego git commit y commits"'), [])
        self.assertEqual(self.run_("printf 'git add .\\n' > f.txt"), [])

    def test_comment_is_not_a_command(self):
        self.assertEqual(self.run_("ls # git commit -m x"), [])

    def test_other_git_subcommands_ignored(self):
        self.assertEqual(self.run_("git log --grep commit; git commit-tree x; git status"), [])

    def test_command_after_heredoc_is_detected(self):
        out = self.run_("cat > f <<EOF\ntexto\nEOF\ngit commit -m x")
        self.assertEqual(out, [("commit", self.base)])


if __name__ == "__main__":
    unittest.main()
