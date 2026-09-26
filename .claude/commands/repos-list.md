---
name: repos-list
description: >
  Listar repositorios del proyecto en Azure DevOps con estadísticas
  de actividad, tamaño y última actualización.
model_tier: fast
context_cost: low
tier: core
---

# Repos List

**Argumentos:** $ARGUMENTS

> Uso: `/repos-list --project {p}`

## Parámetros

- `--project {nombre}` — Proyecto de PM-Workspace (obligatorio)
- `--sort {campo}` — Ordenar por: `name`, `updated`, `size` (defecto: updated)

## Contexto requerido

1. `projects/{proyecto}/CLAUDE.md` — `AZURE_REPOS_PROJECT`
2. @docs/rules/domain/azure-repos-config.md — Config de Azure Repos

## Pasos de ejecución

1. **Leer proyecto** → resolver nombre en Azure DevOps
2. **MCP `list_repositories`** → obtener repos del proyecto
3. **Para cada repo:**
   - Nombre, URL de clone, rama por defecto
   - Tamaño del repo
   - Última fecha de push
4. **Presentar tabla:**

```
## Repositorios — {proyecto}

| Repo | Rama default | Último push | Tamaño |
|---|---|---|---|
| backend-api | main | hace 2h | 45 MB |
| frontend-app | main | hace 1d | 23 MB |
| shared-libs | develop | hace 5d | 8 MB |
| infra-terraform | main | hace 2w | 3 MB |

Total: 4 repositorios
```

## Restricciones

- Solo lectura
- No mostrar repos archivados salvo petición explícita
