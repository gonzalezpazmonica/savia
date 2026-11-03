import { test, expect, beforeEach, afterEach } from "bun:test";
import { blockCommitToMain } from "../guards/block-commit-to-main.ts";

// TEST_BRANCH simula la rama actual sin depender del repo real.
const OLD = process.env.TEST_BRANCH;
const OLD_ALLOW = process.env.SAVIA_ALLOW_MAIN_COMMIT;
const OLD_NODE_ENV = process.env.NODE_ENV;
// TEST_BRANCH solo vale bajo NODE_ENV=test: fijarlo aquí para que un CI con
// NODE_ENV=production o ci no rompa los tests que simulan la rama.
beforeEach(() => { delete process.env.SAVIA_ALLOW_MAIN_COMMIT; process.env.NODE_ENV = "test"; });
afterEach(() => {
  if (OLD_NODE_ENV === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = OLD_NODE_ENV;
  if (OLD === undefined) delete process.env.TEST_BRANCH; else process.env.TEST_BRANCH = OLD;
  if (OLD_ALLOW === undefined) delete process.env.SAVIA_ALLOW_MAIN_COMMIT; else process.env.SAVIA_ALLOW_MAIN_COMMIT = OLD_ALLOW;
});

// ── Debe BLOQUEAR ───────────────────────────────────────────────────────────

test("bloquea git commit en main", async () => {
  process.env.TEST_BRANCH = "main";
  const input = { tool: "bash", args: { command: "git commit -m 'feat: x'" } };
  await expect(blockCommitToMain(input as any, {} as any)).rejects.toThrow(/BLOCKED \[commit-to-main\]/);
});

test("bloquea git commit en master", async () => {
  process.env.TEST_BRANCH = "master";
  const input = { tool: "bash", args: { command: "git commit -m 'x'" } };
  await expect(blockCommitToMain(input as any, {} as any)).rejects.toThrow(/BLOCKED \[commit-to-main\]/);
});

test("bloquea git commit --amend en main", async () => {
  process.env.TEST_BRANCH = "main";
  const input = { tool: "bash", args: { command: "git commit --amend -m 'x'" } };
  await expect(blockCommitToMain(input as any, {} as any)).rejects.toThrow(/BLOCKED \[commit-to-main\]/);
});

// ── Bypass consciente de la operadora ──────────────────────────────────────

test("bypass SAVIA_ALLOW_MAIN_COMMIT=1 permite commit en main (registrado)", async () => {
  process.env.TEST_BRANCH = "main";
  process.env.SAVIA_ALLOW_MAIN_COMMIT = "1";
  const input = { tool: "bash", args: { command: "git commit -m 'bypass intencional'" } };
  await expect(blockCommitToMain(input as any, {} as any)).resolves.toBeUndefined();
});

// ── Debe PERMITIR ──────────────────────────────────────────────────────────

test("permite git commit en rama agent/*", async () => {
  process.env.TEST_BRANCH = "agent/overnight-20260824-x";
  const input = { tool: "bash", args: { command: "git commit -m 'feat: correcto'" } };
  await expect(blockCommitToMain(input as any, {} as any)).resolves.toBeUndefined();
});

test("permite git commit en feature/*", async () => {
  process.env.TEST_BRANCH = "feature/foo";
  const input = { tool: "bash", args: { command: "git commit -m 'x'" } };
  await expect(blockCommitToMain(input as any, {} as any)).resolves.toBeUndefined();
});

test("no interviene en comandos que no son git commit", async () => {
  process.env.TEST_BRANCH = "main";
  for (const cmd of ["git branch --show-current", "git status", "ls", "git push origin main"]) {
    const input = { tool: "bash", args: { command: cmd } };
    await expect(blockCommitToMain(input as any, {} as any)).resolves.toBeUndefined();
  }
});
// ── Destino real de la orden (repos git reales, sin TEST_BRANCH) ───────────
// Casos que fallaron con la sesión en main: el guard miraba la rama del
// checkout de la sesión y no la del repo sobre el que actúa la orden.
import { mkdtempSync, mkdirSync, rmSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { afterAll, beforeAll, describe } from "bun:test";

describe("destino real del commit", () => {
  let root = "", home = "", mainRepo = "", wt = "";
  const OLD_HOME = process.env.HOME;
  const sh = (cwd: string, ...a: string[]) => spawnSync("git", a, { cwd, encoding: "utf8" });
  const run = (command: string, workdir = mainRepo) =>
    blockCommitToMain({ tool: "bash", args: { command, workdir } } as any, {} as any);
  const BLOCK = /BLOCKED \[commit-to-main\]/;

  beforeAll(() => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "bcm-")));
    home = join(root, "home");
    mainRepo = join(home, "repo-main");
    wt = join(home, "wt-x");
    mkdirSync(mainRepo, { recursive: true });
    sh(mainRepo, "init", "-q", "-b", "main");
    sh(mainRepo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init");
    sh(mainRepo, "worktree", "add", "-q", "-b", "agent/x", wt);
    process.env.HOME = home;
  });
  afterAll(() => {
    if (OLD_HOME === undefined) delete process.env.HOME; else process.env.HOME = OLD_HOME;
    rmSync(root, { recursive: true, force: true });
  });
  beforeEach(() => { delete process.env.TEST_BRANCH; });

  // permitidos: el destino es el worktree agent/*
  test("caso 1: W=<worktree>; git -C $W add && git -C $W commit", async () => {
    await expect(run(`W=${wt}; git -C $W add f && git -C $W commit -q --no-edit`)).resolves.toBeUndefined();
  });
  test("caso 2: cd ~/wt sin comillas; git merge; git commit", async () => {
    await expect(run("cd ~/wt-x && git merge origin/main ; git commit -m y")).resolves.toBeUndefined();
  });
  test("caso 3: heredoc cuyo texto dice git commit / commitear no es un commit", async () => {
    await expect(run("cat > notas.md <<'EOF'\nhay que commitear; git commit -m x\nEOF")).resolves.toBeUndefined();
  });
  test("cd con comillas raras al worktree", async () => {
    await expect(run(`cd "${home}"/'wt-x' && git commit -m x`)).resolves.toBeUndefined();
  });

  // bloqueados: el destino es main, por cualquier forma
  test("git -C hacia main desde un worktree", async () => {
    await expect(run(`git -C ${mainRepo} commit -m x`, wt)).rejects.toThrow(BLOCK);
    await expect(run(`git -C "${mainRepo}" commit -m x`, wt)).rejects.toThrow(BLOCK);
  });
  test("cd a main tras un cd al worktree", async () => {
    await expect(run(`cd ${wt} && git add . ; cd ${mainRepo} && git commit -m z`, wt)).rejects.toThrow(BLOCK);
  });
  test("cd al worktree en subshell no salva el commit en main", async () => {
    await expect(run(`(cd ${wt}); git commit -m x`)).rejects.toThrow(BLOCK);
  });
  test("cd al worktree en tubería no salva el commit en main", async () => {
    await expect(run(`cd ${wt} | true; git commit -m x`)).rejects.toThrow(BLOCK);
  });
  test("cd condicional al worktree no salva el commit en main", async () => {
    await expect(run(`false && cd ${wt}; git commit -m x`)).rejects.toThrow(BLOCK);
  });
  test("cd a directorio inexistente no apaga el guard (revisión #1467 P1-2)", async () => {
    await expect(run(`cd "${home}/no-existe" && git commit -m x`)).rejects.toThrow(BLOCK);
    await expect(run(`cd ${home}/no-existe && true; git commit -m x`)).rejects.toThrow(BLOCK);
    await expect(run(`CDPATH=${home}; cd otro && git commit -m x`)).rejects.toThrow(BLOCK);
  });
  test("shell que lee git commit de stdin bloquea en main (revisión #1467 P1-1)", async () => {
    for (const c of ["bash <<'EOF'\ngit commit -m x\nEOF", "sh <<EOF\ngit commit -m x\nEOF",
                     "bash <<< 'git commit -m x'", "echo 'git commit -m x' | bash",
                     "printf 'git commit' | sh -s"]) {
      await expect(run(c)).rejects.toThrow(BLOCK);
    }
    // fail-closed: el cd al worktree dentro del heredoc no se reconoce con certeza
    await expect(run(`bash <<'EOF'\ncd ${wt} && git commit -m x\nEOF`, wt)).rejects.toThrow(BLOCK);
  });
  test("GIT_DIR=<main>/.git y commit-tree bloquean", async () => {
    await expect(run(`GIT_DIR=${mainRepo}/.git git commit -m x`, wt)).rejects.toThrow(BLOCK);
    await expect(run("git commit-tree HEAD^{tree} -m x")).rejects.toThrow(BLOCK);
  });
  test("mkdir + cd en la misma orden: conservador con el cwd en main", async () => {
    await expect(run("mkdir -p d && cd d && git commit -m x")).rejects.toThrow(BLOCK);
  });
  test("variable no resoluble: conservador con el cwd en main", async () => {
    await expect(run("git -C $DESCONOCIDA commit -m x")).rejects.toThrow(BLOCK);
  });
  test("commit tras heredoc sí cuenta", async () => {
    await expect(run("cat > f <<EOF\ntexto\nEOF\ngit commit -m x")).rejects.toThrow(BLOCK);
  });
  test("bash -c con cd a main desde el worktree", async () => {
    await expect(run(`bash -c 'cd ${mainRepo} && git commit -m x'`, wt)).rejects.toThrow(BLOCK);
  });

  // fail-closed: formas que el resolvedor no reconoce (revisión PR #1467)
  test("orden no resoluble delante de git commit bloquea en main", async () => {
    await expect(run("$SUDO git commit -m x")).rejects.toThrow(BLOCK);
    await expect(run(`$(which git) -C ${mainRepo} commit -m x`, wt)).rejects.toThrow(BLOCK);
  });
  test("bash con opciones, awk y script -c que ejecutan git commit bloquean en main", async () => {
    await expect(run('bash --norc -c "git commit -m x"')).rejects.toThrow(BLOCK);
    await expect(run("awk 'BEGIN{system(\"git commit -m x\")}'")).rejects.toThrow(BLOCK);
    await expect(run('script -qc "git commit -m x" /dev/null')).rejects.toThrow(BLOCK);
  });
  test("heredoc sin comillas con $(git commit) bloquea; con comillas es texto", async () => {
    await expect(run("cat <<EOF\n$(git commit -m x)\nEOF")).rejects.toThrow(BLOCK);
    await expect(run("cat <<'EOF'\n$(git commit -m x)\nEOF")).resolves.toBeUndefined();
  });
  test("sin python3: fail-closed, bloquea git commit en cualquier rama", async () => {
    const OLD_PATH = process.env.PATH;
    const bin = join(root, "nopy-bin");
    mkdirSync(bin, { recursive: true });
    const gitPath = spawnSync("sh", ["-c", "command -v git"], { encoding: "utf8" }).stdout.trim();
    spawnSync("ln", ["-sf", gitPath, join(bin, "git")]);
    process.env.PATH = bin;
    try {
      await expect(run(`git -C ${wt} commit -m x`)).rejects.toThrow(/resolvedor de destino no disponible/);
      await expect(run(`git -C ${wt} commit -m x`, wt)).rejects.toThrow(BLOCK);
      await expect(run(`git -C ${wt} commit-tree x`, wt)).rejects.toThrow(BLOCK);
      await expect(run("echo commit", wt)).resolves.toBeUndefined();
    } finally {
      process.env.PATH = OLD_PATH;
    }
  });
  // fail-closed por defecto (decisión 2026-11-03): un caso por P1 de las tres
  // revisiones de seguridad; bloquean aunque el cwd sea el worktree agent/*.
  test("P1 de las revisiones: forma no reconocida bloquea desde el worktree", async () => {
    for (const c of ["git $(echo commit) -m x", 'g(){ git "$@"; }; g commit -m x',
                     'env -S "git commit -m x"', "bash -c -- 'git commit -m x'",
                     "$SUDO git commit -m x", 'bash --norc -c "git commit -m x"',
                     "awk 'BEGIN{system(\"git commit -m x\")}'", 'su -c "git commit -m x"',
                     "cat <<EOF\n$(git commit -m x)\nEOF", "echo 'git commit -m x' | bash",
                     "bash <<< 'git commit -m x'", `CDPATH=${home}; cd repo-main && git commit -m x`,
                     `eval 'git -C ${wt} commit -m x'`, `echo . | xargs git -C ${wt} commit`,
                     `GIT_DIR=${mainRepo}/.git git commit -m x`, "bash -c 'gi''t com''mit'"]) {
      await expect(run(c, wt)).rejects.toThrow(/fail-closed[\s\S]*git -C <ruta> commit/);
    }
  });
  test("texto que solo menciona git commit no bloquea; forma admitida pasa", async () => {
    for (const c of ['echo "luego git commit"', "git log --grep commit",
                     "cat > n.md <<'EOF'\ngit commit -m x\nEOF"]) {
      await expect(run(c)).resolves.toBeUndefined();
    }
    const msg = `git -C ${wt} commit -m "$(cat <<'EOF'\nfix: uno) dos, git add\nEOF\n)"`;
    await expect(run(msg)).resolves.toBeUndefined();
  });
  // revisión 4 (#1467): alias de git, programa ofuscado, bypass ante destino
  // incierto y texto de gh.
  test("alias de git que hace commit bloquea en main; en el worktree pasa", async () => {
    sh(mainRepo, "config", "alias.ci", "commit");
    sh(mainRepo, "config", "alias.st", "status -sb");
    await expect(run("git ci -m x")).rejects.toThrow(/rama humana \(main\)/);
    await expect(run("git ci -m x", wt)).resolves.toBeUndefined();
    await expect(run("git st")).resolves.toBeUndefined();
  });
  test("programa no resoluble con la palabra commit bloquea sin decir git", async () => {
    await expect(run("x=$(printf '\\x67it'); $x commit -m x", wt)).rejects.toThrow(/fail-closed/);
  });
  test("bypass de la operadora vale también ante destino incierto", async () => {
    await expect(run('env -S "git commit -m x"', wt)).rejects.toThrow(/fail-closed/);
    process.env.SAVIA_ALLOW_MAIN_COMMIT = "1";
    try {
      await expect(run('env -S "git commit -m x"', wt)).resolves.toBeUndefined();
    } finally {
      delete process.env.SAVIA_ALLOW_MAIN_COMMIT;
    }
  });
  test("gh pr create con git commit en el cuerpo no bloquea", async () => {
    await expect(run('gh pr create --title t --body "usa git commit -m x"')).resolves.toBeUndefined();
    await expect(run('gh ci "git commit -m x"', wt)).rejects.toThrow(/fail-closed/);
  });
  test("TEST_BRANCH fuera de NODE_ENV=test no anula la rama real", async () => {
    const OLD_ENV = process.env.NODE_ENV;
    process.env.TEST_BRANCH = "agent/x";
    process.env.NODE_ENV = "production";
    try {
      await expect(run("git commit -m x")).rejects.toThrow(BLOCK);
    } finally {
      if (OLD_ENV === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = OLD_ENV;
      delete process.env.TEST_BRANCH;
    }
  });
});
