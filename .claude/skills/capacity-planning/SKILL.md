---
layer: peripheral
name: capacity-planning
description: Usar cuando se calcula la capacidad del equipo para un sprint o periodo.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: azure-devops-operator
  savia.maturity: beta
  savia.category: pm-operations
  savia.context: fork
  savia.context_cost: medium
  savia.priority: high
  savia.summary: "Calcula capacidad del equipo: horas disponibles, focus factor, alertas de sobre-asignacion. Consulta Azure DevOps iterations API. Output: tabla de capacidad por persona + alertas."
  savia.tags: "capacity, team, workload, planning"
---

# Skill: capacity-planning

> Gestión completa de capacidades del equipo: consulta, cálculo y alertas de sobre-asignación.

**Prerequisito:** Leer primero `.opencode/skills/azure-devops-queries/SKILL.md`

## Constantes de esta skill

```bash
TEAM_HOURS_PER_DAY=8          # horas de trabajo por día
TEAM_FOCUS_FACTOR=0.75        # 75% del tiempo es productivo
OVERLOAD_THRESHOLD=1.0        # > 100% = sobre-cargado
WARNING_THRESHOLD=0.85        # > 85% = al límite

ITERATIONS_API="$ORG_URL/$PROJECT/$TEAM/_apis/work/teamsettings/iterations"
```

---

## Flujo 1 — Obtener el ID de la Iteración Actual

```bash
PAT=$(cat $AZURE_DEVOPS_PAT_FILE)
AUTH="Authorization: Basic $(echo -n ":$PAT" | base64)"

ITER_RESPONSE=$(curl -s "$ITERATIONS_API?\$timeframe=current&api-version=7.1" \
  -H "$AUTH" -H "Content-Type: application/json")

ITER_ID=$(echo $ITER_RESPONSE | jq -r '.value[0].id')
ITER_NAME=$(echo $ITER_RESPONSE | jq -r '.value[0].name')
```

---

## Flujo 2 — Consultar Capacidades Configuradas

```bash
CAPACITIES=$(curl -s "$ITERATIONS_API/$ITER_ID/capacities?api-version=7.1" -H "$AUTH")
echo $CAPACITIES | jq '.value[] | {persona: .teamMember.displayName, capacidadDia: .activities[0].capacityPerDay}'
```

Formato esperado: `{displayName, uniqueName, activities[], daysOff[]}`

---

## Flujo 3 — Consultar Días Off del Equipo

```bash
TEAM_DAYS_OFF=$(curl -s "$ITERATIONS_API/$ITER_ID/teamdaysoff?api-version=7.1" -H "$AUTH")
echo $TEAM_DAYS_OFF | jq '.daysOff[] | {start, end}'
```

---

## Flujo 4 — Calcular Horas Disponibles Reales

> Detalle: @references/capacity-formula.md

Algoritmo:
1. Contar días hábiles entre inicio-fin del sprint
2. Restar días off (persona + equipo)
3. Aplicar factor de foco (75%)

Fórmula: `horas_disponibles = (dias_habiles - dias_off) * horas_dia * factor_foco`

---

## Flujo 5 — Calcular Utilización vs Carga Asignada

Obtener RemainingWork y CompletedWork por persona desde WIQL y cruzar con la capacidad del sprint completo:

```bash
Utilización = sum(RemainingWork + CompletedWork por persona) / horas_disponibles_por_persona
```

Las horas disponibles cubren el sprint entero, así que el numerador incluye también lo ya completado.

**Umbrales:**
- 🔴 > 100% — SOBRE-CARGADO
- 🟡 85-100% (ambos incluidos) — AL LÍMITE
- 🟢 < 85% — OK
- ⚪ 0 h disponibles (capacidad 0 en AzDO o sprint sin días hábiles) — SIN DATOS
- `Sin asignar` no recibe capacidad ni alertas

### Ejecutable: `scripts/capacity-calculator.py`

```bash
./scripts/azdevops-queries.sh items      > items.json   # stream de objetos: se acepta
./scripts/azdevops-queries.sh capacities > caps.json
python3 scripts/capacity-calculator.py --items items.json --capacities caps.json \
  [--team-days-off teamdaysoff.json] --sprint-start 2026-09-07 --sprint-end 2026-09-18 \
  [--team-hours-per-day 8] [--focus-factor 0,75] [--output-json]
```

- `--capacities`: salida de `azdevops-queries.sh capacities`, API cruda (`value[].teamMember/activities/daysOff`) o mapa `{persona: {horas_disponibles}}`. `horas_dia` = suma de `capacityPerDay` de las actividades.
- Días off = unión personales + `--team-days-off`; solo restan si caen en día hábil.
- Festivos por defecto: Comunidad de Madrid 2026. Fuera de 2026 avisa (`[WARN]`): pasar `--team-days-off`.
- Sin fechas de sprint: 10 días hábiles por defecto.
- Los miembros presentes en `--capacities` salen aunque no tengan items (carga 0): útil en sprint planning.
- `azdevops-queries.sh capacities` e `items` leen la iteración **actual**; para otra iteración, obtener sus capacidades por API (Flujo 2 con su `ITER_ID`).
- Coma decimal aceptada (`4,5`). Exit: 0 ok · 1 entrada inválida · 2 argumento inválido (fechas invertidas, una sola fecha, foco fuera de (0,1]).

---

## Flujo 6 — Actualizar Capacidades en Azure DevOps

```bash
curl -s -X PATCH "$ITERATIONS_API/$ITER_ID/capacities/$TEAM_MEMBER_ID?api-version=7.1" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"activities": [{"name": "Development", "capacityPerDay": 6}], "daysOff": []}'
```

> ⚠️ Confirmar con usuario antes de ejecutar.

---

## Errores Frecuentes

| Error | Solución |
|-------|----------|
| `404` en capacities | Usar team ID en lugar de nombre |
| Capacidades vacías | Activar sprint en Team Settings |
| Festivos ignorados | Añadir manualmente via API o UI |

---

## Referencias

- `references/capacity-formula.md` — Fórmulas de cálculo
- `references/capacity-api.md` — Estructura respuesta API
- Sprint management: `../sprint-management/SKILL.md`
- Comando: `/report-capacity`
