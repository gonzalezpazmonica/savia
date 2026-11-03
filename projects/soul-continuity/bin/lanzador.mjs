// Elección del Node que ejecuta Soul (JavaScript puro: corre en cualquier Node, también en uno sin
// TypeScript). El Node de algunas distribuciones (Ubuntu 22.22.1, por ejemplo) se compila sin la
// eliminación de tipos y da ERR_NO_TYPESCRIPT: entonces se busca un Node oficial del usuario
// (~/.savia/node, nvm, fnm) y, si no hay ninguno, se explica cómo instalarlo sin sudo.
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const SONDA = fileURLToPath(new URL("./sonda.ts", import.meta.url));
export const NODE_FLAGS = ["--experimental-strip-types", "--no-warnings"];

const isFile = (p) => { try { return existsSync(p) && statSync(p).isFile(); } catch { return false; } };
const ver = (s) => (/^v?(\d+)\.(\d+)\.(\d+)$/.exec(s) ?? []).slice(1).map(Number);
const atLeast = (v, [a, b]) => v.length === 3 && (v[0] > a || (v[0] === a && v[1] >= b));
const cmp = (x, y) => { for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return y[i] - x[i]; return 0; };

/** Nodes de un gestor de versiones (`<dir>/<vX.Y.Z>/<sub>/node`), de la más alta a la más baja, ≥ 22.6. */
function managed(dir, sub, exe) {
  let names = [];
  try { names = readdirSync(dir); } catch { return []; }
  return names.map((n) => ({ n, v: ver(n) })).filter((x) => atLeast(x.v, [22, 6])).sort((a, b) => cmp(a.v, b.v))
    .map((x) => join(dir, x.n, sub, exe)).filter(isFile);
}

/** Candidatos en orden: el Node actual, el oficial de Savia (`install.sh`), nvm y fnm. */
export function nodeCandidates({ env, home, platform, execPath }) {
  const exe = platform === "win32" ? "node.exe" : "node";
  const bin = platform === "win32" ? "" : "bin";
  const fnmDirs = env.FNM_DIR ? [env.FNM_DIR] : [join(home, ".local", "share", "fnm"), join(home, ".fnm"), join(home, "Library", "Application Support", "fnm")];
  const list = [
    execPath,
    join(home, ".savia", "node", bin, exe),
    ...managed(join(env.NVM_DIR || join(home, ".nvm"), "versions", "node"), bin, exe),
    ...fnmDirs.flatMap((d) => managed(join(d, "node-versions"), join("installation", bin), exe)),
  ];
  return [...new Set(list)].filter((p, i) => i === 0 || isFile(p));
}

/** ¿Ejecuta este Node el TypeScript de Soul? Lo prueba de verdad con la sonda. */
export function probeNode(node) {
  const r = spawnSync(node, [...NODE_FLAGS, SONDA], { encoding: "utf8", timeout: 15000, windowsHide: true });
  const m = /^soul-ts-ok (v\d+\.\d+\.\d+)$/.exec(r.stdout ?? "");
  if (r.status === 0 && m) return { ok: true, version: m[1] };
  const v = spawnSync(node, ["--version"], { encoding: "utf8", timeout: 15000, windowsHide: true });
  return { ok: false, version: v.status === 0 ? String(v.stdout).trim() : null, noTs: /ERR_NO_TYPESCRIPT/.test(r.stderr ?? "") };
}

/** El primer candidato que sirve; los que no, con su motivo. */
export function chooseNode(candidates, probe = probeNode) {
  const failures = [];
  for (const node of candidates) {
    const r = probe(node);
    if (r.ok) return { node, version: r.version, failures };
    failures.push({ node, ...r });
  }
  return { node: null, failures };
}

export function noNodeMessage(failures, pkgDir, platform) {
  const lines = failures.map((f) => `  - ${f.node}${f.version ? ` (${f.version})` : ""}: ${f.noTs ? "no ejecuta TypeScript (ERR_NO_TYPESCRIPT)" : f.version ? "no ejecuta el TypeScript de Soul (hace falta Node.js ≥ 22.6 oficial)" : "no arranca"}`);
  const fix = platform === "win32"
    ? ["Solución: instala Node.js LTS oficial desde https://nodejs.org (o con fnm) y abre una terminal nueva."]
    : [
      `Solución, sin sudo: bash ${join(pkgDir, "install.sh")}`,
      "  instala el Node.js LTS oficial en ~/.savia/node y deja la orden «soul» en ~/.local/bin.",
      "O instala Node.js LTS oficial con nvm o fnm, o desde https://nodejs.org, y vuelve a probar.",
    ];
  return [
    "soul: no encuentro un Node.js que ejecute Soul. El Node de algunas distribuciones (Ubuntu, Debian) viene sin soporte de TypeScript.",
    ...lines,
    ...fix,
  ].join("\n");
}
