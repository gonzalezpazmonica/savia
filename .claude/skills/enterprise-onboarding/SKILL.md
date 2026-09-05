---
layer: peripheral
name: enterprise-onboarding
description: Usar cuando se incorporan múltiples personas a la organización de forma masiva.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.context_cost: medium
  savia.dependencies: 
  savia.maturity: stable
  savia.memory: project
  savia.priority: medium
  savia.summary: "Onboarding empresarial a escala: importacion batch de miembros, checklists por rol, tracking de progreso y knowledge transfer. Input: lista de personas + roles. Output: planes personalizados."
  savia.tags: "onboarding, enterprise, batch-import, knowledge-transfer"
---

# Skill: Enterprise Onboarding

> Prerequisito: @docs/rules/domain/onboarding-enterprise.md
> Complementa: @docs/rules/domain/team-structure.md, @.opencode/commands/team-orchestrator.md

Orquesta el onboarding de múltiples personas (CSV batch) con checklist adaptativo por rol y knowledge transfer automático.

## Flujo 1 — Importar CSV (`import`)

1. Validar CSV: name, email, role, team, projects, start_date
2. Por cada fila: crear perfil temporal (si no existe)
3. Verificar equipo existe en teams/{dept}/
4. Generar checklists per-role usando plantilla de onboarding-enterprise.md
5. Crear documentación de Knowledge Transfer por proyecto
6. Output: informe de importación + rutas de checklists + KT docs

**Errores**: Equipo no existe → mostrar teams existentes; Email duplicado → skip con warning.

## Flujo 2 — Checklist generado (`checklist`)

1. Leer plantilla checklist para {role}
2. Personalizar con {persona}, {equipo}, {proyectos}
3. Guardar en `output/onboarding/checklists/{nombre}-{role}.md`
4. Incluir: Fase 0/1/2/3, tareas específicas, buddy assigned, KT doc link
5. Output: checklist personalizado (markdown file)

## Flujo 3 — Progreso (`progress`)

1. Leer checklist actual de {persona}
2. Calcular % completado por fase (T+0, T+7, T+30)
3. Detectar bloqueos (items marked red)
4. Generar `output/onboarding/progress/{nombre}-YYYYMMDD.md`
5. Output: tabla progreso + alertas de bloqueos + recomendaciones

## Flujo 4 — Knowledge Transfer (`knowledge-transfer`)

1. Leer decision-log.md (últimos 10 entries)
2. Leer specs del proyecto asignado
3. Leer team-structure.md de equipo asignado
4. Generar KT doc:
   - Stack overview
   - Key decisions + enlaces
   - Primeras tareas + owner
   - Referencias de documentación
5. Guardar en `output/onboarding/kt/{proyecto}-{nombre}.md`
6. Output: KT document listo para M-1

## Flujo 5 — Sincronizar estado (`sync`)

1. Leer todos los checklists en progress
2. Detectar items desfasados o incompletos
3. Para cada onboarding activo (start_date ≤ today ≤ start_date+30):
   - Recalcular fase actual
   - Alertar si está retrasado
4. Generar resumen en `output/onboarding/sync-YYYYMMDD.md`
5. Output: status dashboard + alertas críticas

## Errores

| Error | Acción |
|---|---|
| CSV malformado | Validar schema; mostrar ejemplo correcto |
| Equipo no existe | Crear con `/team-orchestrator create` primero |
| Perfil incompleto | Ejecutar `/profile-setup` antes del import |
| KT doc no generable | Fallback: generar template vacío para completar manual |

## Seguridad

- NUNCA exponer emails en outputs públicos (usar @handles)
- Checklists locales (output/) pero pueden subirse a SaviaHub bajo cliente
- Datos de onboarding en output/ — git-ignored excepto checklist summary
- Knowledge Transfer puede contener datos del cliente → respetar confidencialidad
