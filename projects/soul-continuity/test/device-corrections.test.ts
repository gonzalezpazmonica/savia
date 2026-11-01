/** P1-2: las correcciones quedan ligadas al dispositivo que las hace y se pueden deshacer. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { makeEngine } from "../src/core/engine.ts";
import { operatorDir } from "../src/core/store.ts";
import { foldLedger } from "../src/contract/claims.ts";
import { readJsonl } from "../src/core/store.ts";

const install = { id: "i", operator: { ref: "op-a", identities: { emails: [] } }, sources: [] };
const K1 = "github:review_request:repo#1";
const K2 = "github:review_request:repo#2";
const K3 = "github:review_request:repo#3";

async function world() {
  const dir = mkdtempSync(join(tmpdir(), "soul-dc-"));
  const e = makeEngine({});
  const c = (key: string, action: "revoke" | "restore", device: string | null, now: string) =>
    e.correct({ install, stateDir: dir, now, key, action, reason: "t", device });
  await c(K1, "revoke", null, "2026-11-01T08:00:00Z");      // la persona en su terminal
  await c(K1, "restore", "dmovil", "2026-11-01T09:00:00Z"); // el móvil lo «restaura»
  await c(K2, "revoke", "dmovil", "2026-11-01T09:01:00Z");  // el móvil lo da por resuelto
  await c(K3, "revoke", "dotro", "2026-11-01T09:02:00Z");   // otro dispositivo
  return { dir, e };
}
const state = (dir: string) => foldLedger(readJsonl(join(operatorDir(dir, "op-a"), "ledger.jsonl")), "op-a");

test("P1-2: cada fila del libro hecha desde un dispositivo lleva su id; la de la terminal no", async () => {
  const { dir } = await world();
  const rows = readFileSync(join(operatorDir(dir, "op-a"), "ledger.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.deepEqual(rows.map((r) => r.device ?? null), [null, "dmovil", "dmovil", "dotro"]);
});

test("P1-2: lista las correcciones vigentes de un dispositivo y solo las suyas", async () => {
  const { dir, e } = await world();
  assert.deepEqual(e.deviceCorrections(dir, "op-a", "dmovil").map((c) => c.key).sort(), [K1, K2]);
  assert.deepEqual(e.deviceCorrections(dir, "op-a", "dotro").map((c) => c.key), [K3]);
  assert.deepEqual(e.deviceCorrections(dir, "op-a", "nadie"), []);
});

test("P1-2: deshacer devuelve cada clave a su estado anterior y no toca las de otro dispositivo", async () => {
  const { dir, e } = await world();
  assert.equal(await e.undoDevice(dir, "op-a", "dmovil", "2026-11-01T10:00:00Z"), 2);
  const s = state(dir);
  assert.equal(s.get(K1)?.action, "revoke", "vuelve a la revocación previa de la persona");
  assert.equal(s.get(K2)?.action, "restore", "sin corrección previa: vuelve a contar");
  assert.equal(s.get(K3)?.action, "revoke", "lo del otro dispositivo sigue");
  assert.deepEqual(e.deviceCorrections(dir, "op-a", "dmovil"), [], "ya no quedan correcciones vigentes del móvil");
});

test("un id de dispositivo con forma rara no se escribe en el libro", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-dc-"));
  await makeEngine({}).correct({ install, stateDir: dir, now: "2026-11-01T08:00:00Z", key: K1, action: "revoke", device: "x\n{inyección}" });
  assert.ok(!readFileSync(join(operatorDir(dir, "op-a"), "ledger.jsonl"), "utf8").includes("inyección"));
});
