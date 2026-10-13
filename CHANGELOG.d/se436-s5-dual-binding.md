---
version_bump: minor
section: Added
---

### Added

- Guard de cúpulas en el motor (SE-436 S5, DUAL_BINDING): hook PreToolUse `dome-guard.sh` para Claude Code y regla nativa en savia-gates para OpenCode, portados del guard de Savia Space. Una escritura del motor en una cúpula pregunta con el aviso de propuesta («Guardar como nota»); una lectura de una cúpula N2 no adjunta con proveedor de nube pregunta y una N3 o superior se deniega. Fuera de las cúpulas no decide nada. Falla cerrado si el registro no se puede leer. En OpenCode el `ask` se aplica como bloqueo con el aviso, porque OpenCode no pasa `permission.ask` a los plugins. Con `SAVIA_DOME_GUARD=space` o `SAVIA_GATES_PIN=1` decide Savia Space. 138 casos compartidos y una prueba de paridad hook ↔ savia-gates.

