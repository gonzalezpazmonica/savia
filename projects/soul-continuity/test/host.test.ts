/**
 * Detecciones del equipo para instalar Soul: VPN, IP configurada ausente (NetworkManager y
 * tailscale0) y secret-tool. Todo con dobles: interfaces y `Run` falsos, PATH temporal.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Run } from "../src/credentials/store.ts";
import {
  type Interfaces, NM_UNMANAGED_FIX, checkListen, checkSecretTool, detectVpn, isCgnat, missingAddress, nmManaged, onInterface, onPath,
} from "../src/cli/host.ts";

const v4 = (address: string, internal = false) => ({ address, family: "IPv4" as const, internal, netmask: "255.255.255.0", mac: "00:00:00:00:00:00", cidr: null });

/** `Run` falso: respuesta por orden; lo no previsto = herramienta ausente (127). */
function fakeRun(map: Record<string, { code: number; stdout?: string }>): Run & { calls: string[] } {
  const calls: string[] = [];
  const f = (async (cmd: string, args: string[]) => {
    const k = [cmd, ...args].join(" ");
    calls.push(k);
    const r = map[k] ?? map[cmd];
    return r ? { code: r.code, stdout: r.stdout ?? "", stderr: "" } : { code: 127, stdout: "", stderr: "no existe" };
  }) as Run & { calls: string[] };
  f.calls = calls;
  return f;
}

test("isCgnat: solo 100.64.0.0/10, con sus bordes", () => {
  assert.equal(isCgnat("100.64.0.0"), true);
  assert.equal(isCgnat("100.127.255.255"), true);
  assert.equal(isCgnat("100.101.7.3"), true);
  assert.equal(isCgnat("100.63.255.255"), false, "borde inferior fuera");
  assert.equal(isCgnat("100.128.0.0"), false, "borde superior fuera");
  assert.equal(isCgnat("192.168.1.10"), false);
  assert.equal(isCgnat("0.0.0.0"), false);
  assert.equal(isCgnat("fd7a:115c:a1e0::1"), false, "IPv6 no");
});

test("detectVpn: la IP de «tailscale ip -4» primero y sin repetir la de la interfaz", async () => {
  const ifaces: Interfaces = { lo: [v4("127.0.0.1", true)], eth0: [v4("192.168.1.20")], tailscale0: [v4("100.101.7.3")] };
  const run = fakeRun({ "tailscale ip -4": { code: 0, stdout: "100.101.7.3\n" } });
  assert.deepEqual(await detectVpn(ifaces, run), [{ address: "100.101.7.3", via: "tailscale" }]);
});

test("detectVpn: sin tailscale, encuentra otra VPN de malla por su interfaz 100.64/10", async () => {
  const ifaces: Interfaces = { eth0: [v4("10.0.0.5")], wt0: [v4("100.90.1.2")] };
  assert.deepEqual(await detectVpn(ifaces, fakeRun({})), [{ address: "100.90.1.2", via: "wt0" }]);
});

test("detectVpn (negativo): sin VPN no propone nada, ni la LAN ni el bucle ni 0.0.0.0", async () => {
  const ifaces: Interfaces = { lo: [v4("127.0.0.1", true)], eth0: [v4("192.168.1.20")], docker0: [v4("172.17.0.1")] };
  const run = fakeRun({ "tailscale ip -4": { code: 0, stdout: "0.0.0.0\n192.168.1.20\n" } });
  assert.deepEqual(await detectVpn(ifaces, run), []);
});

test("onInterface: presente y ausente", () => {
  const ifaces: Interfaces = { tailscale0: [v4("100.101.7.3")] };
  assert.equal(onInterface("100.101.7.3", ifaces), true);
  assert.equal(onInterface("100.101.7.4", ifaces), false);
});

test("nmManaged: gestionada, no gestionada y sin nmcli", async () => {
  assert.equal(await nmManaged("tailscale0", fakeRun({ nmcli: { code: 0, stdout: "eth0:connected\ntailscale0:connected (externally)\n" } })), true);
  assert.equal(await nmManaged("tailscale0", fakeRun({ nmcli: { code: 0, stdout: "eth0:connected\ntailscale0:unmanaged\n" } })), false);
  assert.equal(await nmManaged("tailscale0", fakeRun({ nmcli: { code: 0, stdout: "eth0:connected\n" } })), null, "no la conoce");
  assert.equal(await nmManaged("tailscale0", fakeRun({})), null, "sin nmcli");
});

