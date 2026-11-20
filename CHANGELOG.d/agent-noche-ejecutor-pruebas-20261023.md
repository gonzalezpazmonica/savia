---
version_bump: patch
section: Added
---

### Added

- tests(merge-sprint): suite que mata 6 mutantes supervivientes del ejecutor de fusiones (p2_blocking, main cancelled/timed_out/sin check-runs, checks ilegibles, PR del veredicto) y pruebas pendientes de activar para la inyección en review-register, en `tests-pending/` (fuera de los runners recursivos de `tests/`), con un guard que impide volver a dejarlas bajo `tests/`

