import { test, expect } from "bun:test";
import { execSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { blockBranchSwitchDirty } from "../guards/block-branch-switch-dirty.ts";

// Repo sucio real: el guard consulta `git status` en el cwd del proceso.
function withDirtyRepo(fn: () => Promise<void>): Promise<void> {
  const dir = mkdtempSync(join(tmpdir(), "bbsd-ts-"));
  const prev = process.cwd();
  const git = (a: string) => execSync(`git ${a}`, { cwd: dir, stdio: "ignore" });
  git("init -q -b main"); git("config user.email t@t"); git("config user.name t");
  writeFileSync(join(dir, "a.txt"), "a\n"); git("add a.txt"); git("commit -qm init");
  git("branch feature");
  writeFileSync(join(dir, "a.txt"), "cambio\n");
  process.chdir(dir);
  return fn().finally(() => { process.chdir(prev); rmSync(dir, { recursive: true, force: true }); });
}
const run = (command: string) => blockBranchSwitchDirty({ tool: "bash", args: { command } } as any, {} as any);

test("dirty tree: checkout --merge -- <rutas> passes (2026-11-04 false block)", () =>
  withDirtyRepo(async () => {
    await expect(run("git checkout --merge -- a.txt")).resolves.toBeUndefined();
  }));

test("dirty tree: checkout <rama> and a restore followed by a switch stay blocked", () =>
  withDirtyRepo(async () => {
    await expect(run("git checkout feature")).rejects.toThrow(/branch-switch-dirty/);
    await expect(run("git checkout -- a.txt; git checkout feature")).rejects.toThrow(/branch-switch-dirty/);
  }));

// 2026-11-05: `git -C <clon temporal limpio> checkout <sha>` se bloqueaba porque
// el guard miraba el repo de la sesión (sucio) y no el repo destino. Misma
// entrada que tests/test-block-branch-switch-dirty.bats.
function cleanClone(): { dir: string; sha: string; done: () => void } {
  const root = mkdtempSync(join(tmpdir(), "bbsd-clone-"));
  const dir = join(root, "clon");
  const sh = (a: string, cwd: string) => execSync(a, { cwd, stdio: "pipe", encoding: "utf8" });
  sh(`git init -q -b main ${dir}`, root);
  sh("git config user.email t@t && git config user.name t", dir);
  writeFileSync(join(dir, "b.txt"), "b\n"); sh("git add b.txt && git commit -qm init", dir);
  return { dir, sha: sh("git rev-parse HEAD", dir).trim(), done: () => rmSync(root, { recursive: true, force: true }) };
}

test("dirty session repo: checkout in a clean clone via -C, cd or a literal variable passes", () =>
  withDirtyRepo(async () => {
    const c = cleanClone();
    try {
      for (const cmd of [
        `git -C ${c.dir} checkout ${c.sha}`,
        `git -C "${c.dir}" checkout -q ${c.sha}`,
        `git -C ${c.dir} -c advice.detachedHead=false checkout ${c.sha}`,
        `cd ${c.dir} && git checkout ${c.sha}`,
        `D=${c.dir}; git -C $D checkout ${c.sha}`,
        `git -C ${c.dir} switch --detach ${c.sha}`,
        `git clone -q ${c.dir} ${c.dir}-2 && git -C ${c.dir}-2 checkout ${c.sha}`,
      ]) {
        await expect(run(cmd)).resolves.toBeUndefined();
      }
    } finally { c.done(); }
  }));

test("negative: a dirty target repo still blocks, and an uncertain target fails closed", () =>
  withDirtyRepo(async () => {
    const c = cleanClone();
    try {
      writeFileSync(join(c.dir, "b.txt"), "sucio\n");
      await expect(run(`git -C ${c.dir} checkout ${c.sha}`)).rejects.toThrow(/Repo: /);
      await expect(run(`git -C $NOPE checkout ${c.sha}`)).rejects.toThrow(/no reconocido con certeza/);
      await expect(run(`git -C ${c.dir} checkout -- b.txt`)).resolves.toBeUndefined();
    } finally { c.done(); }
  }));

// Revisión #1483: un `git status` que falla por otra causa que «no es un repo»
// (índice corrupto, timeout, dubious ownership) no cuenta como árbol limpio.
test("fail-closed: a target repo whose git status fails blocks; a plain directory does not", () =>
  withDirtyRepo(async () => {
    const c = cleanClone();
    const plainDir = mkdtempSync(join(tmpdir(), "bbsd-plain-"));
    try {
      writeFileSync(join(c.dir, ".git", "index"), "basura");
      await expect(run(`git -C ${c.dir} checkout ${c.sha}`)).rejects.toThrow(/no se pudo leer/);
      await expect(run(`git -C ${plainDir} checkout main`)).resolves.toBeUndefined();
    } finally { c.done(); rmSync(plainDir, { recursive: true, force: true }); }
  }));
