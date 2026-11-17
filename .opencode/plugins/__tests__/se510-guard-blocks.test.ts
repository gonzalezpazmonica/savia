// se510-guard-blocks.test.ts — SE-510 S2: paridad TS del destino de git add/commit (AC-7)
// y registro de bloqueos desde el corredor TS (AC-4).
import { test, expect } from "bun:test";
import { mkdtempSync, readFileSync, existsSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateBashGlobal, unresolvedGitOp } from "../guards/validate-bash-global.ts";
import { guardNameOf, recordGuardBlock } from "../lib/guard-blocks.ts";
import { BEFORE_GUARDS } from "../lib/before-guards.ts";

const tmp = () => mkdtempSync(join(tmpdir(), "se510-ts-"));
const bash = (command: string, workdir?: string) => ({ tool: "bash", args: { command, workdir } }) as any;

test("B1: git -C con destino no literal se bloquea, como en bash", async () => {
  await expect(validateBashGlobal(bash('git -C "$WT" add -A', tmp()), {} as any)).rejects.toThrow(
    /destino de git add no reconocido/,
  );
});

test("B1b: un git add real canalizado a un intérprete se bloquea", async () => {
  await expect(validateBashGlobal(bash("printf 'git add -A' | bash", tmp()), {} as any)).rejects.toThrow(
    /no reconocido con certeza/,
  );
});

test("F1a/F1b: git worktree add (aislado y como texto canalizado) pasa", async () => {
  const d = tmp();
  const wt = "git worktree add -q -b agent/x /tmp/x origin/main";
  await expect(validateBashGlobal(bash(wt, d), {} as any)).resolves.toBeUndefined();
  await expect(validateBashGlobal(bash(`printf %s '${wt}' | python3 x.py`, d), {} as any)).resolves.toBeUndefined();
});

test("git -C <ruta literal> add pasa; una orden sin git ni commit no consulta nada", () => {
  const d = tmp();
  expect(unresolvedGitOp(`git -C ${d} add -A`, d)).toBeNull();
  expect(unresolvedGitOp("ls -la", d, "/no/existe.py")).toBeNull();
});

test("sin resolvedor, git + add en el texto bloquea (fallo cerrado); git status no", () => {
  const d = tmp();
  expect(unresolvedGitOp(`git -C ${d} add -A`, d, "/no/existe.py")).toMatch(/resolvedor de destino no disponible/);
  expect(unresolvedGitOp("git status", d, "/no/existe.py")).toBeNull();
});

test("la lista de paridad es la del plugin y empieza por los baratos", () => {
  expect(BEFORE_GUARDS[0].name).toBe("toolCallHealing");
  expect(BEFORE_GUARDS[1]).toBe(validateBashGlobal);
});

test("guardNameOf: etiqueta del mensaje o nombre genérico", () => {
  expect(guardNameOf("BLOCKED [force-push]: no")).toBe("force-push");
  expect(guardNameOf("BLOQUEADO [pr-summary-gate]: x")).toBe("pr-summary-gate");
  expect(guardNameOf("BLOCKED [credential-leak/aws]: x")).toBe("credential-leak/aws");
  expect(guardNameOf("BLOCKED: sin etiqueta")).toBe("ts-before-guards");
});

test("recordGuardBlock no registra una excepción que no es un bloqueo (TypeError)", () => {
  const d = tmp();
  const log = join(d, "blocks.jsonl");
  process.env.SAVIA_GUARD_BLOCKS_LOG = log;
  process.env.SAVIA_GUARD_BLOCKS_KEY = join(d, "k");
  try {
    expect(recordGuardBlock(new TypeError("cannot read properties of undefined"), bash("ls"), {})).toBe(false);
    expect(existsSync(log)).toBe(false);
    expect(recordGuardBlock(new Error("BLOCKED: sin etiqueta"), bash("ls"), {})).toBe(true);
    expect(JSON.parse(readFileSync(log, "utf8").trim()).guard).toBe("ts-before-guards");
  } finally {
    delete process.env.SAVIA_GUARD_BLOCKS_LOG;
    delete process.env.SAVIA_GUARD_BLOCKS_KEY;
  }
});

test("recordGuardBlock deja una línea sin la orden en claro", () => {
  const d = tmp();
  const log = join(d, "blocks.jsonl");
  const key = join(d, "k");
  process.env.SAVIA_GUARD_BLOCKS_LOG = log;
  process.env.SAVIA_GUARD_BLOCKS_KEY = key;
  delete process.env.SAVIA_GUARD_LOG_INPUT;
  try {
    const ok = recordGuardBlock(new Error("BLOCKED [force-push]: git push --force blocked."),
      bash("git push --force origin main TOKENSECRETO"), {});
    expect(ok).toBe(true);
    const text = readFileSync(log, "utf8");
    const row = JSON.parse(text.trim());
    expect(row.guard).toBe("force-push");
    expect(row.engine).toBe("ts");
    expect(row.cmd_hmac).toMatch(/^[0-9a-f]{64}$/);
    expect(text).not.toContain("TOKENSECRETO");
    expect(row.input).toBeUndefined();
  } finally {
    delete process.env.SAVIA_GUARD_BLOCKS_LOG;
    delete process.env.SAVIA_GUARD_BLOCKS_KEY;
  }
});

test("recordGuardBlock nunca lanza aunque no pueda escribir", () => {
  const d = tmp();
  writeFileSync(join(d, "f"), "x");
  process.env.SAVIA_GUARD_BLOCKS_LOG = join(d, "f", "no-dir", "x.jsonl");
  process.env.SAVIA_GUARD_BLOCKS_KEY = join(d, "k");
  try {
    expect(recordGuardBlock(new Error("BLOCKED [x]: y"), bash("ls"), {})).toBe(false);
    expect(existsSync(join(d, "f", "no-dir"))).toBe(false);
  } finally {
    delete process.env.SAVIA_GUARD_BLOCKS_LOG;
    delete process.env.SAVIA_GUARD_BLOCKS_KEY;
  }
});
