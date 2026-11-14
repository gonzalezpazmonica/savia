/**
 * `soul source add|list` (SE-490, «Responsabilidad del operador»): conectar una fuente sin editar
 * config.json, con el consentimiento dado por la persona en su terminal. Y su enganche en `soul setup`.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { SourceAdapter } from "../src/contract/adapter.ts";
import { emptyConfig, loadConfig, saveConfig } from "../src/core/config.ts";
import { type CliDeps, runCli } from "../src/cli/cli.ts";
import { CONSENT_STATEMENT } from "../src/cli/source.ts";

const NOW = "2026-11-14T09:00:00Z";

function fakeGithub(): SourceAdapter {
  return {
    name: "github", routes: ["api"], purpose: "t",
    async read(ctx) { return { status: "ok", route: "api", claims: [], ...(ctx ? {} : {}) }; },
  };
}

interface S { dir: string; deps: CliDeps; out: string[]; err: string[]; asked: string[] }

function mk(o: { answers?: string[]; noAsk?: boolean; env?: Record<string, string>; profile?: boolean; raw?: string } = {}): S {
  const dir = mkdtempSync(join(tmpdir(), "soul-source-"));
  if (o.raw !== undefined) writeFileSync(join(dir, "config.json"), o.raw);
  else if (o.profile !== false) {
    const cfg = emptyConfig("inst-test");
    cfg.active_profile = "yo";
    cfg.profiles.yo = { operator: { ref: "op-yo", identities: { emails: ["yo@example.test"] } }, sources: [] };
    cfg.connectors = { enabled: [] };
    saveConfig(dir, cfg);
  }
  const out: string[] = [];
  const err: string[] = [];
  const asked: string[] = [];
  const answers = [...(o.answers ?? [])];
  const deps: CliDeps = {
    dataDir: dir, env: { ...(o.env ?? {}) }, now: () => NOW, out: (s) => out.push(s), err: (s) => err.push(s),
    adapters: { github: fakeGithub() },
    sourceEnv: { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => "t" } },
    credentials: { revoke: async () => ({ tokens_removed: 0, cache_removed: false }), forgetAll: async () => [] },
    platform: "linux", home: dir, run: async () => ({ code: 0, stdout: "", stderr: "" }), node: "/n/node", entry: "/e/soul.ts",
    ...(o.noAsk ? {} : { ask: async (q: string) => { asked.push(q); return answers.shift() ?? ""; } }),
  };
  return { dir, deps, out, err, asked };
}

const cfgText = (s: S) => readFileSync(join(s.dir, "config.json"), "utf8");

test("source add github con «s»: las tres piezas, el consentimiento literal y el motor la da por buena", async () => {
  const s = mk({ answers: ["s"] });
  assert.equal(await runCli(["source", "add", "github", "--purpose", "Revisiones y tareas", "--identity", "mi-usuario"], s.deps), 0, s.err.join("\n"));
  const c = loadConfig(s.dir);
  assert.deepEqual(c.connectors?.enabled, ["github"]);
  assert.equal(c.profiles.yo.sources.length, 1);
  const src = c.profiles.yo.sources[0];
  assert.equal(src.adapter, "github");
  assert.equal(src.purpose, "Revisiones y tareas");
  assert.equal(src.consent.granted_at, NOW);
  assert.equal(src.consent.statement, CONSENT_STATEMENT);
  assert.equal(c.profiles.yo.operator.identities.github, "mi-usuario");
  assert.match(s.out.join("\n"), /soul login github --token-stdin/);
  // El motor: sin consentimiento sería no_consent; con él, la fuente se lee.
  s.out.length = 0;
  assert.equal(await runCli(["adapters", "--json"], s.deps), 0, s.err.join("\n"));
  assert.equal(JSON.parse(s.out.join("\n")).adapters.github.status, "ok");
});

test("source add sin --purpose pregunta con un valor propuesto; Intro lo acepta y «s» consiente", async () => {
  const s = mk({ answers: ["", "s"] });
  assert.equal(await runCli(["source", "add", "jira"], s.deps), 0, s.err.join("\n"));
  assert.match(s.asked[0], /Incidencias asignadas a mí/);
  assert.equal(loadConfig(s.dir).profiles.yo.sources[0].purpose, "Incidencias asignadas a mí y no terminadas");
});

test("source add: la declaración se muestra antes de pedir la «s»", async () => {
  const s = mk({ answers: ["s"] });
  await runCli(["source", "add", "github", "--purpose", "X"], s.deps);
  const t = s.out.join("\n") + s.err.join("\n");
  assert.ok(t.includes(CONSENT_STATEMENT));
  assert.match(t, /soul revoke github/);
});

test("source add (negativo): una respuesta distinta de «s» no escribe nada", async () => {
  for (const a of ["", "n", "si", "sí", "S?", "claro"]) {
    const s = mk({ answers: [a] });
    const before = cfgText(s);
    assert.equal(await runCli(["source", "add", "github", "--purpose", "X"], s.deps), 1, `respuesta «${a}»`);
    assert.equal(cfgText(s), before, `respuesta «${a}»`);
  }
});

test("source add (negativo): adaptador desconocido, vacío y web se rechazan sin escribir", async () => {
  const s = mk({ answers: ["s", "s", "s"] });
  const before = cfgText(s);
  assert.equal(await runCli(["source", "add", "nope", "--purpose", "X"], s.deps), 2);
  assert.equal(await runCli(["source", "add"], s.deps), 2);
  assert.equal(await runCli(["source", "add", "web", "--purpose", "X"], s.deps), 2);
  assert.match(s.err.join("\n"), /web no se conecta con esta orden: tiene su propio flujo/);
  assert.equal(cfgText(s), before);
  assert.equal(s.asked.length, 0, "ni siquiera pregunta");
});

test("source add (negativo): sin terminal exige --purpose, y con él tampoco consiente por su cuenta", async () => {
  const a = mk({ noAsk: true });
  assert.equal(await runCli(["source", "add", "github"], a.deps), 2);
  assert.match(a.err.join("\n"), /--purpose/);
  const b = mk({ noAsk: true });
  const before = cfgText(b);
  assert.equal(await runCli(["source", "add", "github", "--purpose", "X"], b.deps), 2);
  assert.match(b.err.join("\n"), /terminal/);
  assert.equal(cfgText(b), before);
});

test("source add (negativo): desde un frontend de agente se rechaza con código 4 y no pregunta ni escribe", async () => {
  for (const env of [{ CLAUDECODE: "1" }, { OPENCODE: "1" }]) {
    const s = mk({ answers: ["s"], env });
    const before = cfgText(s);
    assert.equal(await runCli(["source", "add", "github", "--purpose", "X"], s.deps), 4);
    assert.equal(await runCli(["source", "list"], s.deps), 4);
    assert.equal(cfgText(s), before);
    assert.equal(s.asked.length, 0);
  }
});

test("source add (negativo): config.json roto no se pisa", async () => {
  const s = mk({ raw: "{ esto no es json", answers: ["s"] });
  assert.equal(await runCli(["source", "add", "github", "--purpose", "X"], s.deps), 1);
  assert.equal(cfgText(s), "{ esto no es json");
});

test("source add (negativo): sin perfil, código 3 y sin config nueva", async () => {
  const s = mk({ profile: false, answers: ["s"] });
  assert.equal(await runCli(["source", "add", "github", "--purpose", "X"], s.deps), 3);
  assert.ok(!existsSync(join(s.dir, "config.json")));
});

test("source add (negativo): una fuente ya activa no se duplica y lo dice", async () => {
  const s = mk({ answers: ["s", "s"] });
  await runCli(["source", "add", "github", "--purpose", "X"], s.deps);
  const once = cfgText(s);
  s.out.length = 0;
  assert.equal(await runCli(["source", "add", "github", "--purpose", "Y"], s.deps), 0);
  assert.match(s.out.join("\n"), /ya está activa/);
  assert.equal(cfgText(s), once);
  assert.equal(s.asked.length, 1, "la segunda vez no pide otro consentimiento");
});

test("source add: tras revoke se puede volver a activar con consentimiento nuevo, sin duplicar", async () => {
  const s = mk({ answers: ["s", "s"] });
  await runCli(["source", "add", "github", "--purpose", "X"], s.deps);
  assert.equal(await runCli(["revoke", "github"], s.deps), 0);
  assert.equal(await runCli(["source", "add", "github", "--purpose", "Z"], s.deps), 0, s.err.join("\n"));
  const c = loadConfig(s.dir);
  assert.equal(c.profiles.yo.sources.length, 1);
  assert.equal(c.profiles.yo.sources[0].consent.revoked_at, undefined);
  assert.deepEqual(c.connectors?.enabled, ["github"]);
});

test("source add: --identity según el adaptador, y un valor no válido no escribe", async () => {
  const s = mk({ answers: ["s", "s", "s"] });
  assert.equal(await runCli(["source", "add", "jira", "--purpose", "X", "--identity", "acc-123"], s.deps), 0);
  assert.equal(await runCli(["source", "add", "azure-devops", "--purpose", "X", "--identity", "ado-9"], s.deps), 0);
  assert.equal(await runCli(["source", "add", "m365-mail", "--purpose", "X", "--identity", "otro@example.test"], s.deps), 0);
  const id = loadConfig(s.dir).profiles.yo.operator.identities;
  assert.equal(id.jira_account, "acc-123");
  assert.equal(id.ado_id, "ado-9");
  assert.deepEqual(id.emails, ["yo@example.test", "otro@example.test"]);
  const t = mk({ answers: ["s"] });
  const before = cfgText(t);
  assert.equal(await runCli(["source", "add", "google-workspace", "--purpose", "X", "--identity", "no es correo"], t.deps), 2);
  assert.equal(cfgText(t), before);
});

test("source add (negativo): --purpose vacío o con saltos de línea no vale", async () => {
  const s = mk({ answers: ["s", "s"] });
  const before = cfgText(s);
  assert.equal(await runCli(["source", "add", "github", "--purpose", "a\nb"], s.deps), 2);
  assert.equal(await runCli(["source", "add", "github", "--purpose", "x".repeat(201)], s.deps), 2);
  assert.equal(cfgText(s), before);
});

test("source add: si la instalación ya audita, deja una entrada; si no, no crea el fichero", async () => {
  const s = mk({ answers: ["s"] });
  await runCli(["source", "add", "github", "--purpose", "X"], s.deps);
  assert.ok(!existsSync(join(s.dir, "audit.jsonl")), "sin auditoría previa no se crea");
  const t = mk({ answers: ["s"] });
  writeFileSync(join(t.dir, "audit.jsonl"), "");
  await runCli(["source", "add", "github", "--purpose", "X"], t.deps);
  const rows = readFileSync(join(t.dir, "audit.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.equal(rows.length, 1);
  assert.equal(rows[0].cmd, "source add github");
  assert.equal(rows[0].exit, 0);
  assert.equal(rows[0].frontend, null);
});

test("source list: fuentes del perfil con su estado; vacío lo dice", async () => {
  const s = mk({ answers: ["s"] });
  assert.equal(await runCli(["source", "list"], s.deps), 0);
  assert.match(s.out.join("\n"), /Sin fuentes/);
  await runCli(["source", "add", "github", "--purpose", "X"], s.deps);
  await runCli(["revoke", "github"], s.deps);
  s.out.length = 0;
  assert.equal(await runCli(["source", "list"], s.deps), 0);
  assert.match(s.out.join("\n"), /github: revocada/);
  assert.equal(await runCli(["source", "borrar"], s.deps), 2);
});

// ------------------------------------------------------------------ setup

/** Instalación ya hecha con VPN: setup solo pregunta servicio, emparejar y (nuevo) la fuente. */
function mkSetup(answers: string[]): S {
  const s = mk({ answers });
  const c = loadConfig(s.dir);
  c.api.listen = ["100.101.7.3"];
  saveConfig(s.dir, c);
  s.deps.ifaces = () => ({ tailscale0: [{ address: "100.101.7.3", family: "IPv4", internal: false, netmask: "255.192.0.0", mac: "00:00:00:00:00:00", cidr: null }] });
  s.deps.reachable = async () => true;
  s.deps.env = { PATH: "" };
  return s;
}

