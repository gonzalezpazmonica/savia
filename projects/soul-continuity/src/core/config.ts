/**
 * Configuración local de la instalación (SE-490). Fichero `config.json` en el directorio
 * de datos del usuario. Nunca lleva tokens: esos van al almacén de credenciales del sistema.
 *
 * - El operador sale del perfil activo (`active_profile`, o `SOUL_PROFILE`). Sin perfil, negativa clara.
 * - Nivel de detalle de la instalación (`detail.level`) con un máximo que fija el operador (`detail.max`).
 * - AC-4d: por un frontend de agente cuyo modelo corre en la nube solo salen recuentos, salvo un
 *   proveedor declarado como aprobado por la organización para N4, con quién y cuándo lo aprobó.
 * - Escucha de la API: direcciones explícitas (las de la VPN del operador); ninguna por defecto.
 */

import { createHash } from "node:crypto";
import { join } from "node:path";
import { type AlertRule, DETAILS, type Detail, type InstallationConfig, type OperatorProfile, type SourceConfig } from "../contract/adapter.ts";
import { parseTs } from "../contract/claims.ts";
import { type ConnectorsConfig, validateConnectors } from "./connectors.ts";
import { readJson, writeJson } from "./store.ts";

export const CONFIG_FILE = "config.json";

export interface ProfileConfig {
  operator: OperatorProfile;
  sources: SourceConfig[];
  alert_rules?: AlertRule[];
}

export interface ApprovedProvider {
  id: string;
  /** Quién de la organización lo aprobó (texto del operador). Obligatorio. */
  approved_by: string;
  approved_at: string;
  /** Nivel de datos aprobado. Solo «N4» permite subir de `recuentos`. */
  scope: string;
  /** Frontends que el operador declara que corren con este proveedor (claude-code, opencode…). */
  frontends: string[];
}

export interface SoulConfig {
  installation_id: string;
  active_profile: string | null;
  profiles: Record<string, ProfileConfig>;
  detail: { level: Detail; max: Detail };
  agent_frontend: { approved_providers: ApprovedProvider[] };
  api: { listen: string[]; port: number };
  /** Adaptadores reales activados por el operador (H-1). Sin este campo, ninguno. */
  connectors?: ConnectorsConfig;
}

export class NoProfileError extends Error {
  readonly code = "NO_PROFILE";
}

export class ConfigError extends Error {
  readonly code = "CONFIG";
}

export const RANK: Record<Detail, number> = { recuentos: 0, titulos: 1, completo: 2 };

export function emptyConfig(installationId: string): SoulConfig {
  return {
    installation_id: installationId,
    active_profile: null,
    profiles: {},
    detail: { level: "titulos", max: "titulos" },
    agent_frontend: { approved_providers: [] },
    api: { listen: [], port: 8787 },
  };
}

function isDetail(v: unknown): v is Detail {
  return typeof v === "string" && (DETAILS as readonly string[]).includes(v);
}

export function validateConfig(c: unknown): string[] {
  const p: string[] = [];
  if (typeof c !== "object" || c === null) return ["la configuración no es un objeto"];
  const v = c as Record<string, any>;
  if (typeof v.installation_id !== "string" || !v.installation_id) p.push("installation_id obligatorio");
  if (v.active_profile !== null && typeof v.active_profile !== "string") p.push("active_profile inválido");
  if (typeof v.profiles !== "object" || v.profiles === null) p.push("profiles debe ser un objeto");
  else for (const [n, pr] of Object.entries(v.profiles as Record<string, any>)) {
    // operator.ref es clave de directorios, ids y operadores de la API: forma cerrada.
    const ref = pr?.operator?.ref;
    if (ref !== undefined && (typeof ref !== "string" || !/^[A-Za-z0-9._-]{1,64}$/.test(ref) || ref === "__proto__" || ref === "constructor" || ref === "prototype")) {
      p.push(`profiles.${n}.operator.ref inválido`);
    }
  }
  if (!isDetail(v.detail?.level) || !isDetail(v.detail?.max)) p.push("detail.level y detail.max: completo | titulos | recuentos");
  else if (RANK[v.detail.level as Detail] > RANK[v.detail.max as Detail]) p.push("detail.level supera detail.max");
  if (!Array.isArray(v.agent_frontend?.approved_providers)) p.push("agent_frontend.approved_providers debe ser una lista");
  if (!Array.isArray(v.api?.listen) || v.api.listen.some((a: unknown) => typeof a !== "string")) p.push("api.listen debe ser una lista de direcciones");
  if (!Number.isInteger(v.api?.port) || v.api.port < 1 || v.api.port > 65535) p.push("api.port inválido");
  p.push(...validateConnectors(v.connectors));
  return p;
}

