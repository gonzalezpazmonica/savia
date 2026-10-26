---
version_bump: patch
section: Fixed
---

### Fixed

- Evals CI Gate (SE-468): el runner ya no puntúa por longitud del input ni con 0.80 fijo; cada dataset emite clean/findings/unknown con huecos (not_executed, no_baseline), el comentario de la PR muestra «no evaluado», el modo vivo sin SAVIA_EVAL_EXECUTOR falla cerrado y un dataset solo cuenta como evaluado si la corrida con el artefacto vaciado produce findings.

