/**
 * Adaptadores de API de Soul Continuidad v1 (SE-490): registro y piezas públicas.
 *
 * Todos son de solo lectura, cumplen `SourceAdapter` del contrato y hablan con
 * las fuentes solo por `Transport` y `CredentialStore`. El núcleo los compone
 * con `HttpTransport` y `SystemCredentialStore`, y con `FileDeltaCache` en el
 * directorio de estado de la instalación.
 */

import type { SourceAdapter } from "../contract/adapter.ts";
import type { DeltaCache } from "./delta-cache.ts";
import type { ApiAdapterName } from "./descriptors.ts";
import { makeAzureDevOpsAdapter } from "./azure-devops.ts";
import { makeGitHubAdapter } from "./github.ts";
import { makeGoogleAdapter } from "./google.ts";
import { makeJiraAdapter } from "./jira.ts";
import { makeM365Adapters } from "./m365.ts";

export interface ApiAdapterOptions {
  /** Caché de sincronización (delta del correo de Microsoft 365). */
  cache?: DeltaCache;
  /** Tope de páginas por colección y lectura. */
  maxPages?: number;
  /** `authserv-id` aceptados del receptor de Gmail (por defecto `mx.google.com`). */
  gmailAuthservIds?: string[];
}

export function makeApiAdapters(o: ApiAdapterOptions = {}): Record<ApiAdapterName, SourceAdapter> {
  return {
    ...makeM365Adapters({ cache: o.cache, maxPages: o.maxPages }),
    "google-workspace": makeGoogleAdapter({ maxPages: o.maxPages, gmailAuthservIds: o.gmailAuthservIds }),
    jira: makeJiraAdapter({ maxPages: o.maxPages }),
    "azure-devops": makeAzureDevOpsAdapter(),
    github: makeGitHubAdapter({ maxPages: o.maxPages }),
  };
}

export { DESCRIPTORS, isApiAdapter, type AdapterDescriptor, type ApiAdapterName } from "./descriptors.ts";
export { HttpTransport, TransportRefused } from "./http-transport.ts";
export { FileDeltaCache, MemoryDeltaCache, type DeltaCache } from "./delta-cache.ts";
