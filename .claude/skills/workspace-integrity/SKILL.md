---
layer: peripheral
name: workspace-integrity
description: "Usar cuando se audita la integridad del workspace (drift, reglas, agentes, baseline)."
allowed-tools: [Bash, Read, Glob]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.disable-model-invocation: false
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Aggregator skill listando 6 scripts de auditoria de integridad del workspace. Detectan drift entre docs y realidad, orphan rules, agents oversized, baseline stale."
  savia.tags: "integrity, audit, drift, workspace, hygiene"
  savia.user-invocable: True
---

# Skill: Workspace Integrity

> Auditores de integridad documento-realidad.
> Ref: SE-043/046/047/048/052/057.

## Cuando usar

- Pre-push (manual check de drift antes de `git push`)
- Al cierre de cada Era (ejecutados en batches 13, 22, 23)
- Mensualmente sobre workspace sano
- Tras refactor que toca muchos ficheros

## Inventario

| Script | Spec | Detecta |
|---|---|---|
| `claude-md-drift-check.sh` | SE-043 | Counters en CLAUDE.md vs filesystem (agents/commands/skills/hooks) |
| `baseline-tighten.sh` | SE-046 | Baseline metrics stale tras cambios estructurales |
| `agents-catalog-sync.sh` | SE-047 | Drift entre `docs/rules/domain/agents-catalog.md` y `.opencode/agents/` |
| `rule-orphan-detector.sh` | SE-048 | Reglas en `docs/rules/domain/` sin referencias cruzadas |
| `rule-manifest-integrity.sh` | SE-057 | `docs/rules/INDEX.md` vs ficheros reales |
| `agent-size-audit.sh` + `agent-size-remediation-plan.sh` | SE-052 | Agents > umbral lineas; plan de split |
| `rule-usage-analyzer.sh` | — | Estadisticas de uso de reglas domain |

## Invocacion

```bash
# Individual checks
bash scripts/claude-md-drift-check.sh
bash scripts/rule-manifest-integrity.sh
bash scripts/agents-catalog-sync.sh --json
bash scripts/rule-orphan-detector.sh --json
bash scripts/agent-size-audit.sh

# Ejecucion uniforme (patron de aggregator)
for script in claude-md-drift-check rule-manifest-integrity agents-catalog-sync rule-orphan-detector; do
  echo "=== $script ==="
  bash scripts/$script.sh --json 2>&1 | head -3
done
```

## Exit codes esperados

- `0` — PASS (sin drift)
- `1` — DRIFT o FINDING (WARN o ERROR)
- `2` — usage error

## Integracion con CI

Cada script emite JSON parseable. CI puede:
- Bloquear merge si `claude-md-drift-check.sh` falla (ya activo vía `readiness-check.sh`)
- Notificar (no bloquear) si `rule-orphan-detector` encuentra >N orphans
- Reporting mensual via `agent-size-audit` con plan de remediation

## No hacen

- No modifican ficheros (solo audit)
- No auto-fixer (SE-062 Era 184 scope)
- No corren tests (eso es `readiness-check.sh`)
- No push ni merge (gate via `push-pr.sh`)

## Decision tree

```
¿CI falla por counter drift?
  → SE-062.1 counter sync (usar claude-md-drift-check.sh)
¿Spec ID duplicado?
  → Revisar docs/propuestas, resolve per SE-044
¿Rule orphan?
  → Remover rule o anadir referencia
¿Agent oversized?
  → agent-size-remediation-plan.sh genera split plan
```

## Referencias

- SE-043 drift check: `scripts/claude-md-drift-check.sh`
- SE-046 baseline: `scripts/baseline-tighten.sh`
- SE-047 catalog sync: `scripts/agents-catalog-sync.sh`
- SE-048 orphan: `scripts/rule-orphan-detector.sh`
- SE-052 agent size: `scripts/agent-size-audit.sh`
- SE-057 manifest: `scripts/rule-manifest-integrity.sh`
- Era 182 audit closure: batch 13 (PR #654)
- Era 184 Consolidation: `docs/propuestas/SE-062-era184-consolidation-hygiene.md`
