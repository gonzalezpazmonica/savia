---
version_bump: patch
section: Security
---

### Security

- validate-bash-global ya ve `git -C <ruta> commit|add`: antes su prefiltro exigía `git commit` y un commit dirigido a main con `-C` pasaba sin bloqueo.
- block-commit-to-main, validate-bash-global y el guard TS miran el repo destino de cada git commit/add con scripts/lib/git_op_targets.py, no el checkout de la sesión. Los heredocs y cadenas que solo mencionan git commit ya no bloquean.
- El resolvedor es fail-closed por defecto (lista blanca): solo reconoce con certeza `git -C <ruta literal>`, `cd <ruta literal>` encadenado con `;`, `&&` o salto de línea, y el cwd de la orden. Cualquier otra forma con `git` y `commit|add` en el texto da el veredicto BLOQUEAR (destino vacío). Eso incluye `bash -c`, `env -S`, `eval`, `xargs`, funciones, alias, envoltorios como `sudo` o `timeout`, variables no literales, `GIT_DIR`, `CDPATH`, un `cd` a un directorio que el hook no ve y heredocs o tuberías hacia una orden no inerte. Mensaje: forma admitida `git -C <ruta> commit …`.
- El guard TS bloquea sin condiciones ante el veredicto BLOQUEAR o si el resolvedor no está disponible. Solo acepta `TEST_BRANCH` bajo `bun test` (NODE_ENV=test).
- Límite conocido: los hooks bash aún aplican al destino vacío la rama del cwd de la orden, así que una forma no reconocida lanzada desde un worktree `agent/*` pasa. Para bloquear sin condiciones falta un cambio en `.claude/hooks/`, que no entra en esta PR.
