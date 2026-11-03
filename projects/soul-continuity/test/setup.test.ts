/**
 * Instalación en un paso: `init` fija la IP de la VPN, `listen`, `doctor`, los mensajes de `serve`
 * (huella ≠ clave, IP ausente) y `soul setup` de punta a punta. Dobles de red, de `Run` y de preguntas.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Run } from "../src/credentials/store.ts";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import type { Interfaces } from "../src/cli/host.ts";
import { NM_UNMANAGED_FIX } from "../src/cli/host.ts";
import { emptyConfig, loadConfig, saveConfig } from "../src/core/config.ts";
import { serveFromCli } from "../src/api/serve.ts";

const v4 = (address: string, internal = false) => ({ address, family: "IPv4" as const, internal, netmask: "255.192.0.0", mac: "00:00:00:00:00:00", cidr: null });
const VPN = "100.101.7.3";

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

function pathWith(...cmds: string[]): string {
  const d = mkdtempSync(join(tmpdir(), "soul-path-"));
  for (const c of cmds) { writeFileSync(join(d, c), "#!/bin/sh\n"); chmodSync(join(d, c), 0o755); }
  return d;
}

function mk(o: { ifaces?: Interfaces; run?: Run; answers?: string[]; env?: Record<string, string>; reachable?: boolean; noAsk?: boolean } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "soul-setup-"));
  const out: string[] = [];
  const err: string[] = [];
  const asked: string[] = [];
  const answers = [...(o.answers ?? [])];
  const deps: CliDeps = {
    dataDir: join(dir, "datos"), env: { PATH: pathWith("secret-tool"), ...o.env }, now: () => new Date().toISOString(),
    out: (s) => out.push(s), err: (s) => err.push(s), adapters: {},
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } },
    credentials: { revoke: async () => ({ tokens_removed: 0, cache_removed: false }), forgetAll: async () => [] },
    platform: "linux", home: dir, run: o.run ?? fakeRun({}), node: "/n/node", entry: "/e/soul.ts",
    ifaces: () => o.ifaces ?? {},
    reachable: async () => o.reachable ?? true,
    ...(o.noAsk ? {} : { ask: async (q: string) => { asked.push(q); return answers.shift() ?? ""; } }),
  };
  return { dir, deps, out, err, asked };
}

const conVpn = () => ({ ifaces: { lo: [v4("127.0.0.1", true)], tailscale0: [v4(VPN)] }, run: fakeRun({ "tailscale ip -4": { code: 0, stdout: `${VPN}\n` }, systemctl: { code: 0 } }) });

// ------------------------------------------------------------------ init y listen

test("init con VPN detectada fija api.listen en la IP de la VPN y lo dice", async () => {
  const s = mk(conVpn());
  assert.equal(await runCli(["init", "trabajo"], s.deps), 0, s.err.join("\n"));
  assert.deepEqual(loadConfig(s.deps.dataDir).api.listen, [VPN]);
  assert.match(s.out.join("\n"), new RegExp(`Escucharé solo en tu VPN: ${VPN.replace(/\./g, "\\.")}`));
});

test("init sin VPN (negativo): api.listen queda vacía y explica qué hacer; nunca 0.0.0.0", async () => {
  const s = mk({ ifaces: { eth0: [v4("192.168.1.20")] } });
  assert.equal(await runCli(["init", "trabajo"], s.deps), 0, s.err.join("\n"));
  assert.deepEqual(loadConfig(s.deps.dataDir).api.listen, []);
  assert.match(s.out.join("\n"), /No encuentro ninguna VPN/);
});

test("init avisa si falta secret-tool, con la orden de instalación", async () => {
  const s = mk({ ...conVpn(), env: { PATH: pathWith("otra") } });
  assert.equal(await runCli(["init", "trabajo"], s.deps), 0);
  assert.match(s.err.join("\n"), /falta secret-tool[\s\S]*apt install libsecret-tools/);
  const t = mk({ ...conVpn() });
  await runCli(["init", "trabajo"], t.deps);
  assert.doesNotMatch(t.err.join("\n"), /secret-tool/, "con secret-tool no avisa");
});

test("init --listen: valida la IP; 0.0.0.0 se rechaza y no crea nada", async () => {
  const s = mk(conVpn());
  assert.equal(await runCli(["init", "trabajo", "--listen", "0.0.0.0"], s.deps), 2);
  assert.equal(existsSync(join(s.deps.dataDir, "config.json")), false);
  assert.equal(await runCli(["init", "trabajo", "--listen", "100.80.0.9"], s.deps), 0, s.err.join("\n"));
  assert.deepEqual(loadConfig(s.deps.dataDir).api.listen, ["100.80.0.9"], "manda la que da la persona");
});

let nextPort = 20000 + (process.pid % 20000);
function withConfig(s: ReturnType<typeof mk>, listen: string[] = []) {
  const c = emptyConfig("i");
  c.active_profile = "yo";
  c.profiles.yo = { operator: { ref: "op-yo", identities: { emails: [] } }, sources: [] };
  c.api = { listen, port: nextPort++ };
  saveConfig(s.deps.dataDir, c);
}

test("listen --detect escribe la IP de la VPN sin editar config.json a mano", async () => {
  const s = mk(conVpn());
  withConfig(s);
  assert.equal(await runCli(["listen", "--detect"], s.deps), 0, s.err.join("\n"));
  assert.deepEqual(loadConfig(s.deps.dataDir).api.listen, [VPN]);
});

test("listen (negativo): --detect sin VPN falla sin tocar nada; comodines e IPs no literales se rechazan", async () => {
  const s = mk({ ifaces: { eth0: [v4("192.168.1.20")] } });
  withConfig(s, ["100.70.0.1"]);
  assert.equal(await runCli(["listen", "--detect"], s.deps), 1);
  assert.match(s.err.join("\n"), /No encuentro ninguna VPN/);
  for (const bad of ["0.0.0.0", "::", "mi-portatil.local"]) assert.equal(await runCli(["listen", bad], s.deps), 2, bad);
  assert.deepEqual(loadConfig(s.deps.dataDir).api.listen, ["100.70.0.1"], "sin cambios");
});

test("listen <ip> que no está en ninguna interfaz: la guarda pero avisa", async () => {
  const s = mk(conVpn());
  withConfig(s);
  assert.equal(await runCli(["listen", "100.80.0.9"], s.deps), 0);
  assert.deepEqual(loadConfig(s.deps.dataDir).api.listen, ["100.80.0.9"]);
  assert.match(s.err.join("\n"), /no está en ninguna interfaz/);
});

test("listen y doctor no se ejecutan desde un frontend de agente", async () => {
  const s = mk({ ...conVpn(), env: { CLAUDECODE: "1" } });
  withConfig(s);
  assert.equal(await runCli(["listen", "--detect"], s.deps), 4);
  assert.equal(await runCli(["setup"], s.deps), 4);
  assert.deepEqual(loadConfig(s.deps.dataDir).api.listen, []);
});

// ------------------------------------------------------------------ doctor

test("doctor: todo en orden => 0 y cada comprobación con «ok»", async () => {
  const s = mk(conVpn());
  withConfig(s, [VPN]);
  assert.equal(await runCli(["doctor"], s.deps), 0, s.out.join("\n"));
  assert.doesNotMatch(s.out.join("\n"), /FALLO/);
});

test("doctor: IP configurada ausente con tailscale0 gestionada => 1 y la orden de unmanaged-devices", async () => {
  const s = mk({ ifaces: { tailscale0: [] }, run: fakeRun({ nmcli: { code: 0, stdout: "tailscale0:connected\n" } }) });
  withConfig(s, [VPN]);
  assert.equal(await runCli(["doctor"], s.deps), 1);
  const o = s.out.join("\n");
  assert.match(o, /FALLO.*no está en ninguna interfaz/);
  assert.ok(o.includes(NM_UNMANAGED_FIX));
});

test("doctor: falta secret-tool => 1 con la orden de instalación; sin perfil también falla", async () => {
  const s = mk({ ...conVpn(), env: { PATH: pathWith() } });
  withConfig(s, [VPN]);
  assert.equal(await runCli(["doctor"], s.deps), 1);
  assert.match(s.out.join("\n"), /FALLO.*secret-tool[\s\S]*libsecret-tools/);
  const t = mk(conVpn());
  assert.equal(await runCli(["doctor"], t.deps), 1);
  assert.match(t.out.join("\n"), /FALLO Soul no está instalado[\s\S]*arreglo: soul setup/);
});

// ------------------------------------------------------------------ serve

test("serve: la huella dice que no es la clave y explica cómo emparejar en lenguaje llano", async () => {
  const s = mk({ ifaces: { lo: [v4("127.0.0.1", true)] } });
  withConfig(s, ["127.0.0.1"]);
  const ac = new AbortController();
  const code = await serveFromCli(s.deps, { signal: ac.signal, onListening: () => ac.abort() });
  assert.equal(code, 0, s.err.join("\n"));
  const o = s.out.join("\n");
  assert.match(o, /huella del certificado \(no es la clave\): sha256\//);
  assert.match(o, /Para emparejar el móvil, abre otra terminal y ejecuta: soul pair/);
  assert.doesNotMatch(o, /Huella del certificado para emparejar/, "la etiqueta antigua confundía la huella con la clave");
});

test("serve (negativo): IP configurada ausente => no intenta escuchar y da el arreglo de NetworkManager", async () => {
  const run = fakeRun({ nmcli: { code: 0, stdout: "tailscale0:connected\n" } });
  const s = mk({ ifaces: { tailscale0: [] }, run });
  withConfig(s, [VPN]);
  assert.equal(await serveFromCli(s.deps, { signal: AbortSignal.abort() }), 1);
  const e = s.err.join("\n");
  assert.match(e, /no está en ninguna interfaz/);
  assert.ok(e.includes(NM_UNMANAGED_FIX));
  assert.doesNotMatch(e, /EADDRNOTAVAIL/);
});

test("serve (negativo): sin sonda de interfaces, un EADDRNOTAVAIL se traduce al mismo diagnóstico", async () => {
  const s = mk({ ifaces: { tailscale0: [] } });
  delete s.deps.ifaces;
  withConfig(s, ["192.0.2.1"]); // TEST-NET-1: no está asignada en ningún equipo
  assert.equal(await serveFromCli(s.deps, { signal: AbortSignal.abort() }), 1);
  assert.match(s.err.join("\n"), /192\.0\.2\.1 no está en ninguna interfaz/);
});

// ------------------------------------------------------------------ setup

test("setup de punta a punta: init, VPN, comprobaciones, arranque de usuario y pair", async () => {
  // init ya fija la IP de la VPN detectada: no hace falta preguntarla. Perfil, correo, servicio y pair.
  const s = mk({ ...conVpn(), answers: ["trabajo", "yo@example.test", "", ""] });
  assert.equal(await runCli(["setup"], s.deps), 0, s.err.join("\n") + s.out.join("\n"));
  const c = loadConfig(s.deps.dataDir);
  assert.equal(c.active_profile, "trabajo");
  assert.deepEqual(c.profiles.trabajo.operator.identities.emails, ["yo@example.test"]);
  assert.deepEqual(c.api.listen, [VPN]);
  assert.ok(existsSync(join(s.dir, ".config/systemd/user/soul-continuity.service")), "servicio de usuario");
  const run = s.deps.run as ReturnType<typeof fakeRun>;
  assert.ok(run.calls.includes("systemctl --user enable --now soul-continuity.service"));
  assert.ok(!run.calls.some((x) => x.startsWith("sudo")), "nada con sudo");
  assert.match(s.out.join("\n"), /clave de emparejamiento: soulpk_/);
  assert.equal(s.asked.length, 4);
  assert.match(s.out.join("\n"), /Escucha configurada: 100\.101\.7\.3/);
});

test("setup con VPN detectada pero sin escucha la propone y la escribe si la persona acepta", async () => {
  const s = mk({ ...conVpn(), answers: ["", "", "n"] });
  withConfig(s, []);
  assert.equal(await runCli(["setup"], s.deps), 0, s.err.join("\n"));
  assert.match(s.asked[0], /He encontrado tu VPN: 100\.101\.7\.3/);
  assert.deepEqual(loadConfig(s.deps.dataDir).api.listen, [VPN]);
});

test("setup sobre una instalación existente no la pisa y no pregunta el perfil", async () => {
  const s = mk({ ...conVpn(), answers: ["", "n"] });
  withConfig(s, [VPN]);
  assert.equal(await runCli(["setup"], s.deps), 0, s.err.join("\n"));
  assert.equal(loadConfig(s.deps.dataDir).active_profile, "yo");
  assert.doesNotMatch(s.asked.join("\n"), /perfil/);
  assert.doesNotMatch(s.out.join("\n"), /soulpk_/, "dijo que no a emparejar");
});

test("setup (negativo): sin VPN y sin IP explica qué hacer, sale con 1 y no instala el arranque", async () => {
  const s = mk({ ifaces: { eth0: [v4("192.168.1.20")] }, run: fakeRun({ systemctl: { code: 0 } }), answers: ["trabajo", "", ""] });
  assert.equal(await runCli(["setup"], s.deps), 1);
  assert.match(s.err.join("\n") + s.out.join("\n"), /No encuentro ninguna VPN/);
  assert.equal(existsSync(join(s.dir, ".config/systemd/user/soul-continuity.service")), false);
});

test("setup (negativo): IP ausente por NetworkManager para antes del arranque y da la orden", async () => {
  const s = mk({ ifaces: { tailscale0: [] }, run: fakeRun({ nmcli: { code: 0, stdout: "tailscale0:connected\n" }, systemctl: { code: 0 } }), answers: [] });
  withConfig(s, [VPN]);
  assert.equal(await runCli(["setup"], s.deps), 1);
  assert.ok(s.out.join("\n").includes(NM_UNMANAGED_FIX));
  assert.equal(existsSync(join(s.dir, ".config/systemd/user/soul-continuity.service")), false);
});

test("setup (negativo): sin terminal interactiva no hace nada", async () => {
  const s = mk({ ...conVpn(), noAsk: true });
  assert.equal(await runCli(["setup"], s.deps), 2);
  assert.match(s.err.join("\n"), /interactiva/);
  assert.equal(existsSync(join(s.deps.dataDir, "config.json")), false);
});

test("setup (negativo): si serve no responde tras el arranque, no abre la ventana de pair", async () => {
  const s = mk({ ...conVpn(), reachable: false, answers: ["trabajo", "", "", ""] });
  assert.equal(await runCli(["setup"], s.deps), 1);
  assert.match(s.err.join("\n"), /no responde/);
  assert.doesNotMatch(s.out.join("\n"), /soulpk_/);
  assert.equal(existsSync(join(s.deps.dataDir, "pairing.json")), false);
});
