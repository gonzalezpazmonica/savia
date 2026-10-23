---
version_bump: patch
section: Fixed
---

### Fixed

- **SE-392 S3 vocabulario de hooks en OpenCode**: savia-gates entrega a los hooks de `.claude/settings.json` las llamadas de OpenCode con nombres y claves de Claude Code (`Edit`, `file_path`…) y evalúa `apply_patch` archivo a archivo como el adaptador Codex. Antes, 4 de 5 bloqueos reales de edición (tdd-gate, parche multiarchivo, parche ilegible) pasaban en OpenCode. Replay de edición con decisiones idénticas en Codex y OpenCode.

