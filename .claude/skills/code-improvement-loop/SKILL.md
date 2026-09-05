---
layer: peripheral
name: code-improvement-loop
description: Usar cuando se quiere ejecutar mejora autónoma de código en segundo plano con PRs para revisión.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: code-reviewer
  savia.maturity: stable
  savia.category: sdd-framework
  savia.context: fork
    savia.loop_level: L2  # L0=draft | L1=report-only | L2=assisted | L3=unattended — ver docs/rules/domain/loop-phasing.md
  savia.maturity: experimental
  savia.priority: medium
  savia.summary: "Bucle autonomo de mejora de codigo: detecta oportunidades (deuda, cobertura, performance), aplica mejoras y genera PRs Draft. Usa ramas agent/improve-*. Revision humana obligatoria."
  savia.tags: "autonomous, improvement, refactoring, pr-draft"
---
## Subagent Scope Guard

> Subagente delegado: ejecuta SOLO la tarea asignada, reporta
> DONE/DONE_WITH_CONCERNS/BLOCKED, y retorna. Previene activación runaway.
# Skill: Code Improvement Loop

> **Regla de seguridad**: `@docs/rules/domain/autonomous-safety.md` — NUNCA merge, SIEMPRE PR Draft con reviewer humano.
> **Inspirado en**: [autoresearch](https://github.com/karpathy/autoresearch) — patrón modificar → medir → mantener/descartar.

## Cuándo usar esta skill

- Se quiere mejorar la calidad del código de forma continua y medible
- Hay deuda técnica acumulada (cobertura, complejidad, linter, TODOs)
- Se busca mejoras incrementales con métricas antes/después para revisión humana

## Qué produce

1. **PRs en Draft** — uno por mejora que supere las métricas baseline, asignados a `AUTONOMOUS_REVIEWER`
2. **improvement-results.tsv** — `output/improvement-results-{YYYYMMDD}.tsv`
3. **Informe de oportunidades** — `output/improvement-opportunities-{YYYYMMDD}.md`
4. **Audit log** — `output/agent-runs/improvement-{YYYYMMDD}-audit.log`
## Prerequisitos

```
1. AUTONOMOUS_REVIEWER configurado            → si no: ❌ ABORT
2. Doble opt-in SPEC-186 (env CODE_IMPROVEMENT_LOOP_ENABLED=true + flag): → si no: ❌ ABORT
   bash scripts/savia-double-optin-check.sh --skill code-improvement-loop --confirm-autonomous
3. Tests pasan (baseline sano)                → si no: ❌ ABORT
4. Métricas baseline capturadas               → si no: capturar antes de empezar
5. Auto Mode activado (claude --enable-auto-mode) → si no: ⚠️ warning, continuar
```

## Flujo completo (patrón autoresearch adaptado)
```
Humano ejecuta /code-improve [--scope {path}] [--tipo {coverage|complexity|lint|deps|todos}]
    ↓
Validar prerequisitos
    ↓
Capturar métricas baseline:
  - Cobertura de tests (%)
  - Complejidad ciclomática (promedio y max)
  - Warnings de linter (count)
  - TODOs sin ticket (count)
  - Dependencias desactualizadas (count)
    ↓
Detectar oportunidades de mejora → mostrar lista → PEDIR CONFIRMACIÓN
    ↓
[Humano confirma]
    ↓
LOOP (por cada oportunidad, hasta max_tasks o max_failures):
  ↓
  Crear rama: agent/improve-{tipo}-{id}
  ↓
  Crear worktree aislado
  ↓
  Aplicar mejora (time-box: AGENT_TASK_TIMEOUT_MINUTES)
  ↓
  Ejecutar tests + capturar métricas post-cambio
  ↓
  Comparar métricas:
    ¿Tests siguen pasando?
    ¿Métrica objetivo mejoró?
    ¿Ninguna otra métrica degradó significativamente?
      ↓
    TODO SÍ → Registrar premisa (SE-350): `bash scripts/coherence-court.sh premises code-improve-{fecha} add decision "mejora {id}: {desc}" --stage improve-{id}`
      → Crear PR Draft con:
      - Título: "agent(improve): {descripción}"
      - Body: métricas antes/después, ficheros modificados, riesgo estimado
      - Reviewer: AUTONOMOUS_REVIEWER
      - Registrar como "pr-created" en results.tsv
      ↓
    ALGO NO → Descartar rama (git branch -D) → registrar como "discarded"
  ↓
  Siguiente oportunidad
    ↓
Generar informe resumen con todas las mejoras propuestas
```

## Tipos de mejora detectables
### 1. Cobertura de tests (`--tipo coverage`)
- Identifica ficheros con cobertura < TEST_COVERAGE_MIN_PERCENT
- Genera tests unitarios para cubrir ramas no cubiertas
- Métrica: delta de cobertura (%)
### 2. Complejidad ciclomática (`--tipo complexity`)
- Identifica funciones con complejidad > 10
- Aplica refactoring: extract method, simplify conditions, early return
- Métrica: complejidad promedio y máxima
### 3. Warnings de linter (`--tipo lint`)
- Ejecuta linter del proyecto y recopila warnings
- Corrige automáticamente los que tienen fix seguro
- Métrica: count de warnings
### 4. Dependencias (`--tipo deps`)
- Identifica dependencias con updates menores/patch disponibles
- Aplica update + ejecuta tests
- Métrica: count de dependencias desactualizadas
### 5. TODOs pendientes (`--tipo todos`)
- Identifica TODOs en código que refieren a tickets cerrados
- Resuelve el TODO o lo elimina si ya está resuelto
- Métrica: count de TODOs

## Formato de results.tsv

```tsv
timestamp	tipo	fichero	rama	status	metrica_antes	metrica_despues	delta	pr_url	descripcion
2026-03-12T02:00:00	coverage	src/auth/	agent/improve-coverage-auth	pr-created	62.3%	78.1%	+15.8%	https://...	Add tests for login flow
2026-03-12T02:18:00	complexity	src/api/handler.ts	agent/improve-complexity-handler	pr-created	14.2	8.7	-5.5	https://...	Extract methods from handler
```

## Restricciones estrictas

```
NUNCA → Hacer merge de un PR
NUNCA → Aprobar un PR
NUNCA → Hacer commit en rama de humano
NUNCA → Cambiar la API pública de un módulo
NUNCA → Modificar tests existentes (solo AÑADIR nuevos)
NUNCA → Aplicar mejoras que degraden CUALQUIER métrica
SIEMPRE → PR en Draft con AUTONOMOUS_REVIEWER
SIEMPRE → Métricas antes/después en el body del PR
SIEMPRE → Ramas agent/improve-*
```

## Cuándo NO usar

- Refactorings mayores que cambian arquitectura o dependencias major
- Si los tests del proyecto no pasan
- Mejoras que requieren decisiones de diseño humanas

## Coherence Court (SE-350) — anti-saturación

Cada mejora que pasa las métricas se registra como premisa (determinista, sin
LLM, JSONL local). **NUNCA** la auditoría LLM (4 jueces) por mejora — satura.
La auditoría completa `/coherence-court --flow code-improve-{fecha}` va al final
(o E1 humana), opt-in `COHERENCE_AUDIT_JUDGES=1`. Policy: gate determinista
