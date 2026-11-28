---
version_bump: patch
section: Fixed
---

### Fixed

- `scripts/knowledge-lint.sh` buscaba la memoria en una ruta fija de una máquina concreta que ya no existía y respondía «nada que revisar» con salida 0. Ahora deriva la carpeta de la memoria automática del propio repositorio (o usa `MEMORY_DIR` si se indica) y, si no existe, falla cerrado con salida 3 y el mensaje «no se ha revisado nada». Seis tests nuevos; el que daba por sano el caso sin carpeta pasa a exigir el error.
