---
layer: peripheral
name: ast-comprehension
description: Usar cuando se explora código desconocido y se necesita comprensión estructural sin leer ficheros enteros.
allowed-tools: [Bash, Read, Glob, Grep, Write]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: code-reviewer
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Query-oriented AST exploration para 16 lenguajes. Empieza en un entrypoint, pide solo lo que necesitas. Reduce tokens 10-100x vs leer ficheros completos. 6 queries tipadas: symbol-search, impl, callers, tests, peek, grep-code. Complementa ast-quality-gate (valida output IA) vs comprensión (entiende código ajeno)."
  savia.tags: "ast, comprehension, legacy, rlm, structural-analysis, pre-edit"
---

# AST Comprehension — Query, no leas

Explorar código ajeno pidiendo **solo lo que necesitas**. El patrón RLM (Recursive Language Models — Zhang, Kraska, Khattab, MIT CSAIL 2025) trata el codebase como dato externo que el modelo examina recursivamente con queries tipadas, en vez de cargar ficheros enteros al contexto.

**Regla**: antes de `Read` de un fichero completo, pregúntate si la respuesta cabe en una de las 6 queries tipadas abajo. Si cabe, úsala. Solo cae a `Read` para ficheros pequeños donde genuinamente necesitas la lectura completa.

## Cuándo usar

- **Pre-edición**: antes de editar un fichero existente → pide solo el símbolo afectado + callers
- **Legacy assessment** (`/legacy-assess`): explora desde entrypoints, sigue la cadena
- **Evaluate repo** (`/evaluate-repo`): estructura + símbolos clave
- **Comprehension report** (`/comprehension-report`): documentar arquitectura sin dump completo
- **Debugging cross-file**: "¿quién llama a X con estos parámetros?"

## Diferencia con ast-quality-gate

| Skill | Input | Pregunta | Output |
|-------|-------|----------|--------|
| `ast-quality-gate` | Código generado por IA | ¿Tiene errores? | Score + issues |
| `ast-comprehension` | Código ajeno/legacy | ¿Qué hace y cómo? | Respuesta a query tipada |

## Las 6 queries tipadas (RLM pattern)

Cada query responde una pregunta concreta con un recipe bash que Claude ejecuta directamente. No hay server, no hay daemon — solo instrucción disciplinada sobre grep/sed/tree-sitter. Tokens estimados por operación típica en un proyecto de 10k LoC.

### 1. `symbol-search <name>` — encontrar dónde está definido
Pregunta: *¿Dónde se define `useAuthStore`?*
```bash
grep -rn "^\(export \)\?\(function\|const\|class\|def\) <name>" src/ --include="*.{ts,tsx,js,vue,py,go,rs}"
```
Tokens: ~20. Evita listar cada mención del nombre.

### 2. `impl <name> <file>` — leer la implementación exacta
Pregunta: *¿Qué hace `scanDirectory` en `walker.ts`?*
```bash
# Con tree-sitter (preferido, si instalado):
tree-sitter parse <file> | jq '.. | select(.type=="function_declaration" and .name=="<name>")'
# Sin tree-sitter (fallback): encontrar línea de definición y extraer hasta el cierre de llaves
awk '/^(export )?(function|const|class) <name>/,/^}/' <file>
```
Tokens: ~50-200 según tamaño de la función. Siempre menor que leer el fichero (500-3000 LoC típico).

### 3. `callers <name>` — quién usa este símbolo
Pregunta: *¿Qué componentes llaman a `useAuthStore`?*
```bash
grep -rn "<name>(" src/ --include="*.{ts,tsx,vue,js}" | grep -v "function <name>\|const <name>"
```
Tokens: ~3 por caller. En savia-web, `useAuthStore` tiene 56 sites → ~200 tokens vs ~15k si lees los 19 ficheros completos. **75x menos**.

### 4. `tests <name>` — tests que referencian X
Pregunta: *¿Hay cobertura de `useAuthStore`?*
```bash
grep -rn "<name>" "**/__tests__/" "**/*.test.*" "**/*.spec.*" "tests/" 2>/dev/null
```
Tokens: ~5 por test reference. Evita listar tests que solo rozan el término.

