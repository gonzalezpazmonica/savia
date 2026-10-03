# lightpanda-browser — Domain knowledge

## Origin

Lightpanda (33K stars GitHub) es un navegador headless escrito desde cero en Zig,
disenado especificamente para agentes de IA y automatizacion. No es un fork de
Chromium ni un parche de WebKit.

## Por que existe esta skill

Savia ya tiene `web-research` y `scrapling-fetch`. Pero ambos usan HTTP simple
(curl/python requests) que no ejecuta JavaScript. Para SPAs, infinite scroll,
o sitios que requieren renderizado JS, esas herramientas fallan.

Lightpanda resuelve esto con `--dump markdown` que ejecuta JS completo y devuelve
markdown. Ademas tiene MCP server y agent mode que permiten a los agentes de
Savia interactuar con paginas web como un humano.

## Arquitectura de integracion

```
Savia agent → skill lightpanda-browser
  → ¿Lightpanda instalado?
    SI → lightpanda fetch --dump markdown $URL
    NO → fallback: scripts/scrapling-fetch.sh --json (scrapling o curl)
  → output markdown → digest pipeline → KG extraction
```

## Decisiones de diseno

- **Nunca bundled**: AGPL-3.0 es incompatible con MIT. Lightpanda es herramienta
  externa opcional como Docker o git.
- **Patron availability check**: `command -v lightpanda` antes de usarlo. Si no
  esta, fallback a `scrapling-fetch.sh`, que informa del backend usado en el
  campo `backend` y falla con exit != 0 ante 4xx/5xx o destinos bloqueados.
- **MCP integration**: si Lightpanda MCP server esta corriendo, los agentes pueden
  usar herramientas de navegacion directamente via MCP.

## Relacion con otras skills

- `web-research`: Lightpanda es el backend preferente para JS-heavy sites
- `scrapling-fetch`: Lightpanda lo reemplaza cuando esta disponible
- `meeting-transcript-extract`: podria usar Lightpanda para extraer transcripciones
  de Teams Web
- `dynamic-web-tester`: Lightpanda como backend CDP para tests web
