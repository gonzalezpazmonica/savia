import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { InstallationConfig, SourceAdapter } from "../src/contract/adapter.ts";
import { makeEngine } from "../src/core/engine.ts";
import { StoppedError, stop } from "../src/core/failsafe.ts";
import { filesUnder, operatorDirName } from "../src/core/store.ts";

const NOW = "2026-10-31T09:00:00Z";
const tmp = () => mkdtempSync(join(tmpdir(), "soul-en-"));

function install(ref: string, sources: InstallationConfig["sources"] = []): InstallationConfig {
  return { id: "i1", operator: { ref, identities: { emails: [`${ref}@example.test`] } }, sources };
}

const consent = { granted_at: "2026-10-01T00:00:00Z" };

/** Adaptador falso de GitHub que devuelve siempre la misma revisión pedida. */
function fakeGithub(calls: { n: number }): SourceAdapter {
  return {
    name: "github", routes: ["api"], purpose: "test",
    async read(ctx) {
      calls.n++;
      await ctx.credentials.acquire("github", ["repo"]); // el token entra en memoria del proceso

      return {
        status: "ok", route: "api", claims: [{
          key: "github:review_request:r1#7", claim_type: "review_request", state: "OBSERVED",
          source_refs: [{ adapter: "github", route: "api", ref: "r1#7" }], sensitivity: ctx.sensitivity,
          observed_at: ctx.now, valid_until: "2026-10-31T10:00:00Z", open: true, awaiting_operator: true, attrs: {},
          title: "Revisa esto", untrusted_text: true,
        }],
      };
    },
  };
}

const TOKEN = "tok-canario-engine-7f3a";
const env = { transport: { request: async () => ({ status: 500, headers: {}, body: null }) }, credentials: { acquire: async () => TOKEN } };

test("lo revocado no vuelve aunque la fuente lo repita", async () => {
  const calls = { n: 0 };
  const e = makeEngine({ github: fakeGithub(calls) });
  const stateDir = tmp();
  const inst = install("op-a", [{ adapter: "github", purpose: "p", consent }]);
  const s1 = await e.snapshot({ install: inst, now: NOW, stateDir, env });
  assert.equal(s1.claims[0].state, "OBSERVED");
  await e.correct({ install: inst, stateDir, now: NOW, key: "github:review_request:r1#7", action: "revoke" });
  const s2 = await e.snapshot({ install: inst, now: NOW, stateDir, env });
  assert.equal(s2.claims[0].state, "REVOKED");
  assert.equal(e.answer(s2, { q: "Q1" }, { install: inst, now: NOW }).items.length, 0);
});

test("el libro es por operador: la corrección de A no afecta a B", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  const a = install("op-a", [{ adapter: "github", purpose: "p", consent }]);
  const b = install("op-b", [{ adapter: "github", purpose: "p", consent }]);
  await e.correct({ install: a, stateDir, now: NOW, key: "github:review_request:r1#7", action: "revoke" });
  const sb = await e.snapshot({ install: b, now: NOW, stateDir, env });
  assert.equal(sb.claims[0].state, "OBSERVED");
});

test("adaptador configurado pero no instalado: falla cerrado, sin afirmaciones", async () => {
  const e = makeEngine({});
  const s = await e.snapshot({ install: install("op-a", [{ adapter: "jira", purpose: "p", consent }]), now: NOW, stateDir: tmp(), env });
  assert.equal(s.adapters.jira.status, "unavailable");
  assert.ok(s.adapters.jira.message);
  assert.equal(s.claims.length, 0);
});

test("sin consentimiento no se llama al adaptador", async () => {
  const calls = { n: 0 };
  const e = makeEngine({ github: fakeGithub(calls) });
  const s = await e.snapshot({ install: install("op-a", [{ adapter: "github", purpose: "p", consent: { granted_at: null } }]), now: NOW, stateDir: tmp(), env });
  assert.equal(s.adapters.github.status, "no_consent");
  assert.equal(calls.n, 0);
});

test("con STOP no se lee ninguna fuente", async () => {
  const calls = { n: 0 };
  const e = makeEngine({ github: fakeGithub(calls) });
  const stateDir = tmp();
  stop(stateDir, "operador", NOW);
  await assert.rejects(e.snapshot({ install: install("op-a", [{ adapter: "github", purpose: "p", consent }]), now: NOW, stateDir, env }), StoppedError);
  assert.equal(calls.n, 0);
});

test("la caché del operador solo guarda metadatos: ni cuerpos ni el token", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  await e.snapshot({ install: install("op-a", [{ adapter: "github", purpose: "p", consent }]), now: NOW, stateDir, env });
  const all = filesUnder(stateDir).map((f) => readFileSync(f, "utf8")).join("\n");
  assert.ok(all.includes("r1#7"));
  assert.ok(!all.includes(TOKEN), "el token del almacén no se persiste");
});

