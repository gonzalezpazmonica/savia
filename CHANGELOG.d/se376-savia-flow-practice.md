---
version_bump: patch
section: Fixed
---

### Fixed

- savia-flow-practice calibrada (SE-376): imputación de horas valida horas (coma es_ES, >0, <=24), el informe suma por tarea y total en rangos multi-mes, cada escritura es una transacción contra origin (fetch, commit, push verificado, reintento si otro clon publicó antes) y sin remoto falla con exit 1 en vez de informar éxito; las lecturas hacen fetch y avisan si leen datos desfasados; sprint create/close/board/velocity ejecutables de verdad; tasks create ya no falla en la segunda tarea y move/assign/list funcionan; savia-flow.sh cierra el sprint activo y metrics cuenta bien.

