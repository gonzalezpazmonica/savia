# SE-376 — Structural Quality Debt Burn-down

**Estado:** APPROVED — Mónica (operadora), 2026-09-05: "Apruebo todas, implementa, pr y merge"
**Prioridad:** P0 · **Developer Type:** agent-team · **Context Risk:** medium
**Origen:** auditoría externa §7 (STILL_RECOMMENDED con baseline corregido)

## 1. Motivación

Los ratchets impiden empeorar pero no obligan a reducir deuda (F3). Cifras del auditor NO reproducen y se corrigen:

| Métrica audit | Real medida 2026-09-05 | Fuente |
|---|---|---|
| "27 agentes sobredimensionados" | **0** (ningún agente >150 líneas) | `validate-ci-local.sh:29-30` sobre `.opencode/agents` |
| "155 skill-quality-violations" | **132 skills no calibradas** (2 Calibrated / 124 Incomplete / 8 Stub / 0 Deprecated) | `scripts/skill-maturity-audit.sh` (SE-167), `output/skill-maturity-kanban-20260905.md` |

## 2. Alcance

Programa de burn-down sobre la deuda REAL medida por los gates existentes (SE-167 kanban, size gates, ci-reliability), no sobre cifras del audit.

### Debt budget (formato)

```yaml
skill_maturity:
  current: 132        # Incomplete+Stub
  target_wave_1: 90
  target_wave_2: 40
  final: 0            # o excepciones aprobadas explícitamente
agent_size:
  current: 0
  final: 0
```

### Clasificación de cada violación

`DELETE | MERGE | SPLIT | REFACTOR | FALSE_POSITIVE | LEGITIMATE_EXCEPTION`

## 3. Reglas

- Nunca subir baseline. Nunca relajar threshold sin spec explícita.
- Nunca añadir excepción solo para silenciar el auditor.
- Toda excepción registra: razón, owner, fecha, re-evaluation date.
- Antes de SPLIT, comprobar MERGE/DELETE. Antes de ampliar una skill, comprobar overlap (SE-270).
- Arreglar una capability NO debe significar hacerla más grande.

## 4. Criterios de aceptación

- Inventario completo con clasificación por skill.
- Cada wave reduce el baseline del budget (verificable en CI).
- Cero regresiones en evals de comportamiento (paired-delta).
- Objetivo final: 0 o excepciones aprobadas por la operadora.

## 5. OpenCode Implementation Plan

### Clasificación
- **Tier:** 2 · **Agent-capable:** yes (inventario+budget) / hybrid (curation por waves)
- **Slices:** S1 debt-budget.yaml + checker · S2 inventario clasificado heurístico (propuestas) · S3 wiring CI diferido (workflows = tier 4)
- **Nota:** objetivos wave del audit: 132→95→40→0

## Referencias

- Auditoría externa §7 · SE-167 · SE-270 · SE-046 `baseline-tighten.sh` · SPEC-109

## Avance

### 2026-10-02 — grupo por riesgo y uso (127 → 124/137)

La deuda remedida el 2026-10-02 es 127/137: 120 Incomplete, 7 Stub y 10 Calibrated. El 27/09 era 128. La operadora eligió un grupo de tres skills por riesgo y uso y aprobó su promoción a `stable`:

