---
version_bump: patch
section: Fixed
---

### Fixed

- compliance-gate evalúa el repo objetivo del commit (git -C, cd previo o cwd de la sesión) y sus ficheros staged, no el de la sesión; sin objetivo determinable bloquea (fail-closed). Los cuerpos de heredoc de cat/tee ya no cuentan como commits.

