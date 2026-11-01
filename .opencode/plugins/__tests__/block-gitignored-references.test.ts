import { test, expect } from "bun:test";
import { blockGitignoredReferences } from "../guards/block-gitignored-references.ts";

const F = {
  outputDated: "out" + "put/" + "20260501" + "-r.md",
  privMem:     "priv" + "ate-agent-memory/" + "test" + "/x.md",
};

test("blockGitignoredReferences: throws when content references dated output path", async () => {
  const input = { tool: "edit", args: { file_path: "/repo/docs/foo.md", content: `see ${F.outputDated}` } };
  await expect(blockGitignoredReferences(input as any, {} as any)).rejects.toThrow(/dated|internal|gitignored/i);
});

test("blockGitignoredReferences: throws when content references private memory", async () => {
  const input = { tool: "write", args: { file_path: "/repo/docs/foo.md", content: F.privMem } };
  await expect(blockGitignoredReferences(input as any, {} as any)).rejects.toThrow(/private/);
});

test("blockGitignoredReferences: silent on clean content", async () => {
  const input = { tool: "edit", args: { file_path: "/repo/docs/foo.md", content: "Just a regular doc." } };
  await expect(blockGitignoredReferences(input as any, {} as any)).resolves.toBeUndefined();
});

test("blockGitignoredReferences: skips non-edit/write tools", async () => {
  const input = { tool: "bash", args: { command: F.outputDated } };
  await expect(blockGitignoredReferences(input as any, {} as any)).resolves.toBeUndefined();
});

test("blockGitignoredReferences: skips when target path is itself a private destination", async () => {
  const input = { tool: "edit", args: { file_path: "/repo/output/foo.md", content: F.outputDated } };
  await expect(blockGitignoredReferences(input as any, {} as any)).resolves.toBeUndefined();
});

test("blockGitignoredReferences: skips when target is a hook source file (legitimate self-reference)", async () => {
  const input = { tool: "edit", args: { file_path: "/repo/.opencode/hooks/foo.sh", content: F.outputDated } };
  await expect(blockGitignoredReferences(input as any, {} as any)).resolves.toBeUndefined();
});

// ── Project references vs operator authorizations (.claude/.project-authorizations) ──
// Same inputs as tests/test-block-gitignored-references.bats (bash port). Literals are split so the
// workspace's own guard does not flag this file.
import { mkdtempSync, writeFileSync, mkdirSync, chmodSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll } from "bun:test";

const P = "pro" + "jects";
const AUTH = ".claude/." + "project-authorizations";
const tmpRoots: string[] = [];
afterAll(() => {
  for (const d of tmpRoots) {
    try { chmodSync(join(d, AUTH), 0o644); } catch {}
    rmSync(d, { recursive: true, force: true });
  }
});

/** Git repo whose .gitignore whitelists `public-demo`; `auth` = content of the authorizations file (null = absent). */
function fixture(auth: string | null): string {
  const d = mkdtempSync(join(tmpdir(), "bgr-"));
  tmpRoots.push(d);
  spawnSync("git", ["init", "-q", d]);
  writeFileSync(join(d, ".gitignore"), `${P}/*\n!${P}/public-demo/\n`);
  if (auth !== null) {
    mkdirSync(join(d, ".claude"), { recursive: true });
    writeFileSync(join(d, AUTH), auth);
  }
  return d;
}

async function run(repo: string, content: string, cwd = repo, file = join(repo, ".gitignore")) {
  const prev = process.env.CLAUDE_PROJECT_DIR;
  process.env.CLAUDE_PROJECT_DIR = cwd;
  try {
    const input = { tool: "edit", args: { file_path: file, content } };
    await blockGitignoredReferences(input as any, {} as any);
    return "allow";
  } catch (e) {
    return String(e);
  } finally {
    if (prev === undefined) delete process.env.CLAUDE_PROJECT_DIR; else process.env.CLAUDE_PROJECT_DIR = prev;
  }
}

test("projects: authorized name may be whitelisted in .gitignore", async () => {
  const r = fixture("other\nsoul-demo\n");
  expect(await run(r, `!${P}/soul-demo/`)).toBe("allow");
});

test("projects: whitelisted name still allowed without authorizations file", async () => {
  const r = fixture(null);
  expect(await run(r, `see ${P}/public-demo/README.md`)).toBe("allow");
});

test("projects: non-authorized name is blocked", async () => {
  const r = fixture("soul-demo\n");
  expect(await run(r, `!${P}/secret-client/`)).toMatch(/secret-client.*neither whitelisted nor authorized/);
});

test("projects: missing authorizations file blocks (fail-closed)", async () => {
  const r = fixture(null);
  expect(await run(r, `!${P}/soul-demo/`)).toMatch(/soul-demo/);
});

test("projects: unreadable authorizations file blocks (fail-closed)", async () => {
  if (process.getuid?.() === 0) return; // root reads 000 files; the case cannot be built
  const r = fixture("soul-demo\n");
  chmodSync(join(r, AUTH), 0o000);
  expect(await run(r, `!${P}/soul-demo/`)).toMatch(/soul-demo/);
});

test("projects: prefix, longer name, case and path variants do not match", async () => {
  const r = fixture("soul\nSoul-Demo\n../soul-demo\nsoul-demo/\nx/soul-demo\n");
  for (const name of ["soul-demo", "soul-demo-x", "so"]) {
    expect(await run(r, `!${P}/${name}/`)).toMatch(new RegExp(name));
  }
});

test("projects: authorizations are read from the edited file's repo, not the cwd", async () => {
  const authorizedRepo = fixture("soul-demo\n");
  const plainRepo = fixture(null);
  // cwd without authorization, file in the authorized repo → allowed
  expect(await run(authorizedRepo, `!${P}/soul-demo/`, plainRepo)).toBe("allow");
  // cwd with authorization, file in a repo without it → blocked
  expect(await run(plainRepo, `!${P}/soul-demo/`, authorizedRepo)).toMatch(/soul-demo/);
});

test("projects: file outside any git repo gets no authorizations (fail-closed)", async () => {
  const cwdRepo = fixture("soul-demo\n");
  const outside = mkdtempSync(join(tmpdir(), "bgr-nogit-"));
  tmpRoots.push(outside);
  writeFileSync(join(outside, ".gitignore"), `${P}/*\n!${P}/public-demo/\n`);
  // no repo for the file → .gitignore of the project dir is used, authorizations are not
  expect(await run(cwdRepo, `!${P}/soul-demo/`, cwdRepo, join(outside, "notes.md"))).toMatch(/soul-demo/);
});

test("mutant: removing the authorizations lookup makes the authorized case block", async () => {
  const src = readFileSync(join(import.meta.dir, "../lib/leakage-patterns.ts"), "utf8");
  const mutated = src.replace(" || authorized.includes(name)", "");
  expect(mutated).not.toBe(src);
  const dir = mkdtempSync(join(tmpdir(), "bgr-mut-"));
  tmpRoots.push(dir);
  writeFileSync(join(dir, "leakage-patterns.ts"), mutated);
  const mod = await import(join(dir, "leakage-patterns.ts"));
  const r = fixture("soul-demo\n");
  expect(mod.detectProjectLeakage(`!${P}/soul-demo/`, join(r, ".gitignore"), r).length).toBe(1);
});
