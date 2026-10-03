---
version_bump: patch
section: Fixed
---

### Fixed

- savia-gates: con SAVIA_GATES_PIN=1 (Space en modo mediado) fija por hash el registro y los scripts de guard al cargar cada directorio y bloquea (GUARDS_MODIFIED) si cambian; las ediciones de guards se bloquean (GUARD_PROTECTED). Antes, un guard editado en el worktree del agente valía en la siguiente llamada (T1).

