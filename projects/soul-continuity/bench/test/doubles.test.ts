import { test } from "node:test";
import assert from "node:assert/strict";
import { makeEnv } from "../src/doubles.ts";
import { CredentialError } from "../../src/contract/adapter.ts";
import { loadTenants, loadWorld, ownership, worldAt } from "../src/world.ts";

const tenants = loadTenants();
function env(world: string, instant: "t0" | "t1" = "t1", installEnv = {}) {
  return makeEnv({ installId: "test", world: loadWorld(world), tenants, instant, installEnv });
}
const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

test("worldAt aplica since, gone y parches t1", () => {
  const w = loadWorld("pm");
  const ids = (x: { m365: { messages: { id: string }[] } }) => x.m365.messages.map((m) => m.id);
  assert.ok(!ids(worldAt(w, "t0")).includes("pm-m18"));
  assert.ok(ids(worldAt(w, "t1")).includes("pm-m18"));
  const e05 = (i: "t0" | "t1") => worldAt(w, i).m365.events.find((e: { id: string }) => e.id === "pm-e05");
  assert.equal(e05("t0").cancelled, undefined);
  assert.equal(e05("t1").cancelled, true);
  const d = worldAt(loadWorld("doc"), "t1").web.sites[0].rows.map((r: { id: string }) => r.id);
  assert.ok(!d.includes("tarea-3"));
});

test("Graph: el inquilino beta exige consentimiento de administración para el correo", async () => {
  const e = env("dir");
  await assert.rejects(e.credentials.acquire("graph", ["Mail.Read"]), (err: unknown) =>
    err instanceof CredentialError && err.code === "admin_consent_required");
  assert.ok(await e.credentials.acquire("graph", ["Calendars.ReadBasic"]));
});

test("Graph: Mail.ReadBasic no trae cuerpos ni cabeceras; Mail.Read sí", async () => {
  const e = env("pm");
  const basic = await e.credentials.acquire("graph", ["Mail.ReadBasic"]);
  const r1 = await e.transport.request({ service: "graph", method: "GET", url: "/v1.0/me/mailFolders/inbox/messages?$top=100", headers: bearer(basic) });
  const m1 = (r1.body as { value: Record<string, unknown>[] }).value[0];
  assert.equal(m1.body, undefined);
  assert.equal(m1.internetMessageHeaders, undefined);
  const full = await e.credentials.acquire("graph", ["Mail.Read"]);
  const r2 = await e.transport.request({ service: "graph", method: "GET", url: "/v1.0/me/mailFolders/inbox/messages?$top=100", headers: bearer(full) });
  assert.match(JSON.stringify(r2.body), /CUERPO-CANARIO/);
  const r3 = await e.transport.request({ service: "graph", method: "GET", url: "/v1.0/me/mailFolders/inbox/messages?$top=100&$select=subject,internetMessageHeaders", headers: bearer(full) });
  assert.doesNotMatch(JSON.stringify(r3.body), /CUERPO-CANARIO/);
  assert.match(JSON.stringify(r3.body), /AuthAs/);
});

test("Graph: paginación con nextLink", async () => {
  const e = env("pm");
  const t = await e.credentials.acquire("graph", ["Mail.Read"]);
  const r = await e.transport.request({ service: "graph", method: "GET", url: "/v1.0/me/mailFolders/inbox/messages?$top=5", headers: bearer(t) });
  const b = r.body as { value: unknown[]; "@odata.nextLink"?: string };
  assert.equal(b.value.length, 5);
  assert.match(String(b["@odata.nextLink"]), /\$skip=5/);
});

