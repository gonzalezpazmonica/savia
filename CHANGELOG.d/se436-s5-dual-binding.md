---
version_bump: minor
section: Added
---

### Added

- Guard de cúpulas en el motor (SE-436 S5, DUAL_BINDING): hook PreToolUse `dome-guard.sh` para Claude Code y regla nativa en savia-gates para OpenCode, portados del guard de Savia Space. Una escritura del motor en una cúpula pregunta con el aviso de propuesta («Guardar como nota»); una lectura de una cúpula N2 no adjunta con proveedor de nube pregunta y una N3 o superior se deniega. Bash resuelve las rutas contra `workdir` (o el cwd de la sesión) y no se deja esquivar con guiones inline (`bash -c`, `python3 -c`), rutas en `clave=valor` (`dd of=`, `curl -F file=@`) ni enlaces bajo una búsqueda. El motor no puede reescribir el registro de cúpulas. Un payload ilegible con cúpulas registradas pregunta. Fuera de las cúpulas no decide nada. Falla cerrado si el registro no se puede leer. En OpenCode el `ask` se aplica como bloqueo con el aviso, porque OpenCode no pasa `permission.ask` a los plugins. Con `SAVIA_DOME_GUARD=space` o `SAVIA_GATES_PIN=1` decide Savia Space. 240 casos compartidos con su decisión esperada y una prueba de paridad hook ↔ savia-gates (el job BATS de CI pasa a node 22 para ejecutarla). El puente de savia-gates ya no ejecuta el gemelo bash de una regla nativa.

