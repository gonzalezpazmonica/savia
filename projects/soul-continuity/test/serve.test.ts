import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request } from "node:https";
import { createServer } from "node:net";
import { emptyConfig, saveConfig } from "../src/core/config.ts";
import { serveFromCli } from "../src/api/serve.ts";
import { pairDevice, revokeDevice } from "../src/api/devices.ts";
import { stop } from "../src/core/failsafe.ts";
import type { CliDeps } from "../src/cli/cli.ts";

function deps(dir: string, out: string[], err: string[]): CliDeps {
  return {
    dataDir: dir, env: {}, now: () => new Date().toISOString(), out: (s) => out.push(s), err: (s) => err.push(s), adapters: {},
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } },
    credentials: { forget: async () => [], forgetAll: async () => [] }, platform: "linux", home: dir,
    run: async () => ({ code: 0, stdout: "", stderr: "" }), node: "n", entry: "e",
  };
}

async function freePort(): Promise<number> {
  const s = createServer();
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", () => r()));
  const p = (s.address() as { port: number }).port;
  await new Promise<void>((r) => s.close(() => r()));
  return p;
}

function setup(listen: string[], port = 8787) {
  const dir = mkdtempSync(join(tmpdir(), "soul-sv-"));
  const cfg = emptyConfig("i");
  cfg.active_profile = "yo";
  cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [] };
  cfg.api = { listen, port };
  saveConfig(dir, cfg);
  return dir;
}

const get = (port: number, ca: string, token: string) => new Promise<number>((res, rej) => {
  const q = request({ host: "127.0.0.1", port, path: "/api/v1/soul/estado", ca, headers: { Authorization: `DPoP ${token}`, DPoP: "p" } }, (r) => { r.resume(); r.on("end", () => res(r.statusCode ?? 0)); });
  q.on("error", rej);
  q.end();
});

test("serve sin direcciones configuradas no arranca: error claro y código 1", async () => {
  const dir = setup([]);
  const out: string[] = [];
  const err: string[] = [];
  assert.equal(await serveFromCli(deps(dir, out, err)), 1);
  assert.match(err.join("\n"), /ninguna dirección de escucha/);
});

test("serve: TLS propio, dispositivo emparejado entra, revocado recibe 401, STOP da 503", async () => {
  const dir = setup(["127.0.0.1"], await freePort());
  const out: string[] = [];
  const err: string[] = [];
  const p = pairDevice(dir, "op-yo", "movil", new Date().toISOString());
  const ac = new AbortController();
  const done = serveFromCli(deps(dir, out, err), { signal: ac.signal, onListening: () => undefined });
  for (let i = 0; i < 50 && !out.some((l) => l.includes("Escuchando")); i++) await new Promise((r) => setTimeout(r, 50));
  const port = Number(/:(\d+)/.exec(out.find((l) => l.includes("Escuchando")) ?? "")?.[1]);
  const ca = readFileSync(join(dir, "tls", "cert.pem"), "utf8");
  try {
    assert.equal(await get(port, ca, p.token), 200);
    assert.equal(await get(port, ca, "otro-token"), 401);
    revokeDevice(dir, p.id, new Date().toISOString());
    assert.equal(await get(port, ca, p.token), 401);
    const q = pairDevice(dir, "op-yo", "tableta", new Date().toISOString());
    stop(dir, "prueba", new Date().toISOString());
    assert.equal(await get(port, ca, q.token), 503);
  } finally {
    ac.abort();
    assert.equal(await done, 0);
  }
  assert.ok(out.some((l) => /sha256\//.test(l)), "muestra la huella para fijar el certificado");
});
