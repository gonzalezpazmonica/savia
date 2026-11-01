/**
 * El instalador de usuario de `docs/instalar.md`, paso a paso por `bin/soul.mjs`, con un HOME
 * falso y dobles de `secret-tool` y `systemctl` en el PATH: no se toca el llavero ni el arranque
 * reales de la máquina que ejecuta el test.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const BIN = fileURLToPath(new URL("../bin/soul.mjs", import.meta.url));
const TOKEN = "github-pat-canario-instalar-1c9";

function files(dir: string): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((f) => { const p = join(dir, f); return statSync(p).isDirectory() ? files(p) : [p]; });
}

function sandbox() {
  const home = mkdtempSync(join(tmpdir(), "soul-home-falso-"));
  const bin = join(home, ".dobles");
  mkdirSync(bin);
  writeFileSync(join(bin, "secret-tool"), `#!/bin/sh
op="$1"; shift
case "$1" in --label=*) shift;; esac
k=$(printf '%s|' "$@" | sha256sum | cut -c1-32)
d="$HOME/.llavero-falso"; mkdir -p "$d"
case "$op" in
  store) cat > "$d/$k";;
  lookup) [ -f "$d/$k" ] && cat "$d/$k" || exit 1;;
  clear) rm -f "$d/$k";;
esac
`);
  writeFileSync(join(bin, "systemctl"), `#!/bin/sh\necho "$@" >> "$HOME/.systemctl-falso.log"\n`);
  chmodSync(join(bin, "secret-tool"), 0o755);
  chmodSync(join(bin, "systemctl"), 0o755);
  // Entorno mínimo de una persona en su terminal: sin variables de frontends de agente.
  const env = { PATH: `${bin}:${process.env.PATH}`, HOME: home, LANG: "C.UTF-8" };
  const soul = (args: string[], input?: string) => spawnSync(process.execPath, [BIN, ...args], { env, input, encoding: "utf8", timeout: 60_000 });
  return { home, soul, data: join(home, ".local", "share", "savia", "soul-continuity") };
}

test("instalar.md: init, status, login, pair, autostart y uninstall con HOME falso, sin dejar estado", () => {
  const s = sandbox();
  let r = s.soul(["init", "trabajo", "--email", "yo@example.test"]);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(existsSync(join(s.data, "config.json")), "la configuración va al directorio de datos del usuario");

  r = s.soul(["status", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(r.stdout).profile, "trabajo");

  r = s.soul(["login", "github", "--token-stdin"], `${TOKEN}\n`);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readdirSync(join(s.home, ".llavero-falso")).length, 1, "el token va al llavero (doble)");
  assert.ok(!files(s.data).some((f) => readFileSync(f, "utf8").includes(TOKEN)), "0 tokens en el directorio de datos");

  const cfg = JSON.parse(readFileSync(join(s.data, "config.json"), "utf8"));
  cfg.api.listen = ["127.0.0.1"];
  writeFileSync(join(s.data, "config.json"), JSON.stringify(cfg));
  r = s.soul(["pair", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(JSON.parse(r.stdout).pin, /^sha256\//);
  assert.match(JSON.parse(r.stdout).clave, /^soulpk_[0-9A-Za-z]{30}_[0-9A-Za-z]{6}$/);

  r = s.soul(["autostart", "install", "--dry-run"]);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(r.stdout.includes(join(s.home, ".config", "systemd", "user")), "el arranque es del usuario, dentro de su HOME");
  assert.equal(existsSync(join(s.home, ".config", "systemd")), false, "--dry-run no escribe nada");

  r = s.soul(["uninstall", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(existsSync(s.data), false, "no queda el directorio de datos");
  assert.deepEqual(readdirSync(join(s.home, ".llavero-falso")), [], "no queda ningún token");
  const left = files(s.home).filter((f) => !f.includes(".dobles") && !f.endsWith(".systemctl-falso.log"));
  assert.deepEqual(left, [], "nada de Soul en el HOME");
  assert.ok(![r.stdout, r.stderr].join("").includes(TOKEN));
});

test("instalar.md: desde un frontend de agente, init y login se rechazan (código 4)", () => {
  const s = sandbox();
  const r = spawnSync(process.execPath, [BIN, "init", "trabajo"], { env: { PATH: process.env.PATH, HOME: s.home, CLAUDECODE: "1" }, encoding: "utf8" });
  assert.equal(r.status, 4);
  assert.equal(existsSync(join(s.data, "config.json")), false, "no crea la instalación (solo queda la auditoría de la llamada)");
  const l = spawnSync(process.execPath, [BIN, "login", "github", "--token-stdin"], { env: { PATH: process.env.PATH, HOME: s.home, CLAUDECODE: "1" }, input: `${TOKEN}\n`, encoding: "utf8" });
  assert.equal(l.status, 4);
  assert.equal(existsSync(join(s.home, ".llavero-falso")), false, "no llega al llavero");
});
