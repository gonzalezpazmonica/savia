import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  CONFIG_FILE, ConfigError, NoProfileError, agentLevel, elementId, emptyConfig, loadConfig, resolveInstall, saveConfig,
} from "../src/core/config.ts";

const tmp = () => mkdtempSync(join(tmpdir(), "soul-cf-"));
const profile = (ref: string) => ({ operator: { ref, identities: { emails: [`${ref}@example.test`] } }, sources: [] });

test("sin fichero de configuración no hay perfil: negativa clara", () => {
  const cfg = loadConfig(tmp());
  assert.throws(() => resolveInstall(cfg, {}), (e: unknown) => e instanceof NoProfileError && /no sé quién eres/i.test(e.message));
});

test("el operador sale del perfil activo de la instalación", () => {
  const cfg = { ...emptyConfig("inst-1"), active_profile: "a", profiles: { a: profile("op-a"), b: profile("op-b") } };
  assert.equal(resolveInstall(cfg, {}).operator.ref, "op-a");
  assert.equal(resolveInstall(cfg, {}).id, "inst-1");
});

test("SOUL_PROFILE elige otro perfil existente; uno inexistente es negativa, no el activo", () => {
  const cfg = { ...emptyConfig("i"), active_profile: "a", profiles: { a: profile("op-a"), b: profile("op-b") } };
  assert.equal(resolveInstall(cfg, { SOUL_PROFILE: "b" }).operator.ref, "op-b");
  assert.throws(() => resolveInstall(cfg, { SOUL_PROFILE: "zz" }), NoProfileError);
});

test("perfil activo que no existe en profiles: negativa", () => {
  const cfg = { ...emptyConfig("i"), active_profile: "x", profiles: { a: profile("op-a") } };
  assert.throws(() => resolveInstall(cfg, {}), NoProfileError);
});

test("configuración corrupta o con nivel desconocido: error, no valores por defecto", () => {
  const d = tmp();
  writeFileSync(join(d, CONFIG_FILE), "{");
  assert.throws(() => loadConfig(d), ConfigError);
  writeFileSync(join(d, CONFIG_FILE), JSON.stringify({ ...emptyConfig("i"), detail: { level: "todo", max: "completo" } }));
  assert.throws(() => loadConfig(d), ConfigError);
  writeFileSync(join(d, CONFIG_FILE), JSON.stringify({ ...emptyConfig("i"), detail: { level: "completo", max: "titulos" } }));
  assert.throws(() => loadConfig(d), ConfigError, "el nivel no puede superar el máximo");
});

test("saveConfig + loadConfig conservan la configuración", () => {
  const d = tmp();
  const cfg = { ...emptyConfig("i"), active_profile: "a", profiles: { a: profile("op-a") } };
  saveConfig(d, cfg);
  assert.deepEqual(loadConfig(d), cfg);
});

test("elementId: opaco, estable, por operador y válido para la API", () => {
  const a = elementId("op-a", "github:review_request:r1#7");
  assert.match(a, /^[A-Za-z0-9_.-]{1,64}$/);
  assert.equal(a, elementId("op-a", "github:review_request:r1#7"));
  assert.notEqual(a, elementId("op-b", "github:review_request:r1#7"));
  assert.ok(!a.includes("r1"));
});

// AC-4d: por un frontend de agente, solo recuentos salvo proveedor aprobado declarado.
test("AC-4d: frontend de agente sin declaración => recuentos", () => {
  const cfg = emptyConfig("i");
  assert.deepEqual(agentLevel(cfg, { frontend: "claude-code" }, "completo"), { level: "recuentos", forced: true, provider: null });
});

test("AC-4d: proveedor declarado pero sin aprobación auditada => recuentos", () => {
  const cfg = { ...emptyConfig("i"), agent_frontend: { approved_providers: [{ id: "prov-x", approved_by: "", approved_at: "2026-10-30T00:00:00Z", scope: "N4" }] } };
  assert.equal(agentLevel(cfg, { frontend: "opencode", provider: "prov-x" }, "completo").level, "recuentos");
});

test("AC-4d: otro proveedor que el aprobado => recuentos", () => {
  const cfg = { ...emptyConfig("i"), agent_frontend: { approved_providers: [{ id: "prov-x", approved_by: "operador", approved_at: "2026-10-30T00:00:00Z", scope: "N4" }] } };
  assert.equal(agentLevel(cfg, { frontend: "opencode", provider: "prov-y" }, "completo").level, "recuentos");
  assert.equal(agentLevel(cfg, { frontend: "opencode" }, "completo").level, "recuentos");
});

test("AC-4d: proveedor aprobado para N4 => nivel de la instalación, nunca por encima", () => {
  const cfg = { ...emptyConfig("i"), agent_frontend: { approved_providers: [{ id: "prov-x", approved_by: "operador", approved_at: "2026-10-30T00:00:00Z", scope: "N4" }] } };
  assert.deepEqual(agentLevel(cfg, { frontend: "opencode", provider: "prov-x" }, "titulos"), { level: "titulos", forced: false, provider: "prov-x" });
});

test("sin frontend de agente, el nivel es el de la instalación", () => {
  assert.equal(agentLevel(emptyConfig("i"), { frontend: null }, "completo").level, "completo");
});
