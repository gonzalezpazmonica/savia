# SE-357 — Control Bands autónomas: detección determinista + tiers σ + cierre del loop

**Status:** APPROVED (2026-08-31, operadora grant merge sesión nocturna)
**Fecha:** 2026-08-31
**Área:** Maintenance / Observabilidad / Autonomía
**Fuente de inspiración:** Anthropic AI-Native SDLC Playbook (Stage 6 — Maintain, "closing the loop" + bands.yaml)
**Criterio humano aplicable:** CRIT-001 (todo local, N3+ jamás a cloud)

---

## Objetivo

Implementar el patrón de **control bands** del playbook de Anthropic para el
cierre del loop de mantenimiento: una detección **100% determinista** (sin LLM)
que vigila métricas con rolling baseline, y que al cruzar un umbral por σ invoca
a un agente con autonomía **escalonada por tier**: `1σ→log`, `2σ→diagnose
(read-only)`, `3σ→propose` (PR o runbook pre-aprobado). El hallazgo se escribe
como `intent.md` que re-entra en el pipeline SDD.

## Contexto

El playbook de Anthropic (2026-08-21) define el patrón en Stage 6: un script
determinista vigila métricas (CI failure rate, 5xx rate, PR cycle time) con
reglas Western Electric sobre una ventana rodante; la detección **nunca usa
modelo**. Al cruzar el band, el agente se invoca de forma headless y solo puede
actuar por rutas gateadas. Savia ya tiene: telemetría local (`telemetry-events.jsonl`,
SE-534), ledger de runs (SE-349), sesión nocturna autónoma (overnight-sprint).
**Lo que falta**: el mecanismo de detección determinista con tiers por σ y la
conversión del hallazgo en `intent.md` para re-entrar al pipeline.

**Rechazo explícito (CRIT-001):** no se usa el monitoreo cloud de Anthropic. El
detector corre local, lee ficheros locales de telemetría, y el agente invocado
corre en la máquina de la operadora.

## Diseño

### 1. Config `control-bands.yaml` (versionada)

```yaml
metric: ci_test_failure_rate
baseline: rolling_30d
rules: western_electric
tiers:
  1sigma: { action: log }
  2sigma: { action: diagnose, tools: "Read,Grep,Bash(gh run view *)" }
  3sigma: { action: propose, routes: [pull_request, runbook:rollback-deploy] }
```

Métricas soportadas (origen local): `ci_test_failure_rate`, `pr_cycle_time`,
`session_error_rate`, `telemetry_anomaly` (desde `telemetry-events.jsonl`).

### 2. Detector determinista `scripts/control-band-detect.sh`

- Entrada: metric + ventana rodante + regla (Western Electric: 1σ/2σ/3σ, runs,
  trends)
- Salida JSON: `{metric, sigma_level, breached, samples, window}`
- **Nunca llama a un LLM.** Es stateless y unit-testable.

### 3. Invocación del agente por tier

`scripts/control-band-agent.sh`:
- `1σ` → log solo (append a `data/control-bands/history.jsonl`)
- `2σ` → invoca agente read-only con tools restringidas → produce diagnóstico
  (`output/research/control-band-{metric}-{ts}.md`)
- `3σ` → invoca agente con rutas gateadas (PR o runbook pre-aprobado) → escribe
  `intent.md` (formato Stage 1) y lo deja en `intent/` para triage humano

### 4. `intent.md` como re-entrada

`intent/` (versionado) con plantilla: problema, evidencia, outcome propuesto,
sistemas afectados, preguntas abiertas. El triage humano decide fix/schedule/
dismiss (dismiss tunca los bands).

## Criterios de aceptación

- **AC-0** Detector calcula σ correctamente (dataset sintético: media/desv est + Western Electric, test)
- **AC-1** `1σ` solo loggea (no invoca agente)
- **AC-2** `2σ` invoca agente read-only (tools restringidas verificadas en test)
- **AC-3** `3σ` produce `intent.md` válido en `intent/`
- **AC-4** El detector nunca llama a un LLM (grep del script: cero invocaciones model)
- **AC-5** Config inválida → fail-closed (no ejecuta tiers)
- **AC-6** Historial append-only en `data/control-bands/history.jsonl`

## OpenCode Implementation Plan

### Bindings touched
- `scripts/control-band-detect.sh` (nuevo), `scripts/control-band-agent.sh` (nuevo)
- `control-bands.yaml` (nuevo), `intent/` (nuevo)
- `scripts/telemetry-events.jsonl` reader (reutiliza SE-534)

### Verification protocol
```bash
bats tests/bats/test-control-bands.bats
bash scripts/control-band-detect.sh --metric ci_test_failure_rate --dry-run
```

### Portability classification
- Bash + awk/python3 stdlib; local; portable

## Referencias
- Anthropic: claude.com/blog/the-ai-native-sdlc-playbook (Stage 6, closing the loop)
- Savia: SE-534 (telemetría), SE-349 (ledger runs), `autonomous-safety.md`, CRIT-001
