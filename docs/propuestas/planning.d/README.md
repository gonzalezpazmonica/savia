# planning.d — fragmentos del registro de planificación (SE-500 S1)

Cada PR registra su spec con un fichero nuevo en lugar de editar `planning-state.json`,
igual que `CHANGELOG.d/` (SE-053). Así dos PR que registran specs distintas no chocan.

- Nombre: `SE-NNN.json` (exactamente, `re.fullmatch` de `SE-[0-9]+\.json`), igual al `id`.
- Contenido: un objeto JSON con el registro completo de la iniciativa, mismo esquema que un
  elemento de `initiatives`. Obligatorios: `id`, `status`, `title`, `evidence`.
- Se crea con `bash scripts/roadmap.sh register SE-NNN --status ESTADO --title "…" [--priority
  --phase --note --evidence --approval]`, que escribe también la entrada de `../LOG.d/`.
- La vista (`python3 scripts/planning-view.py state`) es la base con los fragmentos aplicados en
  orden numérico: si el id ya existe en la base, el fragmento lo sustituye.
- `roadmap.sh validate` corre sobre la vista; `roadmap.sh validate --diff origin/main` exige que
  la base solo cambie por consolidación pura.
- Consolidación: `bash scripts/roadmap.sh consolidate` en una PR ordinaria cuando hay más de 30
  fragmentos o al cerrar una era. Escribe la vista en la base y borra los fragmentos.

Las claves que no son `initiatives` (`route`, `session_plan`, suelos) se siguen editando en la base.
