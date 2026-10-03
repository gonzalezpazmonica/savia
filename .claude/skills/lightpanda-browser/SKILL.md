---
layer: peripheral
name: lightpanda-browser
description: "DEPRECATED 2026-09-04 — sustituida por obscura-browser. No usar en casos nuevos. Se conserva como referencia histórica: Obscura gana en licencia (Apache-2.0 vs AGPL), telemetría (cero vs ON por defecto) y recursos (41MB RAM)."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: tool
  savia.maturity: beta
  savia.context: project
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
LIGHTPANDA_DISABLE_TELEMETRY=true lightpanda fetch --json --dump markdown \
  --obey-robots --block-private-networks \
  --wait-until networkidle --http-timeout 20000 \
  "https://example.com"
```

Valores validos de `--wait-until` (verificado con `lightpanda help fetch`,
1.0.0-nightly): `load`, `domcontentloaded`, `networkalmostidle`, `networkidle`,
`done`. `networkidle0` (estilo Puppeteer) NO existe: Lightpanda aborta con
`InvalidArgument`.

**Exit code no fiable**: `lightpanda fetch` devuelve 0 con un 503 (vuelca el
cuerpo de error) y tambien cuando `--block-private-networks` bloquea la
navegacion (vuelca `# Navigation failed`). Con `--json` el objeto trae
`http_status`: es lo que hay que comprobar, no el exit code.

### 2. CDP server + Puppeteer/Playwright

```bash
lightpanda serve --host 127.0.0.1 --port 9222
# Luego conectar con puppeteer.connect({ browserWSEndpoint: "ws://127.0.0.1:9222" })
```

### 3. MCP server (integracion con SaviaVaults)

```bash
lightpanda mcp --port 9223
# Sin --port usa stdio. Con --port, sesiones aisladas por Mcp-Session-Id
```

Herramientas expuestas (tools/list, 1.0.0-nightly): `goto`, `markdown`,
`html`, `links`, `extract`, `evaluate`, `click`, `fill`, `scroll`, `hover`,
`press`, `waitForSelector`, `interactiveElements`, `detectForms`,
`session_new`/`session_list`/`session_close`, entre otras. No hay
`screenshot` (no tiene motor de renderizado).

### 4. Agent mode (navegacion por lenguaje natural)

```bash
lightpanda agent --task "top story on news.ycombinator.com"
lightpanda agent --no-llm  # REPL basico sin LLM
```

## Patron de integracion con Savia

```bash
if command -v lightpanda &>/dev/null; then
  out=$(LIGHTPANDA_DISABLE_TELEMETRY=true lightpanda fetch --json \
    --dump markdown --obey-robots --block-private-networks "$URL")
  # exito solo si http_status es 2xx (el exit code de lightpanda no lo dice)
else
  bash scripts/scrapling-fetch.sh "$URL" --json --timeout 25
fi
```

Fallback `scripts/scrapling-fetch.sh` (Scrapling si esta instalado, si no
curl; el campo `backend` dice cual se uso):

| Exit | Significado |
|---|---|
| 0 | Respuesta 2xx |
| 1 | Error de red, timeout, 4xx/5xx, > `--max-bytes`, > 5 redirecciones, sin backend |
| 2 | Uso incorrecto (flag sin valor, `--timeout 0`, URL no http/https) |
| 3 | Destino bloqueado por la politica anti-SSRF |

El JSON se emite tambien en error, con `error` relleno y `text_truncated`.

## Seguridad de destinos (SSRF)

- `scrapling-fetch.sh` solo admite http/https, valida cada salto de
  redireccion y fija la IP resuelta. Link-local (169.254.169.254, metadatos
  cloud) y reservadas: bloqueadas siempre. Loopback y redes privadas:
  bloqueadas salvo `--allow-private`.
- Con backend Scrapling la libreria sigue las redirecciones: se valida la
  URL inicial y la final (el contenido interno se descarta), pero la
  peticion intermedia ya se habra hecho.
- Lightpanda NO bloquea redes internas por defecto: pasar siempre
  `--block-private-networks`.
- Limites: `--timeout` total (>= 1 s) y `--max-bytes` (5 MiB por defecto);
  en Lightpanda, `--http-timeout` y `--http-max-response-size`.

## Anti-patrones

- NO usar Lightpanda para HTML estatico (curl basta)
- NO esperar renderizado grafico (no tiene motor de renderizado)
- NO bundear el binario (AGPL-3.0 incompatible con MIT)
- NO usar en modo `agent` para tareas simples (el LLM añade latencia)
- NO olvidar `--obey-robots` ni `--block-private-networks` en produccion
- NO fiarse del exit code de `lightpanda fetch`: usar `--json` y `http_status`

## Limitaciones conocidas

- Beta: algunos sitios pueden fallar
- Sin CORS implementado aun (issue #2015)
- Sin renderizado grafico (solo headless)
- Sin binario nativo Windows (usar WSL2)
- Telemetry activado por defecto (desactivar con LIGHTPANDA_DISABLE_TELEMETRY=true)
- Calibracion SE-376 (2026-10-03): tests en `tests/test-lightpanda-browser.bats`
  contra servidor HTTP local; sin red externa.
