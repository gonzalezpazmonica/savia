import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { SourceAdapter } from "../src/contract/adapter.ts";
import { emptyConfig, saveConfig } from "../src/core/config.ts";
import { filesUnder } from "../src/core/store.ts";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import type { Run } from "../src/credentials/store.ts";
import { autostartPlan } from "../src/startup/autostart.ts";

const NOW = "2026-10-31T09:00:00Z";
const TITLE = "Asunto-confidencial-de-tercero";
const PERSON = "persona.tercera@example.test";
const CLI_TOKEN = "tok-canario-cli-91c2";

function adapter(): SourceAdapter {
  return {
    name: "m365-mail", routes: ["graph"], purpose: "t",
    async read(ctx) {
      await ctx.credentials.acquire("m365-mail", ["Mail.ReadBasic"]);
      return {
        status: "ok", route: "graph", claims: [{
          key: "m365-mail:awaiting_reply:c1@m1", claim_type: "awaiting_reply", state: "OBSERVED",
          source_refs: [{ adapter: "m365-mail", route: "graph", ref: "c1@m1" }], sensitivity: ctx.sensitivity,
          observed_at: ctx.now, valid_until: "2026-10-31T10:00:00Z", event_at: "2026-10-31T08:00:00Z",
          open: true, awaiting_operator: true, title: TITLE, untrusted_text: true,
          attrs: { last_from: PERSON, sender_auth: "tenant" },
        }],
      };
    },
  };
}

interface Setup { dir: string; home: string; deps: CliDeps; out: string[]; err: string[]; forgotten: string[]; runs: string[] }

function setup(opts: { profile?: boolean; level?: "completo" | "titulos" | "recuentos"; env?: Record<string, string>; providers?: any[] } = {}): Setup {
  const dir = mkdtempSync(join(tmpdir(), "soul-cli-"));
  const home = mkdtempSync(join(tmpdir(), "soul-home-"));
  const cfg = emptyConfig("inst-test");
  cfg.detail = { level: opts.level ?? "completo", max: "completo" };
  cfg.agent_frontend.approved_providers = opts.providers ?? [];
  if (opts.profile !== false) {
    cfg.active_profile = "yo";
    cfg.profiles.yo = {
      operator: { ref: "op-yo", identities: { emails: ["yo@example.test"] } },
      sources: [{ adapter: "m365-mail", purpose: "correo", consent: { granted_at: "2026-10-01T00:00:00Z", statement: "bajo mi responsabilidad" } }],
    };
  }
  saveConfig(dir, cfg);
  const out: string[] = [];
  const err: string[] = [];
  const forgotten: string[] = [];
  const runs: string[] = [];
  const run: Run = async (cmd, args) => { runs.push([cmd, ...args].join(" ")); return { code: 0, stdout: "", stderr: "" }; };
  const deps: CliDeps = {
    dataDir: dir, env: { ...(opts.env ?? {}) }, now: () => NOW, out: (s) => out.push(s), err: (s) => err.push(s),
    adapters: { "m365-mail": adapter() },
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => CLI_TOKEN } },
    credentials: { revoke: async (a: string, ref: string) => { forgotten.push(`${a}@${ref}`); return { tokens_removed: 1, cache_removed: false }; }, forgetAll: async () => { forgotten.push("*"); return []; } },
    platform: "linux", home, run, node: "/n/node", entry: "/e/main.ts",
  };
  return { dir, home, deps, out, err, forgotten, runs };
}

const text = (s: Setup) => s.out.join("\n");

test("sin perfil: negativa clara y código 3", async () => {
  const s = setup({ profile: false });
  assert.equal(await runCli(["q1"], s.deps), 3);
  assert.match(s.err.join("\n"), /No sé quién eres/);
});

