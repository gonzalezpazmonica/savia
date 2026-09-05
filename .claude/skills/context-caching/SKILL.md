---
layer: peripheral
name: context-caching
description: Usar cuando se optimiza el orden de carga de contexto para maximizar cache hits.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Optimiza orden de carga de contexto para prompt caching. 4 niveles: foundation -> project -> task -> dynamic. Objetivo: maximizar cache hits (-80% coste en tokens)."
  savia.tags: "caching, performance, tokens, cost-optimization"
  savia.version: 1.0.0
---

# Context Caching Skill

Optimiza el orden de carga de contexto para maximizar cache hits.

## Patrón 1: PBI Decomposition

Descomposición de PBIs grandes en tareas reutilizando contexto:

```
1. Project CLAUDE.md (raramente cambia)
2. Reglas de negocio (cambios cada 2-3 sprints)
3. PBI a descomponer (el input del usuario)
4. User request (único por operación)

Ahorro esperado: 30-40% tokens en 3-5 tareas
```

## Patrón 2: Spec Generation

Generación de specs ejecutables:

```
1. PM-Workspace CLAUDE.md (global rules)
2. Project CLAUDE.md + reglas negocio
3. Skill SDD CLAUDE.md
4. PBI a specificar (cambia cada spec)

Breakpoints:
- Después Level 2: base de spec
- Cada nueva spec: reutiliza Levels 1-3
```

## Patrón 3: Dev Session

Ciclos dev en el mismo proyecto:

```
Inicio:
1. PM-Workspace globals
2. Project context
3. Skill spec-driven-development

Slice 1:
4. Spec-slice 1
5. Target files

Slice 2 (reutiliza Levels 1-3):
4. Spec-slice 2 (reemplaza)
5. Nuevos files

Ahorro: 60% en input tokens sin compactar
```

## Measurement Template

Medir antes vs después:

```
ANTES: 1630 tokens (op1: 850, op2: 780)
DESPUÉS: 150 tokens en op2 (hit)
Ahorro: 630 tokens = 81% descuento
```

## Operación → Cache Hit %

| Operación | Hit % | Acción |
|---|---|---|
| PBI decomposición | 80% | Agrupar tareas |
| Spec generation | 70% | Usar /cache-optimize |
| Dev session (8+ slices) | 90% | Level 1-3 completo |
| Code review (múltiples PRs) | 60% | Cargar rules una vez |
| Sprint planning | 75% | Project estable |

## Anti-Pattern: Thrashing

Detección:
- Output tokens >> input tokens
- Mismo comando varía en duración
- Cache miss rate > 50%

Solución: cargar en orden de estabilidad (Levels 1→4)
