---
layer: peripheral
name: lightpanda-browser
description: "DEPRECATED 2026-09-04 — sustituida por obscura-browser. No usar en casos nuevos. Se conserva como referencia histórica: Obscura gana en licencia (Apache-2.0 vs AGPL), telemetría (cero vs ON por defecto) y recursos (41MB RAM)."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: tool
  savia.maturity: stable
  savia.context: project
  savia.maturity: deprecated
  savia.priority: low
  savia.tags: "browser, headless, web, scraping, markdown, mcp, automation, lightpanda, deprecated"
---

# lightpanda-browser

> **DEPRECATED 2026-09-04** — Sustituida por `obscura-browser`.
> Motivo (benchmark `output/research/obscura-vs-playwright-20260904.md`):
> Obscura ofrece Apache-2.0 bundlable vs AGPL, cero telemetría (Lightpanda la
> tiene ON por defecto) y 3x menos RAM. No iniciar casos nuevos con Lightpanda.
> Contenido conservado como referencia.

Navegador headless optimizado para IA. 9x mas rapido y 16x menos RAM que Chrome.
Escrito en Zig. AGPL-3.0 — solo como herramienta externa, nunca bundled.

## Cuando usar Lightpanda vs alternativas

| Escenario | Usar | Por que |
|---|---|---|
| SPA / React / Vue / Angular | Lightpanda | Ejecuta JS completo |
| Infinite scroll / lazy load | Lightpanda | `--wait-selector` + `--wait-ms` |
| HTML estatico simple | curl + regex | Mas ligero, sin dep externa |
| PDF / captura de pantalla | Playwright | Lightpanda no renderiza graficos |
| Formularios / login | Lightpanda agent mode | Navegacion interactiva |

## Instalacion (externo, no bundled)

```bash
# Linux x86_64
curl -L -o ~/.local/bin/lightpanda \
  https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux
chmod +x ~/.local/bin/lightpanda

# Docker
docker run -d --name lightpanda -p 127.0.0.1:9222:9222 lightpanda/browser:nightly
```

## Operaciones principales

### 1. Dump a markdown (uso mas frecuente)

```bash
lightpanda fetch --dump markdown --obey-robots \
  --wait-until networkidle0 \
  "https://example.com"
```

### 2. CDP server + Puppeteer/Playwright

```bash
lightpanda serve --host 127.0.0.1 --port 9222
# Luego conectar con puppeteer.connect({ browserWSEndpoint: "ws://127.0.0.1:9222" })
```

### 3. MCP server (integracion con SaviaVaults)

```bash
lightpanda mcp --port 9223
# Sesiones aisladas por Mcp-Session-Id header
# Herramientas: navigate, click, type, extract, screenshot, execute
```

### 4. Agent mode (navegacion por lenguaje natural)

```bash
lightpanda agent --task "top story on news.ycombinator.com"
lightpanda agent --no-llm  # REPL basico sin LLM
```

## Patron de integracion con Savia

```bash
if command -v lightpanda &>/dev/null; then
  lightpanda fetch --dump markdown --obey-robots "$URL"
else
  python3 scripts/scrapling-fetch.py "$URL"
fi
```

## Anti-patrones

- NO usar Lightpanda para HTML estatico (curl basta)
- NO esperar renderizado grafico (no tiene motor de renderizado)
- NO bundear el binario (AGPL-3.0 incompatible con MIT)
- NO usar en modo `agent` para tareas simples (el LLM añade latencia)
- NO olvidar `--obey-robots` en produccion

## Limitaciones conocidas

- Beta: algunos sitios pueden fallar
- Sin CORS implementado aun (issue #2015)
- Sin renderizado grafico (solo headless)
- Sin binario nativo Windows (usar WSL2)
- Telemetry activado por defecto (desactivar con LIGHTPANDA_DISABLE_TELEMETRY=true)
