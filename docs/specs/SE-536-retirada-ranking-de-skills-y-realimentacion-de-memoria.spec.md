---
status: PROPOSED
priority: P3
developer_type: agent-single
created: 2026-11-23
author: Savia
phase: D
risk: L2
human_surface: false
related_specs: [SPEC-SKILL-FEEDBACK, SPEC-164, SE-497, SE-515, SE-535]
origin: "Dictamen del 2026-11-23 sobre un documento de propuestas de memoria y aprendizaje (en Savia Labs). Los fallos se reprodujeron en copia aislada sobre main e3687a8cd; la retirada la decidió la operadora por pregunta interactiva."
timeline:
  - from: "2026-11-23"
    learned: "2026-11-23"
    value: "PROPOSED"
    source: "orquestadora; decisión de alcance de la operadora en pregunta interactiva del 2026-11-23"
---
# SE-536 — Retirada del ranking de skills y de la realimentación automática de memoria

## Problema (verificado en origin/main e3687a8cd, 2026-11-23; reproducido en copia aislada)

Dos mecanismos tienen fallos reales y ningún uso. Repararlos sería trabajar sobre nada.

### Ranking de skills (`SPEC-SKILL-FEEDBACK`)

1. **Nunca ha recibido un dato.** `data/skill-invocations.jsonl` no existe en la instalación comprobada. Nada llama a `scripts/skill-feedback-log.sh` salvo la orden manual `/skill-rank` y un mensaje de `scripts/skill-detect.sh`.
2. **Pierde la primera entrada.** `skill-feedback-rank.sh` usa `jq '[inputs]'` sin `-n`: tres invocaciones cuentan como dos y la skill cae en «datos insuficientes». Su propio modo `--test` escribe tres entradas y cuenta dos.
3. **La ventana de 90 días no existe.** Calcula `D90` y `D30` y no los usa: entradas de 2024 puntúan 85 % «healthy» bajo el rótulo «last 90 days».
4. **La puntuación no distingue una skill rota.** Con 0 éxitos de 6 sale 35 % «weak» y no es candidata a retirada: 20 puntos fijos más 15 por no tener opinión registrada.
5. **El registro admite JSON inválido.** `skill-feedback-log.sh` interpola los argumentos: un comentario con comillas rompe la línea.

### Realimentación automática de memoria (`SPEC-164`)

1. **Está apagada.** El hook `.claude/hooks/memory-feedback-task.sh` sale sin hacer nada salvo que `SAVIA_MEMORY_FEEDBACK=on`, y ninguna configuración lo activa. Su última telemetría es del 2026-09-29.
2. **Decide por palabras sueltas.** `scripts/memory-feedback-extractor.py` marca como fallo cualquier salida que contenga `error`, `fail`, `exception` o `traceback`, y como éxito todo lo demás. Una corrección que menciona el error que arregló se apunta como fallo; un proceso que incumple su objetivo sin escribir esas palabras, como éxito.
3. **Está registrado.** Aunque no actúa, el hook figura en `.claude/settings.json` y se invoca tras cada tarea de agente para salir de inmediato.

## Decisión de la operadora (2026-11-23, pregunta interactiva)

| Pregunta | Respuesta literal |
|---|---|
| Dos mecanismos tienen fallos reales pero no se usan: ¿qué hacemos? | «Retirar los dos (Recommended)» |

Es una decisión de alcance, no la aprobación de esta spec.

## Qué decide esta spec

Retirar ambos, cada uno en su PR. No se sustituyen por nada. Si algún día se quiere medir la eficacia de las skills o aprender de los resultados de los agentes, la condición de reapertura es la misma que la entrada del dictamen pedía y Savia ya tiene escrita: resultado ligado a un criterio comprobable y, sin evidencia, `unknown` (SE-515), y ninguna cifra concede autoridad (SE-497).

