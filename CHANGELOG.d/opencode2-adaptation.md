---
version_bump: minor
section: Added
---

### Added

- OpenCode 2: plugin dual V1/V2 (`id`+`setup` y `server()`), adaptador de hooks
  (`shell→bash`, `subagent→task`) y smoke sin bun.
- Gate `scripts/opencode-health-check.sh` (solo lectura) para plugin, config
  efectiva, MCP y contrato dual.
- Specs `SPEC-OC2-01..04` y plan de adaptación con matriz de compatibilidad
  OpenCode 2 / OpenCode 1 / Claude Code / Codex.

### Changed

- Tiers de modelo fuera del agente (`x_savia_model_tiers`): V2 copiaba
  `model_tier` a `request.body`.
- Config V2 aditiva: `permissions`, `policies`, `experimental.subagent_depth`.
- MCP: intérprete del sistema y rutas relativas; `savia-vaults` compilado;
  servidores sin binario desactivados con `enabled: false`.
- `opencode-config-validate.sh` acepta las claves nativas de V2 (`permissions`,
  `policies`, `snapshots`, `update`, etc.) y el prefijo `x_savia_`.
