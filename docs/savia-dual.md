# Savia Dual — Inference Sovereignty

> Savia nunca se queda atascada. Si la nube de Anthropic falla, está lenta,
> tira 429 por cuota, o pierdes conexión, Savia sigue funcionando en local
> sobre gemma4. Cuando la nube vuelve, Savia vuelve a usarla automáticamente.

## La idea

pm-workspace depende de Claude Code / OpenCode, que a su vez dependen de la API de
Anthropic. Esa dependencia es un punto único de fallo: un outage, una
cuota agotada, un corte de red y pierdes la herramienta.

Savia Dual elimina ese punto único añadiendo un **proxy transparente** que
enruta las peticiones de Claude Code / OpenCode al primer upstream que responda bien:

1. Primero intenta **Anthropic** (calidad máxima, latencia baja)
2. Si falla o tarda demasiado, cae a **Ollama local** con gemma4
3. Registra cada decisión en un log auditable

La nube se usa por calidad. El local se usa por continuidad. No renuncias
a ninguna.

## Arquitectura

```
Claude Code / OpenCode ──► savia-dual-proxy (127.0.0.1:8787)
                   │
                   ├─► api.anthropic.com      (primario)
                   │
                   └─► 127.0.0.1:11434        (fallback, Ollama gemma4)
```

Claude Code / OpenCode apunta al proxy vía `ANTHROPIC_BASE_URL=http://127.0.0.1:8787`.
El proxy habla protocolo Anthropic `/v1/messages` a ambos lados — Ollama
≥ 0.20.0 incluye ese endpoint nativo, sin necesidad de traductor.

## Cuándo cae a local

| Evento | Se enruta a Ollama si... |
|---|---|
| Error de red | No hay DNS, conexión rechazada, cable caído |
| HTTP 5xx | El servidor de Anthropic devuelve error |
| HTTP 429 | Cuota de tokens agotada |
| Timeout | N segundos sin cabeceras ni bytes de Anthropic (default 30) |
| Circuit breaker | Tras 3 fallos seguidos, 60 s sólo local |

Sólo `POST /v1/messages` cae a local. Un 4xx (clave inválida, petición
mal formada) se devuelve tal cual. A Ollama nunca viajan `x-api-key`,
`authorization` ni cookies. Las respuestas se reenvían en streaming; si
un stream se corta a medias no se repite en local: el cliente recibe un
evento SSE `error` y el log registra `"stream_interrupted": true`.

## Instalación

**Linux / macOS**:

```bash
bash scripts/setup-savia-dual.sh
```

**Windows (PowerShell)**:

```powershell
pwsh .\scripts\setup-savia-dual.ps1
```

El installer:
1. Instala o actualiza Ollama (vía installer oficial en Linux/macOS o
   `winget` en Windows)
2. Arranca el daemon de Ollama si no está corriendo
3. Detecta RAM y VRAM de la máquina
4. Elige la variante de gemma4 más adecuada:
   - `gemma4:e2b` — máquinas con menos de 12 GB de RAM
   - `gemma4:e4b` — 12–23 GB de RAM o GPU pequeña
   - `gemma4:26b` — 24+ GB de RAM y 12+ GB de VRAM
5. Descarga el modelo
6. Escribe `~/.savia/dual/config.json` y `~/.savia/dual/env`
7. Con doble opt-in, instala el servicio y el bloque de shell:

   ```bash
   SAVIA_DUAL_FAILOVER_ENABLED=true bash scripts/setup-savia-dual.sh --confirm-autonomous
   ```

   Sin él, no toca nada fuera de `~/.savia/dual` y explica cómo arrancar
   el proxy a mano. Salida: 0 ok, 1 paso fallido, 2 argumento inválido.

Los datos de hardware detectados permanecen en memoria durante el
installer. Nunca se escriben a ficheros versionados ni se transmiten
fuera de la máquina.

## Uso diario

**Terminal 1** — proxy en primer plano:

```bash
python3 scripts/savia-dual-proxy.py
```

**Terminal 2** — sesión de Savia:

```bash
source ~/.savia/dual/env
claude
```

A partir de ese momento Claude Code habla con el proxy, que decide a qué
upstream enviar cada petición. No notas la diferencia cuando la nube
responde bien. Cuando hay fallback, puedes verlo en:

```bash
tail -f ~/.savia/dual/events.jsonl
```

## Formato del log

Una línea JSON por petición enrutada:

```json
{"ts":"2026-04-11T17:30:12Z","route":"anthropic","status":200,"latency_ms":420}
{"ts":"2026-04-11T17:31:05Z","route":"ollama","status":200,"fallback_reason":"http_429","local_model":"gemma4:e4b","latency_ms":8300}
```

No contiene prompts ni respuestas — sólo metadatos de enrutamiento.

## Configuración avanzada

`~/.savia/dual/config.json` admite los siguientes campos:

| Campo | Default | Descripción |
|---|---|---|
| `listen_host` | `127.0.0.1` | Solo loopback; otro valor → exit 2 |
| `listen_port` | 8787 | Puerto local del proxy |
| `anthropic_upstream` | `https://api.anthropic.com` | Upstream primario |
| `ollama_upstream` | `http://127.0.0.1:11434` | Upstream de fallback |
| `fallback_triggers.timeout_seconds` | 30 | Timeout para Anthropic |
| `circuit_breaker.consecutive_failures` | 3 | Umbral del circuit breaker |
| `circuit_breaker.cooldown_seconds` | 60 | Duración del modo sólo-local |
| `local_model` | detectado por hardware | Modelo Ollama de fallback |

## Honestidad sobre calidad

Savia local **no equivale** a Claude Opus/Sonnet. gemma4, incluso en la
variante 26B MoE, pierde capacidad notable en:

- Razonamiento profundo multi-paso (specs SDD, arquitectura)
- Code review matizado y consciente de contexto
- Orquestación de sub-agentes
- Ventanas de contexto muy grandes

Para operaciones ofimáticas de Savia (consultar sprint, leer memoria,
ejecutar comandos simples) el modo fallback funciona bien. Para trabajo
de ingeniería profundo, reconectar a la nube antes de continuar.

Savia Dual no oculta estas diferencias: cada fallback se registra con
motivo explícito y el usuario decide si sigue operando degradado o
espera a que la nube vuelva.

## Comparación con otros modos

| | Emergency Mode | Savia Dual |
|---|---|---|
| Activación | Manual (`source env`) | Automática |
| Fallback | Reemplaza la API completa | Sólo cuando falla la primaria |
| Cloud disponible | Tienes que desactivar manualmente | Se usa si funciona |
| Log | No | Sí, auditable |

Emergency Mode sigue existiendo como solución manual cuando quieres
forzar local explícitamente. Savia Dual es la solución automática para
el caso habitual.

## Referencias

- Regla: `docs/rules/domain/savia-dual.md`
- Skill: `.opencode/skills/savia-dual/`
- Comando: `/savia-dual {subcomando}`
- Proxy: `scripts/savia-dual-proxy.py`
- Setup Linux/macOS: `scripts/setup-savia-dual.sh`
- Setup Windows: `scripts/setup-savia-dual.ps1`
