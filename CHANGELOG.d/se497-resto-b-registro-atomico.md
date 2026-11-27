---
version_bump: patch
section: Fixed
---

### Fixed

- SE-497 RESTO-497-b: `learning-lifecycle.sh` ya no cambia una lección si no puede escribir su fila de registro. Antes la transición se aplicaba igual y salía con 0, sin rastro de auditoría; ahora se deshace, la lección queda byte a byte como estaba y sale con 6.
- SE-497 RESTO-497-a: `scl-001-learning-loop.md` y la cabecera del guion dejan de afirmar que ninguna transición a `active` puede originarse en un agente. Lo que S0 entrega es formato verificable del trailer, no autoría: un agente que conozca el formato puede escribirlo, y eso queda para R10 (S5/S6).
