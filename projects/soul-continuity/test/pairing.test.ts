import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer as createTls, connect as tlsConnect } from "node:tls";
import { request } from "node:https";
import { createServer as createNet } from "node:net";
import { emptyConfig, saveConfig } from "../src/core/config.ts";
import { makeSelfSigned } from "../src/api/cert.ts";
import { listDevices } from "../src/api/devices.ts";
import { thumbprint } from "../src/api/dpop.ts";
import {
  PAIR_FILE, PairError, clientProof, formatCode, makePairing, normalizeCode, openPairingWindow, serverProof,
  shortFingerprintDer, spkiSha256Der,
} from "../src/api/pairing.ts";
import { serveFromCli } from "../src/api/serve.ts";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import { newKey, proof } from "./dpop-helper.ts";
import { validar } from "../src/api/schema.ts";

const OPENAPI = JSON.parse(readFileSync(new URL("../src/contract/openapi.json", import.meta.url), "utf8"));
const esquema = (n: string) => OPENAPI.components.schemas[n];

const V = JSON.parse(readFileSync(new URL("../src/contract/vectores-emparejamiento.json", import.meta.url), "utf8"));

// ------------------------------------------------------------------ vectores comunes con la app

test("vectores: normalización del código (Crockford, guion y espacios, alias I/L→1 y O→0)", () => {
  assert.equal(normalizeCode(V.codigo.mostrado), V.codigo.normalizado);
  assert.equal(normalizeCode(V.codigo.tecleado), V.codigo.normalizado);
  for (const e of V.codigo.equivalentes) assert.equal(normalizeCode(e), V.codigo.normalizado, e);
  for (const e of V.codigo.invalidos) assert.equal(normalizeCode(e), null, e);
  assert.equal(normalizeCode(V.codigo.alias.entrada), V.codigo.alias.normalizado);
  assert.equal(formatCode(V.codigo.normalizado), V.codigo.mostrado);
});

test("vectores: huella SPKI, pin, huella corta, huella de la clave y las dos pruebas HMAC", () => {
  const der = Buffer.from(V.spki_der_base64, "base64");
  assert.equal(spkiSha256Der(der), V.spki_sha256);
  assert.equal("sha256/" + createHash("sha256").update(der).digest("base64"), V.pin);
  assert.equal(shortFingerprintDer(der), V.huella_corta);
  assert.match(V.huella_corta, /^[0-9a-f]{4}( [0-9a-f]{4}){3}$/);
  assert.equal(thumbprint(V.device_jwk), V.jwk_thumbprint);
  assert.equal(serverProof(V.codigo.normalizado, V.client_nonce, V.server_nonce, V.spki_sha256), V.proof_servidor);
  assert.equal(clientProof(V.codigo.normalizado, V.client_nonce, V.server_nonce, V.jwk_thumbprint), V.proof_cliente);
  // Control negativo: otro código da otra prueba (la app lo detecta como «código erróneo»).
  assert.equal(serverProof("7K2MD9QX4G", V.client_nonce, V.server_nonce, V.spki_sha256), V.proof_servidor_con_codigo_erroneo);
  assert.notEqual(V.proof_servidor_con_codigo_erroneo, V.proof_servidor);
});

// ------------------------------------------------------------------ máquina de estados de la ventana

const TLS = makeSelfSigned(["127.0.0.1"], new Date());
const nonce = () => randomBytes(32).toString("base64url");
const jwkDe = (k: ReturnType<typeof newKey>) => {
  const j = k.publicKey.export({ format: "jwk" }) as { x: string; y: string };
  return { kty: "EC", crv: "P-256", x: j.x, y: j.y };
};
const codigoEn = (dir: string) => JSON.parse(readFileSync(join(dir, PAIR_FILE), "utf8")).code as string;

function ventana(t0 = 1_800_000_000_000) {
  const dir = mkdtempSync(join(tmpdir(), "soul-pair-"));
  let t = t0;
  const { code } = openPairingWindow(dir, "op-yo", t);
  const p = makePairing({ dataDir: dir, certPem: TLS.cert, now: () => t });
  return { dir, code, p, avanzar: (ms: number) => { t += ms; } };
}
const fallo = (f: () => unknown, status: number, code: string) =>
  assert.throws(f, (e: unknown) => e instanceof PairError && e.status === status && e.code === code);

