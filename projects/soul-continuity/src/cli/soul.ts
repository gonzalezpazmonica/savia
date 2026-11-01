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
import { type CliDeps, runCli } from "./cli.ts";

const dir = dataDir();
let store: SystemCredentialStore | null = null;
// Perezoso: `status` no toca el almacén del sistema (responde en frío y sin él).
const creds = () => (store ??= new SystemCredentialStore(backendFor(process.platform, hostRun), dir));
// Tokens de los adaptadores de API de un operador, sobre el almacén único (H-2).
const tokens = (ref: string) => new ApiTokenStore({ backend: creds().keyed(), operatorRef: ref });

const deps: CliDeps = {
  dataDir: dir,
  env: process.env,
  now: () => new Date().toISOString(),
  out: (s) => process.stdout.write(s + "\n"),
  err: (s) => process.stderr.write(s + "\n"),
  adapters: {},
  adaptersFor: (cfg) => productionAdapters({ connectors: cfg.connectors, dataDir: dir }),
  sourceEnv: { transport: apiTransport(undefined), credentials: { acquire: () => Promise.reject(new Error("sin operador")) } },
  sourceEnvFor: (ref, cfg) => ({ transport: apiTransport(cfg.connectors), credentials: tokens(ref) }),
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
