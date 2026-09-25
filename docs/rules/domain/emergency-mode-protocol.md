---
context_tier: L3
token_budget: 1168
---

# Emergency Mode Protocol — SPEC-122

> Savia conserva capacidad operativa si la API de Anthropic cae. LocalAI actúa como shim drop-in vía `/v1/messages` (compat Anthropic desde v3.10.0).

## Activation criteria

Activar emergency-mode SOLO si se cumple al menos UNA:

1. **API Anthropic caída > 5 min** verificable con `curl https://api.anthropic.com/v1/health` (404/500/timeout).
2. **Rate limit hit** persistente tras exponential backoff (60s×4).
3. **Mandato humano** explícito (`/emergency-mode activate --reason "..."`).
4. **Zero-egress requirement** por regulación (GDPR/HIPAA en session crítica).

NUNCA activar preventivamente — requiere trigger real.

## Activación

```bash
/emergency-mode activate [--reason TEXT]
```

1. Readiness check automático: `bash scripts/localai-readiness-check.sh`.
   Si FAIL (exit 2) → abort con error "LocalAI no preparado".
2. Redirige variables:
   ```
   export ANTHROPIC_BASE_URL=http://localhost:8080/v1
   export ANTHROPIC_MODEL=claude-compatible-local
   ```
3. Feature-flags desactivadas automáticamente:
   - WebFetch / WebSearch (sin internet asumido)
   - MCPs externos (Gmail/GCal/GDrive)
   - Cloud-only skills (report-executive con LLM-judge)
4. Marker en session: `SAVIA_EMERGENCY=1`.

## Operación bajo emergency

### Lo que SE mantiene

- Todas las skills locales (context-compress, headroom-analyze, etc.)
- Comandos de lectura (backlog, sprint, memory-recall)
- Escritura en repos locales
- Validators (pr-plan, receipts, handoff)
- Court (con modelos locales — calidad reducida esperada)

### Lo que SE degrada

- **Tokens/segundo**: ~60% de cloud (MLX ~230 tok/s, Ollama 20-40 tok/s)
- **Quality**: LLM local 3-7B < cloud. D distortion espera subir.
- **Tool use**: Solo tools en sandboxed local.
- **Max context**: Depende del modelo local (típico 32-128K vs 1M cloud).

### Lo que NO funciona

- Gmail/GCal/GDrive MCPs
- Web research agents
- `/tech-research` con WebFetch
- Modelos Opus/Sonnet específicos (local usa equivalente más pequeño)

## Respeto de gates

**CRITICAL**: emergency-mode NO relaja `autonomous-safety.md`:

- La ruta de revisión sigue siendo obligatoria: reviewer distinto elegible o revisión de la operadora única; nunca solicitar self-review a GitHub
- Rule #8 (human E1) sigue aplicando
- Ninguna regla crítica (1-8 de CLAUDE.md) se bypasses
- Receipts protocol (SE-030) sigue vigente

Emergency mode NO es excusa para saltarse safety. Es un fallback de
disponibilidad, no de gobernanza.

## Deactivación

```bash
/emergency-mode deactivate
```

1. Check cloud: `curl https://api.anthropic.com/v1/health` — debe responder 200/204.
2. Unset vars `ANTHROPIC_BASE_URL` y `ANTHROPIC_MODEL`.
3. Re-habilita feature-flags.
4. Emit audit log entry: inicio/fin + razón + turns processed bajo emergency.

## Readiness check scheduled

Hook `session-init.sh` puede opcionalmente invocar:

```bash
SAVIA_EMERGENCY_PREFLIGHT=true  # en pm-config.local.md
```

→ Ejecuta `localai-readiness-check.sh --json` al arranque, reporta estado
silencioso (no bloquea sesión).

## Fallback stack (SAVIA_EMERGENCY)

```
┌────────────────────────────────────────────┐
│  Claude Code (unchanged UX)                │
├────────────────────────────────────────────┤
│  ANTHROPIC_BASE_URL → localhost:8080       │
│                                            │
│  LocalAI v3.10.0+ (Anthropic-compatible)   │
├────────────────────────────────────────────┤
│  Ollama / vLLM / llama.cpp / MLX          │
├────────────────────────────────────────────┤
│  Modelo Claude-compatible-local (7-34B)    │
└────────────────────────────────────────────┘
```

## Audit trail

Cada session en emergency-mode emite:

```json
{
  "event": "emergency_mode",
  "state": "activated | deactivated",
  "timestamp": "ISO-8601",
  "reason": "...",
  "turns_processed": N,
  "degraded_features": ["webfetch","gmail","..."],
  "outcome": "completed | aborted"
}
```

a `output/agent-runs/emergency-{YYYYMMDD}.jsonl`.

## Referencias

- SPEC-122 — `docs/propuestas/SPEC-122-localai-emergency-hardening.md`
- `scripts/localai-readiness-check.sh`
- `.opencode/skills/emergency-mode/SKILL.md`
- [mudler/LocalAI](https://github.com/mudler/LocalAI)
- Rule `autonomous-safety.md` — no se relaja bajo emergency
