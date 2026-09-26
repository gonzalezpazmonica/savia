---
name: web-research
description: Search the web to resolve context gaps — documentation, versions, CVEs, best practices. Auto-starts SearxNG Docker if available, falls back to WebSearch.
argument-hint: "<query> [--cache-only] [--cache-stats] [--cache-clear] [--searxng-status]"
allowed-tools: [Read, Bash, WebSearch, WebFetch, Write]
model_tier: mid
context_cost: medium
tier: core
---

# /web-research — Búsqueda web para resolver gaps de contexto

> Regla: `@docs/rules/domain/web-research-config.md`

## Subcomandos

Si `$ARGUMENTS` es `--cache-stats` → `python3 -m scripts.web-research cache-stats`
Si `$ARGUMENTS` es `--cache-clear` → `python3 -m scripts.web-research cache-clear`
Si `$ARGUMENTS` es `--searxng-status` → ejecutar en Python: `from scripts... import searxng; print(searxng.status())`

## Flujo principal (3 capas con auto-start)

### 1. Orquestar búsqueda

```bash
python3 -c "
import importlib, json
search = importlib.import_module('scripts.web-research.search')
result = search.search('$ARGUMENTS')
print(json.dumps(result, default=str))
"
```

Este script automáticamente:
1. **Sanitiza** el query (elimina PII, proyectos, emails, IPs)
2. **Busca en cache** local primero
3. **Intenta SearxNG** — si Docker disponible, auto-levanta el contenedor `savia-searxng`
4. Si SearxNG no disponible → devuelve `source: needs-websearch`

### 2. Si source = "needs-websearch"

SearxNG no disponible (sin Docker o timeout). Usar **WebSearch** nativo de Claude Code con el query sanitizado. Recopilar resultados y cachearlos.

### 3. Si source = "searxng" o "cache"

Resultados ya disponibles. Formatear y presentar.

### 4. Presentar resultados

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 /web-research
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Query: "{sanitized}" · Categoría: {cat} · Fuente: {source}

1. **{título}** — {url}
   {snippet}

📚 [web:1] {url} · [web:2] {url}

💡 Siguientes pasos: (suggestions.format_suggestions)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ /compact
```

### 5. Restricciones

```
NUNCA → Buscar datos del cliente en la web
NUNCA → Incluir nombres de proyecto/equipo en la query
SIEMPRE → Sanitizar query antes de buscar
SIEMPRE → Citar fuentes con [web:N]
SIEMPRE → Cachear resultados para uso offline
SIEMPRE → Respetar context-budget (max 500 tokens)
```
