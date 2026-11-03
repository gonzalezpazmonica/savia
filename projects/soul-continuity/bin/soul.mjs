#!/usr/bin/env node
// Lanzador de `soul` sobre el runtime oficial de Node.js (≥ 22.6): ejecuta el TypeScript
// del paquete con la eliminación de tipos de Node. Sin compilar, sin ejecutables propios.
// Si este Node no ejecuta TypeScript (ERR_NO_TYPESCRIPT), usa un Node oficial del usuario
// o explica cómo instalarlo sin sudo (lanzador.mjs).
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { NODE_FLAGS, chooseNode, noNodeMessage, nodeCandidates } from "./lanzador.mjs";

const entry = fileURLToPath(new URL("../src/cli/soul.ts", import.meta.url));
const pkg = dirname(dirname(fileURLToPath(import.meta.url)));
const chosen = chooseNode(nodeCandidates({ env: process.env, home: homedir(), platform: process.platform, execPath: process.execPath }));
if (!chosen.node) {
  process.stderr.write(noNodeMessage(chosen.failures, pkg, process.platform) + "\n");
  process.exitCode = 1;
} else {
  const r = spawnSync(chosen.node, [...NODE_FLAGS, entry, ...process.argv.slice(2)], { stdio: "inherit" });
  process.exitCode = r.status ?? 1;
}
