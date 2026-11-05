# Harness Map — Componentes del harness de Savia (L28-M1)

> Línea: `labs/roadmaps/l28-harness-engineering.md` (L28) · Hipótesis:
> `labs/hypotheses/l28-harness-engineering.md` · Ref libro: *Agentic Harness
> Engineering* (roles recorder/governor/gateway/verifier/cache/orchestrator).
>
> Este mapa es el as-is verificado (2026-09-03): cada rol con el script real
> que lo juega hoy. Los huecos documentados son la agenda de L28 F2+.

## Mapa rol → script real

| Rol (libro) | Pregunta que responde | En Savia (script real) | Borde que custodia | Hueco conocido |
|---|---|---|---|---|
| **Recorder** | ¿Qué pasó? | `.claude/hooks/agent-trace-log.sh` + `scripts/savia-trace.sh` + `scripts/audit-receipts.sh` | ejecución → trace | El trace no es siempre el ground truth del veredicto (los courts no lo leen sistemáticamente) |
| **Governor** | ¿Qué transición es permitida? | Gates PreToolUse: `.claude/hooks/data-sovereignty-gate.sh`, `compliance-gate.sh`, `delegation-guard.sh`, `savia-budget-guard.sh` + CRITERIO/líneas rojas | intención → propuesta | — |
| **Gateway** | ¿Único camino propuesta→efecto? | `.claude/hooks/mind-virus-write-gate.sh` + puente savia-gates (hooks bash) + `scripts/agent-gate.sh` | propuesta → efecto | — |
| **Verifier** | ¿La propuesta se valida contra el recorder? | `scripts/court-review.sh` + `scripts/coherence-court.sh` + jueces (`.opencode/agents/*-judge.md`) | veredicto → aceptación | NO grounding sistemático contra trace (F2 lo cierra) |
| **Cache** | ¿Solo entra lo verificado? | `scripts/content-fingerprint.sh` (keys SE-151) + memoria verificada (`scripts/memory-store.sh`) | verificación → reúso | Sin cache de veredictos de gates; riesgo de envenenado si el borde se corta |
| **Orchestrator** | ¿Loop + presupuesto + resume? | `scripts/savia-runs.sh` (ledger SE-349) + `scripts/meta-monitor.sh` + `scripts/overnight-sprint-loop.sh` + `scripts/overnight-handoff-digest.sh` (relevo de la mañana SE-471: declarado / validado / aceptado, solo lectura) | plan → iteración | Sin checkpoint durable SQLite/resume (F4 lo cierra) |

## Prueba de ablación (F1, preregistrada)

- Script: `scripts/l28-ablation.sh` · Fixtures: `tests/fixtures/l28-ablation/`
  (deterministas, sin red, sin reloj — CRIT-001).
- Modelo: sandbox con los 5 componentes; se corta UN borde por escenario y se
  miden 4 fallos: (a) evidencia fabricada aceptada, (b) efecto sin gate,
  (c) cache envenenada, (d) veredicto sin grounding.
- Criterio preregistrado: cada borde cortado reproduce ≥1 fallo; si no
  reproduce, el borde ya estaba roto (hallazgo, no fracaso). CONFIRM si ≥2/4.

### Resultado (2026-09-03) — CONFIRM 4/4, control limpio

| Borde cortado | Esperado | Observado | Reproducido |
|---|---|---|---|
| baseline (control) | — | — | limpio |
| verifier | a, d | a, c, d | sí |
| governor | b | b | sí |
| recorder | d | a, c, d | sí |
| cache | c | c | sí |

Lecturas:

1. **Verifier cortado** admite evidencia fabricada (a) y degrada el grounding
   (d); además envenena la cache (c) porque acepta sin verificar y guarda.
2. **Recorder cortado** es el hallazgo más fuerte: sin trace, el verifier no
   tiene fuente de grounding y el sistema **degrada a accept-ungrounded**
   (a+c+d) en lugar de fail-closed. Es exactamente el hueco que L28-F2
   (verifier grounds contra trace) debe cerrar.
3. **Governor** es el único borde cuyo fallo es contenido: sin gate hay efecto
   no gobernable (b), pero no contamina veredicto ni cache.
4. **Cache cortado** solo envenena reúso (c): el daño aparece en la 2ª
   petición, no en la primera aceptación.

Reproducir:

```bash
bash scripts/l28-ablation.sh --self-test        # control limpio → exit 0
bash scripts/l28-ablation.sh run --json out.json --report out.md
bash scripts/l28-ablation.sh verdict out.json   # CONFIRM | NEGATIVE
```

## Agenda derivada (F2+)

- **F2**: verifier con grounding obligatorio contra trace — cierra el fallo
  (d) y el degrade a accept-ungrounded del recorder cortado.
- **F3**: handoffs con refs+checksum (`validate-handoff-integrity.sh`).
- **F4**: checkpoint durable SQLite con resume para orchestrator.
- **F5**: exactly-once por reserva pre-ejecución de efectos.