| Slice | Entrega | Tier |
|---|---|---|
| S1 | **Ranking de skills.** Se eliminan `scripts/skill-feedback-log.sh`, `scripts/skill-feedback-rank.sh` y `.claude/commands/skill-rank.md`. Se limpian sus menciones en `docs/rules/domain/skill-lifecycle.md`, `scripts/skill-detect.sh` y `tests/test-skill-detect.bats`. `docs/specs/SPEC-SKILL-FEEDBACK.spec.md` queda marcada como retirada. Recuento de órdenes actualizado donde se declare. | previsible 3; se calcula al implementar |
| S2 | **Realimentación de memoria.** Se eliminan `.claude/hooks/memory-feedback-task.sh`, `scripts/memory-feedback-extractor.py`, `tests/bats/test-memory-feedback.bats` y `tests/scripts/test_memory_feedback.py`. Se quita su registro de `.claude/settings.json` (con el pin de configuración actualizado), de `.github/hooks/savia.json`, de `hooks/routing-posttooluse.tsv` y de `docs/hooks-coverage-matrix.md`, y su mención en `scripts/turn-sdlc-audit.sh`. `docs/propuestas/SPEC-164-memory-feedback-loop.md` queda marcada como retirada. Recuento de hooks actualizado donde se declare. | previsible 4 (toca `settings.json`); se calcula al implementar |

**Fuera de la retirada, a propósito:**

- `scripts/skill-detect.sh` y su orden: leen el mismo fichero de invocaciones que nunca existió, así que hoy tampoco tienen datos. Retirarlos es otra decisión; S1 solo les quita la referencia al guion eliminado.
- `scripts/memory-decay.py` y `/memory-prune`: decaimiento por tiempo, de uso manual. No es realimentación automática.
- El fichero local `output/memory-feedback-telemetry.jsonl` no está versionado; no se toca.

## Criterios de aceptación

| AC | Criterio | Slice | autoridad_requerida |
|---|---|---|---|
| AC-1 | No existen los dos guiones del ranking ni la orden `/skill-rank`; ningún fichero los referencia salvo historial y specs cerradas | S1 | estatica |
| AC-2 | **Negativo:** `scripts/skill-detect.sh` y su suite siguen pasando sin el guion de registro; su mensaje no remite a un guion inexistente | S1 | real |
| AC-3 | No existen el hook ni el extractor ni sus dos suites; ningún registro de hooks (configuración, espejo de GitHub, tabla de enrutado, matriz de cobertura) los lista | S2 | estatica |
| AC-4 | **Negativo:** tras quitar el registro, la configuración sigue siendo JSON válido, el pin de configuración coincide y la batería de hooks pasa | S2 | real |
| AC-5 | **Negativo:** `scripts/turn-sdlc-audit.sh` no falla por la ausencia del hook | S2 | real |
| AC-6 | Los recuentos de órdenes y de hooks declarados coinciden con el árbol; las comprobaciones de deriva pasan | S1, S2 | real |
| AC-7 | Cada slice se revierte con una sola PR | S1, S2 | estatica |

## Riesgos

- **Alguien activó la realimentación en su máquina.** La variable solo puede estar en un entorno local. Si lo estaba, perderá un mecanismo que clasificaba mal; la retirada es reversible.
- **Referencias colgadas** en catálogos y recuentos: por eso AC-6.
- **S2 toca configuración sensible:** revisión humana expresa de esa PR.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Orden retirada | `.claude/commands/skill-rank.md` | La misma, vía el enlace `.opencode/commands` |
| Hook retirado | `.claude/hooks/memory-feedback-task.sh`, registro en `.claude/settings.json` | Sin plugin equivalente; se comprueba al implementar |
| Guiones | `scripts/` (comunes) | Los mismos |

### Verification protocol

- [ ] La orden retirada no aparece en el listado de órdenes de ninguno de los dos frontends
- [ ] Ningún plugin de OpenCode referencia el hook retirado
- [ ] Las suites de hooks y de deriva pasan en ambos

### Portability classification

- [x] **PURE_BASH**: retirada de ficheros comunes y de un registro de hook.

## Aprobación

Pendiente. La operadora decidió el alcance el 2026-11-23; aprobar la spec es un acto aparte. Sin superficie humana en lo que se retira.
