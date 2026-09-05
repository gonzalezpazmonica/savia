---
layer: peripheral
name: pr-agent-judge
description: Usar cuando se añade pr-agent como juez externo en el Code Review Court.
metadata:
  savia.maturity: stable
---

# Skill: pr-agent-judge (SPEC-124)

> Wrapper sobre [qodo-ai/pr-agent](https://github.com/qodo-ai/pr-agent) (10.9k ⭐, 60.1% F1) como juez externo opt-in del Code Review Court.

## Rol dentro del Court

Court actual: 4 jueces (correctness, security, architecture, cognitive).
Con opt-in: 5 jueces → añade diversidad (jueces externos con benchmark público).

Se activa solo si `COURT_INCLUDE_PR_AGENT=true` en `pm-config.md`.

## Invocación

```bash
# Modo local (sin CI)
bash scripts/pr-agent-run.sh --pr-number 593 --mode review --output court-format
```

Salida JSON compatible con formato Court:

```json
{
  "judge": "pr-agent",
  "version": "qodo-ai/pr-agent@0.27",
  "verdict": "approve | request_changes | comment",
  "findings": [
    {
      "severity": "medium",
      "category": "correctness",
      "file": "src/foo.ts",
      "line": 42,
      "message": "..."
    }
  ],
  "summary": "..."
}
```

## Modos

- `review` — code review completo
- `describe` — descripción automática del PR
- `improve` — sugerencias de mejora

## Requirements

- [pr-agent](https://github.com/qodo-ai/pr-agent) instalado: `pip install pr-agent` o Docker
- `GITHUB_TOKEN` env var (para acceder al PR)
- Anthropic API key o compatible (`PR_AGENT_MODEL` en pm-config.md). Por defecto resuelto via tier: `mid` → `~/.savia/preferences.yaml` model_mid.

Si `pr-agent` no está instalado, el wrapper **falla gracefully** reportando `{"status":"SKIPPED","reason":"pr-agent not installed"}` sin bloquear al Court.

## Feature flags en pm-config.md

```
COURT_INCLUDE_PR_AGENT   = false        # default opt-in
PR_AGENT_VERSION         = "0.27"       # pin
PR_AGENT_MODEL           = "mid"        # tier, resuelto via preferences.yaml
PR_AGENT_MAX_LINES       = 1000         # evita token blowout
```

## Relación con agentes internos

- Complementa `correctness-judge`, `security-judge`, `architecture-judge`, `cognitive-judge`.
- NO reemplaza ninguno — opt-in para diversity, no para rebaja.
- Orchestrator (`court-orchestrator`) agrega los 5 verdicts con policy ya definida.

## Cuándo NO usar

- PRs > 1000 líneas (coste token excesivo — usar flag PR_AGENT_MAX_LINES)
- PRs de docs-only (rendimiento bajo del tool en ese contexto)
- Rama `agent/*` autogenerada (evitar feedback loop self-review)

## Referencias

- [qodo-ai/pr-agent](https://github.com/qodo-ai/pr-agent)
- SPEC-124 — docs/propuestas/SPEC-124-pr-agent-wrapper.md
- `.claude/agents/court-orchestrator.md`