test("setup ofrece conectar una fuente al final; Intro no añade nada", async () => {
  const s = mkSetup(["", "n", ""]);
  assert.equal(await runCli(["setup"], s.deps), 0, s.err.join("\n"));
  assert.ok(s.asked.some((q) => /conectar una fuente ahora/.test(q)), s.asked.join("|"));
  assert.deepEqual(loadConfig(s.dir).profiles.yo.sources, []);
  assert.deepEqual(loadConfig(s.dir).connectors?.enabled, []);
});

test("setup: responder el nombre de un adaptador llama a source add y conecta esa fuente con consentimiento", async () => {
  const s = mkSetup(["", "n", "github", "", "s"]);
  assert.equal(await runCli(["setup"], s.deps), 0, s.err.join("\n"));
  const src = loadConfig(s.dir).profiles.yo.sources;
  assert.equal(src.length, 1, s.asked.join("|") + s.err.join("|"));
  assert.equal(src[0].adapter, "github");
  assert.equal(src[0].consent.statement, CONSENT_STATEMENT);
  assert.match(s.out.join("\n"), /soul login github/);
});

test("setup (negativo): un nombre que no es adaptador no escribe nada y no rompe setup", async () => {
  const s = mkSetup(["", "n", "web"]);
  assert.equal(await runCli(["setup"], s.deps), 0, s.err.join("\n"));
  assert.deepEqual(loadConfig(s.dir).profiles.yo.sources, []);
  assert.match(s.err.join("\n"), /web no se conecta con esta orden/);
});

test("setup (negativo): si la persona no da la «s», la fuente no se conecta", async () => {
  const s = mkSetup(["", "n", "github", "", "n"]);
  assert.equal(await runCli(["setup"], s.deps), 0, s.err.join("\n"));
  assert.deepEqual(loadConfig(s.dir).profiles.yo.sources, []);
});
