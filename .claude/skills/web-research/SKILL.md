---
layer: peripheral
name: web-research
description: "Usar cuando se necesita buscar en la web para resolver gaps de contexto (docs, versiones, CVEs)."
allowed-tools: [Read, Bash, WebSearch, WebFetch, Write]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.disable-model-invocation: false
  savia.maturity: beta
  savia.priority: high
  savia.summary: "Busca en la web para resolver gaps de contexto: documentacion, versiones, CVEs, best practices. Auto-inicia SearxNG Docker si disponible, fallback a WebSearch. Cache local con TTL."
  savia.tags: "search, web, cache, searxng, citations, gap-detection"
  savia.user-invocable: True
---

# Skill: Web Research

> 3-layer search: cache → SearxNG (Docker auto-start) → Claude WebSearch.
> Inspired by [FAIR-Perplexica](https://github.com/UB-Mannheim/FAIR-Perplexica).

## When to use

- User asks about external technology (versions, APIs, configs)
- Gap detected: CVE, deprecation, compatibility question
- Tech-research-agent needs web sources for investigation
- Developer encounters error from external library

## What it produces

1. **Search results** — reranked by relevance, cached locally
2. **Inline citations** — `[web:N]` with source URLs in footer
3. **Follow-up suggestions** — contextual next commands
4. **Gap detection** — automatic suggestion when external gap detected

## Prerequisites

```
1. Python 3.x available                    → always true in pm-workspace
2. Docker (optional) for SearxNG           → graceful fallback if missing
3. Internet connection (optional)           → cache-only mode if offline
```

## Flow

```
User query or gap detected
  → Sanitize (strip PII, projects, emails, IPs)
  → Check cache (TTL by category)
  → If miss: try SearxNG (auto-start Docker)
  → If SearxNG unavailable: use Claude WebSearch
  → Rerank results (keyword + domain authority)
  → Cache results
  → Format with [web:N] citations
  → Show follow-up suggestions
```

## Key modules

| Module | Lines | Purpose |
|--------|-------|---------|
| `cache.py` | 137 | LRU cache, TTL, stats |
| `sanitizer.py` | 107 | PII removal, classification |
| `rerank.py` | 86 | Heuristic scoring |
| `formatter.py` | 88 | Citation formatting |
| `gap_detector.py` | 110 | External vs internal detection |
| `searxng.py` | 149 | Docker auto-start, cross-platform |
| `search.py` | 88 | 3-layer orchestrator |
| `suggestions.py` | 81 | Post-command follow-ups |

## Scrapling enrichment (SE-061)

Para URLs resultantes de SearxNG/WebSearch que requieren extracción de contenido (más allá de snippet), invocar el wrapper adaptativo `scripts/scrapling-fetch.sh`:

```bash
bash scripts/scrapling-fetch.sh "${URL}" --json --timeout 25
```

- Backend `scrapling` si está instalado: bypass Cloudflare/DataDome nativo
- Fallback transparente a `curl` con user-agent `SaviaResearch/1.0`
- Exit 0/1/2, JSON con `status|title|url_final|text|backend`

Usar cuando WebFetch tool devuelve 403/429/503 o cuando el snippet no es suficiente. No usar para fetch masivo sin respetar robots.txt — ver `docs/rules/domain/research-stack.md`.

## References

- Spec: `docs/propuestas/SPEC-003-web-research-system.md`
- Scrapling backend: `docs/propuestas/SE-061-scrapling-research-backend.md`
- Config: `docs/rules/domain/web-research-config.md`
- Stack chain: `docs/rules/domain/research-stack.md`
- Docs ES: `docs/web-research.md`
- Docs EN: `docs/web-research.en.md`
- Tests: `tests/test-web-research.bats`
