---
layer: peripheral
name: rules-traceability
description: Usar cuando se mapean reglas de negocio a PBIs para trazabilidad completa.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: business-analyst
  savia.maturity: stable
  savia.category: governance
  savia.context: fork
  savia.context_cost: high
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Mapea reglas de negocio (RN-XXX-NN) a PBIs con matriz de trazabilidad. Detecta reglas sin PBI y PBIs sin regla. Output: matriz + informe de cobertura."
  savia.tags: "traceability, business-rules, pbi, matrix"
---

# Skill: Business Rules to PBI Mapping with Traceability

Mapea reglas de negocio (RN-XXX-NN) a Product Backlog Items, creando una matriz de trazabilidad bidireccional que identifica cobertura de reglas, análisis de brechas y propuestas de PBIs faltantes.

**Prerequisitos:** `../azure-devops-queries/SKILL.md`, `../product-discovery/SKILL.md`

---

## Fases

### Fase 1: Parsear reglas de negocio

Leer `projects/{project}/reglas-negocio.md`. Extraer todos los patrones RN-XXX-NN:

```bash
grep -oE 'RN-[A-Z0-9]+-[0-9]+' reglas-negocio.md | sort -u
```

Para cada RN: ID, descripción (párrafo siguiente), tipo (simple/feature).

### Fase 2: Consultar PBIs existentes en Azure DevOps

```bash
curl -s -u ":$(cat $PAT_FILE)" \
  "$AZURE_DEVOPS_ORG_URL/{proyecto}/_apis/wit/wiql?api-version=7.1" \
  -d "{'query':'SELECT [System.Id] FROM workitems'}" | jq '.workItems[].id'
```

Buscar referencias RN en: Title, Description, Tags.

### Fase 3: Construir matriz de trazabilidad

| RN-ID | Descripción | PBI-IDs cubriendo | Cobertura |
|---|---|---|---|
| RN-001-01 | ... | [302, 305] | Completa |
| RN-001-02 | ... | [302] | Parcial |
| RN-002-01 | ... | — | Ninguna |

### Fase 4: Análisis de brechas

Para cada RN sin cobertura o cobertura parcial:
- Si regla simple → proponer PBI directo (título, descripción, criterios de aceptación)
- Si regla feature → flagear para product-discovery (JTBD + PRD antes de crear PBI)

### Fase 5: Propuesta de PBIs

Presentar al PM (sin ejecutar):

```
Título: {inferido de RN}
Descripción: {de RN}
Criterios de aceptación: {derivados de RN}
Tags: [RN-XXX-NN]
Prioridad: (sugerir basado en dependencias)
```

### Fase 6: Crear en Azure DevOps

Tras confirmación:
```bash
curl -X POST -u ":$(cat $PAT_FILE)" \
  "$AZURE_DEVOPS_ORG_URL/{proyecto}/_apis/wit/workitems/\$PBI?api-version=7.1" \
  -d "fields"
```

### Fase 7: Generar reporte

Guardar matriz a `output/YYYYMMDD-traceability-{project}.md` con:
- Matriz RN↔PBI
- Estadísticas de cobertura (%)
- Recomendaciones

---

## Referencias

→ Azure DevOps API: `docs/azure-devops-api-patterns.md`
→ Product Discovery: `../product-discovery/SKILL.md`
