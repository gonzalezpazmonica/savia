---
context_tier: L2
token_budget: 900
spec_ref: SE-350
---

# Coherence Court — Multi-Judge Transversal Consistency Audit

> SE-350. Extrae el patrón "jueces paralelos + scoring + gate" de Code Review Court
> a un componente transversal, desacoplado del dominio de código. Audita la
> **coherencia relativa** entre la salida de la etapa actual y las premisas /
> decisiones / restricciones fijadas en etapas anteriores del **mismo flujo**.
>
> **Pattern alignment**: implementa Genesis **A7 ADVERSARIAL REVIEW** — ver `docs/rules/domain/attention-anchor.md` (SE-080).

## The Court

| Judge | Focus | Agent |
|-------|-------|-------|
| factual | Stage output contradicts facts fixed earlier | `coherence-factual-judge` L1 |
| scope | Violates scope/constraints fixed earlier | `coherence-scope-judge` L1 |
| objectives | Contradicts declared objectives of the flow | `coherence-objectives-judge` L1 |
| premise-drift | Silent premise drift between stages | `coherence-premise-drift-judge` L1 |

Orchestrator: `coherence-court-orchestrator` (L4) — convenes, consolidates, gates.

## Flow

```
1. coherence-court.sh check --flow F --stage-output FILE   (gate de flujo multi-etapa)
2. coherence-court.sh premises F add <kind> <content>      (registro de premisas previas)
3. coherence-court.sh skeleton F <output>                  (genera .coherence.crc)
4. 4 judges review in parallel (fork agents, isolated context)
5. coherence-court-orchestrator consolidates → .coherence.crc
6. coherence-court.sh gate <score> → 0 PASS / 2 CONDITIONAL / 1 FAIL
   (score, --threshold, --conditional y los C H M L de `score`: enteros >= 0,
   validados antes de evaluar; --conditional <= --threshold; flujo sin '/')
7. If FAIL → puerta humana: NO continuar el flujo; humano decide (CRITERIO.md)
```

## Scoring

```
score = 100 - (critical × 25) - (high × 10) - (medium × 3) - (low × 1)
```

| Score | Verdict | Acción |
|-------|---------|--------|
| 90-100 | pass | Continuar flujo (revisión humana ligera) |
| 70-89 | conditional | Revisar discrepancias antes de continuar |
| < 70 | fail | **Puerta humana**: NO continuar el flujo |

Thresholds configurables: global (`COHERENCE_SCORE_PASS`, `COHERENCE_SCORE_CONDITIONAL`)
o por flujo (`rules/coherence.rules.yaml` → `per_flow`).

## Premises registry

`data/coherence-premises-{flow}.jsonl` (gitignored, texto plano local, N3+ nunca sale
de la máquina — CRIT-001). Cada línea es una premisa `{premise_id, flow, stage, kind,
content, source, added_at}`. Kinds: `fact | constraint | objective | decision`.

## Qué NO hace

- No sustituye el juicio humano ni genera veredictos vinculantes.
- No evalúa calidad/corrección absoluta — solo coherencia relativa entre etapas.
- No opera en flujos de una sola etapa (sin "anterior" con qué comparar).
- No auto-resuelve discrepancias: detecta y reporta. "Se delega la ejecución, nunca el criterio."

## .coherence.crc artifact

Per-flow file con YAML frontmatter (schema gemelo de `.review.crc`): `court_id`,
`flow_ref`, `stage_ref`, premisas referenciadas, veredictos de los 4 jueces, score
consolidado, rounds de fix-cycle, firma. Schema: `.claude/schemas/coherence-crc.schema.json`.

## Commands & scripts

- `scripts/coherence-court.sh` — CLI (check/premises/skeleton/score/gate/hash)
- `/coherence-court` — command de invocación

## Config

```
COHERENCE_SCORE_PASS = 90
COHERENCE_SCORE_CONDITIONAL = 70
COHERENCE_PREMISES_DIR = <workspace>/data
```

Ver también `rules/coherence.rules.yaml` (weights, per-flow overrides, gate).

## Integración

- `code-review-court.md`: Code Review Court queda como primera instancia concreta
  especializada en código; migración a consumir Coherence Court = spec separada.
- `autonomous-safety.md`: Coherence Court aplica en modos autónomos (overnight-sprint,
  research) como capa de verificación transversal; nunca sustituye la supervisión humana.
- `court-numeric-scoring.md`: reutiliza la fórmula de scoring 0-100 y pesos.

## Flujos cableados (SE-350 Slice 2)

| Flujo | Punto de cableado | Coste |
|---|---|---|
| overnight-sprint (`overnight-sprint-loop.sh`) | `premises add decision` post-tarea + gate `check` al cierre | determinista ~0 |
| tech-research-agent | premisas del plan al arrancar + gate `check` en cada transición de fase | determinista ~0 |
| code-improvement-loop | `premises add decision` por mejora aceptada | determinista ~0 |

**Política anti-saturación**: el gate **determinista** (premises + `check`, sin
LLM) corre siempre en el bucle. La **auditoría LLM de 4 jueces** se invoca
**una sola vez al final del flujo** (o en revisión E1 humana), nunca por tarea —
`/coherence-court --flow {flujo}`, opt-in vía `COHERENCE_AUDIT_JUDGES=1`.
Motivo: ejecutar 4 jueces LLM por tarea en un bucle nocturno de N tareas
dispararía N×4 llamadas LLM (saturación y coste). CRIT-001: todas las premisas
son JSONL local, cero red.
