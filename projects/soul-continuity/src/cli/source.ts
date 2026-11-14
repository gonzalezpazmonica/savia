/**
 * `soul source add <adaptador>` y `soul source list`: conectar una fuente sin editar `config.json`.
 *
 * Escribe de una vez las tres piezas que el motor exige: `connectors.enabled`, la fuente del perfil
 * (`purpose` + `consent`) y, si se da, la identidad del operador. Es un `saveConfig` único (escritura
 * atómica): o quedan las tres o no queda ninguna. El consentimiento solo lo da la persona: hace falta
 * terminal interactiva y la respuesta «s» a la declaración; sin «s» no se escribe nada. Desde un
 * frontend de agente la CLI la rechaza antes de llegar aquí (no está en la lista de órdenes permitidas).
 * `web` queda fuera: tiene su propio flujo (perfil de navegador). La revocación sigue siendo `soul revoke`.
 */

import { type ApiAdapterName, DESCRIPTORS, isApiAdapter } from "../adapters/descriptors.ts";
import type { SourceConfig } from "../contract/adapter.ts";
import type { SoulConfig } from "../core/config.ts";

export const CONSENT_STATEMENT = "Activo esta fuente bajo mi responsabilidad";

export class SourceUsage extends Error {}

export interface AddOptions {
  adapter: string;
  profile: string;
  purpose?: string;
  identity?: string;
  now: string;
}

const MAX_TEXT = 200;
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}$/;
const PLAIN = /^[^\u0000-\u001f\u007f]+$/;

/** Valida el adaptador. `web` y los desconocidos se rechazan con el motivo. */
export function checkAdapter(adapter: string): asserts adapter is ApiAdapterName {
  if (adapter === "web") throw new SourceUsage("web no se conecta con esta orden: tiene su propio flujo (perfil de navegador, ver docs/instalar.md)");
  if (!adapter) throw new SourceUsage(`source add <adaptador>: ${Object.keys(DESCRIPTORS).join(", ")}`);
  if (!isApiAdapter(adapter)) throw new SourceUsage(`adaptador desconocido: ${adapter.slice(0, 40)}. Valen: ${Object.keys(DESCRIPTORS).join(", ")}`);
}

export function checkPurpose(p: string): string {
  const t = p.trim();
  if (!t || t.length > MAX_TEXT || !PLAIN.test(t)) throw new SourceUsage(`--purpose: texto de 1 a ${MAX_TEXT} caracteres, sin saltos de línea`);
  return t;
}

export function defaultPurpose(adapter: ApiAdapterName): string {
  return DESCRIPTORS[adapter].purpose;
}

/** ¿Hay ya una fuente vigente (no revocada) de este adaptador en el perfil? */
export function isActive(cfg: SoulConfig, profile: string, adapter: string): boolean {
  return cfg.profiles[profile].sources.some((s) => s.adapter === adapter && !s.consent?.revoked_at);
}

/** Devuelve una configuración nueva con las tres piezas; no toca la recibida. */
export function withSource(cfg: SoulConfig, o: AddOptions & { adapter: ApiAdapterName }): SoulConfig {
  const next = structuredClone(cfg);
  const pr = next.profiles[o.profile];
  const purpose = checkPurpose(o.purpose ?? defaultPurpose(o.adapter));
  const id = pr.operator.identities;
  if (o.identity !== undefined) {
    const v = o.identity.trim();
    if (!v || v.length > MAX_TEXT || /\s/.test(v)) throw new SourceUsage("--identity: un valor sin espacios (correo, usuario o id de cuenta)");
    if (o.adapter === "github") id.github = v;
    else if (o.adapter === "jira") id.jira_account = v;
    else if (o.adapter === "azure-devops") id.ado_id = v;
    else {
      if (!EMAIL.test(v)) throw new SourceUsage(`--identity: ${o.adapter} se reconoce por correo (nombre@dominio)`);
      if (!id.emails.some((e) => e.toLowerCase() === v.toLowerCase())) id.emails = [...id.emails, v];
    }
  }
  // Una fuente revocada se sustituye por la nueva (con consentimiento nuevo): no se duplica el adaptador.
  pr.sources = pr.sources.filter((s) => s.adapter !== o.adapter);
  const src: SourceConfig = { adapter: o.adapter, purpose, consent: { granted_at: o.now, statement: CONSENT_STATEMENT } };
  pr.sources.push(src);
  const enabled = next.connectors?.enabled ?? [];
  next.connectors = { ...(next.connectors ?? {}), enabled: enabled.includes(o.adapter) ? enabled : [...enabled, o.adapter] };
  return next;
}

/** Texto que ve la persona antes de dar el consentimiento. */
export function declaration(adapter: ApiAdapterName, purpose: string): string {
  const d = DESCRIPTORS[adapter];
  return [
    `Vas a conectar ${adapter} (solo lectura).`,
    `  Para qué: ${purpose}`,
    `  Nivel de los datos: ${d.sensitivity}`,
    `  Qué no se guarda nunca: ${d.never_persists}`,
    `  Se retira cuando quieras: soul revoke ${adapter}`,
    `Al escribir «s» queda registrado: «${CONSENT_STATEMENT}» (con la fecha y hora de ahora).`,
  ].join("\n");
}

export function nextStep(adapter: ApiAdapterName): string {
  const d = DESCRIPTORS[adapter];
  const how = d.service === "graph" || d.service === "google" ? "" : " --token-stdin";
  return `Siguiente paso: soul login ${adapter}${how}`;
}
