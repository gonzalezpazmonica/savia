# Regla: Seguridad en Modos Autónomos — Supervisión humana obligatoria

> **REGLA INMUTABLE** — Aplica a TODOS los modos autónomos: overnight-sprint, code-improvement-loop, tech-research-agent y cualquier skill futuro que opere sin supervisión directa en tiempo real.
> **Pattern alignment**: implementa Genesis **A9 SUPERVISED EXECUTION** — ver `docs/rules/domain/attention-anchor.md` (SE-080).

## Principio fundamental

**La IA propone, el humano dispone.** (Implementa principios §3 y §9 de `docs/rules/domain/savia-ethical-principles.md`.) Ningún agente autónomo tiene autoridad para tomar decisiones irreversibles. Todo output autónomo es una **propuesta pendiente de revisión humana**.

## Reglas de Git — Ramas y commits

```
NUNCA  → Hacer commit en la rama de un humano (main, develop, feature/* creada por humano)
NUNCA  → Hacer merge de ninguna rama
NUNCA  → Hacer push --force
NUNCA  → Eliminar ramas ajenas

SIEMPRE → Crear rama derivada propia: agent/{modo}-{fecha}-{descripcion}
SIEMPRE → Derivar de la rama original del proyecto (main o develop según flujo)
SIEMPRE → Commits solo en ramas agent/*
SIEMPRE → Prefijo de commit: agent({modo}): descripción
```

### Convención de ramas autónomas

| Modo | Patrón de rama | Ejemplo |
|------|----------------|---------|
| Overnight Sprint | `agent/overnight-{YYYYMMDD}-{tarea}` | `agent/overnight-20260312-fix-linter-warnings` |
| Code Improvement | `agent/improve-{tipo}-{id}` | `agent/improve-coverage-auth-service` |
| Tech Research | `agent/research-{tema}` | `agent/research-ef-alternatives` |

## Reglas de PRs — Revisión humana obligatoria

```
NUNCA  → Aprobar un PR (ni propio ni ajeno)
NUNCA  → Hacer merge de un PR sin permiso expreso REGISTRADO de la operadora
NUNCA  → Auto-asignar como reviewer
NUNCA  → Marcar un PR como "ready for merge" sin grant expreso y gates de riesgo/CI

SIEMPRE → Crear PR en estado Draft
SIEMPRE → Si hay reviewer distinto y elegible, solicitar su revisión
SIEMPRE → Si la operadora es la única colaboradora, dejar PR Draft para su revisión sin solicitar self-review a GitHub
SIEMPRE → Incluir en el PR body: métricas antes/después, descripción del cambio, riesgo estimado
SIEMPRE → Tier 3/4: esperar revisión humana explícita del PR concreto
SIEMPRE → Tier 1/2: exigir grant de merge expreso antes de promover o mergear
```

Merge: grant vigente (SE-343), CI y riesgo; tier 3/4 exige revisión explícita
del PR concreto (SE-362). Ver `autonomous-safety-merge-grant.md`.

## Reglas de investigación — Notificación humana

```
NUNCA  → Crear tareas en el backlog sin aprobación
NUNCA  → Modificar configuración del proyecto basándose en hallazgos
NUNCA  → Instalar dependencias nuevas

SIEMPRE → Generar informe en output/research/{tema}-{YYYYMMDD}.md
SIEMPRE → Notificar a AUTONOMOUS_RESEARCH_NOTIFY al completar
SIEMPRE → Las recomendaciones son PROPUESTAS, no acciones
```

## Configuración requerida

