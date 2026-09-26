---
name: savia-pbi
description: >
  Crear, ver y listar PBIs en Savia Flow (Git-based PM).
  Sin dependencia de Azure DevOps.
argument-hint: "[create|view|list] [--project <name>]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia PBI

**Argumentos:** $ARGUMENTS

> Uso: `/savia-pbi create` | `/savia-pbi view PBI-001` | `/savia-pbi list`

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md
2. `.opencode/skills/company-messaging/references/flow-schemas.md`

## Pasos de ejecucion

1. Mostrar banner: `--- Savia PBI ---`
2. Verificar company repo configurado (`$HOME/.pm-workspace/company-repo`)
3. Si no hay proyecto en args, preguntar nombre del proyecto
4. Detectar accion:
   - **create**: Preguntar titulo, descripcion, prioridad, estimacion.
     Ejecutar: `bash scripts/savia-flow.sh create-pbi <project> <title> <desc> <priority> <estimate>`
   - **view <id>**: Leer PBI file, mostrar frontmatter + cuerpo formateado
   - **list**: Listar PBIs del backlog con `bash scripts/savia-flow.sh metrics <project>`
     y mostrar tabla de PBIs por estado
5. Si create: preguntar si asignar ahora.
   Si si: `bash scripts/savia-flow.sh assign <project> <pbi_id> <handle>`
6. Preguntar si sincronizar: `bash scripts/company-repo.sh sync`
7. Mostrar banner de finalizacion

## Voz Savia (humano)

- Create: "PBI creado. Quieres asignarlo a alguien?"
- List: "Aqui tienes el backlog de {project}."

## Modo agente

```yaml
status: OK
action: "create|view|list"
pbi_id: "PBI-NNN"
project: "name"
```

## Restricciones

- NUNCA crear PBI sin confirmacion del usuario
- Validar que el proyecto existe antes de operar

/compact — Ejecuta para liberar contexto antes del siguiente comando
