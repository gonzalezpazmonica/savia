# SE-529 S0 — forma de las cargas y línea base de compactación

Fecha de medición: 2026-11-13. Solo cifras: ningún texto de conversación ni del almacén entra aquí.
Herramientas: `scripts/compaction-shape-collector.py` (S0.1), `scripts/compaction-shape-probe.py` (S0.1/S0.2), `scripts/compaction-baseline-counts.py` (S0.3/S0.4). Tests: `tests/test-compaction-shape-collector.bats` (12), `tests/test-compaction-baseline-counts.bats` (6).
Frontends: Claude Code 2.1.322 (`claude -p`, modelo haiku), OpenCode 1.19.5 (servidor local, API de sesión, plugin desechable en un directorio temporal).

## Parámetros de S0.5 (fijados antes de cualquier código de S1/S2)

| Parámetro | Valor fijado | Fundamento medido |
|---|---|---|
| Tope de reinyección | **4096 bytes** | S0.2 solo midió que una marca llega al modelo; no midió desplazamiento del resumen del frontend, así que no hay base para subir hacia 6144. Resumen del frontend en 35 compactaciones reales: mediana 16 392 B, P90 19 404 B, máx. 22 594 B. Hoy `post-compaction.sh` imprime 722 B. |
| Lectura máxima del transcript (desde el final) | **589 824 bytes** (576 KiB) | P90 de los bytes que cubren las 30 últimas vueltas (user+assistant) antes de cada frontera: **525 894 B** (n = 35; mediana 242 819; máx. 3 218 224). Siguiente múltiplo de 64 KiB que lo contiene. En 7 de 35 fronteras había menos de 30 vueltas (se lee todo el fichero). Las líneas que no son vueltas (bloques de petición de API de hasta 59 KB) inflan el valor, de ahí que supere la hipótesis de 262 144. |
| Qué cuenta como «fijada» | **`importance_tier` A** | En el almacén real A es 1 de 22 (4,5 %), por debajo del 30 %: no se activa Q1. Aviso: con una sola entrada A, «fijadas» será casi siempre vacío hoy. |

Estos valores no se cambian sin spec ni Causal-Evidence.

## S0.1 — forma de las cargas (6 celdas)

| Evento | Frontend | Entrega | Campos (tipo, bytes) | Tamaño de la carga | ¿Trae el resumen compactado? |
|---|---|---|---|---|---|
| PreCompact | Claude Code | entregado | `session_id` str 36, `transcript_path` str 94, `cwd` str 21, `hook_event_name` str 10, `trigger` str 6 (manual/auto), `prompt_id` str 36, `custom_instructions` null | 327 B | no |
| PostCompact | Claude Code | entregado | `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `trigger`, `prompt_id` (mismos tamaños) + **`compact_summary` str 1 736 B** | 2 105 B (resumen trivial; reales 16–22 KB) | **sí** (`compact_summary`) |
| SessionStart (origen compact) | Claude Code | entregado | `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `source` (= compact), `model`, `prompt_id` | 329 B | no |
| PreCompact = `experimental.session.compacting` | OpenCode | entregado | `input.sessionID` str 30; `output.context` lista vacía | 80 B | no |
| PostCompact = `session.compacted` | OpenCode | entregado | `id` str 30, `type` str 17, `properties.sessionID` str 30 | 126 B | no |
| SessionStart origen compact (equivalente: `experimental.compaction.autocontinue`) | OpenCode | **no entregado** (no observado en 2 compactaciones; no existe un SessionStart equivalente) | — | — | no |

Notas:
- OpenCode **no entrega `transcript_path` ni equivalente** en ninguno de los eventos medidos. La conversación y el resumen viven en la API de sesión del servidor, fuera de la carga del hook.
- Limitación: en OpenCode las dos compactaciones se forzaron con `POST /session/:id/summarize` sobre sesiones **sin turnos** (la llamada de chat a los modelos gratuitos disponibles devolvió error de servidor). Prueba la forma de los eventos, no el comportamiento con historial real.
- `transcript_path` (Claude Code): existe en los tres eventos, en la carpeta de datos del frontend (`~/.claude/projects/<proyecto>/<sesión>.jsonl`, ruta absoluta), fichero regular de la persona, formato un JSON por línea. Tipos de línea vistos: `user`, `assistant`, `attachment`, `system` (subtipo `compact_boundary`), `queue-operation`, `last-prompt`, `api-request`, `api-request-blob`, `api-request-shape`, `session-owner`, `cost-state`, `mode`, `atis-latch`. Bloques de contenido vistos en la sonda: `text`, `thinking`, cadena simple y un tipo de adjunto de herramientas.
- Orden de escritura: en `PreCompact` y `PostCompact` el transcript **todavía no contiene** la línea `compact_boundary`; en las 35 compactaciones previas, la frontera (`system:compact_boundary`, con `trigger`, `preTokens`, `postTokens`, `durationMs`) va seguida del resumen en una línea `user` con `isCompactSummary: true`. Es decir, en Claude Code el resumen está en el transcript y también en `compact_summary` de `PostCompact`.
- Tamaño típico del transcript en el momento de compactar (sesión de prueba mínima): 244 KB; reales: ver P50/P90 en S0.3.

