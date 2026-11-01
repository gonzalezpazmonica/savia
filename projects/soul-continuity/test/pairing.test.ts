import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
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
  PAIR_FILE, PairError, TOKEN_RANDOM_LEN, clientProof, makePairing, newToken, openPairingWindow, pairLink, parseToken, serverProof,
  shortFingerprintDer, spkiSha256Der, tokenChecksum,
} from "../src/api/pairing.ts";
import { serveFromCli } from "../src/api/serve.ts";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import { newKey, proof } from "./dpop-helper.ts";
import { validar } from "../src/api/schema.ts";

const OPENAPI = JSON.parse(readFileSync(new URL("../src/contract/openapi.json", import.meta.url), "utf8"));
const esquema = (n: string) => OPENAPI.components.schemas[n];

const V = JSON.parse(readFileSync(new URL("../src/contract/vectores-emparejamiento.json", import.meta.url), "utf8"));

// ------------------------------------------------------------------ vectores comunes con la app

test("vectores: clave soulpk_ (formato, checksum CRC32 en base62, solo se recortan los extremos, sensible a mayúsculas)", () => {
  const K = V.clave;
  assert.equal(V.version, "soul-pair-v2");
  assert.equal(tokenChecksum(K.aleatorio), K.checksum);
  assert.equal(K.valida, `soulpk_${K.aleatorio}_${K.checksum}`);
  assert.equal(tokenChecksum("0".repeat(30)), K.ceros.slice(-6));
  assert.equal(parseToken(K.valida), K.valida);
  for (const e of K.equivalentes) assert.equal(parseToken(e), K.valida, JSON.stringify(e));
  for (const [n, e] of Object.entries(K.invalidas)) assert.equal(parseToken(e as string), null, n);
  assert.match(K.valida, new RegExp(K.regex));
  // Las claves nuevas cumplen el formato, pasan su checksum y no se repiten.
  const vistas = new Set<string>();
  for (let i = 0; i < 200; i++) { const t = newToken(); assert.equal(parseToken(t), t); vistas.add(t); }
  assert.equal(vistas.size, 200);
  assert.ok(TOKEN_RANDOM_LEN * Math.log2(62) >= 128, "al menos 128 bits");
  assert.equal(Number((TOKEN_RANDOM_LEN * Math.log2(62)).toFixed(1)), K.entropia_bits);
});

test("vectores: el enlace del QR", () => {
  assert.equal(pairLink("100.64.0.1", 8443, V.clave.valida, V.huella_corta), V.qr);
  assert.equal(pairLink("fd00::1", 8443, V.clave.valida, V.huella_corta), V.qr.replace("100.64.0.1", "[fd00::1]"));
});

test("vectores: huella SPKI, pin, huella corta, huella de la clave y las dos pruebas HMAC", () => {
  const der = Buffer.from(V.spki_der_base64, "base64");
  assert.equal(spkiSha256Der(der), V.spki_sha256);
  assert.equal("sha256/" + createHash("sha256").update(der).digest("base64"), V.pin);
  assert.equal(shortFingerprintDer(der), V.huella_corta);
  assert.match(V.huella_corta, /^[0-9a-f]{4}( [0-9a-f]{4}){3}$/);
  assert.equal(thumbprint(V.device_jwk), V.jwk_thumbprint);
  assert.equal(V.mensaje_servidor, `soul-pair-v2|server|${V.client_nonce}|${V.server_nonce}|${V.spki_sha256}`);
  assert.equal(V.mensaje_cliente, `soul-pair-v2|client|${V.client_nonce}|${V.server_nonce}|${V.jwk_thumbprint}`);
  assert.equal(serverProof(V.clave.valida, V.client_nonce, V.server_nonce, V.spki_sha256), V.proof_servidor);
  assert.equal(clientProof(V.clave.valida, V.client_nonce, V.server_nonce, V.jwk_thumbprint), V.proof_cliente);
  // Controles negativos: otra clave da otra prueba (la app lo detecta como «clave errónea»), y la
  // etiqueta v1 con la misma clave también: un servidor o una app v1 no casan con v2.
  assert.equal(serverProof(V.otra_clave, V.client_nonce, V.server_nonce, V.spki_sha256), V.proof_servidor_con_otra_clave);
  assert.notEqual(V.proof_servidor_con_otra_clave, V.proof_servidor);
  assert.notEqual(V.proof_servidor_con_etiqueta_v1, V.proof_servidor);
});

// ------------------------------------------------------------------ máquina de estados de la ventana

const TLS = makeSelfSigned(["127.0.0.1"], new Date());
const nonce = () => randomBytes(32).toString("base64url");
const jwkDe = (k: ReturnType<typeof newKey>) => {
  const j = k.publicKey.export({ format: "jwk" }) as { x: string; y: string };
  return { kty: "EC", crv: "P-256", x: j.x, y: j.y };
};
const claveEn = (dir: string) => JSON.parse(readFileSync(join(dir, PAIR_FILE), "utf8")).token as string;
const reto = (client_nonce: string) => ({ version: "soul-pair-v2", client_nonce });