test("emparejar: el servidor prueba el código, el dispositivo queda ligado a su clave y la ventana no se reutiliza", () => {
  const { dir, code, p } = ventana();
  const cn = nonce();
  const ch = p.challenge({ client_nonce: cn });
  assert.equal(ch.proof, serverProof(code, cn, ch.server_nonce, ch.spki_sha256));
  const k = newKey();
  const jkt = thumbprint(jwkDe(k));
  const r = p.complete({ server_nonce: ch.server_nonce, device_name: "móvil", device_jwk: jwkDe(k), proof: clientProof(code, cn, ch.server_nonce, jkt) });
  assert.match(r.token, /^[A-Za-z0-9_-]{43}$/);
  const d = listDevices(dir).find((x) => x.id === r.device_id);
  assert.equal(d?.jkt, jkt, "la clave queda ligada al emparejar, no en el primer uso");
  assert.equal(existsSync(join(dir, PAIR_FILE)), false, "el código no se queda en disco");
  fallo(() => p.challenge({ client_nonce: nonce() }), 410, "PAIR_EXPIRED");
});

test("código erróneo 3 veces: 401 cada vez y después la ventana queda bloqueada (423), también con el código bueno", () => {
  const { dir, code, p } = ventana();
  const k = newKey();
  const jkt = thumbprint(jwkDe(k));
  const cn = nonce();
  const ch = p.challenge({ client_nonce: cn });
  for (let i = 0; i < 3; i++) {
    fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(k), proof: clientProof("7K2MD9QX4G", cn, ch.server_nonce, jkt) }), 401, "PAIR_BAD_PROOF");
  }
  assert.equal(codigoEn(dir), "", "bloqueada, el código se borra");
  fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(k), proof: clientProof(code, cn, ch.server_nonce, jkt) }), 423, "PAIR_LOCKED");
  fallo(() => p.challenge({ client_nonce: nonce() }), 423, "PAIR_LOCKED");
  assert.equal(listDevices(dir).length, 0);
});

test("dos fallos no bloquean: el tercer intento con el código bueno empareja (borde del límite)", () => {
  const { dir, code, p } = ventana();
  const k = newKey();
  const jkt = thumbprint(jwkDe(k));
  const cn = nonce();
  const ch = p.challenge({ client_nonce: cn });
  for (let i = 0; i < 2; i++) fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(k), proof: "x" }), 401, "PAIR_BAD_PROOF");
  p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(k), proof: clientProof(code, cn, ch.server_nonce, jkt) });
  assert.equal(listDevices(dir).length, 1);
});

test("una prueba válida para otra clave no empareja la clave que se presenta", () => {
  const { dir, code, p } = ventana();
  const cn = nonce();
  const ch = p.challenge({ client_nonce: cn });
  const otra = thumbprint(jwkDe(newKey()));
  fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(newKey()), proof: clientProof(code, cn, ch.server_nonce, otra) }), 401, "PAIR_BAD_PROOF");
  assert.equal(listDevices(dir).length, 0);
});

test("ventana caducada: 410 (justo antes de los 10 minutos aún vale) y sin ventana abierta: 410", () => {
  const a = ventana();
  a.avanzar(10 * 60_000 - 1);
  a.p.challenge({ client_nonce: nonce() });
  a.avanzar(1);
  fallo(() => a.p.challenge({ client_nonce: nonce() }), 410, "PAIR_EXPIRED");
  assert.equal(existsSync(join(a.dir, PAIR_FILE)), false, "caducada, el código se borra");
  const vacio = makePairing({ dataDir: mkdtempSync(join(tmpdir(), "soul-pair-")), certPem: TLS.cert });
  fallo(() => vacio.challenge({ client_nonce: nonce() }), 410, "PAIR_EXPIRED");
});

test("más de 10 retos en una ventana: 429 PAIR_RATE", () => {
  const { p } = ventana();
  for (let i = 0; i < 10; i++) p.challenge({ client_nonce: nonce() });
  fallo(() => p.challenge({ client_nonce: nonce() }), 429, "PAIR_RATE");
});

