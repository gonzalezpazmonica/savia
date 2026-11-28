---
version_bump: patch
section: Fixed
---

### Fixed

- SE-456 RESTO-456-a: el detector de vacuidad también mira `setup()` y `setup_file()` (solo aserciones anuladas, ignorando cuerpos de heredoc); las cuatro aserciones muertas de `setup()` en los tests del Shield y de la digestión enmascarada pasan a ser reales (el contador pasó de 4 a 0)
- SE-456 RESTO-456-a: el heredoc de `setup()` solo se reconoce fuera de comillas, sin `<<<` ni aritmética `$((…))`, y solo si su terminador aparece antes del siguiente bloque; antes un `<<'PY'` entre comillas dejaba invisibles los 17 `@test` de `tests/test-merge-plan.bats`
