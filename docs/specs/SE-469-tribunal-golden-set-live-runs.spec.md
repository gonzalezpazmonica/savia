---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-26
author: Savia
phase: A
risk: L2
related_specs: [SE-274, SE-316, SE-269, SE-265, SE-433, SE-444, SE-449, SE-468]
origin: síntesis de una tesis sobre evaluación y aseguramiento de agentes; diseño en el repo de investigación privado
---

# SE-469 — Tribunales medidos con sus propios golden sets

## Problema

Los tribunales (truth, recommendation, code review) actúan como jueces LLM en cierres y revisiones, y pesan en merges
(SE-433) y en la autoridad del verificador (SE-444). Existen 150 casos esperados
(`tests/evals/{truth-tribunal,recommendation-tribunal,code-review-court}/cases.jsonl`, 50 por tribunal, SE-274 S2) con
`expected`, `should_trigger` y `should_not_trigger`. Pero:

- `scripts/eval-lint.sh` (SE-316) solo valida su esquema; ningún script los ejecuta contra un tribunal.
- La herramienta FP/FN existe (`scripts/judge-calibration.sh`, SE-269 S4), pero el registro local medido en el diseño
  tiene 2 líneas de prueba y el archivo de veredictos de los tribunales está vacío.

Nadie sabe cuánto acierta un juez que influye en los merges.

## Valor y evidencia

- Calibrar jueces LLM contra expertos es la recomendación común (Anthropic, *Demystifying evals for AI agents*; OpenAI,
  *Evaluation best practices*). La literatura marca también los límites: sesgos de posición, recencia y procedencia
  persistentes (arXiv 2509.26072), inconsistencia de los mejores modelos en ~¼ de los casos difíciles (arXiv
  2512.16041) y un desacuerdo del ~4–5 % entre modelos de frontera en verificadores jurídicos (LangChain/Harvey,
  jun-2026). Medir antes de confiar.
- Una medición previa en el repo de investigación privado, con jueces locales frente a un verificador determinista, dio
  especificidades de 0,80–0,95: el rango justifica medir, no presumir.

## Alcance (slice M)

| Slice | Entrega |
|---|---|
| S1 | `scripts/tribunal-golden-run.sh --tribunal X --sample N --budget-usd B [--seed S]`: muestrea N casos con semilla, invoca el tribunal real con el `input` del caso, normaliza el veredicto y lo compara con `expected` / `should_trigger` / `should_not_trigger`. Un veredicto no parseable o un `expected` desconocido cuenta como `indeterminado`, nunca como acierto. |
| S2 | Una línea por caso en el registro de `judge-calibration.sh` (formato existente), más `tribunal_version` (hash del prompt o regla) y `model` (tier, resuelto en local; SE-265). Informe en `output/` con concordancia, FP y FN por tribunal e IC95 de Wilson. |
| S3 | Ejecución bajo demanda o semanal, **nunca** en cada PR. Tope de gasto obligatorio: aborta al superarlo y conserva los parciales. Primer uso: 10 casos por tribunal (30 en total). |

## Fuera de alcance

- Ejecutar en cada PR.
- Cambiar el comportamiento de los tribunales o sustituir jueces por modelos baratos: con estos datos delante, otra spec.
- Reetiquetar golden sets sin revisión humana (si el informe muestra casos mal etiquetados, se corrige con revisión).

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | BATS negativo (demuestra que la métrica puede fallar): con un tribunal simulado que siempre devuelve «trigger», FP = 100 % sobre los casos `should_not_trigger`; con uno que siempre devuelve «no trigger», FN = 100 %. |
| AC2 | BATS: un veredicto no parseable o un `expected` desconocido cuenta como `indeterminado`, no suma aciertos. |
| AC3 | Tras una ejecución real de 30 casos hay exactamente 30 líneas nuevas en el registro, todas con `tribunal_version` y `model`. |
| AC4 | BATS: al superar `--budget-usd` (coste simulado) sale con código ≠0 y conserva los resultados parciales. |
| AC5 | El informe da el IC95 de Wilson por tribunal; con n < 30 en un tribunal advierte que el dato no es decisorio para el kill criterion. |
| AC6 | Misma semilla → misma muestra (test determinista). |
| AC7 | Criterio de salida heredado de SE-468 AC7 (decisión de la operadora 2026-10-26): conectado el ejecutor, la fixture saboteada de SE-468 S3 (artefacto vacío o saboteado de `pbi-decomposition`) da `findings` en el gate de evals; si da `unknown` o `clean`, SE-469 no se cierra. Negativo: el mismo test con el artefacto íntegro no da `findings` por sabotaje. |

## Kill criterion y decisión posterior

- Con el primer uso (10 casos por tribunal) el criterio **no es decisorio**: el límite inferior del IC95 de Wilson es
  ≈0,72 con 10/10 y ≈0,60 con 9/10, así que un solo fallo o el ruido mueven la decisión. Ese primer uso solo calibra
  coste y formato. La decisión se toma con n ≥ 30 por tribunal (90 casos, otra ejecución con su tope de gasto).
- Con n ≥ 30: si los tres tribunales superan el 85 % de concordancia con FP ≤ 10 % (IC inferior ≥ 70 %), se archiva el
  resultado y se pasa a ejecución trimestral. No hacen falta más piezas.
- Con n ≥ 30, si el límite superior del IC95 de alguno queda por debajo del 60 %, se propone en otra spec que ese tribunal no pueda ser el único verificador de un AC
  en el cierre (SE-444) hasta recalibrarlo.

## Riesgos

- Coste en tokens: acotado por el tope.
- Golden sets escritos por agentes, con sesgo del autor: el primer informe mide también el set.
- No determinismo del juez: se fija la semilla del muestreo y se repite si el IC es ancho.

## Esfuerzo

M: runner, adaptador por tribunal, informe y 5 tests. Recomendado después de SE-468, para no alimentar otra vez un gate
vacuo.

## Decisiones pendientes de la operadora

- **D1**: tope de gasto por ejecución (propuesta: 3 USD para la primera, con un modelo de tier medio).
- **D2**: dónde se publica el informe: `output/` local o resumen sin datos en el repo (propuesta: solo cifras agregadas en
  la PR).

## Referencias cruzadas

SE-274 S2 (golden sets), SE-316 (eval-lint), SE-269 S4 (calibración FP/FN), SE-265 (niveles de modelo), SE-433
(merge-sprint), SE-444 (autoridad del verificador), SE-449 (estado epistémico), SE-468 (gate de evals honesto).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/tribunal-golden-run.sh` | script invocado a mano o por automatización | el mismo |
| Invocación del tribunal | agentes `.claude/agents/*-judge.md` vía CLI headless | agentes equivalentes vía `opencode run`; adaptador por frontend |

### Verification protocol

- [ ] Los tests BATS usan un tribunal simulado y corren sin frontend.
- [ ] La ejecución real se prueba al menos una vez desde cada frontend con la misma semilla.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **DUAL_BINDING**: el runner es bash; la invocación del tribunal tiene un adaptador por frontend desde S1.