test("status responde sin perfil, sin red y en frío por debajo de 1 s", async () => {
  const s = setup({ profile: false });
  // AC-1 (< 1 s) con la mejor de 3: un pico de carga del CI no es una regresión; 3 lentas seguidas sí.
  let best = Infinity;
  for (let i = 0; i < 3 && best >= 1000; i++) {
    s.out.length = 0;
    const t0 = performance.now();
    assert.equal(await runCli(["status", "--json"], s.deps), 0);
    best = Math.min(best, performance.now() - t0);
  }
  assert.ok(best < 1000, `status tardó ${Math.round(best)} ms`);
  const j = JSON.parse(text(s));
  assert.equal(j.profile, null);
  assert.equal(j.stopped, false);
});

test("q1 en terminal de la persona, nivel completo: muestra el título como texto de tercero", async () => {
  const s = setup();
  assert.equal(await runCli(["q1", "--json"], s.deps), 0);
  const j = JSON.parse(text(s));
  assert.equal(j.detail, "completo");
  assert.equal(j.items[0].title, TITLE);
  assert.equal(j.items[0].untrusted_text, true);
  assert.ok(text(s).includes(PERSON), "control: a nivel completo el remitente sí sale, así que su ausencia en AC-4d discrimina");
});

// AC-4d — el control positivo de arriba prueba que el test puede ver el título si sale.
for (const env of [{ CLAUDECODE: "1" }, { OPENCODE: "1" }, { SOUL_AGENT_FRONTEND: "otro" }] as Record<string, string>[]) {
  test(`AC-4d: invocada por un frontend de agente (${Object.keys(env)[0]}) solo salen recuentos`, async () => {
    const s = setup({ env });
    for (const q of ["q1", "q2", "q4"]) assert.equal(await runCli([q, "--json"], s.deps), 0);
    assert.equal(await runCli(["adapters", "--json"], s.deps), 0);
    const all = text(s);
    assert.ok(!all.includes(TITLE), "ningún asunto");
    assert.ok(!all.includes(PERSON), "ningún remitente ni nombre");
    assert.ok(!all.includes("c1@m1"), "ninguna referencia de la fuente");
    const j = JSON.parse(s.out[0]);
    assert.equal(j.detail, "recuentos");
    assert.equal(j.counts.awaiting_reply, 1);
    assert.equal(j.forced_by_frontend, true);
  });
}

test("AC-4d: --frontend explícito también fuerza recuentos", async () => {
  const s = setup();
  assert.equal(await runCli(["q2", "--json", "--frontend", "claude-code"], s.deps), 0);
  assert.ok(!text(s).includes(TITLE));
  const j = JSON.parse(text(s));
  assert.equal(j.detail, "recuentos");
  assert.equal(j.counts.awaiting_reply, 1);
});

test("AC-4d: why por un frontend de agente no revela referencia ni título", async () => {
  const s = setup();
  await runCli(["q1", "--json"], s.deps);
  const id = JSON.parse(s.out[0]).items[0].id;
  s.out.length = 0;
  s.deps.env.CLAUDECODE = "1";
  assert.equal(await runCli(["why", id, "--json"], s.deps), 0);
  assert.ok(!text(s).includes("c1@m1"));
  assert.ok(!text(s).includes(TITLE));
});

test("AC-4d: proveedor aprobado para N4 declarado en la configuración local => nivel de la instalación, y queda auditado", async () => {
  const s = setup({ env: { CLAUDECODE: "1" }, providers: [{ id: "prov-org", approved_by: "seguridad de la organización", approved_at: "2026-10-30T00:00:00Z", scope: "N4", frontends: ["claude-code"] }] });
  await runCli(["q1", "--json"], s.deps);
  assert.ok(text(s).includes(TITLE));
  const audit = readFileSync(join(s.dir, "audit.jsonl"), "utf8");
  assert.match(audit, /prov-org/);
  assert.ok(!audit.includes(TITLE), "la auditoría solo guarda recuentos");
});

