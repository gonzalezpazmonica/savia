---
name: pbi-plan-sprint
description: Plan and allocate PBIs to upcoming sprint
tier: extended
---

---

# /pbi-plan-sprint

Flujo completo de Sprint Planning asistido por IA: calcula capacity, propone qué PBIs caben, descompone en tasks y asigna todo de forma equilibrada.

## 1. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **PBI & Backlog** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/workflow.md`
   - `profiles/users/{slug}/projects.md`
   - `profiles/users/{slug}/tools.md`
3. Adaptar output según `identity.rol`, `workflow.sdd_active` y disponibilidad de `tools.azure_devops`
4. Si no hay perfil → continuar con comportamiento por defecto

## 2. Uso
```
/pbi-plan-sprint [--project {nombre}] [--sprint "Sprint 2026-XX"] [--max-sp N]
```

- `--project`: Proyecto (default: el del CLAUDE.md raíz)
- `--sprint`: Sprint al que se planifica (default: el siguiente sprint sin iniciar)
- `--max-sp N`: Limitar la propuesta a N Story Points máximos (override de la capacity calculada)

## 3. Este comando combina y orquesta

→ `capacity-planning/SKILL.md` (para calcular horas disponibles)
→ `sprint-management/SKILL.md` (para obtener el sprint y PBIs candidatos)
→ `pbi-decomposition/SKILL.md` (para descomponer y asignar cada PBI)
→ `azure-devops-queries/SKILL.md` (para todas las llamadas a la API)

## 4. Flujo Completo

### Paso 1 — Obtener Capacity del Equipo

```bash
# Capacity por persona para el sprint objetivo (misma lógica que /report-capacity).
# azdevops-queries.sh lee la iteración ACTUAL: si el objetivo es el siguiente sprint,
# exportar sus capacidades por API (capacity-planning, Flujo 2 con su ITER_ID).
./scripts/azdevops-queries.sh capacities {proyecto} "{equipo}" > /tmp/capacities.json
echo '[]' > /tmp/sprint-items.json   # sprint objetivo aún sin items asignados
python3 scripts/capacity-calculator.py \
  --items /tmp/sprint-items.json --capacities /tmp/capacities.json \
  --sprint-start {fecha_inicio} \
  --sprint-end {fecha_fin} --output-json
```

Resultado: `carga_por_persona.{persona}.horas_disponibles` para cada miembro de
`/tmp/capacities.json` (con carga 0 si aún no tiene items).

### Paso 2 — Obtener PBIs Candidatos del Backlog

```bash
# PBIs en estado Approved/Ready, ordenados por prioridad
WIQL: SELECT Id, Title, StoryPoints, Priority FROM WorkItems
      WHERE WorkItemType IN ('User Story','PBI')
        AND State IN ('Approved','Committed','New')
        AND IterationPath = '{proyecto}\\Backlog'
      ORDER BY Priority ASC, StoryPoints ASC
```

### Paso 3 — Selección de PBIs para el Sprint

Aplicar la regla de sobre-compromiso de `docs/reglas-scrum.md`:
```
SP_max_recomendados = velocity_media × 0.85   (85% del margen de seguridad)
```

Proponer los PBIs de mayor prioridad hasta que la suma de SP alcance `SP_max_recomendados`.
Si el último PBI que cabe tiene muchos SP, considerar si vale la pena incluir uno más pequeño.

### Paso 4 — Descomponer y Asignar cada PBI

Para cada PBI seleccionado, ejecutar las Fases 1-5 de `pbi-decomposition/SKILL.md` en modo batch (ver `/pbi-decompose-batch`), acumulando el estado de carga entre PBIs.

### Paso 5 — Presentar el Plan Completo

```
🗓️  SPRINT PLANNING — {Proyecto} — {Sprint}
    Período: {fechas} | Capacity total: {Xh} ({N} personas)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📌 PBIs PROPUESTOS PARA EL SPRINT ({total SP} SP)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

┌───────┬──────────────────────────────────┬────┬───────┐
│ ID    │ Título                           │ SP │ Prio  │
├───────┼──────────────────────────────────┼────┼───────┤
│ #1234 │ Registro de pacientes            │  5 │ Alta  │
│ #1235 │ Actualizar perfil de paciente    │  3 │ Alta  │
│ #1236 │ Exportar histórico PDF           │  5 │ Media │
│ #1237 │ Notificaciones por email         │  3 │ Media │
└───────┴──────────────────────────────────┴────┴───────┘
Total: 16 SP (velocity media: 18 SP → 89% ✅)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 TASKS DESCOMPUESTAS (resumen)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PBI #1234 — 8 tasks — 17h
PBI #1235 — 5 tasks — 10h
PBI #1236 — 6 tasks — 14h
PBI #1237 — 4 tasks —  8h
Total: 23 tasks — 49h

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 CARGA FINAL DEL EQUIPO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌──────────────────┬────────┬────────┬────────┐
│ Persona          │ Cap.   │ Asign. │ Util.  │
├──────────────────┼────────┼────────┼────────┤
│ María García     │ 60h    │ 52h    │  87% 🟡│
│ Carlos Ruiz      │ 60h    │ 45h    │  75% 🟢│
│ Ana López        │ 60h    │ 48h    │  80% 🟢│
│ Pedro Torres     │ 60h    │ 56h    │  93% 🟡│
└──────────────────┴────────┴────────┴────────┘

⚠️ Pedro Torres al límite — considerar mover 1 task de code review a Ana.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💡 SPRINT GOAL SUGERIDO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"Completar el módulo de gestión de pacientes (registro, actualización y exportación de historial)
 con notificaciones automáticas por email."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
¿Procedo a crear todas las Tasks en Azure DevOps y mover los PBIs a "Committed"? (s/n)
(También puedes pedir: "ajusta el SP goal", "quita el PBI #1236", "reasigna las tasks de Pedro")
```

### Paso 6 — Ejecución tras Confirmación

- Crear todas las Tasks con los datos calculados
- Mover PBIs a estado "Committed" y asignarles el IterationPath del sprint
- Dejar comentario en cada PBI con el resumen de descomposición
- Configurar las capacidades en Azure DevOps si no están configuradas

> ⚠️ Este comando genera muchas operaciones de escritura. Siempre mostrar el plan completo y esperar confirmación explícita antes de ejecutar.
