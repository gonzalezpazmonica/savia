/**
 * Emparejamiento directo app ↔ Soul (SE-490, decisión de la operadora 2026-11-01).
 *
 * `soul pair` abre una ventana de 10 minutos con un código de un solo uso (10 caracteres
 * Crockford base32, `XXXXX-XXXXX`). La app nunca envía el código: cada lado demuestra que lo
 * conoce con un HMAC sobre los nonces de los dos y la huella del certificado que ve.
 *
 * 1. `POST /v1/pair/challenge {client_nonce}` → `{server_nonce, spki_sha256, proof}`, con
 *    `proof = HMAC(código, "soul-pair-v1|server|" + client_nonce + "|" + server_nonce + "|" + spki_sha256)`.
 *    La app compara `spki_sha256` con el certificado que ve en la conexión: un intermediario
 *    con otro certificado no puede dar una prueba válida sin el código.
 * 2. `POST /v1/pair/complete {server_nonce, device_name, device_jwk, proof}`, con
 *    `proof = HMAC(código, "soul-pair-v1|client|" + client_nonce + "|" + server_nonce + "|" + jkt)`.
 *    El dispositivo queda registrado con su clave ya ligada: no hay primer uso que ganar.
 *
 * Errores estables: PAIR_EXPIRED 410 (sin ventana, caducada o usada), PAIR_BAD_PROOF 401,
 * PAIR_LOCKED 423 (3 pruebas fallidas invalidan la ventana), PAIR_RATE 429 (más de 10 retos).
 *
 * El código vive en `pairing.json` (0600, junto a la clave TLS) solo mientras la ventana está
 * abierta: la clave del HMAC es el propio código, así que guardar solo su hash no permitiría
 * calcular la prueba. Al usarse, caducar o bloquearse, se borra.
 */

