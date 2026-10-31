// Puente entre el contrato de continuidad (src/contract) y la política de atención.
// Solo traduce vocabulario: no decide nada y no lee cuerpos de mensajes.

import type { Level, Route, SenderAuth } from '../contract/claims.ts';
import type { Nivel, Origen, Ruta } from './modelo.ts';

const NIVELES: Record<Level, Nivel> = { N1: 1, N2: 2, N3: 3, N4: 4 };

export function nivelDeContrato(level: Level): Nivel {
  return NIVELES[level];
}

/** La ruta `web` no tiene identidad autenticada; cualquier otra ruta es API. */
export function rutaDeContrato(route: Route): Ruta {
  return route === 'web' ? 'WEB' : 'API';
}

/**
 * Solo `tenant` y `dkim_dmarc` autentican al remitente, y solo fuera de la ruta web.
 * `unauthenticated`, `unknown` y cualquier valor inesperado no autentican (fail-closed).
 */
export function origenDeContrato(auth: SenderAuth | string | null | undefined, route: Route): Origen {
  if (route === 'web') return 'NO_AUTENTICADO';
  return auth === 'tenant' || auth === 'dkim_dmarc' ? 'AGENTE_AUTENTICADO' : 'NO_AUTENTICADO';
}