function ventana(t0 = 1_800_000_000_000) {
  const dir = mkdtempSync(join(tmpdir(), "soul-pair-"));
  let t = t0;
  const { token: code } = openPairingWindow(dir, "op-yo", t);
  const p = makePairing({ dataDir: dir, certPem: TLS.cert, now: () => t });
  return { dir, code, p, avanzar: (ms: number) => { t += ms; } };
}
const fallo = (f: () => unknown, status: number, code: string) =>
  assert.throws(f, (e: unknown) => e instanceof PairError && e.status === status && e.code === code);

test("emparejar: el servidor prueba la clave, el dispositivo queda ligado a su clave y la ventana no se reutiliza", () => {
  const { dir, code, p } = ventana();
  const cn = nonce();
  const ch = p.challenge(reto(cn));
  assert.equal(ch.proof, serverProof(code, cn, ch.server_nonce, ch.spki_sha256));
  const k = newKey();
  const jkt = thumbprint(jwkDe(k));
  const r = p.complete({ server_nonce: ch.server_nonce, device_name: "móvil", device_jwk: jwkDe(k), proof: clientProof(code, cn, ch.server_nonce, jkt) });
  assert.match(r.token, /^[A-Za-z0-9_-]{43}$/);
  const d = listDevices(dir).find((x) => x.id === r.device_id);
  assert.equal(d?.jkt, jkt, "la clave queda ligada al emparejar, no en el primer uso");
  assert.equal(existsSync(join(dir, PAIR_FILE)), false, "el código no se queda en disco");
  fallo(() => p.challenge(reto(nonce())), 410, "PAIR_EXPIRED");
});

test("clave errónea 3 veces: 401 cada vez y después la ventana queda bloqueada (423), también con el código bueno", () => {
  const { dir, code, p } = ventana();
  const k = newKey();
  const jkt = thumbprint(jwkDe(k));
  const cn = nonce();
  const ch = p.challenge(reto(cn));
  for (let i = 0; i < 3; i++) {
    fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(k), proof: clientProof(V.otra_clave, cn, ch.server_nonce, jkt) }), 401, "PAIR_BAD_PROOF");
  }
  assert.equal(claveEn(dir), "", "bloqueada, la clave se borra");
  fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(k), proof: clientProof(code, cn, ch.server_nonce, jkt) }), 423, "PAIR_LOCKED");
  fallo(() => p.challenge(reto(nonce())), 423, "PAIR_LOCKED");
  assert.equal(listDevices(dir).length, 0);
});

test("dos fallos no bloquean: el tercer intento con el código bueno empareja (borde del límite)", () => {
  const { dir, code, p } = ventana();
  const k = newKey();
  const jkt = thumbprint(jwkDe(k));
  const cn = nonce();
  const ch = p.challenge(reto(cn));
  for (let i = 0; i < 2; i++) fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(k), proof: "x" }), 401, "PAIR_BAD_PROOF");
  p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(k), proof: clientProof(code, cn, ch.server_nonce, jkt) });
  assert.equal(listDevices(dir).length, 1);
});

test("una prueba válida para otra clave no empareja la clave que se presenta", () => {
  const { dir, code, p } = ventana();
  const cn = nonce();
  const ch = p.challenge(reto(cn));
  const otra = thumbprint(jwkDe(newKey()));
  fallo(() => p.complete({ server_nonce: ch.server_nonce, device_name: "m", device_jwk: jwkDe(newKey()), proof: clientProof(code, cn, ch.server_nonce, otra) }), 401, "PAIR_BAD_PROOF");
  assert.equal(listDevices(dir).length, 0);
});

test("ventana caducada: 410 (justo antes de los 10 minutos aún vale) y sin ventana abierta: 410", () => {
  const a = ventana();
  a.avanzar(10 * 60_000 - 1);
  a.p.challenge(reto(nonce()));
  a.avanzar(1);
  fallo(() => a.p.challenge(reto(nonce())), 410, "PAIR_EXPIRED");
  assert.equal(existsSync(join(a.dir, PAIR_FILE)), false, "caducada, el código se borra");
  const vacio = makePairing({ dataDir: mkdtempSync(join(tmpdir(), "soul-pair-")), certPem: TLS.cert });
  fallo(() => vacio.challenge(reto(nonce())), 410, "PAIR_EXPIRED");
});

test("cliente soul-pair-v1: 426 PAIR_VERSION sin gastar retos ni intentos; una ventana v1 en disco se trata como caducada", () => {
  const { dir, p } = ventana();
  fallo(() => p.challenge({ client_nonce: nonce() }), 426, "PAIR_VERSION");
  fallo(() => p.challenge({ version: "soul-pair-v1", client_nonce: nonce() }), 426, "PAIR_VERSION");
  const en = JSON.parse(readFileSync(join(dir, PAIR_FILE), "utf8"));
  assert.equal(en.challenges.length, 0);
  assert.equal(en.failures, 0);
  // Control: la misma ventana atiende un reto v2.
  p.challenge(reto(nonce()));
  // Ventana de un Soul anterior (v1, con código): no se usa y se borra.
  const viejo = mkdtempSync(join(tmpdir(), "soul-pair-v1-"));
  writeFileSync(join(viejo, PAIR_FILE), JSON.stringify({ v: 1, operator_ref: "op-yo", code: "7K2MD9QX4F", opened_at: 0, expires_at: 4e12, days: 0, failures: 0, challenges: [] }));
  fallo(() => makePairing({ dataDir: viejo, certPem: TLS.cert }).challenge(reto(nonce())), 410, "PAIR_EXPIRED");
  assert.equal(existsSync(join(viejo, PAIR_FILE)), false);
});

