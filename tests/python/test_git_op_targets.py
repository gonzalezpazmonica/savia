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

    def test_cd_to_missing_dir_is_unresolved(self):
        # revisión PR #1467 P1-2: un cd que el hook no ve no se da por fallido
        out = self.run_(f"cd {self.home}/no-existe; git commit -m x")
        self.assertEqual(out, [("commit", "")])

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

    def test_missing_cd_never_makes_and_chain_unreachable(self):
        # antes: `cd <inexistente> && git commit` → [] (fail-open, P1-2)
        self.assertEqual(self.run_(f'cd "{self.home}/no-existe" && git commit -m x'),
                         [("commit", "")])
        out = self.run_(f"cd {self.home}/no-existe || git commit -m y")
        self.assertIn(("commit", self.base), out)

    def test_cdpath_makes_relative_cd_unresolved(self):
        # `CDPATH=/x; cd savia` puede ir a /x/savia aunque ./savia no exista
        self.assertEqual(self.run_(f"CDPATH={self.home}; cd repo-main && git commit -m x",
                                   base=self.wt), [("commit", "")])
        env_out = subprocess.run([sys.executable, SCRIPT, self.base], input="cd wt-x && git commit",
                                 text=True, capture_output=True,
                                 env=dict(os.environ, HOME=self.home, CDPATH=self.home)).stdout
        self.assertEqual(env_out, "commit\t\n")
        # ruta explícitamente relativa (./, ../) no usa CDPATH
        self.assertEqual(self.run_(f"CDPATH=/x; cd ../wt-x && git commit"), [("commit", self.wt)])

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

    def test_git_dir_literal_resolves_to_its_worktree(self):
        # revisión PR #1467 P2-2: desde el worktree, GIT_DIR=<main>/.git apunta a main
        b = self.base
        self.assertEqual(self.run_(f"GIT_DIR={b}/.git git commit", self.wt), [("commit", b)])
        self.assertEqual(self.run_(f"git --git-dir={b}/.git commit", self.wt), [("commit", b)])
        self.assertEqual(self.run_(f"git --git-dir {b}/.git -C /tmp commit", self.wt), [("commit", b)])
        self.assertEqual(self.run_(f"export GIT_DIR={b}/.git; git commit", self.wt), [("commit", b)])
        self.assertEqual(self.run_(f"env GIT_DIR={b}/.git git commit", self.wt), [("commit", b)])

    def test_git_dir_other_forms_are_unresolved(self):
        self.assertEqual(self.run_("GIT_DIR=.git git commit"), [("commit", "")])
        self.assertEqual(self.run_("git --git-dir=$X commit"), [("commit", "")])
        self.assertEqual(self.run_("GIT_DIR=/x/repo.git git commit"), [("commit", "")])
        self.assertEqual(self.run_("git --work-tree=/x commit"), [("commit", "")])

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
        self.assertEqual(self.run_("git log --grep commit; git status; git commit-graph write"), [])

    def test_commit_tree_counts_as_commit(self):
        # revisión PR #1467 P2-1: commit-tree + update-ref mueve main
        self.assertEqual(self.run_("git commit-tree x -m y"), [("commit", self.base)])
        self.assertEqual(self.run_("bash -c 'git commit-tree x'"), [("commit", self.base)])
        self.assertEqual(self.run_('su -c "git commit-tree x"'), [("commit", "")])

    def test_command_after_heredoc_is_detected(self):
        out = self.run_("cat > f <<EOF\ntexto\nEOF\ngit commit -m x")
        self.assertEqual(out, [("commit", self.base)])


    # ── fail-closed (revisión PR #1467) ──
    def test_unresolvable_argv0_emits_op(self):
        for cmd in ("$SUDO git commit -m x", "${X:-} git add .",
                    f"$(which git) -C {self.base} commit -m x", "$G commit -m x"):
            out = self.run_(cmd)
            self.assertTrue(any(op in ("commit", "add") for op, _ in out), (cmd, out))
        # con destino explícito, se resuelve aunque el programa no se conozca
        self.assertIn(("commit", self.base), self.run_(f"$(which git) -C {self.base} commit", self.wt))
        self.assertIn(("commit", self.base), self.run_(f"$SUDO git -C {self.base} commit", self.wt))

    def test_shell_with_options_is_analyzed(self):
        for cmd in ('bash --norc -c "git commit -m x"', 'bash -o pipefail -c "git commit -m x"',
                    'sh +x -c "git commit -m x"'):
            self.assertEqual(self.run_(cmd), [("commit", self.base)], cmd)

    def test_shell_script_file_is_opaque(self):
        self.assertEqual(self.run_("bash run.sh"), [])
        self.assertIn(("commit", ""), self.run_("bash run.sh git commit"))

    def test_exec_capable_commands_text_counts(self):
        for cmd in ("awk 'BEGIN{system(\"git commit -m x\")}'",
                    "sed -n '1e git commit -m x' f",
                    'script -qc "git commit -m x" /dev/null',
                    'su -c "git commit -m x"',
                    'flock f -c "git -C /x commit -m x"',
                    "python3 -c \"import os; os.system('git commit -m x')\""):
            self.assertIn(("commit", ""), self.run_(cmd), cmd)

    # ── shell que lee la orden de stdin (revisión PR #1467 P1-1) ──
    def test_shell_reading_heredoc_runs_body(self):
        for d in ("'EOF'", "EOF", '"EOF"'):
            for sh in ("bash", "sh", "bash -s", "bash -", "bash -s --", "zsh"):
                out = self.run_(f"{sh} <<{d}\ngit commit -m x\nEOF")
                self.assertEqual(out, [("commit", self.base)], (sh, d))
        out = self.run_(f"bash <<'EOF'\ncd {self.wt} && git commit -m x\nEOF")
        self.assertEqual(out, [("commit", self.wt)])

    def test_shell_reading_here_string_runs_it(self):
        self.assertEqual(self.run_("bash <<< 'git commit -m x'"), [("commit", self.base)])
        self.assertEqual(self.run_("bash <<< \"$CMD\""), [])
        self.assertEqual(self.run_("bash <<< \"$CMD git commit\""), [("commit", "")])

    def test_shell_reading_pipe_counts_command_text(self):
        for cmd in ("echo 'git commit -m x' | bash", "printf 'git add .' | sh -s",
                    "echo 'git commit' | $SH", "bash < f.sh; echo git commit",
                    "echo 'import os; os.system(\"git commit\")' | python3"):
            self.assertIn(self.run_(cmd)[0][0], ("commit", "add"), cmd)

    def test_non_shell_heredoc_counts_body_text(self):
        out = self.run_("python3 <<'EOF'\nimport os; os.system('git commit -m x')\nEOF")
        self.assertEqual(out, [("commit", "")])

    def test_inert_reader_of_pipe_or_heredoc_stays_inert(self):
        self.assertEqual(self.run_("echo 'git commit' | grep commit | wc -l"), [])
        self.assertEqual(self.run_("cat <<'EOF' | tee f\ngit commit -m x\nEOF"), [])

    def test_rg_pre_executes(self):
        self.assertEqual(self.run_('rg "git commit" docs'), [])
        self.assertEqual(self.run_("rg --pre 'git commit -m x' y"), [("commit", "")])

    def test_inert_commands_stay_inert(self):
        self.assertEqual(self.run_('grep -r "git commit" docs'), [])
        self.assertEqual(self.run_('cat "git add ." | jq .'), [])

    def test_unquoted_heredoc_substitution_runs(self):
        out = self.run_("cat <<EOF\n$(git commit -m x)\nEOF")
        self.assertEqual(out, [("commit", self.base)])
        out = self.run_("cat <<EOF\nx `git add .` y\nEOF")
        self.assertEqual(out, [("add", self.base)])

    def test_quoted_heredoc_substitution_is_text(self):
        for d in ("'EOF'", '"EOF"', "\\EOF"):
            self.assertEqual(self.run_(f"cat <<{d}\n$(git commit -m x)\nEOF"), [], d)

    def test_analysis_exception_falls_back_to_text(self):
        import importlib.util, io
        spec = importlib.util.spec_from_file_location("got", SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        def boom(*_a, **_k):
            raise RecursionError("simulado")
        mod.run = boom
        old = sys.stdin, sys.stdout, sys.argv
        sys.stdin, sys.stdout = io.StringIO("git -C /x commit -m y"), io.StringIO()
        sys.argv = ["got", self.base]
        try:
            rc = mod.main()
            out = sys.stdout.getvalue()
        finally:
            sys.stdin, sys.stdout, sys.argv = old
        self.assertEqual(rc, 0)
        self.assertEqual(out, "commit\t\n")


if __name__ == "__main__":
    unittest.main()
