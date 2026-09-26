---
name: backlog-git
description: "Control de versiones para backlogs de proyectos"
model_tier: mid
context_cost: medium
allowed_tools: ["Bash", "Read", "Write", "Edit", "Task"]
tier: core
---

# /backlog-git — Versionado de backlogs

> Reglas: @docs/rules/domain/backlog-git-config.md
> Dependencia: @docs/rules/domain/savia-hub-config.md · @docs/rules/domain/client-profile-config.md

## Subcomandos

### /backlog-git snapshot {client} {project}

Captura una foto del estado actual del backlog.

**Flujo:**
1. Verificar SaviaHub + cliente + proyecto existen
2. Detectar fuente del backlog (Azure DevOps, Jira, GitLab, Savia Flow, manual)
3. Extraer PBIs/items con: ID, título, estado, asignado, estimación, prioridad
4. Generar fichero markdown: `backlog-snapshots/YYYYMMDD-HHMMSS.md`
5. Incluir frontmatter con metadatos (fuente, total items, fecha, versión)
6. Commit en SaviaHub: `[backlog-git] snapshot: {client}/{project} ({N} items)`
7. Si remote + no flight-mode → push

**Output:**
```
📸 Snapshot del backlog capturado
   Cliente: {client} · Proyecto: {project}
   Fuente: {source}
   Items: {N} total ({done} done, {in-progress} in-progress, {new} new)
   Fichero: backlog-snapshots/YYYYMMDD-HHMMSS.md
```

### /backlog-git diff {client} {project} [--from REF] [--to REF]

Compara dos snapshots del backlog.

**Flujo:**
1. Sin flags → comparar último snapshot con el anterior
2. Con `--from`/`--to` → comparar snapshots específicos (fecha o índice)
3. Calcular deltas: items añadidos, eliminados, modificados (estado/estimación/asignado)
4. Detectar re-estimaciones (estimación original vs actual)
5. Mostrar resumen formateado

**Output:**
```
📊 Diff del backlog: {from} → {to}
   Añadidos: {N} items | Eliminados: {N} | Modificados: {N}
   Re-estimados: {N} items (Δ total: +{H}h)
   Estado: {N} cambiaron de estado
```

### /backlog-git rollback {client} {project} {snapshot-ref}

Genera un informe de restauración (NO modifica el backlog original).

**Flujo:**
1. Cargar snapshot referenciado
2. Comparar con estado actual → generar diff inverso
3. Listar acciones necesarias para restaurar al estado del snapshot
4. NUNCA ejecutar automáticamente — solo informar al PM
5. El PM decide si aplica manualmente en el PM tool

**Output:**
```
🔄 Plan de rollback al snapshot {ref}
   Acciones necesarias:
   • Restaurar {N} items eliminados
   • Revertir {N} cambios de estado
   • Revertir {N} re-estimaciones
   ⚠️ Revisión manual requerida antes de aplicar
```

### /backlog-git deviation-report {client} {project}

Informe de desvíos acumulados entre snapshots.

**Flujo:**
1. Cargar todos los snapshots del proyecto (cronológicos)
2. Calcular: items añadidos post-planificación, re-estimaciones totales,
   scope creep (%), velocity real vs planificada
3. Generar informe con gráfico ASCII de evolución
4. Guardar en `output/` con formato estándar

**Output:**
```
📈 Informe de desvíos — {client}/{project}
   Período: {first-snapshot} → {last-snapshot} ({N} snapshots)
   Scope creep: +{N} items ({%}%)
   Re-estimación total: +{H}h ({%}%)
   Items sin cerrar desde inicio: {N}
```

## Formato de snapshot (markdown)

```yaml
---
source: "azure-devops"
project: "{project-slug}"
client: "{client-slug}"
timestamp: "2026-03-05T10:00:00Z"
total_items: 42
version: 1
---
```

Seguido de tabla con todos los items del backlog.

## Errores

- SaviaHub no existe → sugerir `/savia-hub init`
- Cliente/proyecto no encontrado → sugerir `/client-create`
- Sin snapshots → sugerir `/backlog-git snapshot`
- PM tool no conectado → ofrecer snapshot manual