test("AC-4d: un frontend de agente no puede exportar, desinstalar ni revocar", async () => {
  const s = setup({ env: { CLAUDECODE: "1" } });
  for (const c of [["export"], ["uninstall", "--yes"], ["revoke", "m365-mail"], ["correct", "x", "resuelto"]]) {
    assert.equal(await runCli(c, s.deps), 4, c.join(" "));
  }
  assert.ok(existsSync(s.dir));
});

test("correct: lo resuelto no vuelve en la siguiente consulta", async () => {
  const s = setup();
  await runCli(["q2", "--json"], s.deps);
  const id = JSON.parse(s.out[0]).items[0].id;
  assert.equal(await runCli(["correct", id, "resuelto"], s.deps), 0);
  s.out.length = 0;
  await runCli(["q2", "--json"], s.deps);
  assert.equal(JSON.parse(s.out[0]).items.length, 0);
});

test("correct con un id que no existe: error y nada en el libro", async () => {
  const s = setup();
  await runCli(["q1", "--json"], s.deps);
  assert.equal(await runCli(["correct", "e0000", "resuelto"], s.deps), 1);
  assert.ok(!filesUnder(s.dir).some((f) => f.endsWith("ledger.jsonl")), "el libro no se crea");
  // control: con un id real el libro sí aparece
  const id = JSON.parse(s.out[0]).items[0].id;
  assert.equal(await runCli(["correct", id, "resuelto"], s.deps), 0);
  assert.ok(filesUnder(s.dir).some((f) => f.endsWith("ledger.jsonl")));
});

test("AC-5: revoke borra la caché del adaptador y su credencial, y deja de leerlo", async () => {
  const s = setup();
  await runCli(["q1", "--json"], s.deps);
  assert.ok(filesUnder(s.dir).some((f) => readFileSync(f, "utf8").includes("c1@m1")));
  assert.equal(await runCli(["revoke", "m365-mail"], s.deps), 0);
  assert.ok(!filesUnder(s.dir).some((f) => readFileSync(f, "utf8").includes("c1@m1")), "caché del adaptador borrada");
  assert.deepEqual(s.forgotten, ["m365-mail@op-yo"], "revoca los tokens del adaptador para el operador del perfil");
  s.out.length = 0;
  await runCli(["adapters", "--json"], s.deps);
  assert.equal(JSON.parse(text(s)).adapters["m365-mail"].status, "consent_revoked");
});

test("STOP: las preguntas no leen fuentes y status lo dice; resume lo levanta", async () => {
  const s = setup();
  assert.equal(await runCli(["stop", "me", "voy"], s.deps), 0);
  assert.equal(await runCli(["q1"], s.deps), 5);
  s.out.length = 0;
  await runCli(["status", "--json"], s.deps);
  assert.equal(JSON.parse(text(s)).stopped, true);
  assert.equal(await runCli(["resume"], s.deps), 0);
  assert.equal(await runCli(["q1"], s.deps), 0);
});

test("mode guarda el modo de atención con ventana", async () => {
  const s = setup();
  assert.equal(await runCli(["mode", "FOCO", "--for", "2h", "--json"], s.deps), 0);
  assert.equal(JSON.parse(text(s)).modo, "FOCO");
  assert.equal(JSON.parse(text(s)).hasta, "2026-10-31T11:00:00.000Z");
  assert.equal(await runCli(["mode", "SIESTA"], s.deps), 2);
});

test("export incluye libro e instantánea, y no lleva tokens", async () => {
  const s = setup();
  await runCli(["q2", "--json"], s.deps);
  const id = JSON.parse(s.out[0]).items[0].id;
  await runCli(["correct", id, "no-aplica"], s.deps);
  s.out.length = 0;
  assert.equal(await runCli(["export"], s.deps), 0);
  const j = JSON.parse(text(s));
  assert.equal(j.operators[0].ledger.length, 1);
  assert.ok(!text(s).includes(CLI_TOKEN), "la exportación no lleva tokens");
  assert.ok(!filesUnder(s.dir).some((f) => readFileSync(f, "utf8").includes(CLI_TOKEN)), "0 tokens en disco");
});

