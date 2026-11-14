/**
 * `install.sh`: Node.js LTS oficial en el espacio del usuario, sin sudo, y la orden `soul` en
 * ~/.local/bin. Sin red: un espejo falso por file:// con un tarball que envuelve el Node de los tests.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, symlinkSync, writeFileSync } from "node:fs";
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

function run(args: string[], env: Record<string, string>, script = SCRIPT) {
  const home = env.HOME;
  return spawnSync("bash", [script, ...args], { encoding: "utf8", env: { PATH: process.env.PATH ?? "", HOME: home, SOUL_NODE_MIRROR_ALLOW_FILE: "1", ...env } });
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

test("install.sh (negativo): un espejo que no es https:// se rechaza antes de descargar nada", { skip: SKIP }, () => {
  for (const m of ["http://nodejs.example.test/dist", "ftp://nodejs.example.test/dist"]) {
    const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
    const r = run(["--download"], { HOME: home, SOUL_NODE_MIRROR: m });
    assert.equal(r.status, 1, m);
    assert.match(r.stderr, /tiene que empezar por https:\/\//, m);
    assert.doesNotMatch(r.stdout, /Descargando/, m);
    assert.ok(!existsSync(join(home, ".savia/node")), m);
  }
});

test("install.sh (negativo): file:// sin la variable de pruebas se rechaza", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const r = run(["--download"], { HOME: home, SOUL_NODE_MIRROR: `file://${mirror(realNode)}`, SOUL_NODE_MIRROR_ALLOW_FILE: "" });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /solo se admite en pruebas/);
  assert.ok(!existsSync(join(home, ".savia/node")));
});

test("install.sh: curl nunca sigue una redirección a HTTP", { skip: SKIP }, () => {
  assert.match(readFileSync(SCRIPT, "utf8"), /curl -fsSL --proto "=\$PROTO" --proto-redir =https /);
});

test("install.sh --download dos veces: deja una sola copia anterior, no una por ejecución", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const m = mirror(realNode);
  for (let i = 0; i < 3; i++) {
    const r = run(["--download"], { HOME: home, SOUL_NODE_MIRROR: `file://${m}` });
    assert.equal(r.status, 0, r.stdout + r.stderr);
  }
  assert.deepEqual(readdirSync(join(home, ".savia")).sort(), ["node", "node.anterior"]);
});

test("install.sh: una ruta con comillas, $ y $(…) queda escapada en la orden soul y no ejecuta nada", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const base = mkdtempSync(join(tmpdir(), "soul-raro-"));
  const raro = join(base, `a'b "c" $(touch PWNED) \`touch PWNED2\``);
  mkdirSync(raro);
  symlinkSync(dirname(SCRIPT), join(raro, "pkg"));
  const r = run([], { HOME: home, PATH: `${dirname(process.execPath)}:${process.env.PATH}` }, join(raro, "pkg", "install.sh"));
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const wrapper = join(home, ".local/bin/soul");
  const h = spawnSync(wrapper, ["help"], { encoding: "utf8", cwd: base, env: { PATH: process.env.PATH ?? "", HOME: home } });
  assert.equal(h.status, 0, h.stderr);
  assert.match(h.stdout, /Órdenes de soul/);
  assert.ok(!existsSync(join(base, "PWNED")) && !existsSync(join(base, "PWNED2")), "la ruta no se ejecutó como código");
});

// --- PATH: oferta de añadir ~/.local/bin al fichero de arranque del shell (SE-490 AC-1) ---
const PTY = `
import os, pty, sys, select
ans, script = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", script])
out = b""
sent = False
while True:
    r, _, _ = select.select([fd], [], [], 20)
    if not r: break
    try: d = os.read(fd, 4096)
    except OSError: break
    if not d: break
    out += d
    if not sent and b"[s/N]" in out:
        os.write(fd, ans.encode()); sent = True
_, st = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf8", "replace"))
sys.exit(os.waitstatus_to_exitcode(st))
`;
const PTY_SKIP = SKIP || (spawnSync("python3", ["-c", "import pty"]).status === 0 ? false : "falta python3");
const LINE = 'export PATH="$HOME/.local/bin:$PATH"';

/** Ejecuta install.sh en una terminal simulada (pty) y contesta `ans` a la pregunta. */
function runTty(ans: string, home: string, shell: string, script = SCRIPT) {
  const env = { PATH: `${dirname(process.execPath)}:${process.env.PATH}`, HOME: home, SHELL: shell, SOUL_NODE_MIRROR_ALLOW_FILE: "1" };
  return spawnSync("python3", ["-I", "-c", PTY, ans, script], { encoding: "utf8", env });
}
const count = (f: string) => readFileSync(f, "utf8").split("\n").filter((l) => l === LINE).length;

