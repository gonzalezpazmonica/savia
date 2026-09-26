---
name: tool-search
description: Buscar comandos, skills y agentes por palabra clave
model_tier: fast
context_cost: low
allowed_tools: ["Glob", "Grep", "Read"]
tier: core
---

# /tool-search [consulta]

Descubre herramientas en los 400+ comandos de pm-workspace mediante búsqueda por palabra clave.

## Parámetros

- `[consulta]` — Palabra clave (requerida): sprint, spec, security, report, etc.
- `--type` — Filtrar por tipo: `command`, `skill`, `agent` (opcional)
- `--category` — Filtrar por categoría: pm, dev, infra, reporting, compliance, discovery, admin
- `--limit` — Número de resultados (máx 20, défault 10)

## Razonamiento

1. Buscar en comando .md por nombre y descripción
2. Buscar en skill.md por nombre y descripción
3. Buscar en agentes por nombre y especialidad
4. Ordenar por relevancia (keyword match + frecuencia de uso)
5. Mostrar solo top N resultados con descripción breve

## Flujo

### Búsqueda simple

```
/tool-search sprint
```

Output: Lista de comandos/skills/agentes que contienen "sprint" con desc breve.

```
📋 Sprint Tools (8 encontrados)

Commands:
  · sprint-plan — Planificar sprint nuevo
  · sprint-status — Estado actual del sprint
  · daily-routine — Reunión de stand-up

Skills:
  · sprint-management — Flujo completo de sprint

Agents:
  · azure-devops-operator — Gestión de work items
```

### Búsqueda con filtro de tipo

```
/tool-search spec --type command
```

Output: Solo comandos que contienen "spec".

### Búsqueda con categoría

```
/tool-search --category dev
```

Output: Todos los comandos de Development (spec-*, dev-*, arch-*, code-*).

## Tips de búsqueda

- Búsqueda por prefijo: `sprint` → todos los sprint-* 
- Búsqueda por concepto: `security` → security-audit, security-review, aepd-*
- Búsqueda por rol: `report` → report-executive, report-hours, report-capacity