test("la ventana guarda la clave en claro solo en pairing.json con permisos 0600", () => {
  const { dir, code } = ventana();
  assert.equal(claveEn(dir), code);
  if (process.platform !== "win32") assert.equal(statSync(join(dir, PAIR_FILE)).mode & 0o777, 0o600);
});

test("más de 10 retos en una ventana: 429 PAIR_RATE", () => {
  const { p } = ventana();
  for (let i = 0; i < 10; i++) p.challenge(reto(nonce()));
  fallo(() => p.challenge(reto(nonce())), 429, "PAIR_RATE");
});

test("entradas mal formadas: 400 y no cuentan como intento (clave privada, nonce corto, campos de más)", () => {
  const { dir, p } = ventana();
  fallo(() => p.challenge(reto("corto")), 400, "INVALID_INPUT");
  fallo(() => p.challenge({ ...reto(nonce()), extra: 1 }), 400, "INVALID_INPUT");
  const ch = p.challenge(reto(nonce()));
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

test("punta a punta: soul pair muestra IP, puerto, clave y huella; la app empareja por TLS y usa DPoP; reusar el jti se rechaza", async () => {
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
    // Un cliente v1 (sin `version`) recibe 426 con un mensaje que dice qué hacer.
    const v1 = await post(port, "/v1/pair/challenge", { client_nonce: nonce() });
    assert.equal(v1.status, 426);
    assert.deepEqual(validar(OPENAPI, esquema("Error"), v1.json), []);
    assert.equal(v1.json.code, "PAIR_VERSION");
    assert.match(v1.json.message, /soul-pair-v1 retirado: actualiza la app/);
    // Sin ventana abierta, el reto da 410 con el sobre de error del contrato.
    const sin = await post(port, "/v1/pair/challenge", reto(nonce()));
    assert.equal(sin.status, 410);
    assert.deepEqual(validar(OPENAPI, esquema("Error"), sin.json), []);
    assert.equal(sin.json.code, "PAIR_EXPIRED");

    const pout: string[] = [];
    assert.equal(await runCli(["pair", "--json"], deps(dir, pout, [])), 0);
    const j = JSON.parse(pout.join("\n"));
    assert.equal(j.codigo, undefined, "ya no hay código v1");
    assert.equal(parseToken(j.clave), j.clave, "la clave cumple formato y checksum");
    assert.deepEqual(j.direcciones, ["127.0.0.1"]);
    assert.equal(j.puerto, port);
    assert.match(j.huella_corta, /^[0-9a-f]{4}( [0-9a-f]{4}){3}$/);
    assert.equal(j.qr, `soul://pair?v=2&h=127.0.0.1&p=${port}&k=${j.clave}&f=${j.huella_corta.replace(/ /g, "")}`);
    const code = j.clave as string;

    const cn = nonce();
    const ch = await post(port, "/v1/pair/challenge", reto(cn));
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
    assert.equal((await post(port, "/v1/pair/challenge", reto(nonce()))).status, 410);
  } finally { ac.abort(); await done; }
});

test("intermediario con otro certificado: la app lo detecta (huella distinta, y sin la clave no puede rehacer la prueba)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "soul-pair-mitm-"));
  const { token: code } = openPairingWindow(dir, "op-yo", Date.now());
  const real = makePairing({ dataDir: dir, certPem: TLS.cert });
  const OTRO = makeSelfSigned(["127.0.0.1"], new Date());
  // El intermediario termina TLS con su certificado y reenvía el reto al servidor real.
  const mitm = createTls({ cert: OTRO.cert, key: OTRO.key }, (s) => s.end());
  await new Promise<void>((r) => mitm.listen(0, "127.0.0.1", () => r()));
  const port = (mitm.address() as { port: number }).port;
  try {
    const visto = await spkiVisto(port);
    const cn = nonce();
    const ch = real.challenge(reto(cn));
    // a) Reenvía la respuesta tal cual: la huella no casa con la que ve la app.
    assert.notEqual(ch.spki_sha256, visto);
    assert.equal(ch.proof, serverProof(code, cn, ch.server_nonce, ch.spki_sha256));
    // b) Pone su propia huella: la prueba ya no verifica con el código que teclea la persona.
    assert.notEqual(ch.proof, serverProof(code, cn, ch.server_nonce, visto));
  } finally { await new Promise<void>((r) => mitm.close(() => r())); }
});