test("0 tokens en disco ni en export aunque el adaptador devuelva el token en sus metadatos", async () => {
  const s = setup();
  const leaky = adapter();
  const read = leaky.read.bind(leaky);
  leaky.read = async (ctx) => {
    const r: any = await read(ctx);
    r.claims[0].attrs.etag = await ctx.credentials.acquire("m365-mail", ["Mail.ReadBasic"]);
    return r;
  };
  s.deps.adapters = { "m365-mail": leaky };
  assert.equal(await runCli(["q2", "--json"], s.deps), 0);
  assert.equal(JSON.parse(text(s)).adapters["m365-mail"].status, "error", "la lectura se descarta");
  s.out.length = 0;
  assert.equal(await runCli(["export"], s.deps), 0);
  assert.ok(!text(s).includes(CLI_TOKEN), "la exportación no lleva tokens");
  assert.ok(!filesUnder(s.dir).some((f) => readFileSync(f, "utf8").includes(CLI_TOKEN)), "0 tokens en disco");
});

test("status responde con la caché ilegible o con un perfil sin operator.ref", async () => {
  const s = setup();
  assert.equal(await runCli(["q1"], s.deps), 0);
  const cache = filesUnder(s.dir).find((f) => f.endsWith("snapshot.json")) as string;
  writeFileSync(cache, "{corte");
  s.out.length = 0;
  assert.equal(await runCli(["status", "--json"], s.deps), 0, s.err.join("\n"));
  assert.equal(JSON.parse(text(s)).last_read_unreadable, true);
  const t = setup();
  const cfg = JSON.parse(readFileSync(join(t.dir, "config.json"), "utf8"));
  delete cfg.profiles.yo.operator.ref;
  writeFileSync(join(t.dir, "config.json"), JSON.stringify(cfg));
  assert.equal(await runCli(["status", "--json"], t.deps), 0, t.err.join("\n"));
  assert.equal(JSON.parse(text(t)).last_read, null);
});

