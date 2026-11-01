/** Pruebas DPoP con la forma exacta que firma la app Android (`Dpop.proof` de savia-space). */
import { createHash, generateKeyPairSync, randomBytes, sign, type KeyObject } from "node:crypto";

const b64 = (b: Buffer | string) => Buffer.from(b).toString("base64url");
export const NOW = 1_800_000_000_000;
export const TOKEN = "tok-dispositivo-0123456789";
export const HTU = "https://100.64.0.7:8787/api/v1/soul/q/q1";

export function proof(key: { privateKey: KeyObject; publicKey: KeyObject }, o: {
  htm?: string; htu?: string; iat?: number; jti?: string; token?: string | null; typ?: string; alg?: string; extraJwk?: Record<string, string>;
} = {}): string {
  const jwk = key.publicKey.export({ format: "jwk" }) as { x: string; y: string };
  const header = { typ: o.typ ?? "dpop+jwt", alg: o.alg ?? "ES256", jwk: { kty: "EC", crv: "P-256", x: jwk.x, y: jwk.y, ...(o.extraJwk ?? {}) } };
  const payload: Record<string, unknown> = { jti: o.jti ?? b64(randomBytes(16)), htm: o.htm ?? "GET", htu: o.htu ?? HTU, iat: Math.floor((o.iat ?? NOW) / 1000) };
  if (o.token !== null) payload.ath = b64(createHash("sha256").update(o.token ?? TOKEN).digest());
  const input = `${b64(JSON.stringify(header))}.${b64(JSON.stringify(payload))}`;
  return `${input}.${b64(sign("sha256", Buffer.from(input), { key: key.privateKey, dsaEncoding: "ieee-p1363" }))}`;
}
export const newKey = () => generateKeyPairSync("ec", { namedCurve: "P-256" });
