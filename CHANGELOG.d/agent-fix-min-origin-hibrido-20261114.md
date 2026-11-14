---
version_bump: minor
section: Fixed
---

### Fixed

- memory: `--min-origin` (SE-352) se aplica en todas las rutas de `memory-store.sh search` (hybrid, vector, graph, grep, auto); antes la ruta híbrida devolvía memorias untrusted aunque se pidiera owner.

