import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { autostartPlan, installAutostart, uninstallAutostart } from "../src/startup/autostart.ts";
import type { Run } from "../src/credentials/store.ts";

const opts = (platform: NodeJS.Platform, home: string) => ({
  platform, home, env: {} as Record<string, string>, node: "/opt/node/bin/node", entry: join(home, "soul", "src", "cli", "main.ts"),
});

const ADMIN = /sudo|runas|\/Library\/LaunchDaemons|\/etc\/systemd|\/lib\/systemd\/system|HighestAvailable|RunLevel>Highest|S-1-5-18|SYSTEM/;

for (const p of ["linux", "darwin", "win32"] as const) {
  test(`${p}: los ficheros quedan bajo el perfil del usuario y no piden privilegios`, () => {
    const home = join("/home", "u");
    const plan = autostartPlan(opts(p, home));
    assert.ok(plan.files.length >= 1);
    for (const f of plan.files) {
      assert.ok(f.path.startsWith(home), f.path);
      assert.doesNotMatch(f.content, ADMIN);
      assert.match(f.content, /serve/);
    }
    for (const c of [...plan.enable, ...plan.disable]) assert.doesNotMatch([c.cmd, ...c.args].join(" "), ADMIN);
  });
}

test("linux: unidad de usuario con Restart y sin privilegios nuevos", () => {
  const f = autostartPlan(opts("linux", "/home/u")).files[0];
  assert.equal(f.path, join("/home/u", ".config", "systemd", "user", "soul-continuity.service"));
  assert.match(f.content, /NoNewPrivileges=yes/);
  assert.match(f.content, /WantedBy=default.target/);
});

test("win32: tarea de inicio de sesión del usuario con privilegio mínimo", () => {
  const plan = autostartPlan(opts("win32", "/home/u"));
  assert.match(plan.files[0].content, /<LogonTrigger>/);
  assert.match(plan.files[0].content, /<RunLevel>LeastPrivilege<\/RunLevel>/);
  assert.equal(plan.enable[0].cmd, "schtasks");
});

test("win32: rutas con & y < se escapan en el XML", () => {
  const o = { ...opts("win32", "/home/u"), entry: "C:/a&b<c>/main.ts" };
  const xml = autostartPlan(o).files[0].content;
  assert.ok(xml.includes("C:/a&amp;b&lt;c&gt;/main.ts"));
  assert.ok(!xml.includes("a&b"));
});

test("install escribe los ficheros y ejecuta solo las órdenes del plan; uninstall los borra", async () => {
  const home = mkdtempSync(join(tmpdir(), "soul-as-"));
  const calls: string[] = [];
  const run: Run = async (cmd, args) => { calls.push([cmd, ...args].join(" ")); return { code: 0, stdout: "", stderr: "" }; };
  const o = opts("linux", home);
  const r = await installAutostart(o, run);
  assert.equal(r.ok, true);
  const unit = join(home, ".config", "systemd", "user", "soul-continuity.service");
  assert.ok(existsSync(unit));
  assert.match(readFileSync(unit, "utf8"), /ExecStart=/);
  assert.deepEqual(calls, autostartPlan(o).enable.map((c) => [c.cmd, ...c.args].join(" ")));
  const u = await uninstallAutostart(o, run);
  assert.equal(u.ok, true);
  assert.equal(existsSync(unit), false);
});

test("dry-run no escribe ni ejecuta nada", async () => {
  const home = mkdtempSync(join(tmpdir(), "soul-as-"));
  let n = 0;
  const run: Run = async () => { n++; return { code: 0, stdout: "", stderr: "" }; };
  const r = await installAutostart(opts("darwin", home), run, { dryRun: true });
  assert.equal(n, 0);
  assert.equal(existsSync(join(home, "Library", "LaunchAgents", "org.savia.soul-continuity.plist")), false);
  assert.ok(r.planned.length > 0);
});

test("si una orden de activación falla, install informa fallo (no OK)", async () => {
  const home = mkdtempSync(join(tmpdir(), "soul-as-"));
  const run: Run = async () => ({ code: 1, stdout: "", stderr: "Failed to connect to bus" });
  const r = await installAutostart(opts("linux", home), run);
  assert.equal(r.ok, false);
  assert.match(r.message, /Failed to connect to bus/);
});