test("AC-4d: toda llamada de un agente queda auditada (status, stop, help, rechazos, errores) sin texto libre", async () => {
  const s = setup({ env: { CLAUDECODE: "1" } });
  assert.equal(await runCli(["status"], s.deps), 0);
  assert.equal(await runCli(["help"], s.deps), 0);
  assert.equal(await runCli(["stop", "motivo-privado"], s.deps), 0);
  assert.equal(await runCli(["q1"], s.deps), 5);
  assert.equal(await runCli(["export-secreto-libre"], s.deps), 4);
  const rows = readFileSync(join(s.dir, "audit.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.deepEqual(rows.map((r) => [r.cmd, r.exit]), [["status", 0], ["help", 0], ["stop", 0], ["q1", 5], ["rechazada", 4]]);
  const raw = readFileSync(join(s.dir, "audit.jsonl"), "utf8");
  assert.ok(!raw.includes("motivo-privado") && !raw.includes("export-secreto-libre"), "ni el motivo ni la orden libre");
  const h = setup();
  assert.equal(await runCli(["status"], h.deps), 0);
  assert.ok(!existsSync(join(h.dir, "audit.jsonl")), "control: la persona en su terminal no genera auditoría");
});

test("status no entrega a un agente en recuentos el motivo del STOP (control: la persona sí lo ve)", async () => {
  const s = setup({ level: "recuentos" });
  assert.equal(await runCli(["stop", "cita-medica"], s.deps), 0);
  s.out.length = 0;
  assert.equal(await runCli(["status", "--json"], s.deps), 0);
  assert.equal(JSON.parse(text(s)).stop_reason, "cita-medica");
  s.out.length = 0;
  s.deps.env.CLAUDECODE = "1";
  assert.equal(await runCli(["status", "--json"], s.deps), 0);
  const j = JSON.parse(text(s));
  assert.equal(j.stopped, true);
  assert.equal(j.stop_reason, null);
});

test("AC-5: uninstall sin --yes no borra nada; con --yes no deja estado", async () => {
  const s = setup();
  await runCli(["q1"], s.deps);
  assert.equal(await runCli(["uninstall"], s.deps), 2);
  assert.ok(existsSync(s.dir));
  assert.equal(await runCli(["uninstall", "--yes"], s.deps), 0);
  assert.equal(existsSync(s.dir), false);
  assert.deepEqual(s.forgotten, ["*"]);
  assert.ok(s.runs.some((r) => r.includes("disable")), "retira el arranque automático");
});

test("orden desconocida o texto libre: ayuda y código 2, sin interpretar", async () => {
  const s = setup();
  assert.equal(await runCli(["qué", "tengo", "hoy"], s.deps), 2);
  assert.match(s.err.join("\n"), /órdenes/);
});

test("pair: abre una ventana con clave soulpk_, IP, puerto y huella corta; no muestra ni guarda ningún token de dispositivo", async () => {
  const s = setup();
  const cfg = JSON.parse(readFileSync(join(s.dir, "config.json"), "utf8"));
  cfg.api = { listen: ["127.0.0.1"], port: 8787 };
  (await import("node:fs")).writeFileSync(join(s.dir, "config.json"), JSON.stringify(cfg));
  assert.equal(await runCli(["pair", "--json"], s.deps), 0);
  const j = JSON.parse(text(s));
  assert.match(j.clave, /^soulpk_[0-9A-Za-z]{30}_[0-9A-Za-z]{6}$/);
  assert.equal(j.codigo, undefined, "sin código v1");
  assert.equal(j.token, undefined);
  assert.match(j.pin, /^sha256\//);
  assert.deepEqual(j.direcciones, ["127.0.0.1"]);
  assert.equal(j.puerto, 8787);
  assert.equal(j.qr, `soul://pair?v=2&h=127.0.0.1&p=8787&k=${j.clave}&f=${j.huella_corta.replace(/ /g, "")}`);
  s.out.length = 0;
  assert.equal(await runCli(["devices", "--json"], s.deps), 0);
  assert.deepEqual(JSON.parse(text(s)).devices, [], "abrir la ventana no da de alta ningún dispositivo");
  assert.equal(await runCli(["unpair", "d-nada"], s.deps), 1);
  assert.equal(await runCli(["pair", "movil"], s.deps), 2, "el nombre lo pone la app: un argumento es error de uso");
  assert.equal(await runCli(["pair", "--days", "0"], s.deps), 2);
});

test("pair: pinta el QR del enlace en la terminal y --qr-png lo guarda en 0600 sin sobrescribir", async () => {
  const { encodeQr, qrToTerminal } = await import("../src/api/qr.ts");
  const s = setup();
  const cfg = JSON.parse(readFileSync(join(s.dir, "config.json"), "utf8"));
  cfg.api = { listen: ["127.0.0.1"], port: 8787 };
  (await import("node:fs")).writeFileSync(join(s.dir, "config.json"), JSON.stringify(cfg));
  assert.equal(await runCli(["pair"], s.deps), 0);
  const t = text(s);
  const clave = /clave de emparejamiento: (soulpk_\S+)/.exec(t)![1];
  const enlace = /enlace para QR: (\S+)/.exec(t)![1];
  assert.match(enlace, new RegExp(`&k=${clave}&`));
  assert.ok(t.includes(qrToTerminal(encodeQr(enlace).modules)), "el QR que se ve es el del enlace con la clave de esta ventana");
  assert.match(t, /no compartas capturas/);

  const png = join(s.dir, "qr.png");
  s.out.length = 0;
  assert.equal(await runCli(["pair", "--qr-png", png, "--json"], s.deps), 0);
  const j = JSON.parse(text(s));
  assert.equal(j.qr_png, png);
  const b = readFileSync(png);
  assert.equal(b.subarray(1, 4).toString("ascii"), "PNG");
  if (process.platform !== "win32") assert.equal((await import("node:fs")).statSync(png).mode & 0o777, 0o600);
  // Ya existe: no se sobrescribe y la ventana recién abierta se cierra (la clave no queda en disco).
  assert.equal(await runCli(["pair", "--qr-png", png], s.deps), 1);
  assert.match(s.err.join("\n"), /--qr-png: no se pudo crear .*EEXIST.*ventana cerrada/);
  assert.equal(existsSync(join(s.dir, "pairing.json")), false);
  assert.deepEqual(readFileSync(png), b);
  assert.equal(await runCli(["pair", "--qr-png"], s.deps), 2, "sin fichero es error de uso");
});

test("pair sin direcciones de escucha: error, sin ventana", async () => {
  const s = setup();
  assert.equal(await runCli(["pair"], s.deps), 1);
  assert.equal(existsSync(join(s.dir, "pairing.json")), false);
  assert.match(s.err.join("\n"), /ninguna dirección/);
});

test("pair desde un frontend de agente se rechaza", async () => {
  const s = setup({ env: { CLAUDECODE: "1" } });
  assert.equal(await runCli(["pair"], s.deps), 4);
});

test("configuración corrupta: stop, resume, help y uninstall siguen funcionando (el fail-safe no depende de ella)", async () => {
  const s = setup();
  (await import("node:fs")).writeFileSync(join(s.dir, "config.json"), "{ roto");
  assert.equal(await runCli(["q1"], s.deps), 1, "control: las preguntas sí fallan");
  assert.equal(await runCli(["stop", "config", "rota"], s.deps), 0);
  assert.ok(existsSync(join(s.dir, "STOP")));
  assert.equal(await runCli(["resume"], s.deps), 0);
  assert.equal(await runCli(["help"], s.deps), 0);
  s.out.length = 0;
  assert.equal(await runCli(["status", "--json"], s.deps), 1, "status responde aunque falle: diagnóstico y código 1");
  assert.equal(JSON.parse(s.out[0]).config_unreadable, true);
  assert.equal(await runCli(["uninstall", "--yes"], s.deps), 0);
  assert.equal(existsSync(s.dir), false);
});

test("correct mio no promete que «no volverá»", async () => {
  const s = setup();
  await runCli(["q2", "--json"], s.deps);
  const id = JSON.parse(s.out[0]).items[0].id;
  s.out.length = 0;
  assert.equal(await runCli(["correct", id, "mio"], s.deps), 0);
  assert.doesNotMatch(text(s), /No volverá/);
});

test("uninstall no borra lo que no es de Soul en el directorio de datos", async () => {
  const s = setup();
  await runCli(["q1"], s.deps);
  const fs = await import("node:fs");
  fs.writeFileSync(join(s.dir, "foto-ajena.jpg"), "x");
  fs.mkdirSync(join(s.dir, "carpeta-ajena"));
  fs.writeFileSync(join(s.dir, "carpeta-ajena", "nota.txt"), "y");
  assert.equal(await runCli(["uninstall", "--yes"], s.deps), 0);
  assert.ok(existsSync(join(s.dir, "foto-ajena.jpg")));
  assert.ok(existsSync(join(s.dir, "carpeta-ajena", "nota.txt")));
  assert.equal(existsSync(join(s.dir, "config.json")), false);
  assert.equal(fs.readdirSync(s.dir).filter((f) => f.startsWith("op-")).length, 0, "no queda estado de Soul");
});

test("correct mio tras resuelto: vuelve a aparecer también con --cached", async () => {
  const s = setup();
  await runCli(["q2", "--json"], s.deps);
  const id = JSON.parse(s.out[0]).items[0].id;
  await runCli(["correct", id, "resuelto"], s.deps);
  s.out.length = 0;
  await runCli(["q2", "--json"], s.deps); // relectura: la caché se reescribe tras la corrección
  assert.equal(JSON.parse(text(s)).items.length, 0, "control: resuelto lo oculta");
  await runCli(["correct", id, "mio"], s.deps);
  s.out.length = 0;
  await runCli(["q2", "--json", "--cached"], s.deps);
  assert.equal(JSON.parse(text(s)).items.length, 1, "mio lo restaura sin releer la fuente");
});

test("salida humana: si una fuente no se leyó, lo dice; no presenta «0» como «no tienes nada»", async () => {
  const s = setup();
  const cfg = JSON.parse(readFileSync(join(s.dir, "config.json"), "utf8"));
  cfg.profiles.yo.sources.push({ adapter: "jira", purpose: "tareas", consent: { granted_at: "2026-10-01T00:00:00Z" } });
  (await import("node:fs")).writeFileSync(join(s.dir, "config.json"), JSON.stringify(cfg));
  assert.equal(await runCli(["q4"], s.deps), 0);
  assert.match(text(s), /1 fuente\(s\) sin leer: jira/);
  s.out.length = 0;
  delete s.deps.adapters["m365-mail"];
  await runCli(["q1"], s.deps);
  assert.match(text(s), /2 fuente\(s\) sin leer/);
});

test("AC-4d: un agente no se sube de nivel declarando proveedor ni haciéndose pasar por otro frontend", async () => {
  const s = setup({ env: { CLAUDECODE: "1" }, providers: [{ id: "prov-org", approved_by: "seguridad", approved_at: "2026-10-30T00:00:00Z", scope: "N4", frontends: ["opencode"] }] });
  // `--provider` no existe: el proveedor solo se liga en config.json. Se prueba que un agente que lo
  // intenta igualmente (flag desconocido + argumento suelto) no gana nivel.
  for (const args of [["q1", "--json", "--provider", "prov-org"], ["q1", "--json", "--frontend", "opencode"]]) {
    s.out.length = 0;
    assert.equal(await runCli(args, s.deps), 0);
    assert.equal(JSON.parse(text(s)).detail, "recuentos", args.join(" "));
    assert.ok(!text(s).includes(TITLE));
  }
});

test("uninstall con el arranque automático instalado y la desactivación fallida: aviso y código 1, no «Desinstalado»", async () => {
  const s = setup();
  const o = { platform: s.deps.platform, home: s.deps.home, env: s.deps.env, node: s.deps.node, entry: s.deps.entry };
  for (const f of autostartPlan(o).files) { mkdirSync(dirname(f.path), { recursive: true }); writeFileSync(f.path, "x"); }
  s.deps.run = async (cmd, args) => { s.runs.push([cmd, ...args].join(" ")); return args.includes("disable") ? { code: 1, stdout: "", stderr: "Failed to connect to bus" } : { code: 0, stdout: "", stderr: "" }; };
  assert.equal(await runCli(["uninstall", "--yes"], s.deps), 1);
  assert.doesNotMatch(text(s), /^Desinstalado/);
  assert.match(s.err.join("\n"), /Failed to connect to bus/);
});

test("uninstall sin arranque instalado: el fallo de desactivar lo que nunca se activó no cuenta (control)", async () => {
  const s = setup();
  s.deps.run = async () => ({ code: 1, stdout: "", stderr: "Unit not found" });
  assert.equal(await runCli(["uninstall", "--yes"], s.deps), 0);
  assert.match(text(s), /^Desinstalado/);
});

test("q3 sin --since: código 2 sin leer ninguna fuente", async () => {
  const s = setup();
  let reads = 0;
  const base = adapter();
  s.deps.adapters = { "m365-mail": { ...base, read: async (ctx) => { reads++; return base.read(ctx); } } };
  assert.equal(await runCli(["q3"], s.deps), 2);
  assert.equal(reads, 0);
  assert.equal(await runCli(["q3", "--since", "2026-10-30T00:00:00Z"], s.deps), 1, "control: con --since lee (y no hay lectura anterior)");
  assert.equal(reads, 1);
});