/** Lee la configuración. Sin fichero: configuración vacía (sin perfil). Corrupta o inválida: ConfigError. */
export function loadConfig(dataDir: string, fallbackId = "sin-instalar"): SoulConfig {
  let raw: unknown;
  try {
    raw = readJson<unknown>(join(dataDir, CONFIG_FILE), null);
  } catch {
    throw new ConfigError(`configuración ilegible: ${join(dataDir, CONFIG_FILE)}`);
  }
  if (raw === null) return emptyConfig(fallbackId);
  const problems = validateConfig(raw);
  if (problems.length) throw new ConfigError(`configuración inválida: ${problems.join("; ")}`);
  return raw as SoulConfig;
}

export function saveConfig(dataDir: string, cfg: SoulConfig): void {
  const problems = validateConfig(cfg);
  if (problems.length) throw new ConfigError(`configuración inválida: ${problems.join("; ")}`);
  writeJson(join(dataDir, CONFIG_FILE), cfg);
}

export function activeProfileName(cfg: SoulConfig, env: Record<string, string | undefined>): string {
  const name = env.SOUL_PROFILE || cfg.active_profile;
  if (!name) throw new NoProfileError("No sé quién eres: esta instalación no tiene perfil activo. Configura uno en config.json (active_profile y profiles).");
  if (!cfg.profiles[name]) throw new NoProfileError(`No sé quién eres: el perfil «${name}» no existe en esta instalación.`);
  return name;
}

export function resolveInstall(cfg: SoulConfig, env: Record<string, string | undefined>): InstallationConfig {
  const p = cfg.profiles[activeProfileName(cfg, env)];
  if (!p.operator?.ref) throw new NoProfileError("No sé quién eres: el perfil activo no tiene operator.ref.");
  return { id: cfg.installation_id, operator: p.operator, sources: p.sources ?? [], alert_rules: p.alert_rules ?? [] };
}

/** Identificador opaco de un elemento para la app y la CLI (no deja ver la fuente ni la referencia). */
export function elementId(operatorRef: string, key: string): string {
  return "e" + createHash("sha256").update(`${operatorRef}\u0000${key}`).digest("hex").slice(0, 20);
}

export interface Caller {
  /** Frontend de agente que invoca la CLI (claude-code, opencode…) o null si es una persona en su terminal. */
  frontend: string | null;
}

/**
 * AC-4d: nivel efectivo para quien llama. Fail-closed: cualquier duda => recuentos.
 * El proveedor no lo declara quien llama: la configuración local (que solo escribe el operador)
 * fija qué frontends corren con cada proveedor aprobado.
 */
export function agentLevel(cfg: SoulConfig, caller: Caller, installLevel: Detail): { level: Detail; forced: boolean; provider: string | null } {
  if (!caller.frontend) return { level: installLevel, forced: false, provider: null };
  const p = cfg.agent_frontend.approved_providers.find((x) => Array.isArray(x.frontends) && x.frontends.includes(caller.frontend as string));
  const approved = p && p.scope === "N4" && typeof p.approved_by === "string" && p.approved_by.trim() !== "" && parseTs(p.approved_at) !== null;
  if (!approved) return { level: "recuentos", forced: installLevel !== "recuentos", provider: null };
  return { level: installLevel, forced: false, provider: p.id };
}
