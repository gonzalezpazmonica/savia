---
version_bump: patch
section: Fixed
---

### Fixed

- merge-sprint: un HOLD registrado sobre la cabeza actual o sobre el sha usado excluye la PR del plan y la aparca en run (antes de re-sincronizar y justo antes del merge). Cualquier otro HOLD de la PR retiene salvo que, después, haya un APPROVE íntegro del mismo rol sobre el sha usado y ese sha sea posterior al retenido: re-aprobar un sha antiguo equivalente no levanta nada. Si git no puede decidir la ancestría, o los argumentos o el registro fallan, retiene (incidente #1642). Incluye los tests de regresión de HOLD entre cabezas equivalentes.
