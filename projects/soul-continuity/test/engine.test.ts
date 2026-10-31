import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { InstallationConfig, SourceAdapter } from "../src/contract/adapter.ts";
import { makeEngine } from "../src/core/engine.ts";
import { StoppedError, stop } from "../src/core/failsafe.ts";
import { filesUnder } from "../src/core/store.ts";

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

test("applyCorrections aplica el libro actual a una instantánea guardada", async () => {
  const e = makeEngine({ github: fakeGithub({ n: 0 }) });
  const stateDir = tmp();
  const inst = install("op-a", [{ adapter: "github", purpose: "p", consent }]);
  const s = await e.snapshot({ install: inst, now: NOW, stateDir, env });
  await e.correct({ install: inst, stateDir, now: NOW, key: "github:review_request:r1#7", action: "revoke" });
  assert.equal(s.claims[0].state, "OBSERVED");
  assert.equal(e.applyCorrections(s, stateDir, NOW).claims[0].state, "REVOKED");
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