test("IP ausente con tailscale0 gestionada por NetworkManager: da la orden exacta de unmanaged-devices", async () => {
  const c = await missingAddress("100.101.7.3", {
    platform: "linux", path: "", ifaces: { tailscale0: [] },
    run: fakeRun({ nmcli: { code: 0, stdout: "tailscale0:connected\n" } }),
  });
  assert.equal(c.level, "fallo");
  assert.match(c.message, /100\.101\.7\.3 no está en ninguna interfaz/);
  assert.match(c.message, /NetworkManager gestiona tailscale0/);
  assert.equal(c.fix, NM_UNMANAGED_FIX);
  assert.match(NM_UNMANAGED_FIX, /unmanaged-devices=interface-name:tailscale0/);
  assert.match(NM_UNMANAGED_FIX, /conf\.d\/unmanaged-devices\.conf/);
});

test("IP ausente (negativo): con tailscale0 no gestionada no culpa a NetworkManager y propone la IP nueva", async () => {
  const c = await missingAddress("100.101.7.3", {
    platform: "linux", path: "", ifaces: { tailscale0: [v4("100.101.9.9")] },
    run: fakeRun({ nmcli: { code: 0, stdout: "tailscale0:unmanaged\n" } }),
  });
  assert.equal(c.level, "fallo");
  assert.doesNotMatch(c.message, /NetworkManager/);
  assert.notEqual(c.fix, NM_UNMANAGED_FIX);
  assert.match(c.fix ?? "", /soul listen 100\.101\.9\.9/);
});

test("IP ausente fuera de Linux: no ejecuta nmcli", async () => {
  const run = fakeRun({ nmcli: { code: 0, stdout: "tailscale0:connected\n" } });
  const c = await missingAddress("100.101.7.3", { platform: "darwin", path: "", ifaces: {}, run });
  assert.ok(!run.calls.some((x) => x.startsWith("nmcli")));
  assert.notEqual(c.fix, NM_UNMANAGED_FIX);
});

test("checkListen: vacía con VPN propone «soul listen <ip>»; vacía sin VPN explica qué hacer", async () => {
  const conVpn = await checkListen([], { platform: "linux", path: "", ifaces: { tailscale0: [v4("100.101.7.3")] }, run: fakeRun({}) });
  assert.equal(conVpn[0].level, "fallo");
  assert.match(conVpn[0].fix ?? "", /^soul listen 100\.101\.7\.3/);
  const sinVpn = await checkListen([], { platform: "linux", path: "", ifaces: { eth0: [v4("192.168.1.2")] }, run: fakeRun({}) });
  assert.match(sinVpn[0].fix ?? "", /No encuentro ninguna VPN/);
  assert.match(sinVpn[0].fix ?? "", /Nunca 0\.0\.0\.0/);
});

test("checkListen: IP presente da ok", async () => {
  const c = await checkListen(["100.101.7.3"], { platform: "linux", path: "", ifaces: { tailscale0: [v4("100.101.7.3")] }, run: fakeRun({}) });
  assert.deepEqual(c.map((x) => x.level), ["ok"]);
});

function pathWith(...cmds: string[]): string {
  const d = mkdtempSync(join(tmpdir(), "soul-path-"));
  mkdirSync(join(d, "sub"));
  for (const c of cmds) { writeFileSync(join(d, c), "#!/bin/sh\n"); chmodSync(join(d, c), 0o755); }
  return d;
}

test("secret-tool: presente da ok; ausente da fallo con la orden de instalación", () => {
  const con = checkSecretTool({ platform: "linux", path: pathWith("secret-tool"), ifaces: {}, run: fakeRun({}) });
  assert.equal(con.level, "ok");
  const sin = checkSecretTool({ platform: "linux", path: pathWith("otra"), ifaces: {}, run: fakeRun({}) });
  assert.equal(sin.level, "fallo");
  assert.match(sin.fix ?? "", /apt install libsecret-tools/);
});

test("secret-tool (negativo): un directorio con ese nombre no cuenta; fuera de Linux no se exige", () => {
  const d = mkdtempSync(join(tmpdir(), "soul-path-"));
  mkdirSync(join(d, "secret-tool"));
  assert.equal(onPath("secret-tool", d, "linux"), false);
  assert.equal(checkSecretTool({ platform: "darwin", path: "", ifaces: {}, run: fakeRun({}) }).level, "ok");
});
