---
status: APPROVED
approved_at: 2026-10-27
approved_by: "operadora, AskUserQuestion 2026-10-27"
priority: P2
developer_type: agent-single
created: 2026-10-26
author: Savia
phase: D
risk: L2
related_specs: [SPEC-188-P3, SE-433, SE-454, SE-444, SE-453, SE-468, SE-469]
origin: síntesis de una tesis sobre evaluación y aseguramiento de agentes; diseño en el repo de investigación privado
condition: "Sube a P1 si la auditoría de trazas (H3) encuentra ≥1 evento confirmado; la parte (a) queda como aviso si H4 da ≥4 de 5 cambios legítimos"
---

# SE-470 — Integridad de los artefactos de evaluación

## Problema

La literatura de 2025–2026 documenta agentes que modifican tests, parchean evaluadores o leen soluciones: METR
(*Recent reward hacking*, jun-2025: o3 con 30,4 % de ejecuciones con trampa en RE-Bench y 0,7 % en HCAST), NIST CAISI
(aserciones comentadas en SWE-bench, 0,1–4,8 % según benchmark), ImpossibleBench (arXiv 2510.20270) y EvilGenie (arXiv
2511.21654). Savia tiene una defensa parcial:

- SPEC-188-P3 sella 5 tests con un hook de cliente (`.opencode/hooks/contract-test-guard.sh`, matcher `Edit|Write`,
  `.claude/contracts/allowlist.txt`). No actúa sobre Bash, en otros arneses ni en CI.
- Ni los golden sets, ni los baselines, ni los umbrales de `tests/evals/` están sellados: el agente evaluado puede
  reescribir su propia vara de medir.
- Desde 2026-07-01, 5 commits coescritos por agentes han modificado ficheros sellados sin `[contract-*]`. Todos parecen
  legítimos (añaden casos), pero el sello no los registró.
- Nadie audita las trazas de ejecución en busca de lecturas de tests ocultos o ediciones de tests.

## Valor y evidencia

- El vector está documentado fuera; dentro no hay todavía ningún evento observado. Por eso es P2 condicionada: dos
  experimentos baratos deciden si sube o se queda en aviso.
- **H3**: un recorrido determinista de recibos stream-json existentes buscando `Read`/`Bash` sobre rutas de holdout y
  `Edit`/`Write` sobre tests. Con ≥ 1 evento confirmado, sube a P1 y se invalidan las cifras de calidad afectadas; con 0
  en n ≥ 40, baja a P3.
- **H4**: reproducir la comprobación de CI sobre los 5 commits citados. Si ≥ 4 de 5 son legítimos y ninguno dañino, la
  parte (a) es aviso, no bloqueo.
- Los tests reservados no bastan solos: EvilGenie mide «only minimal improvement» con ellos, y la réplica de
  ImpossibleBench muestra que una opción explícita de parar reduce más la trampa. Por eso esta spec no propone holdout
  rotatorio.

## Alcance (slice S)

| Slice | Entrega |
|---|---|
| S1 (a) | **Comprobación en CI** (servidor, no evitable desde el cliente): compara la PR con la base y, si toca rutas de `.claude/contracts/allowlist.txt`, `tests/evals/**/cases.jsonl` o `tests/evals/baselines/**` sin `[contract-add]`, `[contract-remove]` o `[eval-change]` en el título, etiqueta la PR (`eval-integrity`) y deja un comentario. Pasa a bloqueo solo si H4 lo justifica. |
| S2 (b) | **Detector de trazas determinista** `scripts/trace-tamper-scan.py`: recibe un recibo stream-json y una lista explícita de rutas protegidas; señala (1) `Read`/`Grep`/`Bash` que lean rutas de holdout, (2) `Edit`/`Write`/`Bash` que modifiquen rutas protegidas y (3) órdenes Bash con `sed -i`, redirección `>`, `rm` o `git checkout` sobre esas rutas. Salida JSON con el contrato de SE-453. |

## Fuera de alcance

- Holdout rotatorio (poco beneficio por su coste, ver arriba).
- Sellar todo `tests/`.
- Un juez LLM de trazas: solo si el detector determinista se queda corto.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | Test que falla antes: un diff sintético que modifica `tests/evals/truth-tribunal/cases.jsonl` sin marca produce la etiqueta `eval-integrity` y el comentario (modo aviso de S1; el bloqueo solo existe si H4 lo justifica y tendrá su propio AC). |
| AC2 | Negativo: el mismo diff con `[eval-change]` en el título no la produce; un diff que no toca rutas protegidas tampoco. |
| AC3 | pytest: un recibo sintético con `Read` sobre una ruta de holdout da 1 hallazgo; un recibo limpio, 0; un `Bash` con `sed -i` sobre un test protegido, 1. |
| AC4 | El detector aplicado a un lote real de recibos produce un informe con su recuento (sea 0 o no); el recuento se cita en la PR sin rutas privadas. |
| AC5 | `capability-entropy.py --check` PASS. |

## Riesgos

- Fricción con cambios legítimos: por eso empieza como etiqueta.
- Falsos positivos del detector: las lecturas legítimas de tests visibles no se señalan porque la lista de rutas
  protegidas es explícita, sin heurísticas.
- Merge-sprint (SE-433) debe respetar la etiqueta; si no lo hace, la etiqueta es decorativa (AC del slice que integre
  ambos).

## Esfuerzo

S: un paso de CI, un script Python y sus tests.

## Decisiones pendientes de la operadora

- **D1**: etiqueta o bloqueo en (a) (propuesta: etiqueta hasta tener H4).
- **D2**: si merge-sprint trata `eval-integrity` como bloqueo de su plan (propuesta: sí, requiere revisión humana
  explícita del PR).

## Referencias cruzadas

SPEC-188-P3 (tests sellados), SE-433 (merge-sprint), SE-454 (invariantes negativos), SE-444 (autoridad del verificador),
SE-453 (contrato de resultado), SE-468 y SE-469 (evals y tribunales).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Paso de CI `eval-integrity` | GitHub Actions, independiente del frontend | el mismo |
| `scripts/trace-tamper-scan.py` | lee recibos stream-json de Claude Code | lee el formato de eventos de OpenCode con un adaptador de entrada |

### Verification protocol

- [ ] El paso de CI no depende del frontend.
- [ ] El detector tiene fixtures de recibo de los dos frontends (o SKIP justificado si OpenCode no emite el formato).
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **DUAL_BINDING**: CI común; el detector acepta los dos formatos de traza desde S2.
