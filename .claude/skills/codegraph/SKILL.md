---
layer: peripheral
name: codegraph
description: Usar cuando se necesita indexación AST persistente para navegación de callers/callees en el código.
allowed-tools: [Bash, Read]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.context: project
  savia.maturity: experimental
  savia.priority: medium
  savia.summary: "CodeGraph (colbymchenry/codegraph) indexa código en SQLite con tree-sitter y lo expone vía MCP stdio. Sustituye grep ad-hoc de .acm/ast-comprehension por queries semánticas. 35% menos coste y 70% menos tool calls (bench upstream). Opt-in por proyecto: requiere `codegraph init -i` y MCP habilitado en opencode.json. NO se carga al arranque (Rule #19)."
  savia.tags: "mcp, ast, tree-sitter, indexing, callers, impact, acm-engine"
  savia.user-invocable: True
---

# CodeGraph — Motor de indexación AST

MCP server externo `@colbymchenry/codegraph` (MIT,
[github.com/colbymchenry/codegraph](https://github.com/colbymchenry/codegraph))
que indexa código con tree-sitter en SQLite y expone 8 tools MCP. Savia lo
usa como **motor** de dos skills, no como reemplazo:

- `agent-code-map` (`.acm`): proyecta el índice a Markdown estructurado.
- `ast-comprehension`: sustituye grep por llamadas MCP semánticas.

`.hcm`, `codebase-map` y Savia Shield siguen siendo nuestros — ortogonales.

## Por qué

Las queries grep tienen tres límites: falsos positivos en `callers` por
matches en comentarios/strings, no son incrementales, y no entienden
routes de framework (Django, Express, FastAPI, Spring). CodeGraph resuelve
los tres con un índice persistente.

## Activación opt-in por proyecto

CodeGraph **no** se instala con Savia. Se activa cuando aporta valor
(>500 ficheros, lenguaje con buen tree-sitter, scope no N4b).

```bash
# 1. Instalar
npm i -g @colbymchenry/codegraph
# o: curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh

# 2. Indexar
cd <proyecto>
codegraph init -i           # crea .codegraph/codegraph.db
codegraph status

# 3. Habilitar MCP en opencode.json (enabled:true)
```

Por defecto el repo Savia trae **`enabled: false`** — Rule #19.

## Herramientas MCP

| Tool | Uso desde Savia |
|---|---|
| `codegraph_search` | query #1 `symbol-search` de ast-comprehension |
| `codegraph_node` | query #2 `impl` |
| `codegraph_callers` | query #3 `callers` (resuelto, no grep) |
| `codegraph_callees` | inverso de callers |
| `codegraph_impact` | análisis pre-edit (sin equivalente nativo) |
| `codegraph_context` | construye contexto — SOLO desde sub-agentes Explore |
| `codegraph_explore` | source de varios símbolos — SOLO desde sub-agentes Explore |
| `codegraph_files` | estructura indexada |
| `codegraph_status` | health del índice |

**Regla operativa** (importada del upstream): `codegraph_context` y
`codegraph_explore` devuelven mucha source y **no** se llaman desde la
sesión principal — se delegan a sub-agentes Explore.

## Uso desde `agent-code-map`

`/codemap:generate` y `/codemap:refresh` invocan `codegraph index --quiet`
y `codegraph status --json`. El generador `.acm` consulta `codegraph_files`
y `codegraph_search` para construir secciones por capa. El hash sha256
del `.acm` incluye versión del índice.

**Fallback**: si CodeGraph no responde, `agent-code-map` cae a grep +
tree-sitter ad-hoc. La integración nunca bloquea.

## Uso desde `ast-comprehension`

Las 6 queries tienen ahora dos backends:

| Query | Backend MCP | Backend grep (fallback) |
|---|---|---|
| `symbol-search` | `codegraph_search` | `grep -rn` |
| `impl` | `codegraph_node --source` | `awk` |
| `callers` | `codegraph_callers` | `grep` + filtro |
| `callees` | `codegraph_callees` | n/a (era debilidad) |
| `tests` | `codegraph_search --kind test` | grep en `__tests__/` |
| `impact` | `codegraph_impact` (nuevo) | n/a |

El agente elige backend en runtime según `codegraph_status`.

## Confidencialidad

`.codegraph/codegraph.db` **debe estar en `.gitignore`** del proyecto —
contiene copia parseable del código y en N4 no puede viajar al repo
público. Ver `docs/rules/domain/codegraph-confidentiality.md`.

`agent-code-map` verifica esto antes de invocar `codegraph index` en
scope N4/N4b. Si `.gitignore` no excluye `.codegraph/`, aborta.

## CLI directo (sin agente)

```bash
codegraph query <symbol> --json
codegraph callers <symbol> --json
codegraph impact <symbol> --depth 2 --json
codegraph affected --stdin   # tests afectados por git diff — útil en CI
```

## Cuándo NO usar

- Proyectos < 500 ficheros (overhead > beneficio).
- Confidencialidad N4b/PM-Only — el índice mezcla todo lo no-gitignored.
- Lenguajes sin tree-sitter relevante (COBOL, JCL, mainframe).
- Sesiones one-shot donde `codegraph init` no se amortiza.

## Referencias

- Repo: <https://github.com/colbymchenry/codegraph> (MIT, activo)
- Skills relacionadas: `agent-code-map`, `ast-comprehension`,
  `human-code-map` (ortogonal), `codebase-map` (ortogonal).
- Regla: `docs/rules/domain/codegraph-confidentiality.md`.
