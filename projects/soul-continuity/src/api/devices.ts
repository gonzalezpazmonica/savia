/**
 * Dispositivos emparejados (SE-490), sobre el modelo de Space (SE-430): un token por
 * dispositivo, revocable, ligado a un operador. En disco solo el SHA-256 del token;
 * el token se muestra una vez al emparejar. Un dispositivo revocado recibe
 * 401 DEVICE_REVOKED y no vuelve a autenticar.
 *
 * - P1-1: la primera prueba DPoP válida liga la huella de la clave del móvil (`jkt`); después solo
 *   vale esa clave. Un token copiado no sirve sin la clave privada del dispositivo.
 * - P2-8: el token caduca (90 días por defecto); caducado, hay que volver a emparejar.
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
  /** Caducidad del token (ISO). Ausente en emparejamientos anteriores: se trata como caducado a los 90 días de `created_at`. */
  expires_at?: string;
  /** Huella RFC 7638 de la clave DPoP del dispositivo, ligada en el primer uso. */
  jkt?: string | null;
}

export const TOKEN_DAYS = 90;
const DAY = 86_400_000;

const hash = (t: string) => createHash("sha256").update(t).digest("hex");

export function listDevices(dataDir: string): Device[] {
  return readJson<{ devices: Device[] }>(join(dataDir, FILE), { devices: [] }).devices;
}

function save(dataDir: string, devices: Device[]): void {
  writeJson(join(dataDir, FILE), { devices });
}

/** `jkt`: huella de la clave del dispositivo cuando el emparejamiento ya la conoce (emparejamiento directo). */
export function pairDevice(dataDir: string, operatorRef: string, name: string, now: string, days = TOKEN_DAYS, jkt: string | null = null): { id: string; token: string; expires_at: string } {
  if (!/^[\p{L}\p{N} ._-]{1,40}$/u.test(name)) throw new Error("nombre de dispositivo no admitido");
  if (!Number.isInteger(days) || days < 1 || days > 397) throw new Error("caducidad del token: entre 1 y 397 días");
  const t = Date.parse(now);
  if (!Number.isFinite(t)) throw new Error("instante inválido");
  const token = randomBytes(32).toString("base64url");
  const id = "d" + randomBytes(6).toString("hex");
  const expires_at = new Date(t + days * DAY).toISOString();
  save(dataDir, [...listDevices(dataDir), { id, name, operator_ref: operatorRef, token_sha256: hash(token), created_at: now, revoked_at: null, expires_at, jkt }]);
  return { id, token, expires_at };
}

/** Liga la clave DPoP al dispositivo si aún no tiene ninguna. Devuelve la huella vigente. */
export function bindKey(dataDir: string, id: string, jkt: string): string | null {
  const all = listDevices(dataDir);
  const d = all.find((x) => x.id === id);
  if (!d) return null;
  if (!d.jkt) {
    d.jkt = jkt;
    save(dataDir, all);
  }
  return d.jkt;
}

export function revokeDevice(dataDir: string, id: string, now: string): boolean {
  const all = listDevices(dataDir);
  const d = all.find((x) => x.id === id);
  if (!d) return false;
  d.revoked_at ??= now;
  save(dataDir, all);
  return true;
}

export interface VerifiedDevice { operator_ref: string; device: string; revoked: boolean; expired: boolean; jkt: string | null }

export function verifyToken(dataDir: string, token: string, now = Date.now()): VerifiedDevice | null {
  const h = Buffer.from(hash(token), "hex");
  for (const d of listDevices(dataDir)) {
    const k = Buffer.from(d.token_sha256, "hex");
    if (k.length === h.length && timingSafeEqual(k, h)) {
      const exp = Date.parse(d.expires_at ?? "") || (Date.parse(d.created_at) || 0) + TOKEN_DAYS * DAY;
      return { operator_ref: d.operator_ref, device: d.id, revoked: d.revoked_at !== null, expired: !(exp > now), jkt: d.jkt ?? null };
    }
  }
  return null;
}
