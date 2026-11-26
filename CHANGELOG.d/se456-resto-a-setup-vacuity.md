---
version_bump: patch
section: Fixed
---

### Fixed

- SE-456 RESTO-456-a: el detector de vacuidad también mira `setup()` y `setup_file()` (solo aserciones anuladas, ignorando cuerpos de heredoc); las cuatro aserciones muertas de `setup()` en los tests del Shield y de la digestión enmascarada pasan a ser reales (el contador pasó de 4 a 0)
