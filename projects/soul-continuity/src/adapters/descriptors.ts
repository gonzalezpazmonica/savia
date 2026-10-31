/**
 * Declaración de cada adaptador de API: propósito, nivel, TTL, permisos y revocación.
 *
 * Los permisos son los delegados mínimos para lo que el adaptador responde; no
 * hay ninguno de escritura. Revocar un adaptador borra su caché local y los
 * tokens de estos permisos del almacén del sistema (AC-5, ver `revoke.ts`).
 * El adaptador `web` es otra pieza (navegador en perfil dedicado) y no está aquí.
 */

import type { Level, Route } from "../contract/claims.ts";
import type { AdapterName } from "../contract/adapter.ts";

export type ApiAdapterName = Exclude<AdapterName, "web">;

export interface AdapterDescriptor {
  name: ApiAdapterName;
  purpose: string;
  /** Nivel por defecto: N4 para datos de empresa; la configuración solo puede subirlo. */
  sensitivity: Level;
  /** Vigencia de cada afirmación observada. */
  ttl_s: number;
  routes: Route[];
  /** Servicio lógico del transporte y del almacén de credenciales. */
  service: string;
  /** Variantes de permisos que el adaptador puede pedir (la primera es la habitual). */
  scopes: string[][];
  /** Qué hace revocar, dicho al operador. */
  revocation: string;
  /** Qué no se guarda nunca. */
  never_persists: string;
}

const G = "https://www.googleapis.com/auth/";
const REVOKE = "Borra la caché local del adaptador (sincronización y metadatos) y sus tokens del almacén de credenciales del sistema.";
const NO_BODIES = "Cuerpos de correos, mensajes, comentarios y descripciones; solo metadatos y referencias.";

export const DESCRIPTORS: Record<ApiAdapterName, AdapterDescriptor> = {
  "m365-mail": {
    name: "m365-mail",
    purpose: "Hilos que esperan mi respuesta (solo metadatos) y correos marcados con fecha",
    sensitivity: "N4", ttl_s: 1800, routes: ["graph"], service: "graph",
    // Mail.Read solo para leer las cabeceras de autenticación del remitente (AC-4c);
    // con sender_identity: false basta Mail.ReadBasic y no hay alertas por remitente.
    scopes: [["Mail.Read"], ["Mail.ReadBasic"]],
    revocation: REVOKE, never_persists: NO_BODIES,
  },
  "m365-calendar": {
    name: "m365-calendar",
    purpose: "Reuniones de mi calendario propio, de ayer a dos semanas vista",
    sensitivity: "N4", ttl_s: 3600, routes: ["graph"], service: "graph",
    scopes: [["Calendars.ReadBasic"]],
    revocation: REVOKE, never_persists: NO_BODIES,
  },
  "m365-teams": {
    name: "m365-teams",
    purpose: "Menciones en mis chats de Teams sin respuesta mía posterior",
    sensitivity: "N4", ttl_s: 1800, routes: ["graph"], service: "graph",
    scopes: [["Chat.Read"]],
    revocation: REVOKE, never_persists: NO_BODIES,
  },
  "m365-files": {
    name: "m365-files",
    purpose: "Documentos compartidos conmigo con comentarios sin resolver",
    sensitivity: "N4", ttl_s: 3600, routes: ["graph"], service: "graph",
    scopes: [["Files.Read.All"]],
    revocation: REVOKE, never_persists: NO_BODIES,
  },
  "google-workspace": {
    name: "google-workspace",
    purpose: "Hilos de Gmail que esperan mi respuesta (metadatos), reuniones, tareas con fecha y documentos con comentarios",
    sensitivity: "N4", ttl_s: 1800, routes: ["api"], service: "google",
    // Tasks es opcional (params.tasks: true): añade su permiso solo si se activa.
    scopes: [[`${G}gmail.metadata`, `${G}calendar.readonly`, `${G}drive.readonly`],
      [`${G}gmail.metadata`, `${G}calendar.readonly`, `${G}drive.readonly`, `${G}tasks.readonly`]],
    revocation: REVOKE, never_persists: NO_BODIES,
  },
  jira: {
    name: "jira",
    purpose: "Incidencias asignadas a mí y no terminadas",
    sensitivity: "N4", ttl_s: 3600, routes: ["api"], service: "jira",
    scopes: [["read:jira-work"]],
    revocation: REVOKE, never_persists: "Descripciones y comentarios de incidencias.",
  },
  "azure-devops": {
    name: "azure-devops",
    purpose: "Elementos asignados a mí y revisiones de PR pedidas sin voto",
    sensitivity: "N4", ttl_s: 3600, routes: ["api"], service: "ado",
    scopes: [["vso.work", "vso.code"]],
    revocation: REVOKE, never_persists: "Descripciones, comentarios y diffs.",
  },
  github: {
    name: "github",
    purpose: "Revisiones pedidas, asignaciones y menciones abiertas",
    sensitivity: "N2", ttl_s: 3600, routes: ["api"], service: "github",
    scopes: [["repo:read"]],
    revocation: REVOKE, never_persists: "Cuerpos de incidencias, PR y comentarios.",
  },
};

export function isApiAdapter(n: string): n is ApiAdapterName {
  return Object.prototype.hasOwnProperty.call(DESCRIPTORS, n);
}
