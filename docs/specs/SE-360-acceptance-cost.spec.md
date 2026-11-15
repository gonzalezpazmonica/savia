# SE-360 — Costo por cambio aceptado: métrica de time-to-acceptance descompuesta

**Status:** APPROVED (2026-08-31, operadora grant merge sesión nocturna)
**Fecha:** 2026-08-31
**Área:** Observabilidad / Métricas / Delivery
**Fuente de inspiración:** Anthropic AI-Native SDLC Playbook (métrica de tiempo desde cambio generado hasta aceptado, descompuesta por etapa)
**Criterio humano aplicable:** CRIT-001 (todo local)

---

## Objetivo

Instrumentar la métrica **costo por cambio aceptado** en Savia: el tiempo desde
que un cambio se genera (commit/PR agent) hasta que se acepta (merge/review),
**descompuesto por etapa**: cola de CI, ejecución de CI, revisión, remediación
(ciclos de fix tras review) y gobernanza (pr-plan, gates, approvals). La métrica
se deriva de hechos ya registrados — no requiere nueva captura manual.

## Contexto

Verificado en esta sesión: Savia ya registra hechos de PR en `agent-runs-ledger.jsonl`
(SE-349: `pr.number/state/ci/review/mergeable/url`), decisiones en
`focal-decisions.jsonl`, y el audit ledger SE-355. **Lo que falta**: una métrica
agregada que descomponga el tiempo total de un cambio por etapa y permita ver
dónde se acumula el coste (cola de CI vs review vs remediación). El playbook
insiste en que "el bottleneck se mueve a los pasos a la izquierda y derecha del
build" — medirlo es el primer paso para atacarlo.

**Rechazo explícito (CRIT-001):** sin telemetría cloud. El agregador lee los
ledgers locales (`data/`) y produce el informe local.

## Diseño

### 1. Fuente de hechos

- `data/agent-runs-ledger.jsonl` (SE-349): run_id, branch, pr {number,state,ci,review,mergeable,url}, timestamps
- `data/audit/actions.jsonl` (SE-355): receipts de pr_merge, gate_deny, etc.
- `output/pr-plan-*.log`: timestamps de gates

### 2. Agregador `scripts/acceptance-cost.sh`

Descompone por cambio (PR) el tiempo total en:

| Etapa | Definición | Fuente |
|---|---|---|
| `cola_ci` | push → primer check start | ledger pr.ci + run timestamps |
| `ci` | primer check start → checks green | ledger pr.ci |
| `revision` | PR open → primera review | ledger pr.review |
| `remediacion` | review changes_requested → PR green de nuevo | ciclos review |
| `gobernanza` | pr-plan / gates / approval humana | audit receipts |

Salida: tabla por PR + agregado (p50/p95 por etapa) + el stage bottleneck.

### 3. Reporte

`scripts/acceptance-cost.sh --days 30 --format markdown|json` → informe en
`output/research/acceptance-cost-{date}.md`.

## Criterios de aceptación

- **AC-0** Agregador calcula tiempo total = suma de etapas para un PR (test con ledger sintético)
- **AC-1** Descompone por etapa (cola_ci, ci, revision, remediacion, gobernanza)
- **AC-2** Identifica el stage bottleneck (mayor p50) por PR
- **AC-3** Reporte markdown y JSON válido
- **AC-4** Lee solo fuentes locales (sin red, sin cloud)
- **AC-5** Sin regresión: ledger SE-349/SE-355 intactos (solo lectura)

## OpenCode Implementation Plan

### Bindings touched
- `scripts/acceptance-cost.sh` (nuevo), `scripts/acceptance-cost-agg.py` (nuevo)
- Reutiliza: SE-349 ledger, SE-355 audit

### Verification protocol
```bash
bats tests/bats/test-acceptance-cost.bats
bash scripts/acceptance-cost.sh --days 7 --format json
```

### Portability classification
- Bash + python3 stdlib; local; portable

## Validación (ejecutada en esta sesión)

- `scripts/acceptance-cost-agg.py`: descompone por etapa (cola_ci, ci, revision, remediacion, gobernanza), p50/p95, bottleneck; ledgers vacíos no fallan; 6 pytest + 3 bats verdes
- `scripts/acceptance-cost.sh`: wrapper CLI (markdown/json) → `output/research/acceptance-cost-{date}.md`

## Referencias
- Anthropic: claude.com/blog/the-ai-native-sdlc-playbook (métrica de aceptación)
- Savia: SE-349 (ledger runs), SE-355 (audit), SE-534 (telemetría), CRIT-001
