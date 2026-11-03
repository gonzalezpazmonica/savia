/**
 * Lanzador `bin/soul.mjs`: con un Node que no ejecuta TypeScript (el de Ubuntu da ERR_NO_TYPESCRIPT)
 * busca un Node oficial (~/.savia/node, nvm, fnm) o explica la solución. Sondas falsas e inyectadas.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { chooseNode, nodeCandidates, noNodeMessage, probeNode } from "../bin/lanzador.mjs";

const BIN = fileURLToPath(new URL("../bin/soul.mjs", import.meta.url));

function fakeHome(dirs: string[]): string {
  const h = mkdtempSync(join(tmpdir(), "soul-lz-"));
  for (const d of dirs) {
    mkdirSync(join(h, d), { recursive: true });
    writeFileSync(join(h, d, "node"), "#!/bin/sh\n");
    chmodSync(join(h, d, "node"), 0o755);
  }
  return h;
}

test("candidatos: el Node actual, ~/.savia/node, nvm y fnm (de la versión más alta a la más baja)", () => {
  const h = fakeHome([".savia/node/bin", ".nvm/versions/node/v22.4.0/bin", ".nvm/versions/node/v24.11.1/bin", ".local/share/fnm/node-versions/v22.12.0/installation/bin"]);
  const c = nodeCandidates({ env: {}, home: h, platform: "linux", execPath: "/usr/bin/node" });
  assert.deepEqual(c, [
    "/usr/bin/node",
    join(h, ".savia/node/bin/node"),
    join(h, ".nvm/versions/node/v24.11.1/bin/node"),
    join(h, ".local/share/fnm/node-versions/v22.12.0/installation/bin/node"),
  ], "la v22.4.0 de nvm queda fuera: no llega a 22.6");
});

test("candidatos (negativo): sin Node oficial instalado solo queda el actual; NVM_DIR y FNM_DIR mandan", () => {
  const vacio = fakeHome([]);
  assert.deepEqual(nodeCandidates({ env: {}, home: vacio, platform: "linux", execPath: "/usr/bin/node" }), ["/usr/bin/node"]);
  const otro = fakeHome(["nvm-propio/versions/node/v24.1.0/bin"]);
  assert.deepEqual(nodeCandidates({ env: { NVM_DIR: join(otro, "nvm-propio") }, home: vacio, platform: "linux", execPath: "/usr/bin/node" }),
    ["/usr/bin/node", join(otro, "nvm-propio/versions/node/v24.1.0/bin/node")]);
});

test("chooseNode: con el Node de Ubuntu sin TypeScript elige el oficial de ~/.savia/node", () => {
  const probes: string[] = [];
  const r = chooseNode(["/usr/bin/node", "/h/.savia/node/bin/node"], (n: string) => {
    probes.push(n);
    return n === "/usr/bin/node" ? { ok: false, version: "v22.22.1", noTs: true } : { ok: true, version: "v24.11.1" };
  });
  assert.equal(r.node, "/h/.savia/node/bin/node");
  assert.deepEqual(probes, ["/usr/bin/node", "/h/.savia/node/bin/node"]);
});

test("chooseNode: si el actual sirve no prueba los demás", () => {
  const probes: string[] = [];
  const r = chooseNode(["/a", "/b"], (n: string) => { probes.push(n); return { ok: true, version: "v24.0.0" }; });
  assert.equal(r.node, "/a");
  assert.deepEqual(probes, ["/a"]);
});

test("chooseNode (negativo): ninguno sirve => sin Node y mensaje con ERR_NO_TYPESCRIPT y la solución sin sudo", () => {
  const r = chooseNode(["/usr/bin/node"], () => ({ ok: false, version: "v22.22.1", noTs: true }));
  assert.equal(r.node, null);
  const m = noNodeMessage(r.failures, "/pkg", "linux");
  assert.match(m, /v22\.22\.1/);
  assert.match(m, /ERR_NO_TYPESCRIPT/);
  assert.match(m, /bash \/pkg\/install\.sh/);
  assert.match(m, /sin sudo/);
  const w = noNodeMessage(r.failures, "C:\\pkg", "win32");
  assert.doesNotMatch(w, /install\.sh/, "en Windows no hay install.sh");
  assert.match(w, /nodejs\.org/);
});

test("probeNode: el Node real que corre los tests ejecuta TypeScript", () => {
  const r = probeNode(process.execPath);
  assert.equal(r.ok, true);
  assert.equal(r.version, process.version);
});

test("probeNode (negativo): un Node que responde ERR_NO_TYPESCRIPT se detecta como tal", { skip: process.platform === "win32" }, () => {
  const d = mkdtempSync(join(tmpdir(), "soul-lz-"));
  const f = join(d, "node");
  writeFileSync(f, "#!/bin/sh\n[ \"$1\" = --version ] && { echo v22.22.1; exit 0; }\necho 'Error [ERR_NO_TYPESCRIPT]: Node.js is not compiled with TypeScript support' >&2\nexit 1\n");
  chmodSync(f, 0o755);
  const r = probeNode(f);
  assert.equal(r.ok, false);
  assert.equal(r.noTs, true);
  assert.equal(r.version, "v22.22.1");
  assert.equal(probeNode(join(d, "no-existe")).ok, false, "un Node que no existe tampoco sirve");
});

test("bin/soul.mjs de punta a punta: con un Node que sí sirve, «help» funciona", () => {
  const h = fakeHome([]);
  const r = spawnSync(process.execPath, [BIN, "help"], { encoding: "utf8", env: { PATH: process.env.PATH ?? "", HOME: h } });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Órdenes de soul/);
});