test("install.sh PATH: con terminal y «s» añade la línea a ~/.zshrc una sola vez, también si se ejecuta dos veces", { skip: PTY_SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  writeFileSync(join(home, ".zshrc"), "alias x=y"); // sin salto de línea final
  const a = runTty("s\n", home, "/bin/zsh");
  assert.equal(a.status, 0, a.stdout + a.stderr);
  assert.equal(count(join(home, ".zshrc")), 1);
  assert.match(readFileSync(join(home, ".zshrc"), "utf8"), /^alias x=y\n/);
  const b = runTty("s\n", home, "/bin/zsh");
  assert.equal(b.status, 0, b.stdout);
  assert.equal(count(join(home, ".zshrc")), 1, "idempotente");
  assert.ok(!existsSync(join(home, ".bashrc")), "no toca ~/.bashrc");
});

test("install.sh PATH: con bash escribe en ~/.bashrc y no en ~/.zshrc", { skip: PTY_SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const r = runTty("s\n", home, "/bin/bash");
  assert.equal(r.status, 0, r.stdout);
  assert.equal(count(join(home, ".bashrc")), 1);
  assert.ok(!existsSync(join(home, ".zshrc")));
});

for (const ans of ["\n", "n\n", "no\n", "x\n"]) {
  test(`install.sh PATH (negativo): la respuesta ${JSON.stringify(ans)} no escribe nada`, { skip: PTY_SKIP }, () => {
    const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
    const r = runTty(ans, home, "/bin/zsh");
    assert.equal(r.status, 0, r.stdout);
    assert.ok(!existsSync(join(home, ".zshrc")) && !existsSync(join(home, ".bashrc")));
    assert.match(r.stdout, /Aviso: .*no está en tu PATH/);
  });
}

test("install.sh PATH (negativo): sin terminal no escribe nada y solo avisa", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const r = run([], { HOME: home, SHELL: "/bin/zsh", PATH: `${dirname(process.execPath)}:${process.env.PATH}` });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.ok(!existsSync(join(home, ".zshrc")) && !existsSync(join(home, ".bashrc")));
  assert.match(r.stdout, /Aviso: .*no está en tu PATH/);
});

test("install.sh PATH (negativo): con un shell desconocido solo avisa, aunque haya terminal", { skip: PTY_SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const r = runTty("s\n", home, "/usr/bin/fish");
  assert.equal(r.status, 0, r.stdout);
  assert.deepEqual(readdirSync(home).filter((f) => f.endsWith("rc")), []);
  assert.match(r.stdout, /Aviso: .*no está en tu PATH/);
});

test("install.sh PATH: si ~/.local/bin ya está en el PATH no pregunta", { skip: SKIP }, () => {
  const home = mkdtempSync(join(tmpdir(), "soul-ish-"));
  const r = run([], { HOME: home, SHELL: "/bin/zsh", PATH: `${join(home, ".local/bin")}:${dirname(process.execPath)}:${process.env.PATH}` });
  assert.doesNotMatch(r.stdout, /Aviso|\[s\/N\]/);
  assert.ok(!existsSync(join(home, ".zshrc")));
});

test("instalar.md §1: ofrece el camino sin git (Download ZIP) y explica la pregunta del PATH", () => {
  const doc = readFileSync(fileURLToPath(new URL("../docs/instalar.md", import.meta.url)), "utf8");
  assert.match(doc, /Download ZIP/);
  assert.match(doc, /~\/\.zshrc/);
  assert.match(doc, /\[s\/N\]/);
});