test("entradas mal formadas: 400 y no cuentan como intento (clave privada, nonce corto, campos de más)", () => {
  const { dir, p } = ventana();
  fallo(() => p.challenge({ client_nonce: "corto" }), 400, "INVALID_INPUT");
  fallo(() => p.challenge({ client_nonce: nonce(), extra: 1 }), 400, "INVALID_INPUT");
  const ch = p.challenge({ client_nonce: nonce() });
  const conD = { ...jwkDe(newKey()), d: "AAAA" };
  fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: conD, proof: "x" }), 400, "INVALID_INPUT");
  fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: { ...jwkDe(newKey()), x: "no+es/base64url" }, proof: "x" }), 400, "INVALID_INPUT");
  assert.equal(JSON.parse(readFileSync(join(dir, PAIR_FILE), "utf8")).failures, 0);
});

// ------------------------------------------------------------------ de punta a punta: soul pair + serve por TLS

function deps(dir: string, out: string[], err: string[]): CliDeps {
  return {
    dataDir: dir, env: {}, now: () => new Date().toISOString(), out: (s) => out.push(s), err: (s) => err.push(s), adapters: {},
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } },
    credentials: { revoke: async () => ({ tokens_removed: 0, cache_removed: false }), forgetAll: async () => [] }, platform: "linux", home: dir,
    run: async () => ({ code: 0, stdout: "", stderr: "" }), node: "n", entry: "e",
  };
}

/** SPKI (SHA-256, base64url) del certificado que la app ve en la conexión. */
function spkiVisto(port: number): Promise<string> {
  return new Promise((res, rej) => {
    const s = tlsConnect({ host: "127.0.0.1", port, rejectUnauthorized: false }, () => {
      const der = s.getPeerX509Certificate()!.publicKey.export({ type: "spki", format: "der" });
      s.end();
      res(spkiSha256Der(der));
    });
    s.on("error", rej);
  });
}

const post = (port: number, path: string, body: unknown, headers: Record<string, string> = {}) => new Promise<{ status: number; json: any }>((res, rej) => {
  // TOFU provisional: la app aún no confía en el certificado; lo comprueba con la prueba del servidor.
  const q = request({ host: "127.0.0.1", port, path, method: "POST", rejectUnauthorized: false, headers: { "Content-Type": "application/json", ...headers } }, (r) => {
    let b = "";
    r.on("data", (c) => (b += c));
    r.on("end", () => res({ status: r.statusCode ?? 0, json: b ? JSON.parse(b) : null }));
  });
  q.on("error", rej);
  q.end(JSON.stringify(body));
});

