---
version_bump: patch
section: Fixed
---

### Fixed

- CI de Soul Continuidad: el job «tsc --strict» deja src/web fuera del tsconfig raíz y lo comprueba con su propio paquete (npm ci + typecheck); además corre sus tests unitarios sin navegador.

