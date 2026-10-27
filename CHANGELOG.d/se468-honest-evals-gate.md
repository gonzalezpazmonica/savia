---
version_bump: patch
section: Fixed
---

### Fixed

- Evals CI Gate (SE-468): el runner ya no puntúa por longitud del input ni con 0.80 fijo; cada dataset emite clean/findings/unknown con huecos (not_executed, no_baseline), el comentario de la PR muestra «no evaluado», el modo vivo sin SAVIA_EVAL_EXECUTOR falla cerrado y un dataset solo cuenta como evaluado si la corrida con el artefacto vaciado produce findings.

- evals (SE-468, revisión independiente): la prueba de sabotaje compara la corrida real con la saboteada; un dataset exige emparejar todo su baseline; baseline o dataset ilegible, ids duplicados y artefacto fuera de la raíz dan `unknown` en vez de romper el informe; `--check-report` valida la forma del informe, no colapsa datasets homónimos, emite `::warning::` con `unknown` y respeta `SAVIA_GATE_UNKNOWN=block`; el comentario de la PR escapa nombres del repo.
