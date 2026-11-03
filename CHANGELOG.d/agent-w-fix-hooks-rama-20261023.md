---
version_bump: patch
section: Security
---

### Security

- validate-bash-global ya ve `git -C <ruta> commit|add`: antes su prefiltro exigía `git commit` y un commit dirigido a main con `-C` pasaba sin bloqueo.
- block-commit-to-main, validate-bash-global y el guard TS miran el repo destino de cada git commit/add con scripts/lib/git_op_targets.py, no el checkout de la sesión. Los heredocs y cadenas que solo mencionan git commit ya no bloquean.
- El resolvedor es fail-closed por defecto (lista blanca): solo reconoce con certeza `git -C <ruta literal>`, `cd <ruta literal>` encadenado con `;`, `&&` o salto de línea, y el cwd de la orden. Cualquier otra forma con `git` y `commit|add` en el texto da el veredicto BLOQUEAR (destino vacío). Eso incluye `bash -c`, `env -S`, `eval`, `xargs`, funciones, alias, envoltorios como `sudo` o `timeout`, variables no literales, `GIT_DIR`, `CDPATH`, un `cd` a un directorio que el hook no ve y heredocs o tuberías hacia una orden no inerte. Mensaje: forma admitida `git -C <ruta> commit …`.
- El guard TS bloquea sin condiciones ante el veredicto BLOQUEAR o si el resolvedor no está disponible. Solo acepta `TEST_BRANCH` bajo `bun test` (NODE_ENV=test).
- El resolvedor resuelve los alias de git en el repo destino (`git config --get alias.<x>`, también los globales): un alias o una orden externa `git-<x>` que no sea un subcomando integrado sin commit cuenta como commit en ese destino, aunque el texto no diga `commit`. Un programa no resoluble seguido de la palabra `commit` (`$x commit`) da BLOQUEAR. `gh pr|issue|release|…` con `git commit` en el cuerpo ya no bloquea.
- Guard TS: llama al resolvedor si la orden dice `git` o `commit` (antes solo `commit`, y `git ci` con alias pasaba). El bypass `SAVIA_ALLOW_MAIN_COMMIT=1` de la operadora vale también ante destino incierto y queda registrado.
- Los hooks bash (block-commit-to-main y validate-bash-global) también bloquean sin condiciones ante el veredicto BLOQUEAR, también desde un worktree `agent/*`, y si falta Python o el resolvedor falla (antes caían a la rama del cwd de la orden).
