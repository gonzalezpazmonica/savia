---
version_bump: patch
section: Changed
---

### Changed

- SE-512 reconciliada con SE-488 y SE-496 (un solo formato de autorización: el permiso nocturno se aprueba fusionando una PR), con sección «Lo que he entendido» y prototipo S0 en docs/specs/assets/SE-512-prototipo.md; spec sigue PROPOSED

- SE-512 tras revisión: AC-12c corregido (sin recibo, código 3; el 7 solo cuando M es anterior a `not_before`), `caduca == not_after` y `emitida` atada al commit del artefacto, título y descripción de la PR de aprobación generados desde el `resumen` y verificados, STOP anotado en el libro de consumidos, restos de «firma» reformulados
