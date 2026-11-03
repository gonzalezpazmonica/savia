#!/usr/bin/env node
// Lanzador de `soul` sobre el runtime oficial de Node.js (≥ 22.6): ejecuta el TypeScript
// del paquete con la eliminación de tipos de Node. Sin compilar, sin ejecutables propios.
// Si este Node no ejecuta TypeScript (ERR_NO_TYPESCRIPT), usa un Node oficial del usuario
// o explica cómo instalarlo sin sudo (lanzador.mjs).
import { homedir } from "node:os";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { launch } from "./lanzador.mjs";

process.exitCode = launch({
  execPath: process.execPath, typescript: process.features?.typescript, version: process.version,
  env: process.env, home: homedir(), platform: process.platform,
  pkg: dirname(dirname(fileURLToPath(import.meta.url))),
  entry: fileURLToPath(new URL("../src/cli/soul.ts", import.meta.url)),
  argv: process.argv.slice(2), stderr: (s) => process.stderr.write(s),
});
