---
layer: peripheral
name: backlog-git-tracker
description: Usar cuando se capturan o comparan snapshots del backlog para detectar drift.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: pm-operations
  savia.maturity: stable
  savia.context_cost: medium
  savia.dependencies: "savia-hub-sync, client-profile-manager"
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Captura snapshots periodicos del backlog (Azure DevOps, Jira, Savia Flow) y los almacena como markdown en SaviaHub. Compara versiones, detecta scope creep y genera informes de desviacion."
  savia.tags: "backlog, snapshot, audit, tracking"
---

# Skill: BacklogGit Tracker

> Regla: @docs/rules/domain/backlog-git-config.md
> Hub: @docs/rules/domain/savia-hub-config.md

## Prerequisitos

- SaviaHub inicializado: `[ -d "$SAVIA_HUB_PATH/.git" ]`
- Cliente y proyecto existen: `[ -d "$SAVIA_HUB_PATH/clients/$CLIENT/projects/$PROJECT" ]`
- Si no existe `backlog-snapshots/` → crear

## Flujo: Snapshot

1. Detectar fuente del backlog (por orden de prioridad):
   - `AZURE_DEVOPS_ORG_URL` → Azure DevOps (WIQL query)
   - `JIRA_BASE_URL` → Jira (JQL query)
   - `GITLAB_URL` → GitLab (Issues API)
   - Directorio `backlog/` en proyecto → Savia Flow
   - Ninguno → modo manual (PM dicta items)
2. Extraer items: ID, título, estado, asignado, estimación (horas), prioridad, tags
3. Generar timestamp: `date -u +%Y%m%d-%H%M%S`
4. Crear directorio si no existe: `mkdir -p backlog-snapshots/`
5. Escribir snapshot markdown con frontmatter YAML + tabla
6. Calcular resumen: total, por estado, estimación total
7. Commit: `[backlog-git] snapshot: $CLIENT/$PROJECT ($TOTAL items)`
8. Si remote + no flight-mode → push (delegar a savia-hub-sync)
9. Mostrar banner con resumen

## Flujo: Diff

1. Resolver referencias:
   - Sin flags → último vs penúltimo snapshot
   - `--from YYYYMMDD` → buscar snapshot con prefijo
   - Índice numérico (`-1`, `-2`) → contar desde el más reciente
2. Parsear ambos snapshots: extraer frontmatter + tabla → mapa ID→item
3. Calcular deltas:
   - Añadidos: `IDs(to) - IDs(from)`
   - Eliminados: `IDs(from) - IDs(to)`
   - Modificados: `IDs(from) ∩ IDs(to)` con campos diferentes
4. Para cada modificado, registrar: campo, valor anterior, valor nuevo
5. Calcular métricas: scope change %, re-estimación total Δh
6. Mostrar diff formateado con banner 📊

## Flujo: Rollback (solo informe)

1. Cargar snapshot referenciado → parsear items
2. Obtener estado actual (último snapshot o query al PM tool)
3. Generar diff inverso: qué acciones serían necesarias
4. Listar acciones en formato checklist:
   - `[ ] Restaurar item #{ID}: "{título}"`
   - `[ ] Revertir estado de #{ID}: {actual} → {original}`
   - `[ ] Revertir estimación de #{ID}: {actual}h → {original}h`
5. **NUNCA ejecutar** — solo informar al PM
6. Guardar informe en `output/` si se solicita

## Flujo: Deviation Report

1. Listar todos los snapshots: `ls backlog-snapshots/*.md | sort`
2. Parsear serie temporal: para cada snapshot, extraer total, por estado, estimación
3. Calcular métricas acumuladas:
   - Scope creep: `(items_final - items_inicial) / items_inicial × 100`
   - Re-estimación: `Σ deltas de estimación`
   - Completion trend: `closed/total` por snapshot
   - Velocity: items cerrados entre snapshots consecutivos
4. Generar gráfico ASCII de evolución (items totales, cerrados, estimación)
5. Guardar en `output/YYYYMMDD-deviation-{client}-{project}.md`
6. Mostrar resumen con banner 📈

## Snapshot manual

Cuando no hay PM tool conectado:
1. Pedir al PM lista de items (puede ser informal)
2. Estructurar en tabla con IDs secuenciales (M001, M002...)
3. Pedir confirmación antes de guardar
4. Mismo flujo de commit/push

## Errores

| Error | Acción |
|-------|--------|
| SaviaHub no existe | Sugerir `/savia-hub init` |
| Cliente no existe | Sugerir `/client-create` |
| Proyecto no existe | Sugerir `/client-edit {slug}` + añadir proyecto |
| Sin snapshots | Sugerir `/backlog-git snapshot` primero |
| PM tool no accesible | Ofrecer snapshot manual |

## Seguridad

- Snapshots son append-only: NUNCA modificar uno existente
- NUNCA ejecutar rollback automático — solo informar
- NUNCA incluir tokens o credentials en snapshots
- Confirmar con PM antes de push al remote