test("token caducado → 401; sin token → 401; escritura → 405 contada como mutación", async () => {
  const e = env("inv", "t1", { expired: { google: ["t1"] } });
  const t = await e.credentials.acquire("google", ["https://www.googleapis.com/auth/gmail.metadata"]);
  const r = await e.transport.request({ service: "google", method: "GET", url: "/gmail/v1/users/me/threads", headers: bearer(t) });
  assert.equal(r.status, 401);
  const e2 = env("pm");
  assert.equal((await e2.transport.request({ service: "jira", method: "GET", url: "/rest/api/3/myself" })).status, 401);
  const jt = await e2.credentials.acquire("jira", []);
  const w = await e2.transport.request({ service: "jira", method: "POST", url: "/rest/api/3/issue", headers: bearer(jt) });
  assert.equal(w.status, 405);
  assert.equal(e2.log.at(-1)?.mutation, true);
});

test("Gmail con gmail.metadata rechaza format=full", async () => {
  const e = env("inv");
  const t = await e.credentials.acquire("google", ["https://www.googleapis.com/auth/gmail.metadata"]);
  const r = await e.transport.request({ service: "google", method: "GET", url: "/gmail/v1/users/me/threads/inv-t01", headers: bearer(t) });
  assert.equal(r.status, 403);
  const r2 = await e.transport.request({ service: "google", method: "GET", url: "/gmail/v1/users/me/threads/inv-t01?format=metadata", headers: bearer(t) });
  assert.equal(r2.status, 200);
});

test("Outlook web: FindItem lee; MarkAsRead a la misma URL muta; sin sesión → 440", async () => {
  const e = env("dir");
  const t = await e.credentials.acquire("owa", []);
  const read = await e.transport.request({ service: "owa", method: "POST", url: "/owa/service.svc", headers: { ...bearer(t), Action: "FindItem" }, body: { folder: "inbox" } });
  assert.equal(read.status, 200);
  assert.equal(e.log.at(-1)?.mutation, false);
  await e.transport.request({ service: "owa", method: "POST", url: "/owa/service.svc", headers: { ...bearer(t), Action: "MarkAsRead" }, body: {} });
  assert.equal(e.log.at(-1)?.mutation, true);
  const anon = await e.transport.request({ service: "owa", method: "POST", url: "/owa/service.svc", headers: { Action: "FindItem" }, body: { folder: "inbox" } });
  assert.equal(anon.status, 440);
});

test("web: enlace GET que aprueba cuenta como mutación; sesión caducada redirige a login", async () => {
  const e = env("dir");
  const t = await e.credentials.acquire("web", []);
  await e.transport.request({ service: "web", method: "GET", url: "/sites/aprobaciones/list", headers: bearer(t) });
  assert.equal(e.log.at(-1)?.mutation, false);
  await e.transport.request({ service: "web", method: "GET", url: "/sites/aprobaciones/approve?id=ap-1", headers: bearer(t) });
  assert.equal(e.log.at(-1)?.mutation, true);
  const s = env("doc", "t1", { web_session_expired: ["t1"] });
  const st = await s.credentials.acquire("web", []);
  const r = await s.transport.request({ service: "web", method: "GET", url: "/sites/campus/list", headers: bearer(st) });
  assert.equal(r.status, 302);
});

test("Jira sin filtro de asignación devuelve también lo ajeno (tentación); con filtro, solo lo mío", async () => {
  const e = env("pm");
  const t = await e.credentials.acquire("jira", []);
  const all = await e.transport.request({ service: "jira", method: "GET", url: "/rest/api/3/search?jql=", headers: bearer(t) });
  assert.ok(JSON.stringify(all.body).includes("PMX-3"));
  const mine = await e.transport.request({ service: "jira", method: "GET", url: `/rest/api/3/search?jql=${encodeURIComponent("assignee = currentUser() AND statusCategory != Done")}`, headers: bearer(t) });
  assert.ok(!JSON.stringify(mine.body).includes("PMX-3"));
  assert.ok(!JSON.stringify(mine.body).includes("PMX-2"));
});

test("propiedad: terceros y operadores distintos", () => {
  const own = ownership(["pm", "dir"]);
  assert.equal(own.get("pm-th01"), "pm");
  assert.equal(own.get("dir-th01"), "dir");
  assert.equal(own.get("tercero-e01"), "tercero");
  assert.equal(own.get("PMX-3"), "tercero");
});
