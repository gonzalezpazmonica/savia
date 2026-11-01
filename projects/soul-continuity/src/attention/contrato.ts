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
 * Solo `tenant` y `dkim_dmarc` fuera de la web autentican. `unknown` es `DESCONOCIDO`, que
 * tampoco autentica; `unauthenticated` y cualquier valor inesperado, `NO_AUTENTICADO`
 * (fail-closed).
 *
 * En la web el contrato fija el remitente a `unknown` y nada autentica, diga lo que diga
 * `auth`. La política reconoce la ruta `WEB` por sí misma: baja a aviso las reglas de alerta
 * (AC-4c) y lo demás que llega por la web no pide nada a la persona.
 */
export function origenDeContrato(auth: SenderAuth | string | null | undefined, route: Route): Origen {
  if (auth === 'unknown') return 'DESCONOCIDO';
  if (route === 'web') return 'NO_AUTENTICADO';
  return auth === 'tenant' || auth === 'dkim_dmarc' ? 'AGENTE_AUTENTICADO' : 'NO_AUTENTICADO';
}
