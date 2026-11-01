import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TOKEN_DAYS, bindKey, listDevices, pairDevice, revokeDevice, verifyToken } from "../src/api/devices.ts";
import { filesUnder } from "../src/core/store.ts";

const T = "2026-10-31T10:00:00Z";
const tmp = () => mkdtempSync(join(tmpdir(), "soul-dev-"));

test("emparejar da un token una sola vez; en disco solo queda su hash", () => {
  const d = tmp();
  const p = pairDevice(d, "op-a", "movil", T);
  assert.match(p.token, /^[A-Za-z0-9_-]{43}$/);
  const disk = filesUnder(d).map((f) => readFileSync(f, "utf8")).join("\n");
  assert.ok(!disk.includes(p.token), "el token no se guarda en claro");
  assert.deepEqual(verifyToken(d, p.token, Date.parse(T)), { operator_ref: "op-a", device: p.id, revoked: false, expired: false, jkt: null });
});

test("token desconocido => null; revocado => revoked y no autentica", () => {
  const d = tmp();
  const p = pairDevice(d, "op-a", "movil", T);
  assert.equal(verifyToken(d, "x".repeat(43)), null);
  assert.equal(revokeDevice(d, p.id, T), true);
  assert.deepEqual(verifyToken(d, p.token, Date.parse(T)), { operator_ref: "op-a", device: p.id, revoked: true, expired: false, jkt: null });
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

test("P2-8: el token caduca a los 90 días (borde incluido) y un emparejamiento antiguo sin fecha también", () => {
  const d = tmp();
  const p = pairDevice(d, "op-a", "movil", T);
  const t0 = Date.parse(T);
  assert.equal(verifyToken(d, p.token, t0 + TOKEN_DAYS * 86_400_000 - 1)?.expired, false);
  assert.equal(verifyToken(d, p.token, t0 + TOKEN_DAYS * 86_400_000)?.expired, true);
  const q = pairDevice(d, "op-a", "corto", T, 1);
  assert.equal(verifyToken(d, q.token, t0 + 2 * 86_400_000)?.expired, true);
  assert.throws(() => pairDevice(d, "op-a", "x", T, 0));
  assert.throws(() => pairDevice(d, "op-a", "x", T, 398));
});

test("P1-1: la primera clave DPoP queda ligada y no se sustituye", () => {
  const d = tmp();
  const p = pairDevice(d, "op-a", "movil", T);
  assert.equal(bindKey(d, p.id, "huella-1"), "huella-1");
  assert.equal(bindKey(d, p.id, "huella-2"), "huella-1", "otra clave no reemplaza a la ligada");
  assert.equal(verifyToken(d, p.token, Date.parse(T))?.jkt, "huella-1");
  assert.equal(bindKey(d, "no-existe", "h"), null);
});