import { X509Certificate, createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { existsSync, rmSync } from "node:fs";
import { join } from "node:path";
import { readJson, writeJson } from "../core/store.ts";
import { pairDevice } from "./devices.ts";
import { thumbprint, validJwkCoord } from "./dpop.ts";

export const PAIR_FILE = "pairing.json";
export const PAIR_WINDOW_MS = 10 * 60_000;
export const PAIR_MAX_FAILURES = 3;
export const PAIR_MAX_CHALLENGES = 10;

/** Alfabeto Crockford base32 (sin I, L, O ni U). */
export const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const NONCE = /^[A-Za-z0-9_-]{43}$/;

export class PairError extends Error {
  readonly status: number;
  readonly code: "PAIR_EXPIRED" | "PAIR_BAD_PROOF" | "PAIR_LOCKED" | "PAIR_RATE" | "INVALID_INPUT";
  constructor(status: number, code: PairError["code"]) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

/** Código tal como lo teclea la persona → forma canónica (10 caracteres), o `null` si no es un código. */
export function normalizeCode(s: string): string | null {
  const c = s.toUpperCase().replace(/[\s-]/g, "").replace(/[IL]/g, "1").replace(/O/g, "0");
  return /^[0-9A-HJKMNP-TV-Z]{10}$/.test(c) ? c : null;
}

export const formatCode = (c: string) => `${c.slice(0, 5)}-${c.slice(5)}`;

export function newCode(): string {
  let c = "";
  for (let i = 0; i < 10; i++) c += CROCKFORD[randomInt(32)];
  return c;
}

const spkiDer = (certPem: string) => new X509Certificate(certPem).publicKey.export({ type: "spki", format: "der" });

/** SHA-256 del SPKI (DER), en base64url: lo que compara la app con el certificado que ve. */
export const spkiSha256Der = (der: Buffer) => createHash("sha256").update(der).digest("base64url");
export const spkiSha256 = (certPem: string) => spkiSha256Der(spkiDer(certPem));

/** Huella corta para leerla en voz alta: 16 primeros hex de SHA-256(SPKI), en grupos de 4. */
export function shortFingerprintDer(der: Buffer): string {
  return createHash("sha256").update(der).digest("hex").slice(0, 16).match(/.{4}/g)!.join(" ");
}
export const shortFingerprint = (certPem: string) => shortFingerprintDer(spkiDer(certPem));

const hmac = (code: string, msg: string) => createHmac("sha256", Buffer.from(code, "utf8")).update(msg, "utf8").digest("base64url");
export const serverProof = (code: string, cn: string, sn: string, spki: string) => hmac(code, `soul-pair-v1|server|${cn}|${sn}|${spki}`);
export const clientProof = (code: string, cn: string, sn: string, jkt: string) => hmac(code, `soul-pair-v1|client|${cn}|${sn}|${jkt}`);

interface Ventana {
  v: 1;
  operator_ref: string;
  /** Vacío cuando la ventana se ha bloqueado: el código ya no sirve y no se guarda. */
  code: string;
  opened_at: number;
  expires_at: number;
  /** Caducidad del token del dispositivo (0 = la de por defecto). */
  days: number;
  failures: number;
  challenges: { server_nonce: string; client_nonce: string }[];
}

/** Abre (o sustituye) la ventana de emparejamiento. Devuelve el código para mostrarlo una vez. */
export function openPairingWindow(dataDir: string, operatorRef: string, now: number, days?: number): { code: string; expires_at: string } {
  const code = newCode();
  const v: Ventana = { v: 1, operator_ref: operatorRef, code, opened_at: now, expires_at: now + PAIR_WINDOW_MS, days: days ?? 0, failures: 0, challenges: [] };
  writeJson(join(dataDir, PAIR_FILE), v);
  return { code, expires_at: new Date(v.expires_at).toISOString() };
}

const cerrar = (dataDir: string) => rmSync(join(dataDir, PAIR_FILE), { force: true });

/** Ventana vigente o el error que toca. Una ilegible o caducada se borra: el código no se queda en disco. */
function vigente(dataDir: string, now: number): Ventana {
  const p = join(dataDir, PAIR_FILE);
  if (!existsSync(p)) throw new PairError(410, "PAIR_EXPIRED");
  let v: Ventana | null;
  try { v = readJson<Ventana | null>(p, null); } catch { v = null; }
  if (!v || v.v !== 1 || typeof v.code !== "string" || !Number.isFinite(v.expires_at) || !Number.isInteger(v.failures) || !Array.isArray(v.challenges)) {
    cerrar(dataDir);
    throw new PairError(410, "PAIR_EXPIRED");
  }
  if (!(now < v.expires_at)) { cerrar(dataDir); throw new PairError(410, "PAIR_EXPIRED"); }
  if (v.failures >= PAIR_MAX_FAILURES || !v.code) throw new PairError(423, "PAIR_LOCKED");
  return v;
}

const iguales = (a: string, b: string) => {
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

const objeto = (c: unknown): Record<string, unknown> => {
  if (!c || typeof c !== "object" || Array.isArray(c)) throw new PairError(400, "INVALID_INPUT");
  return c as Record<string, unknown>;
};

export type Pairing = ReturnType<typeof makePairing>;

export function makePairing(o: { dataDir: string; certPem: string; now?: () => number }) {
  const now = o.now ?? Date.now;
  const spki = spkiSha256(o.certPem);
  return {
    challenge(body: unknown) {
      const c = objeto(body);
      if (Object.keys(c).length !== 1 || typeof c.client_nonce !== "string" || !NONCE.test(c.client_nonce)) throw new PairError(400, "INVALID_INPUT");
      const v = vigente(o.dataDir, now());
      if (v.challenges.length >= PAIR_MAX_CHALLENGES) throw new PairError(429, "PAIR_RATE");
      const server_nonce = randomBytes(32).toString("base64url");
      v.challenges.push({ server_nonce, client_nonce: c.client_nonce });
      writeJson(join(o.dataDir, PAIR_FILE), v);
      return { server_nonce, spki_sha256: spki, proof: serverProof(v.code, c.client_nonce, server_nonce, spki) };
    },
    complete(body: unknown) {
      const c = objeto(body);
      const jwk = c.device_jwk as Record<string, unknown> | undefined;
      if (Object.keys(c).length !== 4 || typeof c.server_nonce !== "string" || !NONCE.test(c.server_nonce)
        || typeof c.proof !== "string" || c.proof.length > 128
        || typeof c.device_name !== "string" || !/^[\p{L}\p{N} ._-]{1,40}$/u.test(c.device_name)
        || !jwk || typeof jwk !== "object" || Array.isArray(jwk) || jwk.kty !== "EC" || jwk.crv !== "P-256" || "d" in jwk
        || !validJwkCoord(jwk.x) || !validJwkCoord(jwk.y)) throw new PairError(400, "INVALID_INPUT");
      const t = now();
      const v = vigente(o.dataDir, t);
      const ch = v.challenges.find((x) => x.server_nonce === c.server_nonce);
      const jkt = thumbprint({ x: jwk.x as string, y: jwk.y as string });
      if (!ch || !iguales(c.proof, clientProof(v.code, ch.client_nonce, ch.server_nonce, jkt))) {
        v.failures++;
        if (v.failures >= PAIR_MAX_FAILURES) v.code = "";
        writeJson(join(o.dataDir, PAIR_FILE), v);
        throw new PairError(401, "PAIR_BAD_PROOF");
      }
      // Un solo uso: la ventana se consume antes de registrar el dispositivo.
      cerrar(o.dataDir);
      const d = pairDevice(o.dataDir, v.operator_ref, c.device_name, new Date(t).toISOString(), v.days || undefined, jkt);
      return { device_id: d.id, token: d.token, expires_at: d.expires_at };
    },
  };
}