test("lastSnapshot devuelve la última instantánea del operador y null para otro", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  await e.snapshot({ install: install("op-a", [{ adapter: "github", purpose: "p", consent }]), now: NOW, stateDir, env });
  assert.equal(e.lastSnapshot(stateDir, "op-a")?.operator_ref, "op-a");
  assert.equal(e.lastSnapshot(stateDir, "op-b"), null);
});

test("cachedSnapshot aplica el libro vigente a la caché, también una restauración posterior a una revocación", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  const inst = install("op-a", [{ adapter: "github", purpose: "p", consent }]);
  const key = "github:review_request:r1#7";
  await e.correct({ install: inst, stateDir, now: NOW, key, action: "revoke" });
  await e.snapshot({ install: inst, now: NOW, stateDir, env }); // la caché se escribe con el elemento revocado
  assert.equal(e.cachedSnapshot(stateDir, "op-a", NOW)?.claims[0].state, "REVOKED");
  await e.correct({ install: inst, stateDir, now: NOW, key, action: "restore" });
  assert.equal(e.cachedSnapshot(stateDir, "op-a", NOW)?.claims[0].state, "OBSERVED");
  assert.equal(e.lastSnapshot(stateDir, "op-a")?.claims[0].state, "OBSERVED");
  assert.equal(e.cachedSnapshot(stateDir, "op-a", "2026-10-31T11:00:00Z")?.claims[0].state, "EXPIRED", "y el TTL se evalúa al leer");
});

test("purgeAdapter borra las afirmaciones del adaptador en la caché y en el historial", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  await e.snapshot({ install: install("op-a", [{ adapter: "github", purpose: "p", consent }]), now: NOW, stateDir, env });
  assert.ok(e.purgeAdapter(stateDir, "op-a", "github") >= 2);
  const all = filesUnder(stateDir).map((f) => readFileSync(f, "utf8")).join("\n");
  assert.ok(!all.includes("r1#7"));
  assert.equal(e.lastSnapshot(stateDir, "op-a")?.adapters.github.status, "consent_revoked");
});

test("historial de Q3: con una lectura cada 5 min se conserva el día anterior (poda por antigüedad)", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  const inst = install("op-a", [{ adapter: "github", purpose: "p", consent }]);
  const t0 = Date.parse("2026-10-30T08:00:00Z");
  for (let i = 0; i <= 12 * 30; i++) { // 30 h de lecturas cada 5 min
    await e.snapshot({ install: inst, now: new Date(t0 + i * 300_000).toISOString(), stateDir, env });
  }
  const now = new Date(t0 + 30 * 3_600_000).toISOString();
  assert.ok(e.snapshotAt(stateDir, "op-a", "2026-10-30T09:30:00Z"), "lo de ayer por la mañana sigue");
  assert.ok(e.snapshotAt(stateDir, "op-a", new Date(Date.parse(now) - 20 * 60_000).toISOString()), "y lo reciente con detalle");
  const files = readdirSync(join(stateDir, operatorDirName("op-a"), "history")).length;
  assert.ok(files <= 24 + 24 * 7 + 1, `historial acotado (${files})`);
});

test("resultado de adaptador mal formado: falla cerrado solo ese adaptador, el resto sigue", async () => {
  const bad: SourceAdapter = { name: "jira", routes: ["api"], purpose: "t", async read() { return { status: "ok", route: "api", claims: [{ key: "jira:task_assigned:X", claim_type: "task_assigned" }] } as never; } };
  const e = makeEngine({ github: fakeGithub({ n: 0 }), jira: bad });
  const s = await e.snapshot({ install: install("op-a", [{ adapter: "github", purpose: "p", consent }, { adapter: "jira", purpose: "p", consent }]), now: NOW, stateDir: tmp(), env });
  assert.equal(s.adapters.jira.status, "error");
  assert.equal(s.adapters.github.status, "ok");
  assert.deepEqual(s.claims.map((c) => c.key), ["github:review_request:r1#7"]);
});

test("historial: un instante con offset o sin segundos se guarda y sirve de base a Q3", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  const inst = install("op-a", [{ adapter: "github", purpose: "p", consent }]);
  await e.snapshot({ install: inst, now: "2026-10-31T11:00+02:00", stateDir, env });
  const h = readdirSync(join(stateDir, operatorDirName("op-a"), "history"));
  assert.deepEqual(h, ["2026-10-31T09-00-00-000Z.json"], "nombre normalizado a UTC");
  assert.ok(e.snapshotAt(stateDir, "op-a", "2026-10-31T09:01:00Z"), "la instantánea recién escrita no se poda");
  // control: con la misma hora en Z también
  await e.snapshot({ install: inst, now: "2026-10-31T09:05:00Z", stateDir, env });
  assert.equal(readdirSync(join(stateDir, operatorDirName("op-a"), "history")).length, 2);
});

