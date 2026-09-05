---
layer: peripheral
name: pbi-decomposition
description: Usar cuando se descompone un PBI en tasks y se estiman las horas.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: business-analyst
  savia.maturity: stable
  savia.category: pm-operations
  savia.context: fork
  savia.context_cost: high
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Descompone PBI en tasks tecnicas con estimacion en horas. Usa architect (capas) y business-analyst (criterios). Input: PBI con acceptance criteria. Output: tasks asignables. Minimo 3 tasks por PBI."
  savia.tags: "pbi, decomposition, estimation, assignment"
---

# Skill: PBI Decomposition, Estimation & Smart Assignment

Descomponer Product Backlog Items (PBIs) en Tasks técnicas, estimarlas en horas y asignarlas inteligentemente a los miembros del equipo en base a su perfil técnico, capacity disponible y contexto del proyecto.

**Prerequisitos:** `../azure-devops-queries/SKILL.md`, `../capacity-planning/SKILL.md`

---

## Decision Checklist

1. Is this item a PBI (not already a Task/Bug/Chore)? -> If already a Task: skip, estimate directly
2. Are acceptance criteria present and >50 characters? -> If NO: return to PO for criteria
3. Does the PBI have a clear "done" definition? -> If NO: escalate to product-discovery first
4. Is estimated effort >13 SP or >5 days? -> If YES: split into 2+ PBIs before decomposing
5. Does the PBI depend on unfinished PBIs? -> If YES: mark dependency, flag blocked tasks

### Abort Conditions
- No acceptance criteria at all -> STOP, require PO input
- PBI is actually an Epic (>21 SP) -> STOP, needs epic-plan first

---

## Triggers

`/pbi-decompose {id}` | `/pbi-assign {id}` | `/pbi-plan-sprint` | NL: "descompon el PBI #1234"

---

## Contexto Requerido

1. `CLAUDE.md` (raíz) — Contexto global, Azure DevOps
2. `projects/{proyecto}/CLAUDE.md` — Stack, arquitectura
3. `projects/{proyecto}/reglas-negocio.md` — Reglas de dominio
4. `projects/{proyecto}/equipo.md` — Perfiles, skills, dedicación
5. `docs/politica-estimacion.md` — Tabla de calibración SP→horas
6. `docs/reglas-scrum.md` — DoR, DoD, WIP limits
7. `projects/{proyecto}/source/` — Estructura, patrones en uso

---

## Fase 1: Análisis del PBI

### 1.1 Obtener el PBI

```bash
curl -s -u ":$PAT" "$AZURE_DEVOPS_ORG_URL/{proyecto}/_apis/wit/workitems/{id}?api-version=7.1" | jq .
```

Extraer: Title, Description, Acceptance Criteria, Story Points, Priority, Tags, Related Links, Discussion.

### 1.2 Analizar dominio funcional

Identificar: Módulos afectados, tipo de cambio (nueva/modificación/refactor), capas involucradas, integraciones externas, impacto en datos, requisitos de seguridad/compliance.

### 1.3 Inspeccionar código fuente

```bash
find projects/{proyecto}/source/src -name "*{modulo}*" | head -10
grep -r "{concepto}" projects/{proyecto}/source/src/ --include="*.cs" | head -10
find projects/{proyecto}/source/tests -name "*{modulo}*" | head -5
```

---

## Fase 2: Descomposición en Tasks

### 2.1 Categorías

Categorías A-E (Análisis, Backend, Frontend, Testing, Transversal).
Estimaciones: 1-8h según tipo. Detalle completo: **`references/phases-detail.md`**

### 2.2 Reglas de descomposición

1. Máximo 8h por Task (subdividir si excede)
2. Mínimo 1h por Task
3. Una Task = Un Responsable
4. Definir Activity en cada Task (Development/Testing/Documentation/Design)
5. Coherencia con SP (suma de horas debe coincidir con calibración)
6. No inflar (no crear tasks innecesarias)
7. **Numeración jerárquica por fases**: Foundation (1.x) → Core (2.x) → Integration (3.x) → Testing (4.x) → Cleanup (5.x)

### 2.3 Adaptación por Stack

Adaptar al stack del proyecto (leído de CLAUDE.md):
- **.NET Clean Architecture**: Tasks B separadas por capa (Domain→Application→Infrastructure→API)
- **.NET N-Layer simple**: Tareas B pueden fusionarse
- **Blazor**: Tasks C específicas para componentes
- **Microservicios**: Una Task por servicio + integración

---

## Fase 3: Estimación Inteligente

### 3.1 Factores de ajuste

```
horas_ajustadas = horas_base × factor_complejidad × factor_conocimiento × factor_riesgo
```

**Factor de complejidad**:
- Código nuevo en módulo bien estructurado: ×1.0
- Módulo legacy/mal documentado: ×1.3
- Refactor con alto acoplamiento: ×1.5
- Integración externa sin SDK: ×1.4
- Primera vez equipo toca módulo: ×1.2

**Factor de conocimiento** (del developer):
- Expert (tocó últimos 3 sprints): ×0.8
- Conoce el módulo: ×1.0
- No conoce pero sabe stack: ×1.2
- Junior o primera vez: ×1.5

**Factor de riesgo**:
- Dependencias externas: ×1.2
- Datos de producción/migración: ×1.3
- Compliance estricto: ×1.2
- Patrón nuevo para equipo: ×1.3

### 3.2 Validación de coherencia

```
total_horas = SUM(horas_ajustadas)
rango_esperado = lookup(SP, politica-estimacion.md)
```

Si desviación > 30% → alertar al PM.

---

## Fases 4-8 y Referencias

Fases 4-8 (asignacion, Azure DevOps, post-creacion): `references/phases-detail.md` | Scoring: `references/assignment-scoring.md`
