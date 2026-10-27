---
version_bump: patch
section: Fixed
---

### Fixed

- validate-agent-permissions.sh detecta herramientas por encima del nivel L0-L4 (antes solo las que faltaban, exit 0 con exceso). Línea base transitoria con responsable y caducidad (2026-11-10) para 15 agentes pendientes de decisión. El frontmatter se lee como YAML real y falla en cerrado (YAML inválido, `tools:` ausente, valores no booleanos, sin nivel = L0); la CI de cada PR ejecuta el gate. Corrige el YAML de `memory-agent` y `expertise-asymmetry-judge`, que no era válido.
