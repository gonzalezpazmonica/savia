---
context_tier: L3
token_budget: 1342
---

# Savia Dual — Inference Sovereignty Layer

> Transparent failover between Anthropic API and a local Ollama instance.
> Savia nunca se queda atascada: si la nube falla, hay un cerebro local.

## Principio

El usuario nunca debe quedarse sin Savia por un fallo externo. Savia Dual
introduce una capa proxy local que enruta las peticiones de Claude Code a
Anthropic cuando funciona correctamente, y cae transparentemente a un
modelo local (gemma4) cuando Anthropic no responde, falla, tira 429 por
cuota, o está lento.

La nube se usa por calidad. El local se usa por continuidad. Sin override
manual, sin cambios de configuración en medio del trabajo.

## Arquitectura

```
Claude Code ──► savia-dual-proxy (127.0.0.1:8787)
                   │
                   ├─► Anthropic API  (primario, calidad máxima)
                   │
                   └─► Ollama local   (fallback, continuidad)
                       /v1/messages nativo (Ollama ≥ 0.20.0)
```

Claude Code se configura con `ANTHROPIC_BASE_URL=http://127.0.0.1:8787`.
El proxy habla protocolo Anthropic a ambos lados. Ollama 0.20+ expone un
endpoint `/v1/messages` nativo, por lo que no hace falta traducción de
formatos.

## Triggers de failover

El proxy enruta a Ollama cuando ocurre CUALQUIERA de los siguientes
eventos en la petición a Anthropic:

| Trigger | Qué detecta | Configurable |
|---|---|---|
| `network_error` | DNS, conexión rechazada, cable caído | sí |
| `http_5xx` | Error del servidor Anthropic | sí |
| `http_429` | Cuota de tokens agotada | sí |
| `timeout_seconds` | N segundos sin cabeceras o sin bytes (timeout de socket, no total) | sí (default 30) |

Además, un **circuit breaker** evita martillear Anthropic cuando está
caído: tras N fallos consecutivos (default 3), el proxy va directo a
Ollama durante `cooldown_seconds` (default 60) antes de volver a probar.

Límites del failover (verificados en `tests/test-savia-dual.bats`):

- Solo `POST /v1/messages` cae a Ollama. Otras rutas reciben la respuesta
  del primario (`"fallback": "not_allowed"` en el log): nada con efectos
  se repite contra otro upstream.
- Un 4xx del primario se devuelve al cliente y no cuenta para el breaker.
- A Ollama solo viajan cabeceras de protocolo (allowlist); nunca
  `x-api-key`, `authorization` ni cookies.
- Respuestas en streaming: tras el primer byte no hay failover; un corte
  cierra con evento SSE `error` y `"stream_interrupted": true` en el log.
- El proxy rechaza escuchar fuera de loopback (exit 2).

## Modelo local por hardware

El installer (`setup-savia-dual.sh` / `.ps1`) detecta RAM y VRAM y
selecciona la variante de gemma4 más adecuada. La lógica es conservadora:

| Recursos detectados | Variante elegida |
|---|---|
| RAM < 12 GB | `gemma4:e2b` (edge, ligero) |
| RAM 12–23 GB | `gemma4:e4b` (edge, equilibrado) |
| RAM ≥ 24 GB y VRAM ≥ 12 GB | `gemma4:26b` (MoE, capacidad máxima) |
| RAM ≥ 24 GB y VRAM < 12 GB | `gemma4:e4b` (más rápido en esa GPU) |

Los valores concretos de hardware del usuario NUNCA se escriben a
ficheros versionados ni se envían a ningún servicio externo. Permanecen
en memoria durante la ejecución del installer.

## Ficheros y ubicaciones

| Ruta | Propósito | Nivel |
|---|---|---|
| `scripts/savia-dual-proxy.py` | Proxy con failover (stdlib, sin deps) | N1 versionado |
| `scripts/setup-savia-dual.sh` | Installer Linux/macOS | N1 versionado |
| `scripts/setup-savia-dual.ps1` | Installer Windows | N1 versionado |
| `~/.savia/dual/config.json` | Config local del usuario | N3 local |
| `~/.savia/dual/env` (`env.ps1`) | Export de `ANTHROPIC_BASE_URL` | N3 local |
| servicio systemd/launchd, bloque en `~/.bashrc`/`~/.zshrc` | Activación persistente; solo con doble opt-in (SPEC-186) | global |
| `~/.savia/dual/events.jsonl` | Log append-only de routing decisions | N3 local |

## Formato de events.jsonl (auditoría)

Una línea JSON por petición enrutada:

```json
{"ts":"2026-04-11T17:30:12Z","route":"anthropic","status":200,"latency_ms":420}
{"ts":"2026-04-11T17:31:05Z","route":"ollama","status":200,"fallback_reason":"http_429","local_model":"gemma4:e4b","latency_ms":8300}
{"ts":"2026-04-11T17:35:00Z","route":"none","status":503,"fallback_reason":"network_error","ollama_error":"ConnectionError","latency_ms":200}
```

El log permite reconstruir exactamente cuándo se usó cada upstream y por
qué. No contiene prompts, respuestas ni datos sensibles — solo metadatos
de enrutamiento.

## Honestidad sobre limitaciones

Esta regla es inviolable: Savia Dual es una **capa de continuidad
operativa**, no un reemplazo de la nube.

- La calidad de razonamiento de gemma4 local es significativamente menor
  que la de Claude Opus/Sonnet. Tareas complejas (specs SDD, code review
  profundo, orquestación multi-agente) degradan notablemente en fallback.
- La latencia en local es mayor (típicamente 5–15 s por respuesta según
  hardware y variante).
- Ventanas de contexto difieren: Anthropic 200K–1M, gemma4 128K–256K.
- Algunas features de Anthropic (prompt caching, tool use avanzado,
  visión) pueden no existir o comportarse distinto en Ollama.

Savia Dual **no oculta** estas diferencias al usuario. Cada fallback se
registra con motivo explícito, y el usuario puede ver en cualquier
momento qué ruta usó cada turno consultando `events.jsonl`.

## Prohibido

```
NUNCA → Desactivar el proxy en medio de una sesión sin avisar al usuario
NUNCA → Enrutar peticiones a otro upstream sin que el config lo declare
NUNCA → Loguear el contenido de prompts o respuestas en events.jsonl
NUNCA → Enviar datos de hardware o telemetría fuera de la máquina
NUNCA → Ocultar al usuario que está operando en modo fallback
```

## Integración con reglas existentes

- Complementa `data-sovereignty.md` (clasificación local de datos) con
  **soberanía de inferencia** (cómputo local de razonamiento).
- Respeta `autonomous-safety.md`: el proxy no toma decisiones por su
  cuenta, solo enruta peticiones ya emitidas por Claude Code.
- Compatible con `hook-profiles.md`: los hooks siguen aplicando
  independientemente del upstream que sirva la respuesta.
