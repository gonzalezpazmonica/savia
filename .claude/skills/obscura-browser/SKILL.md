---
layer: peripheral
name: obscura-browser
description: "Navegador headless nativo de Savia para fetch/scrape (Rust, sin Chromium, 41MB RAM, sin telemetria). Usar cuando se navega a, se extrae contenido de, se scrapea, se renderiza JS, o se necesita CDP/MCP headless. NO para e2e (usar Playwright)."
metadata:
  savia.category: tool
  savia.maturity: stable
  savia.context: project
  savia.maturity: experimental
  savia.priority: high
  savia.tags: "browser, headless, scraping, markdown, cdp, mcp, obscura, rust"
  savia.loop_level: "L0"
  savia.trigger_keywords: "navega a, extrae contenido de, scrapea, renderiza esta pagina, headless browser, obscura"
---

# Skill: obscura-browser

Motor headless nativo de Savia: Rust + V8, motor de render propio, CDP drop-in
para Playwright/Puppeteer, MCP nativo, anti-detect opcional, guard SSRF,
cero telemetria. Adoptado 2026-09-04 tras benchmark vs Playwright (3x menos
RAM, arranque frio 76ms). Depreca a lightpanda-browser.

## Authoritative Paths

> **Lee estos paths antes de actuar. NUNCA asumas firmas, NUNCA inventes paths.**

| Para | Lee este path |
|---|---|
| Binario instalado | `~/.local/bin/obscura` (v0.2.1) + `~/.local/bin/obscura-worker` |
| Fork interno (pin 8a3d048) | `~/tools/obscura` — remotes: `upstream` (h4ckf0r0day/obscura), `fork` |
| Referencia CLI completa | `~/tools/obscura/README.md` (secciones CLI Reference, CDP API, MCP) |
| Variables de entorno | `~/tools/obscura/docs/Environment-variables.md` |
| Benchmark de adopcion | `output/research/obscura-vs-playwright-20260904.md` |
| Skill deprecada (referencia) | `../lightpanda-browser/SKILL.md` |

**Reglas duras**:
- Si `~/.local/bin/obscura` no existe, ABORTA y reporta — no lo descargues sin confirmar.
- Fork interno NUNCA recibe push a upstream. Sync solo: `git -C ~/tools/obscura fetch upstream`.
- Apache-2.0: conserva LICENSE/NOTICE del fork. Bundling permitido (a diferencia de Lightpanda/AGPL).

## Cuándo usar

- Fetch con JS de paginas/SPAs y dump markdown/text/links (uso principal: research y digests)
- Scraping paralelo de N URLs (`obscura scrape`)
- Servidor CDP para automation ligera (Playwright `connectOverCDP`)
- Servidor MCP para agentes (stdio o HTTP)
- Anti-detect/stealth para sitios con bloqueo headless

## Cuándo NO usar

- E2E testing de web apps → Playwright + Chromium real (fidelidad de motor)
- Visual QA / screenshots de fidelidad pixel → Playwright
- HTML estatico simple → `curl` (mas ligero)
- PDF de fidelidad print → Playwright (Obscura exporta PDF pero motor propio)

## Decision Checklist

1. ¿Es un test e2e o validacion visual? → SI: Playwright. NO: continuar.
2. ¿Pagina estatica sin JS? → SI: curl. NO: continuar.
3. ¿Datos N3+ en la sesion? → verifica que solo fluyen al sitio objetivo (motor local, cero telemetria).

### Abort Conditions

- Binario ausente o corrupto → reportar, no reinstalar autonomamente
- Sitio exige Chromium real (DRM, WebGL pesado, media) → delegar a Playwright

## Workflow

```
URL(s) + objetivo (markdown/text/eval)
    ↓
obscura fetch / scrape / serve (según volumen)
    ↓
output estructurado → digest / research / informe
```

### Detalle de cada paso

1. **Un URL**: `obscura fetch "$URL" --dump markdown --quiet`
   - Titulo rapido: `--eval "document.title"`
   - Screenshot: `--screenshot out.png`
   - Dev server local: `--allow-private-network`
   - Proxy: `--proxy socks5://...` (global, antes del subcomando)
2. **Volumen**: `obscura scrape url1 url2 ... --concurrency 10 --format json --quiet`
3. **Sesion interactiva**: `obscura serve --port 9222 [--stealth] [--obey-robots]`
   + Playwright: `chromium.connectOverCDP({ endpointURL: 'ws://127.0.0.1:9222' })`

## Outputs esperados

- stdout: markdown/text/html/json segun `--dump`/`--format`
- Ficheros: screenshots/PDFs en `output/` con naming YYYYMMDD

## Memory hooks

- Fallos de sitio (Obscura no renderiza X) → `bash scripts/memory-store.sh save --type pattern --title "obscura-fallo:<dominio>" --content "<detalle>" --source skill:obscura-browser`

## Related

- Skill: `../lightpanda-browser/SKILL.md` (DEPRECATED — sustituida por esta)
- Skill: `../tier3-probes/SKILL.md`
- Research: `output/research/obscura-vs-playwright-20260904.md`
- Upstream: https://github.com/h4ckf0r0day/obscura (Apache-2.0)
