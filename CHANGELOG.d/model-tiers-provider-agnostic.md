---
version_bump: patch
section: Fixed
---

### Fixed

- Tiers de modelo agnósticos a proveedor restaurados: agentes y comandos declaran `model_tier: heavy|mid|fast` (recuperado del historial git) en vez de IDs de proveedor que rompían Claude Code (75 agentes y 210 comandos con `unrecognized_model`).
- Definición local por frontend en `~/.savia/preferences.yaml` → `tiers.{claude-code,opencode,codex}`; default Claude Code opus/sonnet/haiku. Adaptadores: hook `model-tier-inject.sh` (Claude Code), `plugins/lib/model-tiers.ts` para agentes y comandos (OpenCode) y `savia_resolve_model` (scripts).
- `sync-model-tiers.sh` retirado (reescribía fuentes versionadas); nuevo guard `scripts/model-tier-lint.sh`.
- Hooks Claude Code: modo ejecutable en `cache-hygiene-hook.sh` y `repeat-tool-guard.sh`; `judge-auto-router.sh` lee stdin/`tool_response` (antes usaba `CLAUDE_PLUGIN_ROOT` inexistente); rutas relativas → `$CLAUDE_PROJECT_DIR`; el hook de commit ya no fija un modelo de proveedor; `judge-trigger-detector.sh` sin error aritmético.
- Savia Shield: el autostart era un no-op permanente (los hooks siempre reciben stdin por pipe). Ahora es opt-in con `SAVIA_SHIELD_AUTOSTART=on` hasta calibrar el NER; sin daemon, `data-sovereignty-gate.sh` mantiene el fallback regex. Retirado el hook HTTP duplicado que fallaba en cada Edit/Write con el daemon caído. Allow-list NER normaliza Markdown y añade términos de frontends.
- `validate-bash-global.sh`: `cd "<worktree>"` ya se reconoce (en un worktree `.git` es un fichero); `agents-md-generate.sh` limita el marcador SE-371 a `PROJECT_ROOT`.
- Codex: gates Bash de Savia en `.codex/hooks.json`; el probe de frontera de secretos fallaba en locales no ingleses (`LC_ALL=C`); canaries day-1 con expectativas actualizadas.
- `generate-critical-facts.sh --check` ya no reescribe; el ancla describe la regla de tiers en vez de un modelo fijo. Frontmatter YAML válido en 3 comandos. SDK `@opencode-ai/plugin` 1.18.32.

### Added

- `scripts/skill-listing-overrides.sh`: los comandos `tier: extended` se listan solo por nombre en Claude Code (`skillOverrides`), liberando presupuesto del listado de skills.
