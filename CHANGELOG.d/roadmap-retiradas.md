---
version_bump: patch
section: Changed
---

### Changed

- La cola del roadmap deja de listar trabajo de SE-493 y SE-513 (retiradas); `roadmap.sh validate` falla si una entrada de la cola depende de una spec RETIRED.

- Las fases que dependían de esas specs (SE-498 F3 y R7, SE-514 S2, SE-515 S3–S4) quedan aparcadas en la cola con su motivo (`parked`): `validate` las acepta y `current` las muestra; una dependencia viva de una spec RETIRED sigue fallando.
