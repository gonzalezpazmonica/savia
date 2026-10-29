---
version_bump: patch
section: Fixed
---

### Fixed

- agent-dispatch-validate (perfil strict): un encargo de solo lectura que mencione CHANGELOG, commands, skills o rules ya no se bloquea si el prompt empieza con la marca explícita `[solo-lectura]` o `[read-only]`. Sin la marca se aplican todas las reglas. La intención ya no se deduce de los verbos del texto: con una lista de verbos de escritura siempre faltaba alguno y el hook fallaba en abierto.
