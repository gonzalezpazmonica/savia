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
