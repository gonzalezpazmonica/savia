---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-26
author: Savia
phase: A
risk: L1
related_specs: [SE-349, SE-444, SE-453, SE-332, SE-458, SE-472]
origin: síntesis de una tesis sobre calendario agéntico y sprint nocturno; diseño en el repo de investigación privado
---

# SE-471 — Relevo nocturno con evidencia: declarado, validado y aceptado

## Problema

Por la mañana, la persona que revisa el trabajo autónomo nocturno abre una a una las marcas de fin de cada worker
(`<runs>/<nombre>/done`), de 1–3 líneas: `ESTADO: OK|PARCIAL|FALLO`, una URL o un motivo, y la siguiente acción. Dos
defectos:

1. **«OK» lo declara el propio ejecutor.** No dice nada de CI, revisión independiente ni merge. Output generado,
   validación y outcome aceptado son tres cosas distintas (SE-444 lo exige para los AC; el relevo no lo aplica).
2. **Las decisiones pendientes están dispersas.** PARCIAL, FALLO y las líneas «Siguiente» se leen en orden de
   directorio, no por lo que desbloquean.

Muestra de referencia medida en el diseño: 159 marcas, 125 OK, 24 PARCIAL y 10 FALLO (21 % no OK). El ledger SE-349 tiene
3 entradas porque la orquestación por cola no lo alimenta. El horizonte de tareas de los agentes se mide al 50 % de éxito
(METR, mar-2025); al 80 % es varias veces menor, así que una noche sin validación independiente produce «OK» falsos.

## Valor y evidencia

- Es el único punto de la tesis que toca un dolor medido, y es barato (solo lectura).
- Agrupar decisiones también puede empeorar la calidad: un lote grande de aprobaciones se aprueba sin mirar (fatiga de
  aprobación, sesgo de automatización). Por eso el digest tiene **tope** y muestra primero lo que bloquea; encaja con el
  presupuesto de atención de SE-458.
- No hay evidencia de que un resumen reduzca el tiempo de coordinación (con alta adopción de IA, el tiempo de revisión
  sube; Faros AI 2025, correlacional). El kill criterion lo mide en vez de suponerlo.

## Alcance (slice S)

`scripts/overnight-handoff-digest.sh` (nombre provisional), de **solo lectura**, con núcleo Python stdlib si hace falta:

```
overnight-handoff-digest.sh --runs-dir <dir> [--since <ISO>] [--log <fichero>]
                            [--online] [--max-decisions 7] [--format md|json]
```

| Slice | Entrega |
|---|---|
| S1 | **Offline**: lee las marcas `done` y, opcionalmente, un log `<ISO> start|end <nombre> [rc=N]`. Por run: `declarado` (OK/PARCIAL/FALLO/sin marca/malformada), `validado` y `aceptado` = `desconocido`. Lista de decisiones con tope, en este orden: (1) sin marca con `end` rc≠0, (2) FALLO, (3) OK con `validado: no`, (4) PARCIAL, (5) malformada. Cada entrada lleva su «Siguiente» literal y la ruta de la marca; lo que pasa del tope se cuenta («+N sin listar»). Cabecera con totales y ventana temporal. |
| S2 | **Online** (`--online`): por cada URL de PR, `gh pr view --json state,isDraft,reviewDecision,statusCheckRollup,mergedAt`. `validado: sí` si CI verde **y** sin CHANGES_REQUESTED; `no` si CI rojo o cambios pedidos. `aceptado: sí` si merged. Sin red o sin `gh`, se degrada a offline y lo dice. |

La raíz de runs es siempre un parámetro: ninguna ruta en el código.

## Fuera de alcance

Escribir en el ledger SE-349 (slice posterior, otra decisión), recomendar foco más allá del orden de decisiones,
notificar, programarse con cron, leer diffs o contenido de PRs.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | Fixture de 6 runs (OK, OK con CI rojo simulado, PARCIAL, FALLO, sin marca con rc=1, marca malformada): la salida JSON clasifica cada run como se espera y las decisiones respetan el orden de S1. |
| AC2 | Negativo: una marca sin línea `ESTADO:` sale como `malformada` y aparece en decisiones; nunca cuenta como OK. |
| AC3 | Negativo: offline, ningún run sale con `validado: sí` ni `aceptado: sí`; se muestra `desconocido`, nunca un valor inferido. |
| AC4 | Con `--max-decisions 2` y 5 candidatas se listan 2 y la salida dice «+3 sin listar». |
| AC5 | El script no escribe fuera de stdout: test que compara mtimes del árbol de fixtures antes y después. |
| AC6 | `--online` con `gh` simulado en un `PATH` falso produce los tres estados; si `gh` falla, aviso «degradado a offline» y exit 0. |
| AC7 | < 2 s offline sobre 200 marcas generadas. |

Cada AC tiene su test BATS y la aserción falla si se elimina la lógica correspondiente (SE-456).

## Métrica y kill criterion

- Primer uso: medir el porcentaje de OK no validados sobre las marcas existentes. Si es < 5 %, se eliminan las columnas
  `validado`/`aceptado` y queda una lista simple.
- Durante 10 mañanas, minutos declarados por la persona revisora hasta cerrar la lista de decisiones, frente a la lectura
  manual (sin telemetría de actividad). **Kill**: si la mediana no baja ≥ 30 %, o el digest omite una decisión que estaba
  en las marcas, se retira el script.

## Riesgos

- Otro informe sin uso: mitigado por el kill criterion y por ser un único script, sin skill ni comando nuevos.
- Fomentar aprobar sin mirar: tope de decisiones y la discrepancia «OK sin validar» en primera línea.
- Formato de marca no normado: parser tolerante que marca `malformada` en vez de adivinar.

## Esfuerzo

S: un script, fixtures y 7 tests.

## Decisiones pendientes de la operadora

- **D1**: si la orquestación por cola registra también en el ledger SE-349 (propuesta: otra spec, después del kill
  criterion).
- **D2**: normar el formato de la marca de fin en `autonomous-safety-reference.md` (propuesta: sí, con el formato que el
  parser ya tolera).

## Referencias cruzadas

SE-349 (ledger de runs), SE-444 (autoridad del verificador), SE-453 (contrato de resultado), SE-332 (handback), SE-458
(presupuesto de atención), SE-472 (vigencia por tarea; sus tareas suspendidas aparecen como decisión).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/overnight-handoff-digest.sh` | script invocado a mano | el mismo |

### Verification protocol

- [ ] Los tests corren sin frontend.
- [ ] Sin hooks nuevos.
- [ ] Las marcas de fin las escriben workers de cualquier frontend con el mismo formato.

### Portability classification

- [x] **PURE_BASH**: lectura de ficheros y `gh` opcional; ningún binding de frontend.
