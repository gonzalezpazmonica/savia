---
version_bump: patch
section: Fixed
---

### Fixed

- validate-agent-permissions.sh detecta herramientas por encima del nivel L0-L4 (antes solo las que faltaban, exit 0 con exceso). Línea base transitoria con responsable y caducidad (2026-11-10) para 15 agentes pendientes de decisión; parser de `tools:` robusto ante listas multilínea, líneas en blanco y comentarios.
