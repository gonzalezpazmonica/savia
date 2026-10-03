---
context_tier: L2
token_budget: 863
---

# Research Stack — Backend Chain

> Cadena de backends para research agents: orden de preferencia, fallbacks, y consideraciones de legalidad.

## Cadena de resolución

Para URLs que requieren extracción de contenido (no solo snippet/title de search):

```
1. Cache local (TTL por categoría)
     ↓ (miss)
2. WebFetch tool (Claude Code / OpenCode)
     ↓ (403/429/503/empty)
3. scripts/scrapling-fetch.sh --json
     ↓ (scrapling no instalado)
4. curl con user-agent SaviaResearch/1.0 (fallback automático en el wrapper)
```

Cada nivel tiene exit codes claros, JSON output, y telemetría local. La skill consumidora decide continuar o abortar según verdict.

## Cuándo usar cada backend

| Backend | Caso | Cost | Anti-bot |
|---|---|---|---|
| Cache | URL ya fetcheada en TTL | 0 | N/A |
| WebFetch | URL pública sin gates | token/call | Básico |
| `scrapling-fetch.sh` + Scrapling | Cloudflare/DataDome/Akamai gated | CPU local | Alto |
| `scrapling-fetch.sh` + curl | Sites abiertos, fallback | Red | Ninguno |

## Reglas de uso

1. **Robots.txt respect**: Antes de scrape masivo (≥10 URLs del mismo dominio), verificar robots.txt del dominio. Scrapling lo soporta pero no lo activa por defecto en el wrapper.
2. **Rate limiting**: Max 1 request/segundo al mismo dominio salvo que el site publique `Crawl-Delay: 0`. El wrapper no lo impone — responsabilidad del caller.
3. **ToS awareness**: scraping ≠ API legítima. Cada dominio tiene política propia. Para research legítima/pública está aceptado; para extracción comercial masiva no.
4. **GDPR**: No extraer datos personales identificables (nombres, emails, teléfonos) sin base legal. Si el site protege con login, no bypassearlo.
5. **Destinos internos (SSRF)**: `scrapling-fetch.sh` sale con exit 3 ante loopback/redes privadas (salvo `--allow-private`) y SIEMPRE ante link-local/metadatos cloud (169.254.169.254), también tras una redirección. 4xx/5xx salen con exit 1, nunca como éxito. Límites: `--timeout` total ≥ 1 s y `--max-bytes` (5 MiB por defecto).
6. **Attribution**: Los informes generados por research agents DEBEN citar la URL origen en `Fuentes`.

## No hacer

- No usar Scrapling para login/autenticación automatizada (fuera de scope, riesgo legal)
- No bypass de paywalls ni contenido bajo suscripción
- No scrapear sites donde un captcha/login impide acceso no autenticado
- No almacenar HTML raw en repo público — solo texto extraído y citado

## Observabilidad

- Cada fetch registra: `url`, `backend_used`, `status`, `timestamp`, `latency_ms` en `output/research-log.tsv` (local, gitignored)
- Scrapling failures automatic trigger fallback curl, sin error visible para el caller

## MCP opt-in (SE-061 Slice 4)

Para activar Scrapling como MCP server nativo (opt-in, NO default):

1. Verificar entorno: `bash scripts/scrapling-probe.sh --check-browser`
2. Instalar: `pip install 'scrapling[ai]'`
3. Auditar: `bash scripts/mcp-security-audit.sh` (MCP-01..MCP-11 deben pasar)
4. Copiar entry `template.scrapling` desde `.claude/mcp-templates/scrapling.json` a `.claude/mcp.json → mcpServers`
5. NO añadir `autoApprove` (regla MCP-02)
6. Reiniciar Claude Code / OpenCode

El MCP expone capacidades de fetch adaptativo al LLM directamente. Uso opt-in porque la activación requiere Chromium (~500MB) y dependencias pesadas. Ver `.claude/mcp-templates/scrapling.json` para la config template.

## Referencias

- Probe: `scripts/scrapling-probe.sh` (SE-061 Slice 1)
- Wrapper: `scripts/scrapling-fetch.sh` (SE-061 Slice 2)
- Spec: `docs/propuestas/SE-061-scrapling-research-backend.md`
- Skill tech-research: `.opencode/skills/tech-research-agent/SKILL.md`
- Skill web-research: `.opencode/skills/web-research/SKILL.md`
- Config: `docs/rules/domain/web-research-config.md`
