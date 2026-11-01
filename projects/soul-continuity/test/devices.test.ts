import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { listDevices, pairDevice, revokeDevice, verifyToken } from "../src/api/devices.ts";
import { filesUnder } from "../src/core/store.ts";

const T = "2026-10-31T10:00:00Z";
const tmp = () => mkdtempSync(join(tmpdir(), "soul-dev-"));

test("emparejar da un token una sola vez; en disco solo queda su hash", () => {
  const d = tmp();
  const p = pairDevice(d, "op-a", "movil", T);
  assert.match(p.token, /^[A-Za-z0-9_-]{43}$/);
  const disk = filesUnder(d).map((f) => readFileSync(f, "utf8")).join("\n");
  assert.ok(!disk.includes(p.token), "el token no se guarda en claro");
  assert.deepEqual(verifyToken(d, p.token), { operator_ref: "op-a", device: p.id, revoked: false });
});

test("token desconocido => null; revocado => revoked y no autentica", () => {
  const d = tmp();
  const p = pairDevice(d, "op-a", "movil", T);
  assert.equal(verifyToken(d, "x".repeat(43)), null);
  assert.equal(revokeDevice(d, p.id, T), true);
  assert.deepEqual(verifyToken(d, p.token), { operator_ref: "op-a", device: p.id, revoked: true });
  assert.equal(revokeDevice(d, "no-existe", T), false);
});

test("revocar un dispositivo no afecta a otro", () => {
  const d = tmp();
  const a = pairDevice(d, "op-a", "movil", T);
  const b = pairDevice(d, "op-a", "tableta", T);
  revokeDevice(d, a.id, T);
  assert.equal(verifyToken(d, b.token)?.revoked, false);
  assert.equal(listDevices(d).length, 2);
});

test("nombre de dispositivo inválido se rechaza", () => {
  assert.throws(() => pairDevice(tmp(), "op-a", "mi <móvil>", T));
});
