---
version_bump: patch
section: Fixed
---

### Fixed

- merge-sprint: un HOLD registrado sobre la cabeza actual, o cualquier otro HOLD de la PR sin un APPROVE posterior del mismo rol sobre el sha usado, excluye la PR del plan y la aparca en run (antes de re-sincronizar y justo antes del merge). El HOLD sobre la cabeza actual retiene siempre (incidente #1642).

