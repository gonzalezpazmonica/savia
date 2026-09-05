---
layer: peripheral
name: azure-pipelines
description: Usar cuando se gestiona o depura CI/CD con Azure Pipelines.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: azure-devops-operator
  savia.maturity: stable
  savia.category: devops
  savia.context: fork
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Gestion de CI/CD con Azure Pipelines: estado, ejecucion, creacion de pipelines, logs y artefactos. Autenticacion via PAT. Output: status + acciones."
  savia.tags: "pipelines, ci-cd, azure, deployment"
---

# Skill: azure-pipelines

> Skill para gestión de CI/CD con Azure Pipelines via MCP.
> Léela antes de cualquier operación con pipelines.

## Contexto

Azure Pipelines gestiona builds y releases de los proyectos.
PM-Workspace accede via el MCP `azure-devops` (ya declarado en `mcp.json`).

**MCP tools de pipelines disponibles:**
- `get_build_definitions` — listar pipelines del proyecto
- `get_builds` — listar builds (filtrar por pipeline, branch, status)
- `get_build_status` — estado de una build específica
- `get_build_logs` — logs de una build (timeline + contenido)
- `run_pipeline` — ejecutar una pipeline (requiere confirmación PM)
- `preview_pipeline_run` — preview de qué se ejecutará (sin ejecutar)
- `create_pipeline` — crear pipeline desde YAML
- `list_artifacts` — artefactos de una build
- `download_artifacts` — descargar artefactos

---

## 1. Autenticación

Usa el mismo PAT de Azure DevOps configurado en `pm-config.md`.

**Scopes requeridos:** `Build R/W` (además de los existentes).

```bash
# El MCP lee el PAT del entorno automáticamente
# Verificar: el PAT debe tener scope "Build (Read & Execute)"
```

---

## 2. Reglas Críticas

1. **NUNCA ejecutar pipeline sin confirmación** del PM (regla 3)
2. **SIEMPRE preview antes de run** — usar `preview_pipeline_run`
3. **Deploys a PRO** requieren doble confirmación + link al PBI/Release
4. **Variables sensibles** (secrets) NO se muestran en logs
5. **Artefactos** se guardan en `output/artifacts/{proyecto}/{build-id}/`

---

## 3. Patrones de uso

### Obtener estado de pipelines
```
MCP: get_build_definitions(project=PROYECTO)
→ Para cada definition: get_builds(project, definitionId, top=5)
→ Calcular: % éxito, duración media, trends
```

### Ejecutar pipeline
```
MCP: preview_pipeline_run(project, pipelineId, branch)
→ Mostrar resumen al PM → Confirmar
→ MCP: run_pipeline(project, pipelineId, branch, variables)
→ MCP: get_build_status(project, buildId) [polling si --watch]
```

### Crear pipeline
```
1. Seleccionar template (references/yaml-templates.md)
2. Adaptar al proyecto (lenguaje, tests, deploy targets)
3. MCP: preview_pipeline_run → validar YAML
4. Confirmar con PM
5. MCP: create_pipeline(project, name, yamlPath, repository)
```

---

## 4. Interpretación de estados

| Build Status | Significado | Acción PM |
|---|---|---|
| `succeeded` | Build OK | Ninguna |
| `partiallySucceeded` | Warnings o tests flaky | Revisar logs |
| `failed` | Error en build/test | Investigar + crear Bug si recurrente |
| `canceled` | Cancelado por usuario/timeout | Verificar causa |
| `inProgress` | Ejecutándose | Esperar o monitorizar |
| `notStarted` | En cola | Normal si hay carga |

---

## 5. Multi-entorno (DEV → PRE → PRO)

Los pipelines multi-stage siguen el patrón:

```
Build → Test → Deploy DEV (auto) → Deploy PRE (approval) → Deploy PRO (approval)
```

Ver `references/stage-patterns.md` para patrones detallados.

**Gates de aprobación:**
- DEV: automático tras build+test OK
- PRE: aprobación del tech lead
- PRO: aprobación del PM + PO (doble gate)

---

## 6. Referencias

- Templates YAML: `references/yaml-templates.md`
- Patrones de stages: `references/stage-patterns.md`
- Config entornos: `@docs/rules/domain/environment-config.md`
- MCP Azure DevOps: `@.claude/mcp.json`
