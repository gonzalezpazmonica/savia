---
layer: peripheral
name: agent-runs-board
description: "Usar cuando se lanza, supervisa o consulta un run autónomo (overnight-sprint, code-improvement-loop, tech-research-agent, SDD) y se necesita el ledger operativo con estado derivado. Triggers: 'registra el run', 'board de runs', 'estado del run', 'savia-runs', '¿en qué columna está mi run?', 'ci_failed', 'needs_input', 'merge_conflict'."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: dev-orchestrator
  savia.category: pm-operations
  savia.context: fork
  savia.loop_level: L0  # L0=draft | L1=report-only | L2=assisted | L3=unattended — ver docs/rules/domain/loop-phasing.md
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Ledger operativo de runs autónomos (SE-349): hechos durables + estado derivado en lectura + board Working/Needs you/In review/Ready to merge/Done. Guardrail: un run con PR vivo no es terminable."
  savia.tags: "autonomous, observability, ledger, board, se-349"
---

## Subagent Scope Guard

> If you were dispatched as a subagent to execute a specific delegated task,
> **skip this skill's full orchestration workflow**. Execute only the assigned
> task, report result (DONE / DONE_WITH_CONCERNS / BLOCKED), and return.

# Skill: Agent Runs Board (SE-349)

> Fuente de verdad: `docs/specs/SE-349-agent-runs-ledger.spec.md`

## Cuándo usar

- Estás lanzando un run autónomo (overnight-sprint, code-improvement-loop,
  tech-research-agent, agent-task, SDD) y debes **registrarlo** en el ledger.
- Quieres saber **en qué columna está** cada run o **qué necesita atención**.
- Un PR de un run falla CI o recibe `changes_requested` y necesitas localizar
  el run que lo posee.

## Paths autoritativos (lee ANTES de actuar)

| Recurso | Path |
|---|---|
| Script CLI | `scripts/savia-runs.sh` |
| Spec | `docs/specs/SE-349-agent-runs-ledger.spec.md` |
| Ledger (datos) | `data/agent-runs-ledger.jsonl` (gitignored) |
| Inspiración | https://github.com/Untrivial-ai/agent-orchestrator (`docs/architecture.md`) |

## Modelo mental

**El estado de display NUNCA se almacena.** El ledger solo guarda hechos
durables (`activity_state`, `is_terminated`, hechos de PR). El estado visible
(working, needs_input, ci_failed, changes_requested, merge_conflict, approved,
review_pending, pr_open, draft, merged, terminated, idle) se **deriva en
lectura** por precedencia. Si no ves una columna, no es que el run esté roto:
es que sus hechos no la producen todavía.

## Flujo de registro (obligatorio al lanzar un run)

```bash
# 1. Nace el run → devuelve run_id
R=$(bash scripts/savia-runs.sh start <mode> <agent> "<task>" \
      --project <proyecto> --branch <rama agent/*>)
# mode ∈ overnight|improve|research|agent-task|sdd

# 2. A medida que avanza
bash scripts/savia-runs.sh state "$R" active        # trabajando
bash scripts/savia-runs.sh state "$R" waiting_input # esperando input
bash scripts/savia-runs.sh state "$R" blocked       # bloqueado (permiso)

# 3. Cuando hay PR
bash scripts/savia-runs.sh pr "$R" <number> \
      --state open --ci passing --review requested --mergeable true

# 4. Cuando el PR se resuelve → actualiza hechos, no fuerces
bash scripts/savia-runs.sh pr "$R" <number> --state merged --ci passing --review approved
```

## Guardrail de terminación (NO lo esquives)

`finish` **se niega** si el run posee un PR `open|draft` vivo. Es deliberado:
un run cuyo PR sigue vivo (CI pendiente, review, mergeable) **no está muerto**.
Camino correcto:

1. Resuelve el PR (merge/close) y actualiza `pr --state merged|closed`.
2. O desposee explícitamente: `bash scripts/savia-runs.sh pr "$R" clear`.
3. Entonces: `bash scripts/savia-runs.sh finish "$R"`.

`--force` es último recurso documentado, no atajo de rutina.

## Lectura del board

```bash
bash scripts/savia-runs.sh status          # board derivado (Working/Needs you/...)
bash scripts/savia-runs.sh status --json   # machine-readable
bash scripts/savia-runs.sh list --json     # tabla con derived_status
bash scripts/savia-runs.sh list --mode overnight
bash scripts/savia-runs.sh show "$R"       # hechos + derivado + traza de precedencia
```

### Qué significa cada columna

| Columna | Significado | Acción esperada |
|---|---|---|
| WORKING | run activo sin señales de bloqueo | observar |
| NEEDS YOU | `needs_input`, `ci_failed`, `changes_requested`, `merge_conflict`, `blocked` | **aquí está el trabajo**: input, fix CI, resolver cambios o conflicto |
| IN REVIEW | PR abierto/draft esperando review | revisar o esperar revisores |
| READY TO MERGE | PR aprobado y mergeable | merge humano |
| DONE | PR merged | archivar |
| TERMINATED | run terminado sin merge | revisar por qué |

## Reglas de datos (CRIT-001)

- Todo es **local** (`data/agent-runs-ledger.jsonl`, gitignored). Cero red,
  cero telemetría a proveedor (AO usa PostHog cloud — SE-349 lo rechaza).
- NO escribas el ledger a mano; usa el CLI (upsert por `run_id`).
- N3+ no sale del workspace; el ledger es dato operativo interno.

## Referencia rápida del CLI

```
savia-runs.sh init                                     # asegura ledger
savia-runs.sh start  <mode> <agent> <task> [--project P] [--branch B] [--url U]
savia-runs.sh state  <run_id> <spawning|active|waiting_input|blocked|exited>
savia-runs.sh pr     <run_id> <number> [--state open|draft|merged|closed]
                      [--ci passing|failing|pending|unknown]
                      [--review none|requested|changes_requested|approved]
                      [--mergeable true|false|unknown] [--url U]
savia-runs.sh pr     <run_id> clear                    # desposee el PR
savia-runs.sh finish <run_id> [--force]                # guardrail de terminación
savia-runs.sh status [--json]                          # board derivado
savia-runs.sh list   [--mode M] [--json]               # tabla con derived_status
savia-runs.sh show   <run_id>                          # hechos + traza
savia-runs.sh reset                                    # dev/test: vacía ledger
```
