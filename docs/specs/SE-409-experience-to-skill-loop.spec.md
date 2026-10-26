---
status: APPROVED
approved_at: 2026-10-27
approved_by: "operadora, AskUserQuestion 2026-10-27"
priority: P3
developer_type: agent-single
created: 2026-09-29
phase: D
risk: L2
related_specs: [SE-380, SE-376, SE-406, SE-167]
origin: output/research/harness-referencias-20260929.md (§3, NousResearch/hermes-agent — NO VERIFICADO)
---

# SE-409 — Bucle experiencia → skill con curación y retirada

> **Evidencia verificada (2026-09-29, README de hermes-agent):** se confirma que
> crea skills a partir de la experiencia y las mejora con el uso, que se impulsa a
> persistir conocimiento, que busca en sus conversaciones pasadas y que construye
> un modelo del usuario entre sesiones. **No** documenta curación ni retirada de
> skills: esa parte es aportación de Savia. Solo se adoptan patrones; el producto
> no (instalador remoto ejecutado directamente desde la red y "Tool Gateway" de
> pago que enruta búsquedas y navegador por terceros).

## Problema

Savia tiene las piezas sueltas: `skill-propose`, `lesson-extract`,
`instinct-manage` y el lifecycle de SE-380. Pero el bucle no se cierra. Una tarea
compleja resuelta no genera una propuesta de skill verificable. Las skills nuevas
entran sin test certificado (SE-376 mide una deuda de 128/137) y las que no se
usan no se retiran. hermes-agent se presenta como "el agente que crece contigo"
por crear y mejorar skills a partir de la experiencia.

## Slices

### S0 — Verificación de la fuente (README: hecho 2026-09-29)

Queda por leer la guía de Skills System y el código del bucle de aprendizaje
(disparador de la propuesta y criterio de mejora) antes de diseñar S1.

- AC1: nota sobre el disparador y el criterio de mejora de hermes-agent (MIT; no
  se copia código sin aprobación).

### S1 — Propuesta automática como PR Draft

Tras una tarea marcada como resuelta con ≥ N pasos o ≥ 1 corrección, se
propone una skill con test que puntúe ≥ 80 en el auditor, como PR Draft. Nunca
se instala directamente.

- AC2: sin test certificado no hay propuesta (coherente con SE-376).
- AC3: maker-checker: el checker rechaza las propuestas que duplican una skill
  existente (búsqueda en el registry de SE-375).

### S2 — Retirada por desuso

Usar `usage report` (SE-380) para marcar como candidatas a DEPRECATED las skills
sin uso en 90 días. La decisión es humana.

- AC4: la lista de candidatas es reproducible y no borra nada.

### S3 — Recordatorio para persistir conocimiento

Al cerrar una tarea con hallazgos nuevos (corrección, workaround o decisión), el
harness recuerda persistirlos en memoria (`memory-store.sh save`) si no se ha
hecho. Es un aviso, no una escritura automática.

- AC5: el recordatorio no se dispara si en la sesión ya hubo un `save` con el mismo tema.

## Fuera de alcance

Gateway multicanal: ya lo cubre SE-406. Automodificación sin revisión humana.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Detector de tarea resuelta | hook Stop | evento `session.idle` |
| Propuesta y retirada | bash/python | idéntico |

### Verification protocol

- [ ] La propuesta se genera igual en ambos runtimes

### Portability classification

- [x] **DUAL_BINDING**
