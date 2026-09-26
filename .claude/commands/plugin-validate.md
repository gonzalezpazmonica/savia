---
name: plugin-validate
description: Validar estructura de plugin — skills, agents, commands e integridad
argument-hint: "[--strict] [--report]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
model_tier: mid
context_cost: medium
tier: core
---

# /plugin-validate

Valida la integridad de pm-workspace como plugin distributable.
Inspecciona skills, agents, commands, PII, líneas límite y frontmatter.

## Uso

```
/plugin-validate [--strict] [--report]
```

### Argumentos

- `--strict` (opcional): Tratar warnings como errores; bloquear en críticos
- `--report` (opcional): Guardar validación en output/validation.json

### Ejemplos

```
/plugin-validate
/plugin-validate --strict
/plugin-validate --report
```

## Validaciones

| Validación | Tipo | Límite | Descripción |
|---|---|---|---|
| Skill SKILL.md | Error | ≤ 150 líneas | Archivo markdown de skill |
| Agent frontmatter | Error | Requerido | Campos: name, description, model |
| Command description | Error | Requerido | Campo description en YAML |
| Archivos SKILL.md | Error | Todos | Cada skill debe tener SKILL.md |
| PII en exports | Error | Ninguna | Ningún dato personal en archivos |
| Integridad refs | Warning | ≥90% | Skills/agents referenciados |
| Línea promedio | Warning | ≤100 | Promedio de líneas por archivo |

## Output

Reporte estructurado con:
- ✅ Validaciones pasadas
- ⚠️ Advertencias
- 🔴 Errores críticos
- Acciones recomendadas

## Validación detallada

**Skills:** Verifica SKILL.md existe en cada directorio `skills/{nombre}/`

**Agents:** Valida frontmatter YAML completo (name, description, model)

**Commands:** Asegura descripción y campos requeridos en frontmatter

**PII:** Grep por emails, nombres reales, URLs privadas, datos sensibles

**Integridad:** Línea promedio dentro límites para mantenibilidad
