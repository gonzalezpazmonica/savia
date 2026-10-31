// Puente entre el contrato de continuidad (src/contract) y la política de atención.
// Solo traduce vocabulario: no decide nada y no lee cuerpos de mensajes.

import type { Level, Route, SenderAuth } from '../contract/claims.ts';
import type { Nivel, Origen, Ruta } from './modelo.ts';

const NIVELES: Record<Level, Nivel> = { N1: 1, N2: 2, N3: 3, N4: 4 };

/** Un nivel fuera del contrato (dato externo, versión nueva, minúsculas) es N4 (fail-closed). */
export function nivelDeContrato(level: Level | string | null | undefined): Nivel {
  return Object.hasOwn(NIVELES, level as string) ? NIVELES[level as Level] : 4;
}

/** La ruta `web` no tiene identidad autenticada; cualquier otra ruta es API. */
export function rutaDeContrato(route: Route): Ruta {
  return route === 'web' ? 'WEB' : 'API';
}

/**
 * Fuera de la web, solo `tenant` y `dkim_dmarc` autentican; `unauthenticated`, `unknown` y
 * cualquier valor inesperado no autentican (fail-closed).
 *
 * En la web el contrato fija el remitente a `unknown`: el evento lo trae el adaptador y llega
 * a la política con ruta `WEB`, que nunca produce alerta, solo aviso (AC-4c). Cualquier otro
 * valor en la web contradice el contrato y no autentica.
 */
export function origenDeContrato(auth: SenderAuth | string | null | undefined, route: Route): Origen {
  if (route === 'web') return auth === 'unknown' ? 'AGENTE_AUTENTICADO' : 'NO_AUTENTICADO';
  return auth === 'tenant' || auth === 'dkim_dmarc' ? 'AGENTE_AUTENTICADO' : 'NO_AUTENTICADO';
}