## S0.2 — canal de reinyección

Método: dos marcas aleatorias sin significado (12 hex), una impresa por un hook `PostCompact` y otra por un hook `SessionStart` origen compact; sesión nueva, `/compact`, y en el turno siguiente se pregunta qué cadenas con ese patrón ve el modelo (la pregunta no contiene las marcas; las marcas no aparecen en la orden del hook, que las lee de un fichero).

| Vía | Rondas con la marca en el contexto del modelo |
|---|---|
| Salida de `PostCompact` | **5 de 5** |
| Salida de `SessionStart` origen compact | **5 de 5** |

Más 2 rondas preliminares, una con confusión (la orden del hook contenía la marca y falló) y una limpia, también positivas.

Conclusión (AC-2): **ambas vías llegan al modelo en `claude -p`**; la reinyección actual por `PostCompact` no es inalcanzable, por lo que S2 no queda bloqueado y la PR de `settings.json` (tier 4, Q3) **no es necesaria por motivos de alcance del canal**. Límites que quedan abiertos: (1) solo se midió modo no interactivo y modelo haiku; el modo interactivo no se ha probado; (2) se usaron marcas impresas por hooks de prueba, no el `post-compaction.sh` real ni `session-hot.md`, porque probarlos exige registrarlos en `settings.json` (tier 4, fuera de este encargo); (3) no se midió si el bloque desplaza al resumen (de ahí el tope de 4096).

## S0.3 — línea base de extracción

Compactaciones de Claude Code encontradas en transcripciones locales (3 131 sesiones revisadas): **35** (28 automáticas, 7 manuales), repartidas en 3 proyectos (28 / 5 / 2). Todas tienen línea de resumen. **AC-3 (≥ 10 en Claude Code): cumplido por conteo de transcripciones.**

- Elementos extraídos por el hook: **no medible desde las transcripciones**: la salida de `PreCompact` no se persiste en ellas (0 apariciones de «Pre-compact: N items extracted» en todas las transcripciones). Indicadores indirectos: 0 entradas con origen «pre-compact auto-save» en el almacén activo (22 entradas) ni en su archivo (22 entradas); 12 filas «Session Context» acumuladas en 11 ficheros `session-hot.md` (no atribuibles a una compactación concreta).
- Las 35 compactaciones son históricas: no se capturó la carga de entrada del hook en ellas. El colector queda listo (ver abajo) para recogerlas en las próximas.
- Muestra de 10 con lectura humana del hueco (decisiones reales vs extraídas): **no hecha** (exige leer conversaciones; queda para la operadora o una pasada autorizada).
- OpenCode: **2 compactaciones** medidas (sesiones vacías), por debajo del mínimo de 3 con historial real. **Carencia declarada**; AC-3 queda abierto para OpenCode.

## S0.4 — línea base de reinyección (almacén activo)

- Entradas: **22** (0 líneas corruptas). `"project":"null"`: **18 (81,8 %)**; 3 nombres de proyecto distintos (2 / 1 / 1 entradas).
- Reparto por `importance_tier`: A = 1 (4,5 %), B = 8, C = 13.
- `post-compaction.sh` con el almacén real (HOME aislado para no vaciar `session-hot.md`): imprime **722 bytes** en 13 líneas, sale 0. De las 20 últimas entradas que lee, **2 (10 %)** pertenecen al proyecto activo; el resto son «null» u otros proyectos. Confirma la mezcla entre proyectos descrita en la spec.

## Estado frente a los AC de S0

| AC | Estado |
|---|---|
| AC-1 (6 celdas) | informe completo; el comprobador automático no existe aún (no era de S0) |
| AC-2 (canal) | cumplido: ambas vías 5/5, con límites declarados |
| AC-3 (línea base) | parcial: Claude Code ≥10 por conteo de transcripciones; elementos extraídos por el hook no medibles; muestra humana pendiente; OpenCode 2 de 3 (carencia declarada) |
| Parámetros S0.5 | fijados arriba |

## Recoger compactaciones reales los próximos días

El colector es opt-in (`SAVIA_COMPACT_SHAPE=1`) y no está registrado en `settings.json`. Sin tocarlo, una sesión de Claude Code lo activa con `--settings <fichero-personal>` que registre `PreCompact`, `PostCompact` y `SessionStart` (origen compact) con la orden `python3 -I scripts/compaction-shape-collector.py --event <evento> --frontend claude-code` (lee la carga por stdin, no imprime nada, siempre sale 0). El registro va a `~/.local/state/savia/compact-shape.jsonl` (permisos 600) o a `SAVIA_COMPACT_SHAPE_LOG`. `scripts/compaction-shape-probe.py --dry-run` imprime un fichero de ejemplo. Registrarlo de forma permanente en `settings.json` sería una PR aparte, tier 4.
