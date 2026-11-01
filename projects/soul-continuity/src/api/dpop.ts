/**
 * Verificación de la prueba DPoP de la app (SE-490, P1-1; RFC 9449), con la forma que firma el
 * cliente Android de Savia Space (`Dpop.proof`): cabecera `typ: dpop+jwt`, `alg: ES256` y `jwk`
 * EC P-256 pública; carga `jti`, `htm`, `htu` (sin consulta), `iat` en segundos y `ath`.
 *
 * - Firma ES256 (r||s) con la clave del `jwk`; nunca se acepta otro algoritmo ni una clave privada.
 * - `htu` = `https://<Host de la petición><ruta>`: una prueba para otra dirección o ruta no vale.
 * - `iat` dentro de ±60 s; `jti` de un solo uso en una ventana en memoria acotada (llena => rechazo).
 * - `ath` = SHA-256 del token: la prueba va ligada al token que acompaña.
 * - Devuelve la huella RFC 7638 de la clave: quien llama la liga al dispositivo en el primer uso y
 *   después exige la misma (`expectedJkt`).
 */

import { createHash, createPublicKey, verify } from "node:crypto";

export const DPOP_SKEW_MS = 60_000;

export class DpopError extends Error {
  readonly code: "forma" | "cabecera" | "firma" | "htm" | "htu" | "tiempo" | "reenvio" | "ath" | "clave";
  constructor(code: DpopError["code"]) {
    super(`prueba DPoP rechazada: ${code}`);
    this.code = code;
  }
}

const B64URL = /^[A-Za-z0-9_-]+$/;

/** Coordenada P-256 canónica: 32 bytes en base64url sin relleno (43 caracteres). Otra forma daría otra huella. */
export const validJwkCoord = (v: unknown): v is string => typeof v === "string" && /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/.test(v);

export function thumbprint(jwk: { x: string; y: string }): string {
  // RFC 7638: miembros obligatorios en orden lexicográfico, sin espacios.
  return createHash("sha256").update(`{"crv":"P-256","kty":"EC","x":"${jwk.x}","y":"${jwk.y}"}`).digest("base64url");
}

function part(s: string): Record<string, unknown> {
  if (!B64URL.test(s)) throw new DpopError("forma");
  let v: unknown;
  try { v = JSON.parse(Buffer.from(s, "base64url").toString("utf8")); } catch { throw new DpopError("forma"); }
  if (!v || typeof v !== "object" || Array.isArray(v)) throw new DpopError("forma");
  return v as Record<string, unknown>;
}

export interface DpopRequest {
  proof: string;
  method: string;
  /** Ruta de la petición, sin consulta. */
  path: string;
  /** Cabecera Host tal como llegó. */
  host: string;
  token: string;
  now: number;
  /** Huella ligada al dispositivo; si falta, se acepta y se devuelve para ligarla. */
  expectedJkt?: string | null;
}

export function makeDpopVerifier(o: { maxJti?: number } = {}) {
  const maxJti = o.maxJti ?? 10_000;
  const seen = new Map<string, number>(); // jti → caduca

  return function verifyDpop(r: DpopRequest): { jkt: string } {
    const parts = typeof r.proof === "string" ? r.proof.split(".") : [];
    if (parts.length !== 3 || r.proof.length > 4096 || !B64URL.test(parts[2])) throw new DpopError("forma");
    const h = part(parts[0]);
    const p = part(parts[1]);
    const jwk = h.jwk as Record<string, unknown> | undefined;
    if (h.typ !== "dpop+jwt" || h.alg !== "ES256" || !jwk || typeof jwk !== "object") throw new DpopError("cabecera");
    if (jwk.kty !== "EC" || jwk.crv !== "P-256" || !validJwkCoord(jwk.x) || !validJwkCoord(jwk.y) || "d" in jwk) throw new DpopError("cabecera");
    let ok = false;
    try {
      const key = createPublicKey({ key: { kty: "EC", crv: "P-256", x: jwk.x, y: jwk.y }, format: "jwk" });
      ok = verify("sha256", Buffer.from(`${parts[0]}.${parts[1]}`), { key, dsaEncoding: "ieee-p1363" }, Buffer.from(parts[2], "base64url"));
    } catch { ok = false; }
    if (!ok) throw new DpopError("firma");
    const jkt = thumbprint({ x: jwk.x, y: jwk.y });
    if (r.expectedJkt && r.expectedJkt !== jkt) throw new DpopError("clave");
    if (p.htm !== r.method) throw new DpopError("htm");
    if (p.htu !== `https://${r.host}${r.path}`) throw new DpopError("htu");
    if (typeof p.iat !== "number" || !Number.isFinite(p.iat) || Math.abs(p.iat * 1000 - r.now) > DPOP_SKEW_MS) throw new DpopError("tiempo");
    if (p.ath !== createHash("sha256").update(r.token).digest("base64url")) throw new DpopError("ath");
    const jti = p.jti;
    if (typeof jti !== "string" || jti.length < 8 || jti.length > 128) throw new DpopError("forma");
    for (const [k, exp] of seen) if (exp <= r.now) seen.delete(k);
    if (seen.has(jti) || seen.size >= maxJti) throw new DpopError("reenvio");
    seen.set(jti, p.iat * 1000 + DPOP_SKEW_MS + 1);
    return { jkt };
  };
}
