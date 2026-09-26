---
name: backlog-patterns
description: Detecta PBIs duplicados o similares entre proyectos del portfolio
developer_type: all
agent: task
context_cost: high
model_tier: mid
tier: core
---

# /backlog-patterns

> 🦉 Savia encuentra trabajo duplicado entre proyectos antes de que lo hagas dos veces.

---

## Cargar perfil de usuario

Grupo: **PBI & Backlog** — cargar:

- `identity.md` — rol (PM decide acciones, dev sugiere)
- `workflow.md` — planning_cadence
- `projects.md` — lista de proyectos activos

---

## Subcomandos

- `/backlog-patterns` — análisis completo de patrones entre todos los proyectos
- `/backlog-patterns --project {a} {b}` — comparar backlogs de dos proyectos
- `/backlog-patterns --type duplicates` — solo PBIs duplicados
- `/backlog-patterns --type shared` — solo funcionalidades compartibles

---

## Flujo

### Paso 1 — Extraer PBIs activos de cada proyecto

Para cada proyecto del portfolio, obtener vía Azure DevOps:

- PBIs en estado New, Approved, Committed
- Título, descripción, tags, acceptance criteria
- Story points estimados

### Paso 2 — Análisis de similitud

Comparar PBIs entre proyectos usando:

1. **Similitud de título** — fuzzy matching (≥70% = candidato)
2. **Similitud semántica** — comparar descripciones por conceptos clave
3. **Tags comunes** — PBIs con mismos tags en distintos proyectos
4. **Patrones funcionales** — auth, logging, notifications, exports (cross-cutting)

### Paso 3 — Clasificar hallazgos

```
📊 Backlog Patterns — Portfolio ({N} proyectos, {N} PBIs analizados)

🔴 Duplicados probables (similitud ≥85%):
  - "Implementar autenticación OAuth2" (proyecto-A #1234)
    ≈ "Añadir login con OAuth" (proyecto-B #5678)
    Similitud: 89% | SP duplicados: 13

🟡 Funcionalidad compartible (similitud 70-84%):
  - "Sistema de notificaciones email" aparece en 3 proyectos
    Candidato a librería compartida | SP total: 21

🟢 Patrones reutilizables:
  - Patrón "export a Excel" implementado en proyecto-A
    Proyecto-C lo necesita → sugerir reutilización
```

### Paso 4 — Recomendaciones

1. **Consolidar**: PBIs duplicados → asignar a un solo proyecto, otros consumen
2. **Extraer**: Funcionalidad repetida → librería compartida o servicio común
3. **Reutilizar**: Código existente en un proyecto → referencia para otros

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: backlog_patterns
projects_compared: 4
pbis_analyzed: 87
duplicates_found: 3
shared_candidates: 5
estimated_sp_savings: 34
```

---

## Restricciones

- **NUNCA** marcar como duplicado sin ≥70% de similitud
- **NUNCA** eliminar PBIs automáticamente — solo sugerir consolidación
- Similitud semántica es orientativa, la decisión final es del PM/PO
- Respetar que proyectos distintos pueden necesitar implementaciones distintas
