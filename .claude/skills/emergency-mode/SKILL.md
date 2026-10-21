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

1. **Verificar readiness**: `bash scripts/localai-readiness-check.sh [--url URL] [--model MODEL] [--json]` (requiere `jq`)
   - `Estado: READY` (exit 0) o `READY (con warnings)` (exit 1: RAM o disco justos, o no medidos, p. ej. macOS sin `/proc/meminfo`): se puede cambiar.
   - `Estado: NOT READY` (exit 2): LocalAI caído, sin `/v1/messages` (LocalAI < 3.10.0), sin modelos o **sin el modelo pedido**. No hay switchover. Exit 2 también para argumentos inválidos.
   - Modelo pedido ausente (por defecto `claude-compatible-local`): el mensaje lista los ids cargados. Repetir con `--model <id cargado>`; ese id es el que va en `ANTHROPIC_MODEL`.
   - Comprueba 5 cosas: LocalAI responde, shim Anthropic `/v1/messages`, modelo por id exacto en `/v1/models`, RAM y disco (umbrales `LOCALAI_{RAM,DISK}_{OK,MIN}_GB`).
2. **Apuntar cliente al endpoint local** (con exit < 2 el script imprime estas líneas con los valores reales):
   ```bash
   export ANTHROPIC_BASE_URL="http://localhost:8080"
   export ANTHROPIC_MODEL="claude-compatible-local"
   export ANTHROPIC_SMALL_FAST_MODEL="claude-compatible-local"
   ```
   Sin `/v1`: Claude Code añade `/v1/messages` a la base; con `…/8080/v1` pediría `/v1/v1/messages` (404). Sin `ANTHROPIC_MODEL`, Claude Code pide su modelo cloud por defecto, que LocalAI no tiene. `ANTHROPIC_SMALL_FAST_MODEL` cubre las tareas de fondo.
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
unset ANTHROPIC_BASE_URL ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL
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
