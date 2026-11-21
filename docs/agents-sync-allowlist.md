---
title: Agents Sync Allowlist — SE-253 Slice 3
spec: SE-253
created: "2026-07-03"
---

# Agents Sync Allowlist

Agentes que existen en un solo lado del sistema dual por diseño.
Cualquier agente NO listado aquí debe tener par en ambos directorios.

Verificación automática: `bash scripts/agents-catalog-sync.sh --check`

---

## Agentes solo en `.opencode/agents/` (top-level)

| Agente | Lado | Motivo |
|---|---|---|
| `archive-digest` | .opencode only | Subagente OpenCode-specific — digest de ficheros comprimidos vía markitdown, solo usado desde OpenCode |
| `authority-claim-judge` | .opencode only | Juez del Recommendation Tribunal — invocado solo por tribunal-orchestrator vía Task tool, no necesita par en .claude |
| `code-twin-agent` | .opencode only | Agente especializado en consultar Application Code Twin — feature OpenCode exclusiva (SPEC-190) |
| `criterion-simulation-judge` | .opencode only | Juez SPEC-194 — solo ejecuta como subagente del tribunal, no como agente directo |

## Subagentes `decision-trees/` (`.opencode/agents/decision-trees/`)

Todos son subagentes de árbol de decisión — no tienen equivalente en .claude/agents/ por diseño.
Son invocados solo por el orquestador decision-trees-orchestrator.

| Subagente | Motivo |
|---|---|
| `architect-decisions` | Árbol de decisión del architect — feature OpenCode |
| `business-analyst-decisions` | Árbol de decisión del business-analyst |
| `code-reviewer-decisions` | Árbol de decisión del code-reviewer |
| `commit-guardian-decisions` | Árbol de decisión del commit-guardian |
| `court-orchestrator-decisions` | Árbol de decisión del court-orchestrator |
| `dev-orchestrator-decisions` | Árbol de decisión del dev-orchestrator |
| `dotnet-developer-decisions` | Árbol de decisión del dotnet-developer |
| `frontend-developer-decisions` | Árbol de decisión del frontend-developer |
| `sdd-spec-writer-decisions` | Árbol de decisión del sdd-spec-writer |
| `security-guardian-decisions` | Árbol de decisión del security-guardian |

## References (`.opencode/agents/references/`)

Ficheros de referencia para los agentes — no son agentes ejecutables.

| Fichero | Motivo |
|---|---|
| `code-reviewer-report-format` | Plantilla de informe — referencia, no agente |
| `commit-guardian-report-format` | Plantilla de informe — referencia |
| `security-guardian-report-format` | Plantilla de informe — referencia |
| `truth-tribunal-orchestrator-output-schema` | Schema de output — referencia |
| `truth-tribunal-orchestrator-tiered` | Configuración tiered — referencia |