test("correct usa la misma regla de clave que el libro: lo que el libro ignoraría no se escribe", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  const inst = install("op-a", [{ adapter: "github", purpose: "p", consent }]);
  for (const bad of ["GitHub:review_request:r1#7", "github:review_request:r1 7", "git hub:review_request:r1#7"]) {
    await assert.rejects(e.correct({ install: inst, stateDir, now: NOW, key: bad, action: "revoke" }), /clave inválida/, bad);
  }
  assert.equal(e.ledger(stateDir, "op-a").length, 0);
  // control: una clave válida sí entra en el libro y tiene efecto
  await e.correct({ install: inst, stateDir, now: NOW, key: "github:review_request:r1#7", action: "revoke" });
  assert.equal(e.ledger(stateDir, "op-a").length, 1);
});

/** Adaptador de Jira que refleja el token recibido del almacén en el campo indicado. */
function leakyJira(where: "title" | "attrs" | "extra" | "message" | "none"): SourceAdapter {
  return {
    name: "jira", routes: ["api"], purpose: "test",
    async read(ctx) {
      const tok = await ctx.credentials.acquire("jira", ["read"]);
      if (where === "message") return { status: "error", route: "api", message: `fallo con ${tok}` };
      const claim: any = {
        key: "jira:task_assigned:J-1", claim_type: "task_assigned", state: "OBSERVED",
        source_refs: [{ adapter: "jira", route: "api", ref: "J-1" }], sensitivity: ctx.sensitivity,
        observed_at: ctx.now, valid_until: "2026-10-31T10:00:00Z", open: true, awaiting_operator: true,
        attrs: where === "attrs" ? { etag: `W/${tok}` } : {},
        title: where === "title" ? `Tarea ${tok}` : "Tarea", untrusted_text: true,
      };
      if (where === "extra") claim.raw = { authorization: `Bearer ${tok}` };
      return { status: "ok", route: "api", claims: [claim] };
    },
  };
}

for (const where of ["title", "attrs", "extra", "message"] as const) {
  test(`un adaptador que devuelve el token (en ${where}) no lo lleva a disco y se descarta su lectura`, async () => {
    const e = makeEngine({ github: fakeGithub({ n: 0 }), jira: leakyJira(where) });
    const stateDir = tmp();
    const inst = install("op-a", [{ adapter: "github", purpose: "p", consent }, { adapter: "jira", purpose: "p", consent }]);
    const s = await e.snapshot({ install: inst, now: NOW, stateDir, env });
    const all = filesUnder(stateDir).map((f) => readFileSync(f, "utf8")).join("\n");
    assert.ok(all.includes("r1#7"), "control: lo del adaptador limpio sí se guarda");
    assert.ok(!all.includes(TOKEN), "0 tokens en disco");
    assert.ok(!JSON.stringify(s).includes(TOKEN), "ni en la instantánea devuelta");
    assert.equal(s.adapters.jira.status, "error");
    assert.ok(!s.claims.some((c) => c.key.startsWith("jira:")));
  });
}

test("el token se detecta también escapado en JSON; sin reflejo, la lectura cuenta", async () => {
  const QUOTED = 'tok"con\\comillas';
  const e = makeEngine({ jira: leakyJira("title") });
  const stateDir = tmp();
  const inst = install("op-a", [{ adapter: "jira", purpose: "p", consent }]);
  const s = await e.snapshot({ install: inst, now: NOW, stateDir, env: { ...env, credentials: { acquire: async () => QUOTED } } });
  assert.equal(s.adapters.jira.status, "error");
  assert.ok(!filesUnder(stateDir).some((f) => readFileSync(f, "utf8").includes(JSON.stringify(QUOTED).slice(1, -1))));
  const ok = await makeEngine({ jira: leakyJira("none") }).snapshot({ install: inst, now: NOW, stateDir: tmp(), env });
  assert.equal(ok.adapters.jira.status, "ok", "control negativo: un adaptador que no refleja el token no se descarta");
});

test("una instantánea corrupta en el historial no tumba Q3 ni la purga, y la purga la elimina", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  const inst = install("op-a", [{ adapter: "github", purpose: "p", consent }]);
  await e.snapshot({ install: inst, now: NOW, stateDir, env });
  await e.snapshot({ install: inst, now: "2026-10-31T09:05:00Z", stateDir, env });
  const h = join(stateDir, operatorDirName("op-a"), "history");
  const files = readdirSync(h).sort();
  assert.equal(files.length, 2);
  writeFileSync(join(h, files[1]), '{"schema":"se490/snap'); // corte a mitad de escritura
  assert.equal(e.snapshotAt(stateDir, "op-a", "2026-10-31T09:10:00Z")?.issued_at, NOW, "se usa la legible anterior");
  assert.ok(e.purgeAdapter(stateDir, "op-a", "github") >= 2);
  assert.deepEqual(readdirSync(h), [files[0]], "la ilegible se borra: no se puede filtrar");
  assert.ok(!filesUnder(stateDir).map((f) => readFileSync(f, "utf8")).join("\n").includes("r1#7"), "y nada del adaptador queda");
});
