// Frase accionable en español llano para cada error de las herramientas MCP.
// Solo añade orientación: no cambia el texto, el código ni la semántica del error original.
// Las frases de permiso y de nota ausente son deliberadamente genéricas: no revelan qué hay detrás.

import { AuthError } from '../auth/index.js';
import { RagError } from '../rag/types.js';
import { FilesError } from '../files/types.js';
import { RouteError } from '../retrieval/route.js';
import { NoteNotFoundError } from '../storage/index.js';
import { SecurityError } from '../security/index.js';

const UNKNOWN_DOME = 'La cúpula no existe: lista las cúpulas con vault_domes y usa uno de esos nombres.';
const INVALID_PARAMS = 'La entrada no es válida: revisa los parámetros de la herramienta y vuelve a llamarla.';

export function howToProceed(e: unknown): string | undefined {
  if (e instanceof NoteNotFoundError) {
    return 'La nota no existe o no puedes verla: busca con vault_search o vault_list antes de leerla y usa la ruta exacta que devuelvan.';
  }
  if (e instanceof AuthError) {
    return 'No tienes permiso para esta operación en esa cúpula: comprueba tu credencial o pide acceso a quien administra la cúpula; no reintentes con la misma credencial.';
  }
  if (e instanceof SecurityError) {
    // Los textos vienen de src/security/index.ts; un test los recorre con el VaultSecurity real.
    if (/^Extension not allowed\b/.test(e.message)) return 'Ese tipo de fichero no se admite en la cúpula: usa una extensión permitida, por ejemplo .md para notas.';
    if (/max depth\b/.test(e.message)) return 'La ruta tiene demasiadas carpetas anidadas: usa una ruta con menos niveles dentro de la cúpula.';
    return 'La ruta no es válida o no es accesible: usa una ruta relativa dentro de la cúpula, sin «..», fuera de carpetas internas y sin enlaces que salgan de ella.';
  }
  if (e instanceof FilesError) {
    if (e.code === 'CONFLICT' || e.code === 'IDEMPOTENCY_CONFLICT') {
      return 'La versión cambió desde que la leíste: vuelve a leer el estado actual, aplica tu cambio sobre él y reintenta con la versión nueva.';
    }
    if (e.code === 'NOT_FOUND') return 'No se encontró el elemento: consulta la lista de ficheros de la cúpula antes de pedirlo.';
    if (e.code === 'POLICY_DENIED') return 'La política de la cúpula no permite esta operación: revisa el nivel de confidencialidad o pide permiso a quien administra la cúpula.';
    if (e.code === 'INVALID_INPUT') return INVALID_PARAMS;
    return undefined;
  }
  if (e instanceof RagError) {
    if (e.code === 'UNKNOWN_DOME') return UNKNOWN_DOME;
    if (e.code === 'INVALID_INPUT') return INVALID_PARAMS;
    return undefined;
  }
  if (e instanceof RouteError) {
    return 'La ruta de recuperación no es válida: quita el parámetro route para la búsqueda por defecto o usa una ruta conocida.';
  }
  const msg = e instanceof Error ? e.message : String(e);
  if (/^Dome ".*" not found/.test(msg)) return UNKNOWN_DOME;
  if (/^(POLICY_DENIED|QUARANTINED_PATH)\b/.test(msg)) {
    return 'La escritura no se admite en esa ruta o con ese nivel: usa otra ruta o un nivel de confidencialidad que la cúpula admita.';
  }
  if (/^INVALID_CLASSIFICATION\b/.test(msg)) {
    return 'El nivel de confidencialidad del frontmatter no es válido: usa N1, N2, N3, N4 o N4b y vuelve a escribir.';
  }
  return undefined;
}
