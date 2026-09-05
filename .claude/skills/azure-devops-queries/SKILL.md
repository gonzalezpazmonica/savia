---
layer: peripheral
name: azure-devops-queries
description: "Usar cuando se necesitan consultas WIQL, actualización de work items o datos de sprint en Azure DevOps."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: azure-devops-operator
  savia.maturity: stable
  savia.category: devops
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Operaciones CRUD con Azure DevOps: queries WIQL, work items, sprint status, capacity. Autenticacion via PAT o az CLI. Input: proyecto + query. Output: datos estructurados."
  savia.tags: "azure-devops, wiql, work-items, api"
---

# Skill: azure-devops-queries

> Skill transversal. Léela SIEMPRE antes de cualquier operación con Azure DevOps.

## Constantes de esta skill

```bash
# Leer siempre desde el entorno (configuradas en .claude/.env y CLAUDE.md raíz)
ORG_URL="${AZURE_DEVOPS_ORG_URL}"          # https://dev.azure.com/MI-ORGANIZACION
ORG_NAME="${AZURE_DEVOPS_ORG_NAME}"        # MI-ORGANIZACION
PAT_FILE="${AZURE_DEVOPS_PAT_FILE}"        # $HOME/.azure/devops-pat
API_VERSION="${AZURE_DEVOPS_API_VERSION}"  # 7.1
```

---

## 1. Autenticación

### Opción A — Azure CLI (preferida)
```bash
az devops configure --defaults organization=$ORG_URL project=$PROJECT_NAME
export AZURE_DEVOPS_EXT_PAT=$(cat $PAT_FILE)
az devops project list --output table
```

### Opción B — REST API directa con curl
```bash
PAT=$(cat $PAT_FILE)
B64_PAT=$(echo -n ":$PAT" | base64)
curl -H "Authorization: Basic $B64_PAT" \
     -H "Content-Type: application/json" \
     "$ORG_URL/$PROJECT/_apis/..."
```

---

## 2. Regla Crítica: Filtrar SIEMPRE por IterationPath

> ⚠️ SIEMPRE incluir filtro `[System.IterationPath] UNDER @CurrentIteration` en las queries WIQL, salvo que se pida explícitamente una query cross-sprint.

Sin este filtro, las queries devuelven TODOS los work items del proyecto desde el inicio, lo que satura el contexto y degrada la calidad de las respuestas.

---

## 3. Queries WIQL Fundamentales

> Detalle: @references/wiql-queries.md

Cinco queries básicas para la mayoría de casos:
1. Items del sprint actual con horas
2. Bugs activos por severidad
3. Items por persona (carga actual)
4. PBIs para sprint planning
5. Items completados en el sprint

**Ejecutar con CLI:**
```bash
az boards query --wiql "SELECT..." --project "$PROJECT_NAME" --output json | jq '.workItems[].id'
```

---

## 4. Operaciones CLI Frecuentes

```bash
# Listar sprints del equipo
az boards iteration team list --project "$PROJECT_NAME" --team "$TEAM_NAME" --output table

# Obtener work item por ID
az boards work-item show --id XXXX --output json

# Actualizar horas
az boards work-item update --id XXXX \
  --fields "Microsoft.VSTS.Scheduling.CompletedWork=8"
```

---

## 5. REST API Directa — Endpoints Clave

```bash
BASE="$ORG_URL/$PROJECT/_apis"
BASE_TEAM="$ORG_URL/$PROJECT/$TEAM/_apis"

# Capacidades, días off, board, iteración actual
GET $BASE_TEAM/work/teamsettings/iterations/{iterationId}/capacities?api-version=$API_VERSION
GET $BASE_TEAM/work/teamsettings/iterations/{iterationId}/teamdaysoff?api-version=$API_VERSION
GET $ORG_URL/$PROJECT/_odata/v4.0-preview/WorkItemSnapshot?\$filter=...
GET $BASE_TEAM/work/teamsettings/iterations?\$timeframe=current&api-version=$API_VERSION
```

---

## 6. Campos WIQL — Referencia Rápida

> Detalle: @references/wiql-fields.md

Campos principales: `System.Id`, `System.Title`, `System.State`, `System.AssignedTo`, `System.WorkItemType`, `System.IterationPath`, `Microsoft.VSTS.Scheduling.StoryPoints`, `Microsoft.VSTS.Scheduling.RemainingWork`, `Microsoft.VSTS.Common.Activity`, `Microsoft.VSTS.Common.Priority`, `Microsoft.VSTS.Common.Severity`

---

## 7. Errores Comunes y Soluciones

| Error | Solución |
|-------|----------|
| `TF400813: The user is not authorized` | Regenerar PAT con scopes correctos |
| `VS403501: The query returned too many results` | Añadir filtro UNDER @CurrentIteration |
| `TF26027: Iteration not found` | Verificar con `az boards iteration team list` |
| `400 Bad Request en capacities API` | Usar team ID en lugar de nombre |
| Resultados vacíos en @CurrentIteration | Configurar sprint activo en AzDevOps |

---

## Referencias

→ Patrones WIQL: `references/wiql-patterns.md`
→ Campos detallados: `references/wiql-fields.md`
→ Analytics OData: `references/odata-patterns.md`
