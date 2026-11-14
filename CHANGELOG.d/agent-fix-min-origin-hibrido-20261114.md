---
version_bump: minor
section: Fixed
---

### Fixed

- memory: `--min-origin` (SE-352) se aplica en todas las rutas de `memory-store.sh search` (hybrid, vector, graph, grep, auto); antes la ruta híbrida devolvía memorias untrusted aunque se pidiera owner.

- memory: el filtro de origen usa el `origin`/`valid_to` de la propia línea devuelta por el índice vectorial y el grep, de modo que una revisión untrusted ya superseded no hereda el origen owner de la vigente; el grep híbrido filtra antes del recorte a top; `--min-origin system` es coherente entre bash y Python; en `--mode vector` un fallo del filtro es error (exit 1).
