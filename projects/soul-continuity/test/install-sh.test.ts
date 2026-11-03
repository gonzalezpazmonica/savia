/**
 * `install.sh`: Node.js LTS oficial en el espacio del usuario, sin sudo, y la orden `soul` en
 * ~/.local/bin. Sin red: un espejo falso por file:// con un tarball que envuelve el Node de los tests.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(new URL("../install.sh", import.meta.url));
const SKIP = process.platform === "win32" ? "install.sh es para Linux y macOS" : false;
const OS = process.platform === "darwin" ? "darwin" : "linux";
const ARCH = process.arch === "arm64" ? "arm64" : "x64";
const VER = "v24.99.0";

/** Espejo con `latest-v24.x/SHASUMS256.txt` y un tarball cuyo bin/node es `nodeScript`. */
function mirror(nodeScript: string, opts: { badSum?: boolean } = {}): string {
  const m = mkdtempSync(join(tmpdir(), "soul-mirror-"));
  const name = `node-${VER}-${OS}-${ARCH}`;
  const stage = join(m, "stage", name, "bin");
  mkdirSync(stage, { recursive: true });
  writeFileSync(join(stage, "node"), nodeScript);
  chmodSync(join(stage, "node"), 0o755);
  const line = join(m, "latest-v24.x");
  mkdirSync(line);
  const tgz = join(line, `${name}.tar.gz`);
  const t = spawnSync("tar", ["-czf", tgz, "-C", join(m, "stage"), name]);
  assert.equal(t.status, 0, String(t.stderr));
  const sum = opts.badSum ? "0".repeat(64) : createHash("sha256").update(readFileSync(tgz)).digest("hex");
  writeFileSync(join(line, "SHASUMS256.txt"), `${"1".repeat(64)}  node-${VER}-win-x64.zip\n${sum}  ${name}.tar.gz\n`);
  return m;
}

const realNode = `#!/bin/sh\nexec "${process.execPath}" "$@"\n`;
const noTsNode = "#!/bin/sh\n[ \"$1\" = --version ] && { echo v22.22.1; exit 0; }\necho 'Error [ERR_NO_TYPESCRIPT]' >&2\nexit 1\n";

function run(args: string[], env: Record<string, string>) {
  const home = env.HOME;
  return spawnSync("bash", [SCRIPT, ...args], { encoding: "utf8", env: { PATH: process.env.PATH ?? "", HOME: home, ...env } });
}

test("install.sh --download: baja el Node oficial, comprueba su SHA-256, lo deja en ~/.savia/node y crea ~/.local/bin/soul", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const m = mirror(realNode);
  const r = run(["--download"], { HOME: home, SOUL_NODE_MIRROR: `file://${m}` });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.ok(existsSync(join(home, ".savia/node/bin/node")));
  const wrapper = join(home, ".local/bin/soul");
  assert.match(readFileSync(wrapper, "utf8"), /generado por install\.sh/);
  assert.match(r.stdout, /soul setup/);
  // La orden creada funciona de verdad.
  const h = spawnSync(wrapper, ["help"], { encoding: "utf8", env: { PATH: process.env.PATH ?? "", HOME: home } });
  assert.equal(h.status, 0, h.stderr);
  assert.match(h.stdout, /Órdenes de soul/);
});

test("install.sh (negativo): una suma SHA-256 que no cuadra no instala nada", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const r = run(["--download"], { HOME: home, SOUL_NODE_MIRROR: `file://${mirror(realNode, { badSum: true })}` });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /SHA-256/);
  assert.ok(!existsSync(join(home, ".savia/node")), "nada instalado");
  assert.ok(!existsSync(join(home, ".local/bin/soul")));
});

test("install.sh (negativo): si el Node descargado no ejecuta TypeScript, falla y no lo deja", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const r = run(["--download"], { HOME: home, SOUL_NODE_MIRROR: `file://${mirror(noTsNode)}` });
  assert.notEqual(r.status, 0);
  assert.ok(!existsSync(join(home, ".savia/node/bin/node")));
});

test("install.sh: si el Node del PATH ya ejecuta TypeScript no descarga nada", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const vacio = mkdtempSync(join(tmpdir(), "soul-mirror-"));
  const r = run([], { HOME: home, PATH: `${dirname(process.execPath)}:${process.env.PATH}`, SOUL_NODE_MIRROR: `file://${vacio}` });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.ok(!existsSync(join(home, ".savia/node")), "no descarga");
  assert.match(readFileSync(join(home, ".local/bin/soul"), "utf8"), new RegExp(process.execPath.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")));
});

test("install.sh (negativo): no pisa una orden «soul» ajena en ~/.local/bin", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  mkdirSync(join(home, ".local/bin"), { recursive: true });
  writeFileSync(join(home, ".local/bin/soul"), "#!/bin/sh\necho ajena\n");
  const r = run([], { HOME: home, PATH: `${dirname(process.execPath)}:${process.env.PATH}` });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.equal(readFileSync(join(home, ".local/bin/soul"), "utf8"), "#!/bin/sh\necho ajena\n");
  assert.match(r.stderr, /no la toco/);
});

test("install.sh nunca usa sudo", { skip: SKIP }, () => {
  assert.doesNotMatch(readFileSync(SCRIPT, "utf8").split("\n").filter((l) => !l.trim().startsWith("#")).join("\n"), /\bsudo\b/);
});
