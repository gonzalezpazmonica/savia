---
version_bump: patch
section: Fixed
---

### Fixed

- Guardas: crear un worktree o añadir un remoto ya no se bloquea como si fuera añadir ficheros al índice sin destino seguro. Restaurar ficheros con checkout y opciones antes del separador se reconoce como restauración en bash y TS; cambiar de rama con el árbol sucio sigue bloqueado, también detrás de una restauración en la misma orden.
- Guardas: un directorio llamado `remote` o `worktree` ya no oculta un `git add` real, tampoco si el valor de `-C`, `-c` o `--work-tree` va entre comillas o con un espacio escapado. Una redirección o un comentario tras el separador ya no cuenta como ruta, y un salto de línea separa órdenes (bash y TS).
- Guardas: `git checkout <rama> -- $FILES` o `-- $(…)` sin ninguna ruta conocida ya no cuenta como restauración (si la expansión queda vacía, bash cambia de rama); con el árbol sucio se bloquea, en bash y TS.
- Guardas (TS): el prefiltro del cambio de rama ya no se salta un alias de git (`git co feature`). El filtro de heredocs conserva el texto si el resto de la orden copia el fichero a uno que se ejecuta solo (`cat n.md >> ~/.bashrc`, `tee -a .profile`) y suma a esos destinos `.bash_aliases`, `profile.d/`, fish, `.claude/`, `.opencode/` y `.github/`.
- Guardas (TS): el cambio de rama con el árbol sucio se comprueba en el repo sobre el que actúa la orden (`git -C <clon> checkout <sha>`, `cd`, variables literales), con el mismo resolvedor y el mismo fallo cerrado que los guards de commit en main. Un borrado recursivo escrito como texto en un heredoc que solo escribe un fichero ya no se toma como orden; si el heredoc va a un intérprete o el fichero se ejecuta después, sigue bloqueando. El filtro conserva el texto cuando bash lo ejecutaría: continuación de línea en la línea del heredoc, delimitador con comillas a medias (`<<EOF'X'`), fichero ejecutado después por glob o variable, o destino que se ejecuta solo (`.git/`, `.bashrc`, `.profile`).
- Guardas (TS): si `git status` falla en el repo destino por algo distinto de «no es un repo» (índice corrupto, tiempo agotado, propietario dudoso), el cambio de rama se bloquea en vez de darse por limpio.
- Guardas (bash): el hook de cambio de rama usa el mismo resolvedor que TS (`git_op_targets.py --switch`). Con el árbol sucio, `git checkout <rama> -- >/dev/null`, `-- 2>&1`, `-- # comentario` y un cambio de rama en otra línea que una restauración u otra orden con `--` vuelven a bloquear. Entrada JSON inválida, comando no textual o destino incierto (`cd $VAR && git switch …`) bloquean (fallo cerrado, como en TS); antes salían 0.
- Guardas (TS): el filtro de heredocs ya no infiere que el fichero es inerte por no ver su nombre después. Solo quita el cuerpo si el destino es una ruta literal y todo el resto de la orden son órdenes de datos de una lista cerrada (cat, tee, echo, printf, grep, wc, head, tail, cut, tr, ls, mkdir); `export BASH_ENV=…` + `bash -c`, `bash /tmp/x-*`, `npm test`, `make`, comillas que envuelven la línea del heredoc o un segundo heredoc dudoso conservan todo el texto.
- Guardas (bash, pendiente de aplicar a mano): el resumen de PR leído del worktree de la PR con la plantilla completa en el mensaje, el borrado sin confirmación de ficheros propios en rutas de trabajo de agentes, y el texto de heredocs a fichero. Ver el parche en la PR #1483.

