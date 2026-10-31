/**
 * Dispositivos emparejados (SE-490), sobre el modelo de Space (SE-430): un token por
 * dispositivo, revocable, ligado a un operador. En disco solo el SHA-256 del token;
 * el token se muestra una vez al emparejar. Un dispositivo revocado recibe
 * 401 DEVICE_REVOKED y no vuelve a autenticar.
 */

import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { join } from "node:path";
import { readJson, writeJson } from "../core/store.ts";

const FILE = "devices.json";

export interface Device {
  id: string;
  name: string;
  operator_ref: string;
  token_sha256: string;
  created_at: string;
  revoked_at: string | null;
}

const hash = (t: string) => createHash("sha256").update(t).digest("hex");

export function listDevices(dataDir: string): Device[] {
  return readJson<{ devices: Device[] }>(join(dataDir, FILE), { devices: [] }).devices;
}

function save(dataDir: string, devices: Device[]): void {
  writeJson(join(dataDir, FILE), { devices });
}

export function pairDevice(dataDir: string, operatorRef: string, name: string, now: string): { id: string; token: string } {
  if (!/^[\p{L}\p{N} ._-]{1,40}$/u.test(name)) throw new Error("nombre de dispositivo no admitido");
  const token = randomBytes(32).toString("base64url");
  const id = "d" + randomBytes(6).toString("hex");
  save(dataDir, [...listDevices(dataDir), { id, name, operator_ref: operatorRef, token_sha256: hash(token), created_at: now, revoked_at: null }]);
  return { id, token };
}

export function revokeDevice(dataDir: string, id: string, now: string): boolean {
  const all = listDevices(dataDir);
  const d = all.find((x) => x.id === id);
  if (!d) return false;
  d.revoked_at ??= now;
  save(dataDir, all);
  return true;
}

export function verifyToken(dataDir: string, token: string): { operator_ref: string; device: string; revoked: boolean } | null {
  const h = Buffer.from(hash(token), "hex");
  for (const d of listDevices(dataDir)) {
    const k = Buffer.from(d.token_sha256, "hex");
    if (k.length === h.length && timingSafeEqual(k, h)) return { operator_ref: d.operator_ref, device: d.id, revoked: d.revoked_at !== null };
  }
  return null;
}
