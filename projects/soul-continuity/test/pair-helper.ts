/** Lado de la app del emparejamiento directo (soul-pair-v2), para las pruebas de punta a punta. */
import { randomBytes } from "node:crypto";
import { request } from "node:https";
import { connect as tlsConnect } from "node:tls";
import type { KeyObject } from "node:crypto";
import { thumbprint } from "../src/api/dpop.ts";
import { PAIR_VERSION, clientProof, parseToken, serverProof, spkiSha256Der } from "../src/api/pairing.ts";

/** SPKI (SHA-256, base64url) del certificado que la app ve en la conexión. */
export function spkiVisto(port: number): Promise<string> {
  return new Promise((res, rej) => {
    const s = tlsConnect({ host: "127.0.0.1", port, rejectUnauthorized: false }, () => {
      const der = s.getPeerX509Certificate()!.publicKey.export({ type: "spki", format: "der" });
      s.end();
      res(spkiSha256Der(der));
    });
    s.on("error", rej);
  });
}

export const postPair = (port: number, path: string, body: unknown) => new Promise<{ status: number; json: any }>((res, rej) => {
  // TOFU provisional: la app aún no confía en el certificado; lo comprueba con la prueba del servidor.
  const q = request({ host: "127.0.0.1", port, path, method: "POST", rejectUnauthorized: false, headers: { "Content-Type": "application/json" } }, (r) => {
    let b = "";
    r.on("data", (c) => (b += c));
    r.on("end", () => res({ status: r.statusCode ?? 0, json: b ? JSON.parse(b) : null }));
  });
  q.on("error", rej);
  q.end(JSON.stringify(body));
});

export const jwkDe = (k: { publicKey: KeyObject }) => {
  const j = k.publicKey.export({ format: "jwk" }) as { x: string; y: string };
  return { kty: "EC", crv: "P-256", x: j.x, y: j.y };
};

/** Empareja como la app: comprueba la huella que ve y la prueba del servidor antes de enviar la suya. */
export async function emparejarComoApp(port: number, pegado: string, key: { publicKey: KeyObject }, nombre = "movil") {
  const code = parseToken(pegado);
  if (!code) throw new Error("clave mal copiada");
  const cn = randomBytes(32).toString("base64url");
  const ch = await postPair(port, "/v1/pair/challenge", { version: PAIR_VERSION, client_nonce: cn });
  if (ch.status !== 200) throw new Error(`reto: ${ch.status} ${ch.json?.code}`);
  if (ch.json.spki_sha256 !== await spkiVisto(port)) throw new Error("intermediario: la huella no es la del certificado que se ve");
  if (ch.json.proof !== serverProof(code, cn, ch.json.server_nonce, ch.json.spki_sha256)) throw new Error("la prueba del servidor no casa con la clave");
  const jkt = thumbprint(jwkDe(key));
  const fin = await postPair(port, "/v1/pair/complete", { server_nonce: ch.json.server_nonce, device_name: nombre, device_jwk: jwkDe(key), proof: clientProof(code, cn, ch.json.server_nonce, jkt) });
  if (fin.status !== 200) throw new Error(`completar: ${fin.status} ${fin.json?.code}`);
  return fin.json as { device_id: string; token: string; expires_at: string };
}
