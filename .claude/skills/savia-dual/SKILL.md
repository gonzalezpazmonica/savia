---
layer: peripheral
name: savia-dual
description: "Usar cuando la inferencia cloud falla, es lenta o está rate-limited y se necesita failover local."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: governance
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Runs a local proxy at 127.0.0.1:8787 that routes Claude Code requests to Anthropic when available and transparently falls back to a local Ollama gemma4 instance on network failure, 5xx, 429, or timeout. Cloud for quality, local for continuity."
---

# Skill: savia-dual

> Soberanía de inferencia dual. Cuando la nube va bien, calidad máxima.
> Cuando la nube falla, Savia sigue funcionando en local.

## Prerequisitos (gate de arranque del failover)

```
Doble opt-in (SPEC-186):                  → si no: ❌ ABORT
  bash scripts/savia-double-optin-check.sh \
    --skill savia-dual --confirm-autonomous
Requiere AMBOS: SAVIA_DUAL_FAILOVER_ENABLED=true Y flag explicito.
```

## Cuándo se activa

Esta skill se activa cuando el usuario necesita:
- Trabajar sin conexión estable (viajes, zonas rurales, cortes)
- Protegerse de incidentes de Anthropic (outages, latencia alta)
- Asegurar continuidad ante agotamiento de cuota de tokens
- Experimentar con modelos locales sin renunciar a la calidad cloud

## Componentes

1. **Proxy** — `scripts/savia-dual-proxy.py`
2. **Installer Linux/macOS** — `scripts/setup-savia-dual.sh`
3. **Installer Windows** — `scripts/setup-savia-dual.ps1`
4. **Regla** — `docs/rules/domain/savia-dual.md`
5. **Comando** — `/savia-dual {install|start|stop|status|test}`
6. **Docs** — `docs/savia-dual.md`

## Flujo de instalación

```
./scripts/setup-savia-dual.sh           # Linux/macOS
pwsh .\scripts\setup-savia-dual.ps1     # Windows
```

El installer:
1. Instala o actualiza Ollama
2. Detecta RAM y VRAM del equipo (datos locales, no se persisten)
3. Elige la variante de gemma4 más adecuada
4. Descarga el modelo
5. Escribe `~/.savia/dual/config.json` y `~/.savia/dual/env`
6. Deja instrucciones para arrancar el proxy

## Flujo de uso diario

```bash
# Terminal 1: arrancar proxy
python3 scripts/savia-dual-proxy.py

# Terminal 2: cargar env y arrancar Claude Code
source ~/.savia/dual/env
claude
```

A partir de ese momento, Claude Code envía peticiones al proxy, que las
enruta según configuración. El usuario NO percibe la diferencia cuando
la nube responde bien. Cuando hay fallback, puede ver el motivo en
`~/.savia/dual/events.jsonl`.

## Reglas operativas

- **Cloud first, local fallback**: nunca al revés. La calidad prima.
- **Transparencia total**: cada routing decision se registra con motivo.
- **Sin bypass**: el proxy no expone ningún modo para forzar fallback
  manualmente; la única forma de usar local es parar el proxy o
  desactivar `ANTHROPIC_BASE_URL`.
- **Circuit breaker**: 3 fallos consecutivos → 60s solo local → reintenta
  Anthropic. Evita martillear el upstream caído.

## Límites honestos

gemma4 local NO es equivalente a Opus/Sonnet. Usar con expectativas:

| Tarea | Cloud | Local gemma4 |
|---|---|---|
| Lectura de memoria, /help, /sprint-status | ✅ | ✅ aceptable |
| Conversación operativa | ✅ | 🟡 usable, más lento |
| Specs SDD, code review | ✅ | ❌ calidad insuficiente |
| Orquestación multi-agente | ✅ | ❌ pierde contexto |

Para uso ofimático de Savia (status, memoria, comandos simples) el
modo fallback es perfectamente viable. Para trabajo profundo de
ingeniería, reconectar a la nube antes de continuar.

## Relación con otras skills

- **data-sovereignty** (skill existente): soberanía de datos sensibles
  → esta skill añade **soberanía de inferencia** sobre el razonamiento
- **emergency-mode**: modo emergencia manual → Savia Dual es el modo
  automático y transparente equivalente, sin intervención del usuario
