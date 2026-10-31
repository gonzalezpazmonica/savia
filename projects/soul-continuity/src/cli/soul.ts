/**
 * Punto de entrada real de `soul`: compone la CLI con el sistema (directorio de datos,
 * almacén de credenciales, transporte de solo lectura, arranque y API local).
 * Lo lanza `bin/soul.mjs` sobre el runtime oficial de Node.js; no hay ejecutables propios.
 */

import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import { dataDir } from "../core/store.ts";
import { fetchTransport, productionAdapters } from "../core/runtime.ts";
import { SystemCredentialStore, backendFor, hostRun } from "../credentials/store.ts";
import { type CliDeps, runCli } from "./cli.ts";

const dir = dataDir();
let store: SystemCredentialStore | null = null;
// Perezoso: `status` no toca el almacén del sistema (responde en frío y sin él).
const creds = () => (store ??= new SystemCredentialStore(backendFor(process.platform, hostRun), dir));

const deps: CliDeps = {
  dataDir: dir,
  env: process.env,
  now: () => new Date().toISOString(),
  out: (s) => process.stdout.write(s + "\n"),
  err: (s) => process.stderr.write(s + "\n"),
  adapters: productionAdapters(),
  sourceEnv: { transport: fetchTransport(), credentials: { acquire: (s, sc) => creds().acquire(s, sc) } },
  credentials: { forget: (s) => creds().forget(s), forgetAll: () => creds().forgetAll() },
  platform: process.platform,
  home: homedir(),
  run: hostRun,
  node: process.execPath,
  entry: fileURLToPath(import.meta.url),
  // serve: se conecta con la API local (src/api).
};

process.exitCode = await runCli(process.argv.slice(2), deps);