| Skill | Test | Auditor | Qué prueba |
|---|---|---|---|
| `agent-messaging` | `tests/test-agent-messaging.bats` (#1180) | 87 | ya certificado; faltaba la promoción |
| `overnight-sprint` | `tests/test-overnight-sprint.bats` (16) | 93 | doble opt-in: los dos factores, el valor exacto, el grant SE-343 y que el bypass solo funcione dentro de BATS; clasificación de fallos SE-250; `STATE.md` de SE-228 |
| `savia-vaults` | `tests/test-savia-vaults.bats` (9) | 86 | cada comando documentado existe en la CLI; ciclo de usuarios y tokens de SE-423 (0600 y sin el secreto, alcance, revocación, rename, máximo de días) |

**Hallazgo.** `.claude/skills/savia-vaults/SKILL.md` documentaba un binario `vaults` que no existe y comandos que tampoco existen (`server start`, `dome sync`, `dome index`, `health`, `config show`). Se ha reescrito con los comandos reales. El test falla si vuelve a aparecer un comando inexistente: verificado con la versión anterior y con un subcomando inventado.

**Resultado.** `scripts/debt-budget-check.sh` da 124 ≤ 133 (wave 0). Avanzar de wave sigue siendo decisión humana.

Ficheros: `.claude/skills/agent-messaging/SKILL.md`, `.claude/skills/overnight-sprint/SKILL.md` y `.claude/skills/savia-vaults/SKILL.md` (maturity `stable`), `docs/propuestas/SE-376-debt-inventory.tsv` y `docs/propuestas/planning-state.json` (estado).

### 2026-10-02 — grupo seguridad y memoria (124 → 121/137)

| Skill | Test | Auditor | Hallazgos corregidos |
|---|---|---|---|
| `git-secret-scanner` | `tests/test-git-secret-scanner.bats` (14) | 88 | `scripts/git-history-secret-scan.sh` daba «limpio» (exit 0) si gitleaks fallaba; ahora sale con 4. `scripts/install-prepush-hook.sh` instalaba en `.git/worktrees/<n>/hooks`, que git no lee; ahora usa `rev-parse --git-path hooks`, que respeta `core.hooksPath`. Los dos tests fallan con el código anterior |
| `workspace-integrity` | `tests/test-workspace-integrity.bats` (10) | 83 | La skill documentaba `--json` donde no existe, códigos de salida erróneos y «no modifican ficheros» (`--apply` y `baseline-tighten` sí escriben). La ayuda de `scripts/agent-size-audit.sh` decía `.opencode/agents`, pero audita `.claude/agents` |
| `savia-memory` | `tests/test-savia-memory.bats` (11) | 88 | La skill documentaba `save "<tipo>" "<contenido>"` (se rechaza) y `--source session` (inválido). `scripts/memory-store.sh` escribía el índice real `~/.savia-memory/auto/MEMORY.md` desde 9 ficheros de test; ahora, dentro de BATS, nunca toca el índice del usuario (`SAVIA_MEMORY_INDEX_FILE` para tests). 11 suites verificadas con el fichero intacto |

Las skills `.claude/skills/git-secret-scanner/SKILL.md`, `.claude/skills/workspace-integrity/SKILL.md` y `.claude/skills/savia-memory/SKILL.md` pasan a `stable` con OK de la operadora. `debt-budget-check`: 121 ≤ 133.

Hallazgo fuera de alcance: `.opencode/agents` (90, fuente de `AGENTS.md` y del catálogo) y `.claude/agents` (75, los que lee Claude Code) divergen. 15 agentes solo existen para OpenCode y los comunes tienen contenido distinto.

`.gitignore`: excepción exacta `!tests/test-git-secret-scanner.bats`, en la lista enumerada del escáner (el patrón `**/*-secret*` sigue cerrado).

### 2026-10-03 — dag-scheduling (test certificado; promoción pendiente)

| Skill | Test | Auditor | Hallazgos corregidos |
|---|---|---|---|
| `dag-scheduling` | `tests/test-dag-scheduling.bats` (23) | 93 | `scripts/wave-executor.sh`: `max_parallel` 0 o no numérico, un grafo sin array `tasks` y una tarea sin `depends_on` daban `success` con exit 0 sin ejecutar nada (errores de jq tragados). Sin `-k`, una tarea que ignora SIGTERM colgaba el motor indefinidamente. Ids con espacios se partían por word-splitting. Exit 124 propio de la tarea se contaba como timeout (exit 3). SIGTERM/SIGINT al motor dejaba las tareas huérfanas (timeout lidera su propio grupo, Ctrl-C no le llega). `--report` sin valor: «unbound variable» |

Validación de esquema en `scripts/wave-executor-lib.sh` (contrato de `docs/specs/SPEC-WAVE-DAG.spec.md` §2.1, `depends_on` ausente = `[]`). `SDD_MAX_PARALLEL_AGENTS` y `SDD_DEFAULT_TIMEOUT_MIN` pasan a leerse (la skill los documentaba y el motor los ignoraba). `.claude/skills/dag-scheduling/SKILL.md` aclara lo que el motor no hace (camino crítico, worktrees, reintentos). `tests/test-wave-executor.bats` recupera 85 (bajaba a 77 al crecer el script). Sigue en `beta`: la promoción espera el OK de la operadora.
