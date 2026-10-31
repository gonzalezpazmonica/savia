import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { SourceAdapter } from "../src/contract/adapter.ts";
import { emptyConfig, saveConfig } from "../src/core/config.ts";
import { filesUnder } from "../src/core/store.ts";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import type { Run } from "../src/credentials/store.ts";

const NOW = "2026-10-31T09:00:00Z";
const TITLE = "Asunto-confidencial-de-tercero";
const PERSON = "persona.tercera@example.test";

function adapter(): SourceAdapter {
  return {
    name: "m365-mail", routes: ["graph"], purpose: "t",
    async read(ctx) {
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
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "tok" } },
    credentials: { forget: async (s: string) => { forgotten.push(s); return [s]; }, forgetAll: async () => { forgotten.push("*"); return []; } },
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
  const t0 = performance.now();
  assert.equal(await runCli(["status", "--json"], s.deps), 0);
  assert.ok(performance.now() - t0 < 1000);
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
  const s = setup({ env: { CLAUDECODE: "1", SOUL_AGENT_PROVIDER: "prov-org" }, providers: [{ id: "prov-org", approved_by: "seguridad de la organización", approved_at: "2026-10-30T00:00:00Z", scope: "N4" }] });
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
});

test("AC-5: revoke borra la caché del adaptador y su credencial, y deja de leerlo", async () => {
  const s = setup();
  await runCli(["q1", "--json"], s.deps);
  assert.ok(filesUnder(s.dir).some((f) => readFileSync(f, "utf8").includes("c1@m1")));
  assert.equal(await runCli(["revoke", "m365-mail"], s.deps), 0);
  assert.ok(!filesUnder(s.dir).some((f) => readFileSync(f, "utf8").includes("c1@m1")), "caché del adaptador borrada");
  assert.deepEqual(s.forgotten, ["m365-mail"]);
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
  assert.ok(!text(s).includes('"tok"'));
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

test("pair: token una sola vez, huella del certificado y direcciones; en disco solo el hash", async () => {
  const s = setup();
  const cfg = JSON.parse(readFileSync(join(s.dir, "config.json"), "utf8"));
  cfg.api = { listen: ["127.0.0.1"], port: 8787 };
  (await import("node:fs")).writeFileSync(join(s.dir, "config.json"), JSON.stringify(cfg));
  assert.equal(await runCli(["pair", "movil", "--json"], s.deps), 0);
  const j = JSON.parse(text(s));
  assert.match(j.token, /^[A-Za-z0-9_-]{43}$/);
  assert.match(j.pin, /^sha256\//);
  assert.deepEqual(j.direcciones, ["127.0.0.1:8787"]);
  assert.ok(!filesUnder(s.dir).some((f) => readFileSync(f, "utf8").includes(j.token)));
  s.out.length = 0;
  assert.equal(await runCli(["devices", "--json"], s.deps), 0);
  assert.equal(JSON.parse(text(s)).devices[0].name, "movil");
  assert.ok(!text(s).includes("token_sha256"), "devices no enseña ni el hash");
  assert.equal(await runCli(["unpair", j.id], s.deps), 0);
  assert.equal(await runCli(["unpair", "d-nada"], s.deps), 1);
});

test("pair sin direcciones de escucha: error, sin token", async () => {
  const s = setup();
  assert.equal(await runCli(["pair", "movil"], s.deps), 1);
  assert.match(s.err.join("\n"), /ninguna dirección/);
});

test("pair desde un frontend de agente se rechaza", async () => {
  const s = setup({ env: { CLAUDECODE: "1" } });
  assert.equal(await runCli(["pair", "movil"], s.deps), 4);
});

test("configuración corrupta: stop, resume, help y uninstall siguen funcionando (el fail-safe no depende de ella)", async () => {
  const s = setup();
  (await import("node:fs")).writeFileSync(join(s.dir, "config.json"), "{ roto");
  assert.equal(await runCli(["q1"], s.deps), 1, "control: las preguntas sí fallan");
  assert.equal(await runCli(["stop", "config", "rota"], s.deps), 0);
  assert.ok(existsSync(join(s.dir, "STOP")));
  assert.equal(await runCli(["resume"], s.deps), 0);
  assert.equal(await runCli(["help"], s.deps), 0);
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
