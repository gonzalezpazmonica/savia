---
name: savia-dual
description: Gestiona Savia Dual — inference sovereignty con failover entre Anthropic y gemma4 local
developer_type: all
agent: none
context_cost: low
model_tier: fast
allowed-tools: [Read, Bash, Glob, Grep]
argument-hint: "{install|start|stop|status|test|logs}"
tier: core
---

# /savia-dual {subcomando}

> Inference sovereignty. Cuando la nube funciona, calidad maxima.
> Cuando falla, Savia sigue viva en local.

## Prerequisitos

- Python 3.8+ (para el proxy)
- Permisos de escritura en `$HOME/.savia/dual/`
- Para `install`: conexion a internet la primera vez

## Subcomandos

### `/savia-dual install`

Instala desde cero:
- Linux/macOS: `bash scripts/setup-savia-dual.sh`
- Windows: `pwsh .\scripts\setup-savia-dual.ps1`

El installer detecta OS, instala Ollama si falta, detecta RAM/VRAM,
selecciona la variante de gemma4 adecuada, la descarga y escribe la
configuracion en `~/.savia/dual/`.

### `/savia-dual start`

Arranca el proxy en primer plano:

```bash
python3 scripts/savia-dual-proxy.py
```

Abre esto en una terminal dedicada. En otra terminal, carga el env y
arranca Claude Code:

```bash
source ~/.savia/dual/env
claude
```

### `/savia-dual stop`

Detiene el proxy (Ctrl+C si esta en primer plano, o
`pkill -f savia-dual-proxy`). Al parar el proxy, Claude Code vuelve
a apuntar al valor previo de `ANTHROPIC_BASE_URL` si existia.

### `/savia-dual status`

Muestra diagnostico:
- Proxy en ejecucion (chequea `/health`)
- Ollama corriendo con el modelo elegido
- Ruta del config file y valores actuales
- Ultimas 10 decisiones de routing (de events.jsonl)

Equivale a:

```bash
curl -s http://127.0.0.1:8787/health
cat ~/.savia/dual/config.json
tail -10 ~/.savia/dual/events.jsonl
```

### `/savia-dual test`

Envia una peticion de prueba al proxy para verificar end-to-end:

```bash
curl -s -X POST http://127.0.0.1:8787/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{"model":"claude-sonnet-4-6","max_tokens":50,
       "messages":[{"role":"user","content":"ping"}]}'
```

Reporta ruta usada (anthropic u ollama) y latencia.

### `/savia-dual logs`

Muestra los ultimos eventos de routing en formato legible:

```bash
tail -20 ~/.savia/dual/events.jsonl
```

## Banner obligatorio al terminar

Cada subcomando muestra:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OK /savia-dual {subcomando}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ /compact — libera contexto antes del siguiente comando
```

## Restricciones

- El proxy escucha SOLO en 127.0.0.1. No exponer a la red.
- events.jsonl NUNCA contiene prompts ni respuestas.
- Hardware detectado por el installer NUNCA se persiste en ficheros
  versionados.
- No existe modo "forzar fallback": la nube se usa siempre que responda.

## Referencias

- Regla: `docs/rules/domain/savia-dual.md`
- Skill: `.opencode/skills/savia-dual/SKILL.md` + `DOMAIN.md`
- Doc: `docs/savia-dual.md`
