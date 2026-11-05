---
version_bump: patch
section: Fixed
---

### Fixed

- Guardas: crear un worktree o añadir un remoto ya no se bloquea como si fuera añadir ficheros al índice sin destino seguro. Restaurar ficheros con checkout y opciones antes del separador se reconoce como restauración en bash y TS; cambiar de rama con el árbol sucio sigue bloqueado, también detrás de una restauración en la misma orden.
- Guardas: un directorio llamado `remote` o `worktree` ya no oculta un `git add` real, tampoco si el valor de `-C`, `-c` o `--work-tree` va entre comillas o con un espacio escapado. En TS, una redirección o un comentario tras el separador ya no cuenta como ruta, y un salto de línea separa órdenes. El arreglo equivalente del hook bash (redirecciones, comentarios y salto de línea) está pendiente de aplicar a mano: requiere permiso de fichero sensible.
- Guardas (TS): el cambio de rama con el árbol sucio se comprueba en el repo sobre el que actúa la orden (`git -C <clon> checkout <sha>`, `cd`, variables literales), con el mismo resolvedor y el mismo fallo cerrado que los guards de commit en main. Un borrado recursivo escrito como texto en un heredoc que solo escribe un fichero ya no se toma como orden; si el heredoc va a un intérprete o el fichero se ejecuta después, sigue bloqueando. El filtro conserva el texto cuando bash lo ejecutaría: continuación de línea en la línea del heredoc, delimitador con comillas a medias (`<<EOF'X'`), fichero ejecutado después por glob o variable, o destino que se ejecuta solo (`.git/`, `.bashrc`, `.profile`).
- Guardas (TS): si `git status` falla en el repo destino por algo distinto de «no es un repo» (índice corrupto, tiempo agotado, propietario dudoso), el cambio de rama se bloquea en vez de darse por limpio.
- Pendiente en el hook bash de cambio de rama, que sigue en esta PR con la regla nueva: con el árbol sucio, `git checkout <rama> -- >/dev/null`, `-- 2>&1`, `# -- x` y un cambio de rama en la línea siguiente a una restauración pasan. Su arreglo y los tests bats están en la PR #1483; aplicarlo requiere permiso de fichero sensible.
- Guardas (bash, pendiente de aplicar a mano): el mismo criterio de repo destino para el cambio de rama, el resumen de PR leído del worktree de la PR con la plantilla completa en el mensaje, el borrado sin confirmación de ficheros propios en rutas de trabajo de agentes, y el texto de heredocs a fichero. Ver el parche en la PR #1483.

