---
version_bump: patch
section: Fixed
---

### Fixed

- `tdd-gate.sh`: cuando el directorio destino aún no existe (primer fichero de una carpeta nueva), el hook sube hasta el ancestro existente más cercano antes de `git -C`, así resuelve el repo destino en vez de caer en el de la sesión y no ver tests que sí existen. Dos casos bats, uno de control negativo. Aportación de @ivantintore (#1318).
