---
version_bump: patch
section: Fixed
---

### Fixed

- scope-guard: deja de rehashear el índice racy en cada Stop. Comprueba la spec activa y los ficheros declarados antes de lanzar git, y refresca el índice antes del diff. En un checkout como el de la CI pasa de 450-507 ms de mediana a 23 ms.

