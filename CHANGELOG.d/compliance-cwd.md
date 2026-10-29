---
version_bump: patch
section: Fixed
---

### Fixed

- compliance-gate evalúa el repo objetivo del commit (git -C, cd previo o cwd de la sesión) y sus ficheros staged, no el de la sesión; sin objetivo determinable bloquea (fail-closed). Detecta commits en cualquier línea de la orden y los evalúa todos. Falla cerrado si hay un cd dentro de un subshell o entre comillas, pushd/popd o variables que cambian el repo de git. Un commit dentro de un heredoc se evalúa como commit: se acepta ese falso positivo para no repetir el falso verde del filtro anterior.

