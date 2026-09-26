---
name: tool-catalog
description: Catálogo categorizado de herramientas (400+ comandos)
model_tier: fast
context_cost: low
allowed_tools: ["Glob", "Read"]
tier: core
---

# /tool-catalog [categoría]

Navega el catálogo completo de comandos, skills y agentes, organizados por categoría.

## Parámetros

- `[categoría]` — Expandir una categoría específica (opcional)
  - `pm`, `dev`, `infra`, `reporting`, `compliance`, `discovery`, `admin`
- `--format` — Formato de salida: `list` (defecto), `table`

## Razonamiento

1. Contar comandos por categoría
2. Contar skills por categoría
3. Contar agentes por especialidad
4. Mostrar resumen conciso
5. Si se especifica categoría, expandir con detalles

## Flujo

### Resumen de categorías

```
/tool-catalog
```

Output:

```
📚 Catálogo de Herramientas (pm-workspace)

📌 PM Operations (24 comandos, 3 skills)
📌 Development (18 comandos, 5 skills)
📌 Infrastructure (22 comandos, 2 skills)
📌 Reporting (15 comandos, 8 skills)
📌 Communication (12 comandos, 1 skill)
📌 Compliance (14 comandos, 4 skills)
📌 Discovery (10 comandos, 2 skills)
📌 Admin (16 comandos, 2 skills)

Total: 131 comandos · 27 skills · 33 agentes

Usa: /tool-catalog {categoría} para expandir
```

### Expansión de categoría

```
/tool-catalog dev
```

Output:

```
📌 Development (18 comandos, 5 skills, 10 agentes)

Commands:
  · spec-generate — Generar spec ejecutable
  · spec-verify — Verificar spec vs código
  · spec-status — Estado de specs en sprint
  · arch-health — Auditar salud arquitectura
  · arch-review — Revisar decisión de arquitectura
  · code-review — Revisar PR
  ...

Skills:
  · spec-driven-development (SDD)
  · architectural-patterns
  · testing-strategy
  ...

Agents:
  · architect, code-reviewer, sdd-spec-writer
  · dotnet-developer, typescript-developer, java-developer
  ...
```

