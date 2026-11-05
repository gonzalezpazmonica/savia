#!/usr/bin/env python3
"""Tests de scripts/lib/git_op_targets.py: destino de cada git commit/add de una
orden, con criterio fail-closed. Destino vacío = veredicto BLOQUEAR."""
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

    def run_(self, cmd, base=None, **env_extra):
        env = {k: v for k, v in os.environ.items() if k != "CDPATH"}
        env.update(HOME=self.home, **env_extra)
        p = subprocess.run([sys.executable, SCRIPT, base or self.base], input=cmd,
                           text=True, capture_output=True, env=env)
        self.assertEqual(p.returncode, 0, p.stderr)
        return [tuple(line.split("\t")) for line in p.stdout.splitlines()]

    def assertBlocks(self, cmd, op="commit", base=None, **env):
        out = self.run_(cmd, base, **env)
        self.assertIn((op, ""), out, (cmd, out))

    # ── destino reconocido con certeza (casos legítimos de hoy) ──
    def test_git_C_with_literal_var(self):
        out = self.run_(f"W={self.wt}; git -C $W add f && git -C $W commit -q --no-edit")
        self.assertEqual(out, [("add", self.wt), ("commit", self.wt)])

    def test_git_C_quoted(self):
        self.assertEqual(self.run_(f'git -C "{self.wt}" commit -m x'), [("commit", self.wt)])
        self.assertEqual(self.run_(f"git -C '{self.wt}' commit -m x"), [("commit", self.wt)])
        self.assertEqual(self.run_(f'W={self.wt}; git -C "${{W}}" commit'), [("commit", self.wt)])

    def test_git_C_relative_and_multiple(self):
        self.assertEqual(self.run_("git -C .. -C wt-x commit"), [("commit", self.wt)])

    def test_cd_unquoted_tilde_semicolon(self):
        out = self.run_("cd ~/wt-x && git merge origin/main ; git commit -m y")
        self.assertEqual(out, [("commit", self.wt)])

    def test_cd_quoted_and_odd_quotes(self):
        self.assertEqual(self.run_(f'cd "{self.wt}" && git commit -m x'), [("commit", self.wt)])
        self.assertEqual(self.run_(f'cd "{self.home}"/\'wt-x\' && git commit -m x'),
                         [("commit", self.wt)])

    def test_cd_newline_separated(self):
        self.assertEqual(self.run_(f"cd {self.wt}\ngit add -A\ngit commit -m x"),
                         [("add", self.wt), ("commit", self.wt)])

    def test_cd_back_to_main_after_worktree(self):
        out = self.run_(f"cd {self.wt} && git add . ; cd {self.base} && git commit -m z")
        self.assertEqual(out, [("add", self.wt), ("commit", self.base)])

    def test_git_C_to_main_from_worktree(self):
        out = self.run_(f"git -C {self.base} commit -m x", base=self.wt)
        self.assertEqual(out, [("commit", self.base)])

    def test_plain_commit_uses_cwd(self):
        self.assertEqual(self.run_("git commit -m x", base=self.wt), [("commit", self.wt)])
        self.assertEqual(self.run_("git commit-tree HEAD^{tree} -m x"), [("commit", self.base)])

    def test_safe_git_config_and_flags(self):
        out = self.run_(f"git -c user.email=t@t -c user.name=t --no-pager -C {self.wt} commit -m x")
        self.assertEqual(out, [("commit", self.wt)])

    def test_cd_in_pipeline_or_background_does_not_persist(self):
        self.assertEqual(self.run_(f"cd {self.wt} | true; git commit -m x"), [("commit", self.base)])
        self.assertEqual(self.run_(f"cd {self.wt} & git commit -m x"), [("commit", self.base)])

    def test_commit_message_heredoc_substitution(self):
        # forma habitual: el cuerpo (comillas y paréntesis sueltos) es texto
        cmd = (f"git -C {self.wt} add -A && git -C {self.wt} commit -m \"$(cat <<'EOF'\n"
               "fix(x): uno) dos, it's\ngit add y git commit mencionados\nEOF\n)\"")
        self.assertEqual(self.run_(cmd), [("add", self.wt), ("commit", self.wt)])

    def test_and_chain_after_cd_is_exact(self):
        out = self.run_(f"git status && cd {self.wt} && git commit -m x")
        self.assertEqual(out, [("commit", self.wt)])

    def test_or_true_without_cd_is_certain(self):
        self.assertEqual(self.run_(f"git -C {self.wt} commit -m x || true"), [("commit", self.wt)])

    # ── texto que solo menciona commit: no bloquea ──
    def test_heredoc_text_is_not_a_command(self):
        cmd = "cat > notas.md <<'EOF'\nhay que commitear; git commit -m x\nlos commits\nEOF\necho ok"
        self.assertEqual(self.run_(cmd), [])

    def test_inert_commands_stay_inert(self):
        for cmd in ('echo "luego git commit y commits"', "printf 'git add .\\n' > f.txt",
                    'grep -r "git commit" docs', 'rg "git commit" docs',
                    "echo 'git commit' | grep commit | wc -l",
                    "cat <<'EOF' | tee f\ngit commit -m x\nEOF", "ls # git commit -m x"):
            self.assertEqual(self.run_(cmd), [], cmd)

    def test_other_git_subcommands_ignored(self):
        self.assertEqual(self.run_("git log --grep commit; git status; git commit-graph write"), [])

    def test_uncertain_form_without_git_commit_words_emits_nothing(self):
        # fail-closed solo cuando el texto puede hacer commit/add
        for cmd in ("bash -c 'make test'", "for f in a b; do echo $f; done", "$X --version",
                    "(cd /tmp && ls)", "eval \"$CMD\""):
            self.assertEqual(self.run_(cmd), [], cmd)

    def test_worktree_and_remote_add_are_not_git_add(self):
        # 2026-11-04: `worktree add` en una forma incierta (envoltorio, bucle,
        # subshell) se leía como `git add` sin destino → bloqueo falso.
        for cmd in (f"timeout 60 git -C {self.base} worktree add -q -b agent/x {self.wt}-n origin/main",
                    f"for w in a b; do git -C {self.base} worktree add -q -b agent/$w {self.wt}-$w origin/main; done",
                    f"(git worktree add -q -b agent/x {self.wt}-n origin/main)",
                    "timeout 9 git remote add up https://example.invalid/r.git"):
            self.assertEqual(self.run_(cmd), [], cmd)

    def test_real_add_next_to_worktree_add_still_blocks(self):
        # Solo se neutraliza la pareja `worktree|remote add`; un `git add` real,
        # `submodule add` (indexa) o `notes add` (hace commit) siguen contando.
        for cmd in (f"timeout 60 git worktree add {self.wt}-n && timeout 60 git add .",
                    "for f in a; do git worktree add x; git add $f; done",
                    "timeout 9 git submodule add https://example.invalid/r.git",
                    "timeout 9 git notes add -m x"):
            self.assertBlocks(cmd, "add")

    def test_dir_named_remote_or_worktree_does_not_hide_real_add(self):
        # Revisión #1483: el valor de -C/--git-dir/--work-tree que termina en
        # `remote` o `worktree` no es el subcomando; el `git add` es real.
        for cmd in ("timeout 60 git -C ~/src/remote add .",
                    "timeout 60 git -C ../worktree add -A",
                    "timeout 60 git -C remote add .",
                    "timeout 60 git --git-dir remote add .",
                    "timeout 60 git --work-tree=/x/worktree add ."):
            self.assertBlocks(cmd, "add")
        # Revisión #1483 (2.ª): un valor entrecomillado o con espacio escapado
        # que acaba en ` remote`/` worktree` es UN solo argumento de la opción.
        for cmd in ('timeout 60 git -C "/tmp/mi remote" add .',
                    "timeout 60 git -C '/tmp/mi worktree' add -A",
                    "timeout 60 git -C /x/a\\ worktree add .",
                    'timeout 60 git -c "k=v remote" add .',
                    'timeout 60 git --work-tree "/x/y remote" add .',
                    "sh -c \"git -C '/x/mi remote' add .\""):
            self.assertBlocks(cmd, "add")
        # Con opciones globales delante, `worktree add` sigue sin contar.
        for cmd in (f"timeout 60 git -c a.b=1 -C {self.base} --no-pager worktree add {self.wt}-n",
                    "timeout 9 git --git-dir=/x/.git remote add up https://example.invalid/r.git"):
            self.assertEqual(self.run_(cmd), [], cmd)

    def test_command_after_heredoc_is_detected(self):
        out = self.run_("cat > f <<EOF\ntexto\nEOF\ngit commit -m x")
        self.assertEqual(out, [("commit", self.base)])

    # ── BLOQUEAR: revisión de seguridad 1 (P1-1, P1-2, P1-3) ──
    def test_rev1_p1_1_unresolvable_subcommand_and_function(self):
        self.assertBlocks("git $(echo commit) -m x")
        self.assertBlocks('g(){ git "$@"; }; g commit -m x')
        self.assertBlocks('function g { git "$@"; }; g commit -m x')
        self.assertBlocks("alias g='git commit'; g -m x")

    def test_rev1_p1_2_env_split_string(self):
        self.assertBlocks('env -S "git commit -m x"')

    def test_rev1_p1_3_shell_c_double_dash(self):
        self.assertBlocks("bash -c -- 'git commit -m x'")

    # ── BLOQUEAR: revisión de seguridad 2 (P1-1, P1-2) ──
    def test_rev2_p1_1_unresolvable_program(self):
        for cmd in ("$SUDO git commit -m x", "${X:-} git add .",
                    f"$(which git) -C {self.wt} commit -m x"):
            self.assertBlocks(cmd, "add" if "add" in cmd else "commit")

    def test_rev2_p1_1_shell_options_and_exec_capable_commands(self):
        for cmd in ('bash --norc -c "git commit -m x"', 'bash -o pipefail -c "git commit -m x"',
                    "awk 'BEGIN{system(\"git commit -m x\")}'", "sed -n '1e git commit -m x' f",
                    'script -qc "git commit -m x" /dev/null', 'su -c "git commit -m x"',
                    'flock f -c "git -C /x commit -m x"',
                    "python3 -c \"import os; os.system('git commit -m x')\""):
            self.assertBlocks(cmd)

    def test_rev2_p1_2_unquoted_heredoc_substitution(self):
        self.assertBlocks("cat <<EOF\n$(git commit -m x)\nEOF")
        self.assertBlocks("cat <<EOF\nx `git add .` y\nEOF", "add")
        # con delimitador entrecomillado es texto
        for d in ("'EOF'", '"EOF"', "\\EOF"):
            self.assertEqual(self.run_(f"cat <<{d}\n$(git commit -m x)\nEOF"), [], d)

    # ── BLOQUEAR: revisión de seguridad 3 (P1-1, P1-2) ──
    def test_rev3_p1_1_shell_reading_stdin(self):
        for cmd in ("echo 'git commit -m x' | bash", "bash <<'EOF'\ngit commit -m x\nEOF",
                    "sh <<EOF\ngit commit -m x\nEOF", "bash <<< 'git commit -m x'",
                    "printf 'git commit' | sh -s",
                    f"bash <<'EOF'\ncd {self.wt} && git commit -m x\nEOF"):
            self.assertBlocks(cmd)
        self.assertBlocks("printf 'git add .' | sh -s", "add")

    def test_rev3_p1_2_cdpath_and_missing_dir(self):
        self.assertBlocks(f"CDPATH={self.home}; cd repo-main && git commit -m x", base=self.wt)
        self.assertBlocks("cd wt-x && git commit -m x", base=self.home, CDPATH=self.home)
        self.assertBlocks(f'cd "{self.home}/no-existe" && git commit -m x')
        self.assertBlocks("mkdir -p d && cd d && git commit -m x")
        # ruta explícitamente relativa (./, ../) no usa CDPATH
        self.assertEqual(self.run_("cd ../wt-x && git commit", CDPATH="/x"), [("commit", self.wt)])

    # ── BLOQUEAR: otras formas no reconocidas (decisión 2026-11-03) ──
    def test_wrappers_and_executors_block(self):
        for cmd in ("env FOO=1 git commit -m x", "sudo git commit -m x", "timeout 9 git commit",
                    "nohup git commit -m x", "command git commit", "exec git commit",
                    "eval 'git commit -m x'", "eval \"$CMD\" git commit",
                    "echo . | xargs git commit -m x", "find . -exec git add {} +",
                    "time git commit -m x", "source x.sh && git commit -m x"):
            self.assertBlocks(cmd, "add" if " add " in cmd else "commit")

    def test_uncertain_cwd_blocks(self):
        for cmd in ("git -C $NOPE commit -m x", "cd $(pwd) && git commit", "cd - && git commit",
                    "cd $NOPE && git commit", f"cd {self.wt} || exit 1; git commit -m x",
                    f"false && cd {self.wt} || true; git commit -m x",
                    f"false && cd {self.wt}; git commit -m x",
                    f"git status && cd {self.wt}; git commit -m x",
                    f"pushd {self.wt} && git commit", f"(cd {self.wt} && git add f)",
                    "cd ~nadie && git commit"):
            self.assertBlocks(cmd, "add" if "add" in cmd else "commit")

    def test_git_dir_and_options_block(self):
        b = self.base
        for cmd in (f"GIT_DIR={b}/.git git commit", f"git --git-dir={b}/.git commit",
                    f"export GIT_DIR={b}/.git; git commit", "git --work-tree=/x commit",
                    "GIT_WORK_TREE=/x git commit", "git -c alias.ci=commit ci -m x",
                    "git -c core.editor=vi commit"):
            self.assertBlocks(cmd, base=self.wt)
        # alias sin resolver: commit en el destino conocido (revisión 4, P1-2)
        self.assertEqual(self.run_("git ci -m 'commit'", base=self.wt), [("commit", self.wt)])

    def test_blocks_from_agent_worktree_too(self):
        # el veredicto no depende de la rama del cwd: el llamante bloquea
        self.assertBlocks(f"bash -c 'cd {self.base} && git commit -m x'", base=self.wt)

    def test_unbalanced_quotes_block(self):
        self.assertBlocks("git commit -m 'sin cerrar")
        self.assertBlocks("echo $(git commit -m x")  # paréntesis sin cerrar

    def test_generic_command_mentioning_git_commit_blocks(self):
        self.assertBlocks('make GIT="git commit"')
        self.assertBlocks("rg --pre 'git commit -m x' y")
        self.assertBlocks("python3 <<'EOF'\nimport os; os.system('git commit -m x')\nEOF")
        self.assertBlocks("bash -c 'gi''t com''mit'")  # comillas partidas

    # ── revisión 4 (seguridad P1-2, P2-1; corrección P2-2) ──
    def _alias_repo(self):
        repo = os.path.join(self.home, "repo-alias")
        if not os.path.isdir(repo):
            os.makedirs(repo)
            env = dict(os.environ, HOME=self.home, GIT_CONFIG_NOSYSTEM="1")
            env.pop("GIT_CONFIG_GLOBAL", None)
            for args in (["init", "-q"], ["config", "alias.ci", "commit"],
                         ["config", "alias.st", "status -sb"],
                         ["config", "alias.sh", "!git commit"],
                         ["config", "alias.ci2", "ci"]):
                subprocess.run(["git", "-C", repo] + args, check=True, env=env)
            with open(os.path.join(self.home, ".gitconfig"), "w") as f:
                f.write("[alias]\n\tgci = commit\n")
        return repo

    def run_git(self, cmd):
        return self.run_(cmd, GIT_CONFIG_NOSYSTEM="1")

    def test_rev4_p1_2_git_alias_counts_as_commit(self):
        repo = self._alias_repo()
        self.assertEqual(self.run_git(f"git -C {repo} ci -m x"), [("commit", repo)])
        self.assertEqual(self.run_git(f"git -C {repo} sh"), [("commit", repo)])
        self.assertEqual(self.run_git(f"git -C {repo} ci2 -m x"), [("commit", repo)])
        self.assertEqual(self.run_git(f"git -C {repo} gci -m x"), [("commit", repo)])  # global
        self.assertEqual(self.run_git(f"git -C {repo} flow finish"), [("commit", repo)])  # externa
        self.assertEqual(self.run_git("git -C $X ci -m x"), [("commit", "")])  # destino incierto

    def test_rev4_p1_2_safe_alias_and_builtin_do_not_emit(self):
        repo = self._alias_repo()
        self.assertEqual(self.run_git(f"git -C {repo} st"), [])
        self.assertEqual(self.run_git(f"git -C {repo} status"), [])
        self.assertEqual(self.run_git(f"git -C {repo} log --oneline"), [])

    def test_rev4_p2_1_unresolvable_program_with_commit_word(self):
        self.assertBlocks("x=$(printf '\\x67it'); $x commit -m x")
        self.assertBlocks("$(echo Z2l0|base64 -d) commit -m x")
        self.assertEqual(self.run_("$EDITOR notas.txt"), [])

    def test_rev4_c_p2_2_gh_text_is_inert(self):
        self.assertEqual(self.run_('gh pr create --title t --body "usa git commit -m x"'), [])
        self.assertEqual(self.run_("gh pr comment 1 --body 'git add y git commit'"), [])
        # una extensión o alias de gh puede ejecutar el texto: sigue bloqueando
        self.assertBlocks('gh ci "git commit -m x"')
        # la sustitución dentro del cuerpo sí se ejecuta
        out = self.run_(f'gh pr create --body "$(git -C {self.wt} commit -m x)"')
        self.assertIn(("commit", self.wt), out)

    def test_analysis_exception_blocks(self):
        import importlib.util
        import io
        spec = importlib.util.spec_from_file_location("got", SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        def boom(*_a, **_k):
            raise RecursionError("simulado")
        mod.run = boom
        old = sys.stdin, sys.stdout, sys.argv
        sys.stdin, sys.stdout = io.StringIO(f"git -C {self.wt} commit -m y"), io.StringIO()
        sys.argv = ["got", self.base]
        try:
            rc = mod.main()
            out = sys.stdout.getvalue()
        finally:
            sys.stdin, sys.stdout, sys.argv = old
        self.assertEqual(rc, 0)
        self.assertEqual(out, "commit\t\n")


class SwitchTargets(unittest.TestCase):
    """--switch: destino real de cada `git checkout|switch` que puede mover HEAD
    (block-branch-switch-dirty). Mismo criterio fail-closed que commit/add."""

    setUpClass = Targets.__dict__["setUpClass"]
    tearDownClass = Targets.__dict__["tearDownClass"]
    assertBlocks = Targets.assertBlocks

    def run_(self, cmd, base=None, **env_extra):
        env = {k: v for k, v in os.environ.items() if k != "CDPATH"}
        env.update(HOME=self.home, **env_extra)
        p = subprocess.run([sys.executable, SCRIPT, "--switch", base or self.base], input=cmd,
                           text=True, capture_output=True, env=env)
        self.assertEqual(p.returncode, 0, p.stderr)
        return [tuple(line.split("\t")) for line in p.stdout.splitlines()]

    def test_switch_git_C_targets_other_repo(self):
        self.assertEqual(self.run_(f"git -C {self.wt} checkout abc123"), [("switch", self.wt)])
        self.assertEqual(self.run_(f"git -C {self.wt} switch --detach abc123"), [("switch", self.wt)])
        self.assertEqual(self.run_(f"git -C {self.wt} -c advice.detachedHead=false checkout -q x"),
                         [("switch", self.wt)])

    def test_switch_literal_var_and_cd(self):
        self.assertEqual(self.run_(f"D={self.wt}; git -C $D checkout abc"), [("switch", self.wt)])
        self.assertEqual(self.run_(f"cd {self.wt} && git checkout abc"), [("switch", self.wt)])
        self.assertEqual(self.run_("git checkout feature"), [("switch", self.base)])

    def test_switch_clone_created_in_same_command(self):
        new = os.path.join(self.home, "clon-nuevo")
        out = self.run_(f"git clone -q {self.base} {new} && git -C {new} checkout abc")
        self.assertEqual(out, [("switch", new)])

    def test_switch_restore_is_not_a_switch(self):
        self.assertEqual(self.run_(f"git -C {self.wt} checkout -- a.txt"), [])
        self.assertEqual(self.run_("git checkout HEAD -- a.txt >/dev/null"), [])
        # negativos: `--` sin rutas, redirección o comentario tras `--` sí cambian de rama
        self.assertEqual(self.run_("git checkout feature --"), [("switch", self.base)])
        self.assertEqual(self.run_("git checkout feature -- >/dev/null"), [("switch", self.base)])
        self.assertEqual(self.run_("git checkout feature # -- x"), [("switch", self.base)])
        # una restauración previa no excusa un cambio de rama posterior
        self.assertEqual(self.run_(f"git checkout -- a; git -C {self.wt} checkout b"),
                         [("switch", self.wt)])

    def test_switch_restore_with_unknown_paths_blocks(self):
        # `-- $FILES` o `-- $(…)` vacíos dejan `git checkout feature --`: cambio de rama
        self.assertBlocks("git checkout feature -- $FILES", op="switch")
        self.assertBlocks("git checkout origin/main -- $(git diff --name-only x)", op="switch")
        self.assertBlocks("git checkout feature -- `true`", op="switch")
        # con una ruta conocida junto a la desconocida sigue siendo restauración
        self.assertEqual(self.run_("git checkout feature -- a.txt $FILES"), [])
        # variable conocida no vacía: restauración
        self.assertEqual(self.run_("F=a.txt; git checkout feature -- $F"), [])
        # variable conocida vacía: `--` solo, cambio de rama en el cwd
        self.assertEqual(self.run_("F=; git checkout feature -- $F"), [("switch", self.base)])

    def test_switch_uncertain_blocks(self):
        self.assertBlocks("git -C $NOPE checkout abc", op="switch")
        self.assertBlocks("sudo git checkout abc", op="switch")
        self.assertBlocks("bash -c 'git switch main'", op="switch")

    def test_switch_text_is_inert_and_commit_ignored(self):
        self.assertEqual(self.run_("echo 'git checkout main'"), [])
        self.assertEqual(self.run_(f"git -C {self.wt} commit -m x"), [])
        self.assertEqual(self.run_("git status"), [])

    def test_commit_mode_ignores_checkout(self):
        p = subprocess.run([sys.executable, SCRIPT, self.base], input="git checkout main",
                           text=True, capture_output=True)
        self.assertEqual(p.stdout, "")


if __name__ == "__main__":
    unittest.main()
