---
version_bump: patch
section: Fixed
---

### Fixed

- merge-sprint (SE-433): un merge rechazado libera la reserva F5 y la reconciliación exige el SHA reservado y la cuenta del ejecutor; un merge ajeno para con merge_externo.
- merge-sprint: solicitudes al juez acotadas al grant y al head; los PRs en pausa awaiting_judge conservan la etiqueta de auto-rebase; plan borra etiquetas huérfanas.
- merge-sprint: solo vuelve a Draft lo que el ejecutor sacó de Draft; la solicitud al juez excluye derivados y no pasa el diff por argv; fix_author por email o trailer Fix-Author; el prefiltro detecta tests debilitados.

