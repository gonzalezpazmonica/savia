### Added

- **SE-392 S3 (parcial) gates compartidos y adaptador Codex**: `scripts/dual-cli/gates.py`
  ejecuta los handlers de `.claude/settings.json` con fallo cerrado (timeout con
  muerte del grupo de procesos, salida inválida, `ask`, handlers http/prompt sin
  transporte) y `codex-hook.py` traduce PreToolUse de Codex, incluido `apply_patch`
  por archivo. Replay del mismo corpus contra los hooks reales por el núcleo Codex y
  por `shell-bridge.ts` de OpenCode: decisiones idénticas. No activa hooks ni cambia
  `.codex/hooks.json`.