test("punta a punta: soul pair muestra IP, puerto, código y huella; la app empareja por TLS y usa DPoP; reusar el jti se rechaza", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-pair-e2e-"));
  const cfg = emptyConfig("i");
  cfg.active_profile = "yo";
  cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [] };
  const libre = createNet();
  await new Promise<void>((r) => libre.listen(0, "127.0.0.1", () => r()));
  const puerto = (libre.address() as { port: number }).port;
  await new Promise<void>((r) => libre.close(() => r()));
  cfg.api = { listen: ["127.0.0.1"], port: puerto };
  saveConfig(dir, cfg);
  const out: string[] = [];
  const ac = new AbortController();
  const done = serveFromCli(deps(dir, out, []), { signal: ac.signal, refreshMs: 60_000 });
  for (let i = 0; i < 80 && !out.some((l) => l.includes("Escuchando")); i++) await new Promise((r) => setTimeout(r, 25));
  const port = Number(/:(\d+)/.exec(out.find((l) => l.includes("Escuchando")) ?? "")?.[1]);
  try {
    // Sin ventana abierta, el reto da 410 con el sobre de error del contrato.
    const sin = await post(port, "/v1/pair/challenge", { client_nonce: nonce() });
    assert.equal(sin.status, 410);
    assert.deepEqual(validar(OPENAPI, esquema("Error"), sin.json), []);
    assert.equal(sin.json.code, "PAIR_EXPIRED");

    const pout: string[] = [];
    assert.equal(await runCli(["pair", "--json"], deps(dir, pout, [])), 0);
    const j = JSON.parse(pout.join("\n"));
    assert.match(j.codigo, /^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$/);
    assert.deepEqual(j.direcciones, ["127.0.0.1"]);
    assert.equal(j.puerto, port);
    assert.match(j.huella_corta, /^[0-9a-f]{4}( [0-9a-f]{4}){3}$/);
    assert.match(j.qr, /^soul:\/\/pair\?h=127\.0\.0\.1&p=\d+&c=[0-9A-Z]{5}-[0-9A-Z]{5}$/);
    const code = normalizeCode(j.codigo)!;

    const cn = nonce();
    const ch = await post(port, "/v1/pair/challenge", { client_nonce: cn });
    assert.equal(ch.status, 200);
    assert.deepEqual(validar(OPENAPI, esquema("RetoPar"), ch.json), [], "el reto cumple el contrato");
    assert.ok(validar(OPENAPI, esquema("RetoPar"), { ...ch.json, extra: 1 }).length, "control: el esquema rechaza campos de más");
    assert.equal(ch.json.spki_sha256, await spkiVisto(port), "la huella del reto es la del certificado que se ve");
    assert.equal(ch.json.proof, serverProof(code, cn, ch.json.server_nonce, ch.json.spki_sha256));
    assert.equal(j.huella_corta.replace(/ /g, ""), Buffer.from(ch.json.spki_sha256, "base64url").toString("hex").slice(0, 16));

    const k = newKey();
    const jkt = thumbprint(jwkDe(k));
    const fin = await post(port, "/v1/pair/complete", { server_nonce: ch.json.server_nonce, device_name: "movil", device_jwk: jwkDe(k), proof: clientProof(code, cn, ch.json.server_nonce, jkt) });
    assert.equal(fin.status, 200, JSON.stringify(fin.json));
    assert.deepEqual(validar(OPENAPI, esquema("ParCompletado"), fin.json), []);
    const token = fin.json.token as string;

    const llamar = (prueba: string) => new Promise<number>((res, rej) => {
      const q = request({ host: "127.0.0.1", port, path: "/api/v1/soul/estado", rejectUnauthorized: false, headers: { Authorization: `DPoP ${token}`, DPoP: prueba } }, (r) => { r.resume(); r.on("end", () => res(r.statusCode ?? 0)); });
      q.on("error", rej);
      q.end();
    });
    const htu = `https://127.0.0.1:${port}/api/v1/soul/estado`;
    const p1 = proof(k, { htu, iat: Date.now(), token });
    assert.equal(await llamar(p1), 200);
    assert.equal(await llamar(p1), 401, "reusar el jti de una prueba DPoP se rechaza");
    assert.equal(await llamar(proof(newKey(), { htu, iat: Date.now(), token })), 401, "otra clave no vale: quedó ligada al emparejar");
    // La ventana ya se usó.
    assert.equal((await post(port, "/v1/pair/challenge", { client_nonce: nonce() })).status, 410);
  } finally { ac.abort(); await done; }
});

test("intermediario con otro certificado: la app lo detecta (huella distinta, y sin el código no puede rehacer la prueba)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-pair-mitm-"));
  const { code } = openPairingWindow(dir, "op-yo", Date.now());
  const real = makePairing({ dataDir: dir, certPem: TLS.cert });
  const OTRO = makeSelfSigned(["127.0.0.1"], new Date());
  // El intermediario termina TLS con su certificado y reenvía el reto al servidor real.
  const mitm = createTls({ cert: OTRO.cert, key: OTRO.key }, (s) => s.end());
  await new Promise<void>((r) => mitm.listen(0, "127.0.0.1", () => r()));
  const port = (mitm.address() as { port: number }).port;
  try {
    const visto = await spkiVisto(port);
    const cn = nonce();
    const ch = real.challenge({ client_nonce: cn });
    // a) Reenvía la respuesta tal cual: la huella no casa con la que ve la app.
    assert.notEqual(ch.spki_sha256, visto);
    assert.equal(ch.proof, serverProof(code, cn, ch.server_nonce, ch.spki_sha256));
    // b) Pone su propia huella: la prueba ya no verifica con el código que teclea la persona.
    assert.notEqual(ch.proof, serverProof(code, cn, ch.server_nonce, visto));
  } finally { await new Promise<void>((r) => mitm.close(() => r())); }
});
