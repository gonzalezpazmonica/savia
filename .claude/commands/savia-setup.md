---
name: savia-setup
description: >
  Onboarding interactivo del usuario. Pregunta el stack (frontend × proveedor
  × capacidades × budget × auth) y persiste en ~/.savia/preferences.yaml.
  Re-ejecutable idempotentemente cuando el stack cambia.
argument-hint: ""
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# Savia Setup

**Argumentos:** $ARGUMENTS

> Uso: `/savia-setup`

Cada usuario decide su frontend (Claude Code, OpenCode v1.14, Codex, Cursor,
otro) y su proveedor de inferencia (Anthropic API, hosted-OSS, LocalAI,
Ollama, vendor corporativo, endpoint custom). Savia opera de forma
agnóstica al stack — este comando captura tus elecciones para que el
framework respete tu setup en lugar de asumir un default Claude Code.

## Qué hace

1. Lanza `bash scripts/savia-preferences.sh init` (entrevista 8 preguntas).
2. Cada pregunta tiene **campo libre** — no hay lista cerrada de vendors.
3. El resultado se persiste en `~/.savia/preferences.yaml` (per-user, NUNCA
   commiteado al repo).
4. La validación rechaza claves prohibidas (`api_key`, `password`, `secret`,
   `token`) — esos viven en un credential manager, no aquí.

## Las 8 preguntas

1. **Frontend** que usas (claude-code / opencode / codex / cursor / other)
2. **Proveedor de inferencia** (free text — vendor / "localai" / "ollama" /
   "custom-corp" / etc.)
3. Modelos preferidos por tier (heavy / mid / fast — campo libre por tier)
4. ¿Tu stack expone **hook events**? (yes / no / autodetect)
5. ¿Tu stack expone **Task tool / subagent fan-out**? (yes / no / autodetect)
6. ¿Tu stack expone **slash commands**? (yes / no / autodetect)
7. **Budget** que respetar (none / req-count / token-count / dollar-cap +
   límite mensual)
8. **Auth shape** (none / api-key / oauth / mtls / corporate-custom)

`autodetect` significa que `scripts/savia-env.sh` decidirá según señales del
env (e.g. `CLAUDE_PROJECT_DIR` set → has_hooks=yes).

## Después del setup

- `bash scripts/savia-env.sh print` muestra el estado activo (workspace,
  provider, capabilities).
- `bash scripts/savia-preferences.sh show` muestra el archivo completo.
- `bash scripts/savia-preferences.sh validate` verifica el schema.
- `bash scripts/savia-preferences.sh reset --confirm` borra preferences.

## Privacidad

- `~/.savia/preferences.yaml` es **personal**, vive en tu home, **nunca** en
  el repo.
- El validator rechaza claves de credenciales — esos secretos van en
  variables de entorno, OS keychain o vault.
- Cualquier nombre de vendor que escribas queda en tu archivo local. El repo
  nunca lo ve.

## Spec ref

- SPEC-127 Slice 1 (`docs/propuestas/SPEC-127-savia-opencode-provider-agnostic.md`)
- `docs/rules/domain/provider-agnostic-env.md`
- `docs/rules/domain/model-alias-schema.md`

## Ejecución

Ejecuta el onboarding interactivo:

```bash
bash scripts/savia-preferences.sh init
```