`AUTONOMOUS_REVIEWER` y `AUTONOMOUS_RESEARCH_NOTIFY` se resuelven en runtime
desde **fuentes locales gitignored** (NUNCA del repo público — Rule #20):

```
1) .claude/rules/pm-config.local.md  (gitignored)
2) ~/.savia/preferences.yaml          (SPEC-127)
3) Slug del usuario activo en .claude/profiles/active-user.md (fallback genérico "@local-user")
```

scripts/savia-env.sh expone `savia_autonomous_reviewer()` que aplica esta cadena.
### Gate de arranque

Reviewer distinto elegible: solicitar revisión. Si la operadora autenticada es
la única colaboradora, usar PR Draft y revisión propia con CI y grant expreso;
GitHub rechaza self-review. Sin operadora ni reviewer elegible: abortar.

## Reglas de fail-safe

```
SIEMPRE → Time-box por tarea: AGENT_TASK_TIMEOUT_MINUTES (default 15 min)
SIEMPRE → Abort tras AGENT_MAX_CONSECUTIVE_FAILURES fallos consecutivos (default 3)
SIEMPRE → Registrar CADA intento en results.tsv (éxitos, descartes y crashes)
SIEMPRE → Si se detecta que el agente está en loop (misma acción 3+ veces) → abort
SIEMPRE → Si consumo de contexto > 80% → compact y evaluar si continuar
```

## Auditoría

Cada sesión autónoma genera `output/agent-runs/{modo}-{fecha}-audit.log`. Campos mínimos:
- Timestamp inicio/fin
- Tareas intentadas (pr-created / discarded / crash / timeout)
- Ramas creadas · PRs creados (URLs) · métricas agregadas
- Razón de parada (completado / max-tasks / max-failures / timeout global / abort manual)
- `handback_to` — a quién se escaló en cada handback (SE-332; vacío si no hubo escalación)

## Auto Mode — Capa complementaria (Claude Code 2026-03-24)

`claude --enable-auto-mode` bloquea acciones destructivas pre-tool-call. NO
reemplaza esta regla; añade defensa en profundidad (Settings → Auto Mode).
Ref: anthropic.com/engineering/claude-code-auto-mode

## Escalamiento de modelo

Si un agente falla consecutivamente en una tarea:
- Intento 1: tier `fast`
- Intento 2: tier `mid`
- Intento 3: tier `heavy`
- Intento 4+: ABORT — registrar como "requiere intervención humana"

OOM, timeout o error de infra: NO escalar — descartar y continuar.

## Emergency-mode (LocalAI fallback) — SPEC-122

`/emergency-mode` cambia SOLO el endpoint (`ANTHROPIC_BASE_URL` → LocalAI), **no bypassa** los gates. Rama `agent/*`, PR Draft y revisión de la operadora o reviewer elegible siguen obligatorios. Ver `emergency-mode/SKILL.md` y `emergency-mode-protocol.md`.

## Subagent Scope Guard — SE-146

Cuando un agente o skill se invoca como **subagente delegado** (recibe una tarea concreta desde un orquestador), debe:

```
1. EJECUTAR solo la tarea asignada — sin activar workflows de orquestación completos
2. REPORTAR resultado: DONE | DONE_WITH_CONCERNS | BLOCKED
3. RETORNAR — no continuar en bucle ni lanzar sub-agentes adicionales
```

**Por qué**: las skills de alto impacto (overnight-sprint, code-improvement-loop, adversarial-security, etc.) tienen bucles de orquestación que, activados íntegramente por un subagente, generan runs en cascada fuera de control.

**Detección de contexto subagente**: tarea vía `Task` tool, env `SAVIA_SUBAGENT=1`, o flag `--subagent` → aplicar este guard. **Skills con este guard**: adversarial-security, code-improvement-loop, consensus-validation, dag-scheduling, overnight-sprint, spec-driven-development, tdd-vertical-slices, verification-lattice.

## Handback Obligation — SE-332

Instancia autónoma bloqueada **escala a su padre inmediato, un nivel a la vez**; toda cadena termina en manual **POR CONSTRUCCIÓN**. Resolución: `scripts/handback-resolve.sh`. Handback **reference-first** (`contexto_ref` solo rutas), `termination_reason: handback` (exit 6), `handback_to` en audit. Cadena por modo y schema: `agent-handoff-protocol.md`, `terminal-state-protocol.md`, spec SE-332.

## Doble opt-in para skills autónomas — SPEC-186

Era 199 Wave 1. Toda skill autónoma exige **dos confirmaciones independientes** en cada invocación: variable de entorno persistente Y flag `--confirm-autonomous`. Helper canónico:
```
bash scripts/savia-double-optin-check.sh --skill <nombre> --confirm-autonomous
```
Detalle completo (mapeo skill→variable, auditoría, bypass de tests, exit codes): ver `docs/rules/domain/double-optin-protocol.md`. Modos L2+: `maker-checker-protocol.md` + `loop-verify.sh`.
## Dual Pool — Proposal vs Result State (SE-235)
Proposal = rama `agent/*` o nido no mergeado. Result = en main con PR aprobado humano. Ver `SE-235-dual-pool-proposal-result.md`.
