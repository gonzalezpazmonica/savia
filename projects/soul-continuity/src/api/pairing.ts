/**
 * Emparejamiento directo app ↔ Soul (SE-490, decisión de la operadora 2026-11-01): soul-pair-v2.
 *
 * `soul pair` abre una ventana de 10 minutos con una **clave de emparejamiento** de un solo uso
 * al estilo de las API key: `soulpk_<30 base62>_<CRC32 en 6 base62>` (178 bits de un CSPRNG; el
 * checksum solo detecta errores de copia). La app nunca envía la clave: cada lado demuestra que la
 * conoce con un HMAC sobre los nonces de los dos y la huella del certificado que ve.
 *
 * 1. `POST /v1/pair/challenge {version: "soul-pair-v2", client_nonce}` → `{server_nonce, spki_sha256, proof}`, con
 *    `proof = HMAC(clave, "soul-pair-v2|server|" + client_nonce + "|" + server_nonce + "|" + spki_sha256)`.
 *    La app compara `spki_sha256` con el certificado que ve en la conexión: un intermediario
 *    con otro certificado no puede dar una prueba válida sin la clave.
 * 2. `POST /v1/pair/complete {server_nonce, device_name, device_jwk, proof}`, con
 *    `proof = HMAC(clave, "soul-pair-v2|client|" + client_nonce + "|" + server_nonce + "|" + jkt)`.
 *    El dispositivo queda registrado con su clave ya ligada: no hay primer uso que ganar.
 *
 * soul-pair-v1 (código Crockford de 10 caracteres, ~50 bits) se retira: con la prueba del reto se
 * podía adivinar el código sin conexión. Un reto sin `version` o con otra da PAIR_VERSION 426.
 *
 * Errores estables: PAIR_EXPIRED 410 (sin ventana, caducada o usada), PAIR_BAD_PROOF 401,
 * PAIR_LOCKED 423 (3 pruebas fallidas invalidan la ventana), PAIR_RATE 429 (más de 10 retos),
 * PAIR_VERSION 426 (cliente de otra versión del protocolo).
 *
 * La clave vive en `pairing.json` (0600, junto a la clave TLS) solo mientras la ventana está
 * abierta: es la clave del HMAC, así que guardar solo su hash no permitiría calcular la prueba.
 * Al usarse, caducar o bloquearse, se borra.
 */

