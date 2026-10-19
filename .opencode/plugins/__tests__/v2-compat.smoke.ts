// v2-compat.smoke.ts — SPEC-OC2-01
//
// Verificación ejecutable sin framework (node --experimental-strip-types).
// Comprueba el contrato dual V1/V2 del plugin y que los guards siguen
// bloqueando a través del adaptador V2 (incluida la normalización
// shell→bash y subagent→task).
//
// Uso: node --experimental-strip-types .opencode/plugins/__tests__/v2-compat.smoke.ts

import assert from "node:assert/strict";
import plugin from "../savia-foundation.ts";
import { normalizeToolName, toV1Before, toV1After } from "../lib/v2-compat.ts";

function fakeCtx() {
  const hooks: Record<string, Array<(event: any) => Promise<void> | void>> = {};
  const mk = (domain: string) => ({
    hook: async (name: string, cb: (event: any) => Promise<void> | void) => {
      const key = `${domain}.${name}`;
      (hooks[key] ??= []).push(cb);
      return { dispose: async () => {} };
    },
  });
  return { ctx: { tool: mk("tool"), session: mk("session") }, hooks };
}

async function fire(hooks: Record<string, Array<(event: any) => Promise<void> | void>>, key: string, event: any) {
  for (const cb of hooks[key] ?? []) await cb(event);
}

async function main() {
  // Contrato del default export
  assert.equal(plugin.id, "savia-foundation");
  assert.equal(typeof plugin.setup, "function");
  assert.equal(typeof plugin.server, "function");

  // Normalización de nombres de tool
  assert.equal(normalizeToolName("shell"), "bash");
  assert.equal(normalizeToolName("subagent"), "task");
  assert.equal(normalizeToolName("edit"), "edit");

  // Adaptador before: output.args es el mismo objeto que event.input
  const ev = { tool: "shell", input: { command: "git push --force origin x" } };
  const mapped = toV1Before(ev);
  assert.equal(mapped.input.tool, "bash");
  assert.equal(mapped.output.args, ev.input);

  // Adaptador after: resultado textual
  const after = toV1After({ tool: "read", input: { filePath: "a.md" }, status: "completed", result: { output: "x" } });
  assert.equal(after.output.output, "x");

  // V2: el guard de force-push bloquea a través del setup
  const { ctx, hooks } = fakeCtx();
  await plugin.setup(ctx as any);
  await assert.rejects(
    () => fire(hooks, "tool.execute.before", { tool: "shell", input: { command: "git push --force origin feat" } }),
    /BLOCKED \[force-push\]/,
  );

  // V2: un comando benigno no se bloquea y el hook muta event.input in-situ
  const benign = { tool: "shell", input: { command: "git status --short" } };
  await fire(hooks, "tool.execute.before", benign);
  assert.equal(benign.input.command, "git status --short");

  // V2: model.request elimina claves que V2 copia desde el agente
  const body: any = { model_tier: "fast", x_savia_foo: 1, temperature: 0.1 };
  await fire(hooks, "session.model.request", { body });
  assert.deepEqual(body, { temperature: 0.1 });

  // V1: server() devuelve los hooks históricos y bloquea igual
  const v1 = await (plugin.server as any)({ directory: process.cwd() });
  await assert.rejects(
    () => v1["tool.execute.before"]({ tool: "bash", args: { command: "git push origin main" } }, { args: { command: "git push origin main" } }),
    /BLOCKED \[force-push\]|main/,
  );

  console.log("SMOKE PASS: dual V1/V2 plugin contract + guards + sanitización");
}

main().catch((err) => {
  console.error("SMOKE FAIL:", err);
  process.exit(1);
});