### 5. `peek <file> <start> <end>` — rango exacto de líneas
Pregunta: *¿Qué hay en `config.ts` líneas 40-65?*
```bash
sed -n '<start>,<end>p' <file>
```
Tokens: proporcional al rango. Úsalo cuando ya sabes dónde mirar.

### 6. `grep-code <pattern>` — scope-aware (código, no comentarios)
Pregunta: *¿Dónde se usa el flag `STRICT_MODE` en código real, no en comentarios?*
```bash
# Filtro heurístico: excluir líneas que empiezan con // # /* * (comentarios comunes)
grep -rn "<pattern>" src/ | grep -vE '^\s*(//|#|/\*|\*)'
```
Tokens: típicamente 5-10x menos que grep plano en código con mucho comentario.

## Pipeline de exploración (RLM)

1. **Entrypoint** — Empieza en algo concreto: error message, función, endpoint API, log line. Usa `symbol-search` o `grep-code` para localizarlo.
2. **Impl** — Lee la implementación exacta con `impl`. No el fichero — la función.
3. **Trace up** — `callers` para saber quién invoca. Lee esos impls. Repite.
4. **Trace tests** — `tests` para ver cobertura. Los tests suelen contener el uso canónico.
5. **Parar cuando tengas la narrativa**. No cuando hayas leído cada cosa relacionada.


## Backend opt-in: CodeGraph MCP

Las 6 queries tienen ahora dos backends. Si el MCP `codegraph` está activo
en el proyecto (ver `.opencode/skills/codegraph/SKILL.md`), se usa como
backend preferido — devuelve resultados resueltos semánticamente, no matches
de grep que pueden ser comentarios o strings.

| Query | Backend MCP (preferido) | Backend grep (fallback) |
|---|---|---|
| `symbol-search` | `codegraph_search` | `grep -rn` |
| `impl` | `codegraph_node --source` | `awk` |
| `callers` | `codegraph_callers` | `grep` + filtro |
| `callees` | `codegraph_callees` | n/a |
| `tests` | `codegraph_search --kind test` | grep en `__tests__/` |
| `grep-code` | `codegraph_search` filtrado | grep con filtro de comentarios |

Además CodeGraph añade dos queries que grep no puede emular:

- `codegraph_impact <symbol>` — qué se afecta al cambiar X.
- `codegraph affected --stdin` — tests afectados por un diff (CI).

El agente decide el backend en runtime con `codegraph_status`. Sin CodeGraph
activo, todo sigue funcionando con grep.

## Anti-patterns

- ❌ `Read` de un fichero entero para responder "¿qué hace función X?" → usa `impl`.
- ❌ `grep` seguido de `Read` de cada match → usa `callers` (devuelve solo call sites).
- ❌ Dump JSON monolítico para un fichero cuando la pregunta era sobre 1 símbolo → usa `impl`.
- ❌ Leer test file completo para entender qué prueba un símbolo → usa `tests`.

## Extracción monolítica (fallback para legacy assessment)

Si la tarea es *inventariar* un codebase entero (no responder una pregunta), entonces sí corresponde el dump completo. Ver `references/extraction-commands.md` para el pipeline de 3 capas (tree-sitter + semgrep + native tooling) y `references/comprehension-schema.md` para el JSON schema.

## Prerrequisitos

- `tree-sitter-cli` (opcional): `npm install -g tree-sitter-cli` — mejora `impl` y `grep-code`.
- `jq` para normalización JSON de tree-sitter output.
- `awk` / `sed` / `grep` (siempre disponibles) — fallback suficiente para las 6 queries.

## Referencias

- Paper RLM: *Recursive Language Models* — Zhang, Kraska, Khattab (arXiv:2512.24601).
- Research interno: `output/research-coderlm-20260418.md` — evaluación de coderlm y decisión de robar patrón sin adoptar el binario.
- `references/extraction-commands.md` — comandos por lenguaje.
- `references/comprehension-schema.md` — JSON schema del modo monolítico.
