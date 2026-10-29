---
version_bump: patch
section: Fixed
---

### Fixed

- compliance-gate evalúa el repo objetivo del commit (git -C, cd previo o cwd de la sesión) y sus ficheros staged, no el de la sesión; sin objetivo determinable bloquea (fail-closed). Detecta commits en cualquier línea de la orden y los evalúa todos. Falla cerrado si hay un cd dentro de un subshell o entre comillas, pushd/popd o variables que cambian el repo de git. Un commit dentro de un heredoc se evalúa como commit: se acepta ese falso positivo para no repetir el falso verde del filtro anterior. El cd que no se puede seguir bloquea: va tras `{`, `then`, `do` o `!`, aparece en prosa, corre en segundo plano o en tubería, o está dentro de `sh -c` o `eval`. Funciona como lista blanca. La palabra «eval» en el mensaje del commit no bloquea.

