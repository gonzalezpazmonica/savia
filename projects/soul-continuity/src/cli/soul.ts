/**
 * Punto de entrada real de `soul`: compone la CLI con el sistema (directorio de datos,
 * almacén único de credenciales, adaptadores activados por el operador, transporte de solo
 * lectura, arranque y API local).
 * Lo lanza `bin/soul.mjs` sobre el runtime oficial de Node.js; no hay ejecutables propios.
 */

import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import { dataDir } from "../core/store.ts";
import { apiTransport, productionAdapters, revokeSource } from "../core/connectors.ts";
import { SystemCredentialStore, backendFor, hostRun } from "../credentials/store.ts";
import { SystemCredentialStore as ApiTokenStore } from "../adapters/credential-store.ts";
import type { ConnectorsConfig } from "../core/connectors.ts";
import { type CliDeps, runCli } from "./cli.ts";
import { oauthRefresher } from "./login.ts";

const dir = dataDir();
let store: SystemCredentialStore | null = null;
// Perezoso: `status` no toca el almacén del sistema (responde en frío y sin él).
const creds = () => (store ??= new SystemCredentialStore(backendFor(process.platform, hostRun), dir));
// Tokens de los adaptadores de API de un operador, sobre el almacén único (H-2); se renuevan con la
// aplicación OAuth propia de la configuración, si la hay.
const tokens = (ref: string, c?: ConnectorsConfig) => new ApiTokenStore({ backend: creds().keyed(), operatorRef: ref, refresh: oauthRefresher(c) });

/** Secreto por stdin, sin eco si es un terminal. Nunca por argv ni por variables de entorno. */
async function readSecret(): Promise<string> {
  const tty = process.stdin.isTTY;
  if (tty) { process.stderr.write("Pega el token y pulsa Intro: "); process.stdin.setRawMode?.(true); }
  let s = "";
  try {
    for await (const c of process.stdin) {
      const t = String(c);
      if (tty && /[\r\n\u0004]/.test(t)) { s += t.split(/[\r\n\u0004]/)[0]; break; }
      if (tty && t === "\u0003") throw new Error("cancelado");
      s += t;
    }
  } finally {
    if (tty) { process.stdin.setRawMode?.(false); process.stderr.write("\n"); process.stdin.pause(); }
  }
  return s;
}

const deps: CliDeps = {
  dataDir: dir,
  env: process.env,
  now: () => new Date().toISOString(),
  out: (s) => process.stdout.write(s + "\n"),
  err: (s) => process.stderr.write(s + "\n"),
  adapters: {},
  adaptersFor: (cfg) => productionAdapters({ connectors: cfg.connectors, dataDir: dir }),
  sourceEnv: { transport: apiTransport(undefined), credentials: { acquire: () => Promise.reject(new Error("sin operador")) } },
  sourceEnvFor: (ref, cfg) => ({ transport: apiTransport(cfg.connectors), credentials: tokens(ref, cfg.connectors) }),
  tokenStore: (ref, cfg) => tokens(ref, cfg.connectors),
  readSecret,
  credentials: {
    revoke: (adapter, ref) => revokeSource({ adapter, operatorRef: ref, dataDir: dir, tokens: tokens(ref) }),
    forgetAll: () => creds().forgetAll(),
  },
  platform: process.platform,
  home: homedir(),
  run: hostRun,
  node: process.execPath,
  entry: fileURLToPath(import.meta.url),
  serve: async (d) => (await import("../api/serve.ts")).serveFromCli(d),
};

process.exitCode = await runCli(process.argv.slice(2), deps);
