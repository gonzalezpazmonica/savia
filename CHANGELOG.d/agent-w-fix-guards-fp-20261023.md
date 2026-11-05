---
version_bump: patch
section: Fixed
---

### Fixed

- Guardas: crear un worktree o añadir un remoto ya no se bloquea como si fuera añadir ficheros al índice sin destino seguro. Restaurar ficheros con checkout y opciones antes del separador se reconoce como restauración en bash y TS; cambiar de rama con el árbol sucio sigue bloqueado, también detrás de una restauración en la misma orden.
- Guardas: un directorio llamado `remote` o `worktree` ya no oculta un `git add` real, tampoco si el valor de `-C`, `-c` o `--work-tree` va entre comillas o con un espacio escapado. En TS, una redirección o un comentario tras el separador ya no cuenta como ruta, y un salto de línea separa órdenes. El arreglo equivalente del hook bash (redirecciones, comentarios y salto de línea) está pendiente de aplicar a mano: requiere permiso de fichero sensible.

