// se510-guard-blocks.test.ts — SE-510 S2: paridad TS del destino de git add/commit (AC-7)
// (el registro de bloqueos, AC-4, está en guard-blocks.test.ts).
import { test, expect } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateBashGlobal, unresolvedGitOp } from "../guards/validate-bash-global.ts";
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

test("sin resolvedor, el alias stage (sinónimo de add) bloquea igual que add", () => {
  const d = tmp();
  expect(unresolvedGitOp(`git -C ${d} stage -A`, d, "/no/existe.py")).toMatch(/resolvedor de destino no disponible/);
  expect(unresolvedGitOp("git stash list", d, "/no/existe.py")).toBeNull();
});

test("continuaciones de línea (barra + salto) no ocultan git add, con y sin resolvedor", async () => {
  const d = tmp();
  const cont = 'gi\\\nt -C "$WT" ad\\\nd -A'; // bash ejecuta: git -C "$WT" add -A
  expect(unresolvedGitOp(cont, d)).toMatch(/destino de git add no reconocido/);
  expect(unresolvedGitOp(cont, d, "/no/existe.py")).toMatch(/resolvedor de destino no disponible/);
  await expect(validateBashGlobal(bash(cont, d), {} as any)).rejects.toThrow(/no reconocido con certeza/);
  // Negativo: con destino literal, la misma continuación se resuelve y pasa.
  expect(unresolvedGitOp(`gi\\\nt -C ${d} ad\\\nd -A`, d)).toBeNull();
});

test("la lista de paridad es la del plugin y empieza por los baratos", () => {
  expect(BEFORE_GUARDS[0].name).toBe("toolCallHealing");
  expect(BEFORE_GUARDS[1]).toBe(validateBashGlobal);
});