import { X509Certificate, createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { crc32 } from "node:zlib";
import { existsSync, rmSync } from "node:fs";
import { join } from "node:path";
import { readJson, writeJson } from "../core/store.ts";
import { pairDevice } from "./devices.ts";
import { thumbprint, validJwkCoord } from "./dpop.ts";

export const PAIR_FILE = "pairing.json";
export const PAIR_WINDOW_MS = 10 * 60_000;
export const PAIR_MAX_FAILURES = 3;
export const PAIR_MAX_CHALLENGES = 10;

export const PAIR_VERSION = "soul-pair-v2";
export const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
/** Caracteres aleatorios de la clave: 30 × log2(62) ≈ 178,6 bits. */
export const TOKEN_RANDOM_LEN = 30;
const TOKEN = /^soulpk_([0-9A-Za-z]{30})_([0-9A-Za-z]{6})$/;
const NONCE = /^[A-Za-z0-9_-]{43}$/;

export class PairError extends Error {
  readonly status: number;
  readonly code: "PAIR_EXPIRED" | "PAIR_BAD_PROOF" | "PAIR_LOCKED" | "PAIR_RATE" | "PAIR_VERSION" | "INVALID_INPUT";
  constructor(status: number, code: PairError["code"]) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

/** CRC32 (IEEE) de la parte aleatoria, en 6 caracteres base62 big-endian. Solo detecta errores de copia. */
export function tokenChecksum(random: string): string {
  let n = crc32(Buffer.from(random, "ascii")), c = "";
  for (let i = 0; i < 6; i++) { c = BASE62[n % 62] + c; n = Math.floor(n / 62); }
  return c;
}

/**
 * Clave tal como se pega → la clave, o `null` si está mal copiada (formato o checksum).
 * Sensible a mayúsculas: solo se quitan los espacios en blanco de los extremos.
 */
export function parseToken(s: string): string | null {
  const t = s.trim();
  const m = TOKEN.exec(t);
  return m && tokenChecksum(m[1]) === m[2] ? t : null;
}

export function newToken(): string {
  let r = "";
  for (let i = 0; i < TOKEN_RANDOM_LEN; i++) r += BASE62[randomInt(62)];
  return `soulpk_${r}_${tokenChecksum(r)}`;
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

/** Enlace que va en el QR: `soul://pair?v=2&h=<ip>&p=<puerto>&k=<clave>&f=<huella corta sin espacios>`. */
export function pairLink(host: string, port: number, token: string, huella: string): string {
  const h = host.includes(":") ? `[${host}]` : host;
  return `soul://pair?v=2&h=${h}&p=${port}&k=${token}&f=${huella.replace(/ /g, "")}`;
}

const hmac = (key: string, msg: string) => createHmac("sha256", Buffer.from(key, "utf8")).update(msg, "utf8").digest("base64url");
export const serverProof = (key: string, cn: string, sn: string, spki: string) => hmac(key, `${PAIR_VERSION}|server|${cn}|${sn}|${spki}`);
export const clientProof = (key: string, cn: string, sn: string, jkt: string) => hmac(key, `${PAIR_VERSION}|client|${cn}|${sn}|${jkt}`);

interface Ventana {
  v: 2;
  operator_ref: string;
  /** La clave en claro (es la del HMAC). Vacía cuando la ventana se ha bloqueado: ya no sirve y no se guarda. */
  token: string;
  opened_at: number;
  expires_at: number;
  /** Caducidad del token del dispositivo (0 = la de por defecto). */
  days: number;
  failures: number;
  challenges: { server_nonce: string; client_nonce: string }[];
}

/** Abre (o sustituye) la ventana de emparejamiento. Devuelve la clave para mostrarla una vez. */
export function openPairingWindow(dataDir: string, operatorRef: string, now: number, days?: number): { token: string; expires_at: string } {
  const token = newToken();
  const v: Ventana = { v: 2, operator_ref: operatorRef, token, opened_at: now, expires_at: now + PAIR_WINDOW_MS, days: days ?? 0, failures: 0, challenges: [] };
  writeJson(join(dataDir, PAIR_FILE), v);
  return { token, expires_at: new Date(v.expires_at).toISOString() };
}

const cerrar = (dataDir: string) => rmSync(join(dataDir, PAIR_FILE), { force: true });
/** Cierra la ventana abierta (la clave sale del disco). */
export const closePairingWindow = cerrar;

/** Ventana vigente o el error que toca. Una ilegible, caducada o de v1 se borra: la clave no se queda en disco. */
function vigente(dataDir: string, now: number): Ventana {
  const p = join(dataDir, PAIR_FILE);
  if (!existsSync(p)) throw new PairError(410, "PAIR_EXPIRED");
  let v: Ventana | null;
  try { v = readJson<Ventana | null>(p, null); } catch { v = null; }
  if (!v || v.v !== 2 || typeof v.token !== "string" || !Number.isFinite(v.expires_at) || !Number.isInteger(v.failures) || !Array.isArray(v.challenges)) {
    cerrar(dataDir);
    throw new PairError(410, "PAIR_EXPIRED");
  }
  if (!(now < v.expires_at)) { cerrar(dataDir); throw new PairError(410, "PAIR_EXPIRED"); }
  if (v.failures >= PAIR_MAX_FAILURES || !v.token) throw new PairError(423, "PAIR_LOCKED");
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
      // Un cliente v1 no manda `version`: se le dice que actualice, no que su código está mal.
      if (c.version !== PAIR_VERSION) throw new PairError(426, "PAIR_VERSION");
      if (Object.keys(c).length !== 2 || typeof c.client_nonce !== "string" || !NONCE.test(c.client_nonce)) throw new PairError(400, "INVALID_INPUT");
      const v = vigente(o.dataDir, now());
      if (v.challenges.length >= PAIR_MAX_CHALLENGES) throw new PairError(429, "PAIR_RATE");
      const server_nonce = randomBytes(32).toString("base64url");
      v.challenges.push({ server_nonce, client_nonce: c.client_nonce });
      writeJson(join(o.dataDir, PAIR_FILE), v);
      return { server_nonce, spki_sha256: spki, proof: serverProof(v.token, c.client_nonce, server_nonce, spki) };
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
      if (!ch || !iguales(c.proof, clientProof(v.token, ch.client_nonce, ch.server_nonce, jkt))) {
        v.failures++;
        if (v.failures >= PAIR_MAX_FAILURES) v.token = "";
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
