#!/usr/bin/env node
// Lanzador de `soul` sobre el runtime oficial de Node.js (≥ 22.6): ejecuta el TypeScript
// del paquete con la eliminación de tipos de Node. Sin compilar, sin ejecutables propios.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const entry = fileURLToPath(new URL("../src/cli/soul.ts", import.meta.url));
const r = spawnSync(process.execPath, ["--experimental-strip-types", "--no-warnings", entry, ...process.argv.slice(2)], { stdio: "inherit" });
process.exitCode = r.status ?? 1;
