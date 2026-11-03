# LOG.d — entradas pendientes del log de specs (SE-500 S1)

Cada transición de estado se escribe como un fichero nuevo en lugar de editar `LOG.md`.

- Nombre: `SE-NNN-ESTADO.md`, con `ESTADO` en la lista cerrada de `roadmap.sh validate`
  (IDEA, PROPOSED, APPROVED, IMPLEMENTING, IMPLEMENTED, REJECTED, SUPERSEDED, DEFERRED, RETIRED).
  Cualquier otro nombre falla y nunca se usa como ruta.
- Contenido: exactamente una cabecera `## YYYY-MM-DD SE-NNN ESTADO` en la primera línea,
  coincidente con el nombre, y un párrafo opcional sin más cabeceras.
- Lo escriben `bash scripts/roadmap.sh register` y `bash scripts/spec-lifecycle.sh`.
- Vista (`python3 scripts/planning-view.py log`): cabecera de `LOG.md`, luego estas entradas por
  fecha, id numérico y rango de estado (todo descendente), luego el cuerpo de la base.
  `validate` avisa si una entrada tiene fecha anterior a la más reciente de la base.
- `LOG.md` solo cambia con `bash scripts/roadmap.sh consolidate`.
