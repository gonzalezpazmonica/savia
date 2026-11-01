import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import {
  ForeignClientError, assertOwnClient, browserFlow, classifyOAuthError, deviceFlow, googleProvider, microsoftProvider, refreshToken,
} from "../../src/adapters/oauth.ts";

const CLIENT = { client_id: "11111111-2222-4333-8444-555555555555", owner: "organization" as const };

interface Mode { device: "ok" | "admin" | "declined"; pendings: number; slowDown: boolean; refresh: "ok" | "expired" | "admin" | "unconsented" }

async function idp(mode: Mode) {
  const seen: { path: string; form: URLSearchParams }[] = [];
  const challenges = new Map<string, string>(); // code → challenge
  let polls = 0;
  const srv = createServer((req: IncomingMessage, res: ServerResponse) => {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", () => {
      const u = new URL(req.url ?? "/", "http://idp");
      const form = new URLSearchParams(raw);
      seen.push({ path: u.pathname, form });
      const send = (status: number, body: unknown) => { res.writeHead(status, { "content-type": "application/json" }); res.end(JSON.stringify(body)); };
      if (u.pathname.endsWith("/devicecode")) {
        return send(200, { device_code: "dev-1", user_code: "ABCD-EFGH", verification_uri: "https://login.example/device", interval: 1, expires_in: 900 });
      }
      if (u.pathname === "/authorize-sim") {
        // El «navegador» de los tests registra el challenge para este código.
        challenges.set(String(u.searchParams.get("code")), String(u.searchParams.get("challenge")));
        return send(200, {});
      }
      if (u.pathname.endsWith("/token")) {
        const g = form.get("grant_type");
        if (g === "urn:ietf:params:oauth:grant-type:device_code") {
          if (mode.device === "admin") return send(400, { error: "invalid_grant", error_codes: [90094], error_description: "AADSTS90094: Admin approval required." });
          if (mode.device === "declined") return send(400, { error: "authorization_declined" });
          if (polls++ < mode.pendings) return send(400, { error: mode.slowDown && polls === 1 ? "slow_down" : "authorization_pending" });
          return send(200, { access_token: "at-1", refresh_token: "rt-1", expires_in: 3600, scope: form.get("scope") });
        }
        if (g === "authorization_code") {
          const ch = challenges.get(String(form.get("code")));
          const ok = ch && createHash("sha256").update(String(form.get("code_verifier"))).digest("base64url") === ch;
          if (!ok) return send(400, { error: "invalid_grant", error_description: "PKCE" });
          return send(200, { access_token: "at-b", refresh_token: "rt-b", expires_in: 3600 });
        }
        if (g === "refresh_token") {
          if (mode.refresh === "expired") return send(400, { error: "invalid_grant", error_description: "AADSTS700082: The refresh token has expired." });
          if (mode.refresh === "admin") return send(400, { error: "invalid_grant", error_codes: [90094], error_description: "AADSTS90094: Admin approval required." });
          if (mode.refresh === "unconsented") return send(400, { error: "invalid_grant", error_codes: [65001], error_description: "AADSTS65001: The user or administrator has not consented." });
          return send(200, { access_token: "at-2", expires_in: 3600 });
        }
      }
      send(404, {});
    });
  });
  await new Promise<void>((r) => srv.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${(srv.address() as AddressInfo).port}`;
  return { base, seen, challenges, close: () => new Promise<void>((r) => srv.close(() => r())) };
}

const provider = (base: string) => ({ ...microsoftProvider("organizations"), deviceEndpoint: `${base}/t/oauth2/v2.0/devicecode`, tokenEndpoint: `${base}/t/oauth2/v2.0/token`, authorizeEndpoint: `${base}/t/oauth2/v2.0/authorize` });
const noSleep = async () => {};

test("identificadores de aplicación ajenos o sin declarar se rechazan antes de ninguna petición", () => {
  const ms = microsoftProvider("organizations");
  for (const id of ["04b07795-8ddb-461a-bbee-02f9e1bf7b46", "de8bc8b5-d9f9-48b1-a8ad-b748da725064", "1fec8e78-bce4-4aaf-ab1b-5451cc387264", "14d82eec-204b-4c2f-b7e8-296a70dab67e", "D3590ED6-52B3-4102-AEFF-AAD2292AB01C"]) {
    assert.throws(() => assertOwnClient(ms, { client_id: id, owner: "organization" }), ForeignClientError, id);
  }
  assert.throws(() => assertOwnClient(googleProvider, { client_id: "32555940559.apps.googleusercontent.com", owner: "operator" }), ForeignClientError);
  assert.throws(() => assertOwnClient(ms, { client_id: "", owner: "organization" }), ForeignClientError);
  assert.throws(() => assertOwnClient(ms, { client_id: CLIENT.client_id } as never), ForeignClientError, "sin dueño declarado");
  assert.doesNotThrow(() => assertOwnClient(ms, CLIENT));
});

test("flujo de dispositivo: muestra el código, espera con pending/slow_down y pide solo los permisos mínimos", async () => {
  const s = await idp({ device: "ok", pendings: 2, slowDown: true, refresh: "ok" });
  try {
    const prompts: string[] = [];
    const waits: number[] = [];
    const t = await deviceFlow({
      provider: provider(s.base), client: CLIENT, scopes: ["Mail.ReadBasic"],
      onPrompt: (p) => prompts.push(`${p.user_code} ${p.verification_uri}`), sleep: async (ms) => { waits.push(ms); }, now: () => 1_000_000,
    });
    assert.equal(t.access_token, "at-1");
    assert.equal(t.refresh_token, "rt-1");
    assert.equal(t.expires_at, 1_000_000 + 3600_000);
    assert.deepEqual(prompts, ["ABCD-EFGH https://login.example/device"]);
    assert.deepEqual(waits, [1000, 6000, 6000], "slow_down suma 5 s al intervalo");
    const scope = s.seen.find((x) => x.path.endsWith("/devicecode"))!.form.get("scope");
    assert.equal(scope, "Mail.ReadBasic offline_access");
  } finally {
    await s.close();
  }
});

test("flujo de dispositivo: el inquilino exige administración → admin_consent_required", async () => {
  const s = await idp({ device: "admin", pendings: 0, slowDown: false, refresh: "ok" });
  try {
    await assert.rejects(deviceFlow({ provider: provider(s.base), client: CLIENT, scopes: ["Mail.Read"], onPrompt: () => {}, sleep: noSleep }),
      (e: { code?: string }) => e.code === "admin_consent_required");
  } finally {
    await s.close();
  }
});

test("flujo de dispositivo: rechazado por el usuario → no_credential", async () => {
  const s = await idp({ device: "declined", pendings: 0, slowDown: false, refresh: "ok" });
  try {
    await assert.rejects(deviceFlow({ provider: provider(s.base), client: CLIENT, scopes: ["Mail.Read"], onPrompt: () => {}, sleep: noSleep }),
      (e: { code?: string }) => e.code === "no_credential");
  } finally {
    await s.close();
  }
});

test("flujo de navegador con PKCE: escucha solo en 127.0.0.1, valida state y canjea con el verificador", async () => {
  const s = await idp({ device: "ok", pendings: 0, slowDown: false, refresh: "ok" });
  try {
    const t = await browserFlow({
      provider: provider(s.base), client: CLIENT, scopes: ["Calendars.ReadBasic"],
      openUrl: async (url) => {
        const u = new URL(url);
        const redirect = new URL(String(u.searchParams.get("redirect_uri")));
        assert.equal(redirect.hostname, "127.0.0.1");
        assert.equal(u.searchParams.get("code_challenge_method"), "S256");
        await fetch(`${s.base}/authorize-sim?code=c-1&challenge=${u.searchParams.get("code_challenge")}`);
        // Un state falso no se acepta y no rompe el flujo.
        const bad = await fetch(`${redirect}?code=c-1&state=falso`);
        assert.equal(bad.status, 400);
        await fetch(`${redirect}?code=c-1&state=${u.searchParams.get("state")}`);
      },
    });
    assert.equal(t.access_token, "at-b");
  } finally {
    await s.close();
  }
});

test("flujo de navegador: error de consentimiento en la redirección → admin_consent_required", async () => {
  const s = await idp({ device: "ok", pendings: 0, slowDown: false, refresh: "ok" });
  try {
    await assert.rejects(browserFlow({
      provider: provider(s.base), client: CLIENT, scopes: ["Mail.Read"],
      openUrl: async (url) => {
        const u = new URL(url);
        await fetch(`${u.searchParams.get("redirect_uri")}?error=access_denied&error_description=${encodeURIComponent("AADSTS90094: Admin approval required")}&state=${u.searchParams.get("state")}`);
      },
    }), (e: { code?: string }) => e.code === "admin_consent_required");
  } finally {
    await s.close();
  }
});

test("renovación: ok, caducada y sin consentimiento (no_credential), administración exigida (admin_consent_required)", async () => {
  for (const [mode, expect] of [["ok", "at-2"], ["expired", "no_credential"], ["unconsented", "no_credential"], ["admin", "admin_consent_required"]] as const) {
    const s = await idp({ device: "ok", pendings: 0, slowDown: false, refresh: mode });
    try {
      const p = refreshToken({ provider: provider(s.base), client: CLIENT, refresh_token: "rt-1", scopes: ["Mail.Read"], now: () => 0 });
      if (mode === "ok") {
        const t = await p;
        assert.equal(t.access_token, expect);
        assert.equal(t.refresh_token, "rt-1", "conserva el refresh si la respuesta no trae otro");
      } else await assert.rejects(p, (e: { code?: string }) => e.code === expect);
    } finally {
      await s.close();
    }
  }
});

test("classifyOAuthError: códigos de Microsoft y de Google", () => {
  // 65001 lo resuelve la persona con un nuevo inicio de sesión: no es de administración.
  assert.equal(classifyOAuthError({ error: "invalid_grant", error_description: "AADSTS65001: not consented" }), "no_credential");
  assert.equal(classifyOAuthError({ error: "invalid_grant", error_codes: [65001] }), "no_credential");
  assert.equal(classifyOAuthError({ error: "admin_policy_enforced" }), "admin_consent_required");
  assert.equal(classifyOAuthError({ error: "access_denied", error_description: "AADSTS90094" }), "admin_consent_required");
  assert.equal(classifyOAuthError({ error: "access_denied", error_codes: [90095] }), "admin_consent_required");
  assert.equal(classifyOAuthError({ error: "access_denied", error_description: "AADSTS65004: User declined to consent" }), "no_credential");
  assert.equal(classifyOAuthError({ error: "access_denied", error_codes: [65004] }), "no_credential");
  assert.equal(classifyOAuthError({ error: "authorization_pending" }), "pending");
  assert.equal(classifyOAuthError({ error: "slow_down" }), "slow_down");
  assert.equal(classifyOAuthError({ error: "expired_token" }), "no_credential");
  assert.equal(classifyOAuthError({ error: "lo-que-sea" }), "no_credential");
});

test("endpoints sin HTTPS fuera de loopback se rechazan", async () => {
  const p = { ...microsoftProvider("organizations"), tokenEndpoint: "http://idp.example/token" };
  await assert.rejects(refreshToken({ provider: p, client: CLIENT, refresh_token: "r", scopes: [] }), /HTTPS/);
});
