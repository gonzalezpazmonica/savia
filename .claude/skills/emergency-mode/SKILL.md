---
layer: peripheral
name: emergency-mode
description: Usar cuando la API de Anthropic está caída y se necesita continuar operando con LocalAI.
allowed-tools: [Bash, Read]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: resilience
  savia.context: global
  savia.maturity: experimental
  savia.priority: high
  savia.summary: "SPEC-122 Slice 2: skill que documenta y orquesta el modo emergencia. Usa `scripts/localai-readiness-check.sh` para verificar el stack local antes de proponer el switchover. NO modifica variables de entorno automáticamente — solo emite el plan. Decisión del switchover es humana."
  savia.tags: "emergency, localai, sovereignty, spec-122"
  savia.user-invocable: True
---

# Emergency Mode — Savia ↔ LocalAI Switchover

## Cuándo usar

- API de Anthropic caída (503/504/timeout > 5 min)
- Red externa bloqueada en el entorno
- Ensayo de recuperación planificado (drill)

## Activación

1. **Verificar readiness**: `bash scripts/localai-readiness-check.sh`
   - Debe reportar `VERDICT: VIABLE` o `READY`.
   - Si `NEEDS_INSTALL`: instalar LocalAI antes del switchover.
2. **Apuntar cliente al endpoint local**:
   ```bash
   export ANTHROPIC_BASE_URL="http://localhost:8080/v1"
   ```
3. **Arrancar Claude Code normalmente** — usa el mismo binario, cambia solo el backend.

## Lo que cambia

| Feature | Cloud (default) | Emergency (LocalAI) |
|---|---|---|
| Chat básico | ✅ | ✅ (con modelo local compat) |
| Tool use | ✅ | ✅ |
| Web Search | ✅ | ❌ |
| Gmail/GCal MCP | ✅ | ❌ |
| Prompt caching | ✅ | ⚠️ limitado |
| Vision | ✅ | ⚠️ depende del modelo |
| Velocidad | Baseline | ~60% baseline |

## Gates que NO se saltan

- Rule #8 (autonomous-safety): AUTONOMOUS_REVIEWER sigue obligatorio.
- PRs siguen en Draft, review humano aplica.
- Shield daemon, pre-commit hooks, PII scan, confidentiality sign siguen activos.

## Vuelta a cloud

```bash
unset ANTHROPIC_BASE_URL
```
La siguiente sesión vuelve al endpoint Anthropic.

## Referencias

- SPEC-122: `docs/propuestas/SPEC-122-localai-emergency-hardening.md`
- Protocolo: `docs/rules/domain/emergency-mode-protocol.md`
- Readiness check: `scripts/localai-readiness-check.sh`
- Rule #8: `docs/rules/domain/autonomous-safety.md`

## Anti-patterns

- **NO** setear `ANTHROPIC_BASE_URL` globalmente en `.bashrc` — emergency es transitorio.
- **NO** saltarse el readiness check — el switchover sin validación puede dar errores crípticos.
- **NO** auto-escalar de cloud-down a emergency sin decisión humana — Rule #8.
