import { test } from "node:test";
import assert from "node:assert/strict";
import { validateClaim } from "../../src/contract/claims.ts";
import { Stop, check, claim, odataAll, safeRef, sameOrigin, token, toIso } from "../../src/adapters/common.ts";
import { ctxWith } from "./support.ts";

test("claim: TTL del descriptor, título limpio y marcado como no fiable", () => {
  const ctx = ctxWith({ now: "2026-11-02T08:00:00Z" });
  const c = claim(ctx, "m365-mail", "awaiting_reply", "c1@m1", { title: "  Hola‮\u0000 mundo  " });
  assert.deepEqual(validateClaim(c), []);
  assert.equal(c.title, "Hola mundo");
  assert.equal(c.untrusted_text, true);
  assert.equal(c.valid_until, "2026-11-02T08:30:00.000Z"); // m365-mail: 1800 s
  const sin = claim(ctx, "github", "mention", "r#1", {});
  assert.equal(sin.untrusted_text, undefined);
  assert.equal(sin.valid_until, "2026-11-02T09:00:00.000Z");
});

test("safeRef rechaza refs que romperían la clave", () => {
  assert.equal(safeRef("AAMk-1"), "AAMk-1");
  assert.equal(safeRef(42), "42");
  assert.equal(safeRef("a:b"), null);
  assert.equal(safeRef("a b"), null);
  assert.equal(safeRef(""), null);
  assert.equal(safeRef(null), null);
});

test("toIso: sin zona solo si la fuente declara UTC", () => {
  assert.equal(toIso("2026-11-02T09:00:00.0000000", true), "2026-11-02T09:00:00.000Z");
  assert.equal(toIso("2026-11-02T09:00:00+01:00"), "2026-11-02T08:00:00.000Z");
  assert.equal(toIso("ayer"), null);
});

test("check: cada estado HTTP a su estado del contrato", () => {
  const st = (status: number, opts = {}) => {
    try {
      check({ status, headers: {}, body: {} }, "X", opts);
      return "ok";
    } catch (e) {
      return (e as Stop).status;
    }
  };
  assert.equal(st(200), "ok");
  assert.equal(st(401), "token_expired");
  assert.equal(st(203), "token_expired");
  assert.equal(st(403), "error");
  assert.equal(st(403, { forbiddenIsConsent: true }), "admin_consent_required");
  assert.equal(st(429), "unavailable");
  assert.equal(st(500), "error");
  assert.throws(() => check({ status: 200, headers: {}, body: "<html>" }, "X"), Stop);
});

test("odataAll: tope de páginas falla cerrado, no devuelve datos parciales", async () => {
  let calls = 0;
  const ctx = ctxWith({
    transport: {
      async request(req) {
        calls++;
        const n = Number(new URL(req.url, "http://x").searchParams.get("p") ?? 0);
        return { status: 200, headers: {}, body: { value: [{ id: n }], "@odata.nextLink": `/v1.0/x?p=${n + 1}` } };
      },
    },
  });
  await assert.rejects(odataAll(ctx, "graph", "t", "/v1.0/x", "Graph", { maxPages: 3 }), (e: Stop) => e.status === "unavailable");
  assert.equal(calls, 3);
});

test("odataAll: lee todas las páginas por debajo del tope", async () => {
  const ctx = ctxWith({
    transport: {
      async request(req) {
        const n = Number(new URL(req.url, "http://x").searchParams.get("p") ?? 0);
        const body: Record<string, unknown> = { value: [{ id: n }] };
        if (n < 2) body["@odata.nextLink"] = `https://graph.example/v1.0/x?p=${n + 1}`;
        return { status: 200, headers: {}, body };
      },
    },
  });
  const all = await odataAll(ctx, "graph", "t", "/v1.0/x", "Graph", { maxPages: 3 });
  assert.deepEqual(all.map((x) => x.id), [0, 1, 2]);
});

test("sameOrigin: un enlace hacia otro host no se sigue con el token", () => {
  assert.equal(sameOrigin("https://a.example/v1.0/x?p=1", "https://a.example/v1.0/x", "G"), "https://a.example/v1.0/x?p=1");
  assert.throws(() => sameOrigin("https://malo.example/x", "https://a.example/v1.0/x", "G"), Stop);
  assert.equal(sameOrigin("https://cualquiera.example/v1.0/x?p=1", "/v1.0/x", "G"), "/v1.0/x?p=1");
});

test("token: traduce los errores del almacén por código, no por clase", async () => {
  const fail = (code: string) => ctxWith({ credentials: { async acquire() { throw Object.assign(new Error("x"), { code }); } } });
  await assert.rejects(token(fail("admin_consent_required"), "graph", ["Mail.Read"]),
    (e: Stop) => e.status === "admin_consent_required" && e.fallback === "web");
  await assert.rejects(token(fail("no_credential"), "graph", []), (e: Stop) => e.status === "token_expired");
  await assert.rejects(token(fail("session_expired"), "graph", []), (e: Stop) => e.status === "session_expired");
  const empty = ctxWith({ credentials: { async acquire() { return ""; } } });
  await assert.rejects(token(empty, "graph", []), (e: Stop) => e.status === "token_expired");
});
