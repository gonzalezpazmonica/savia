---
version_bump: patch
section: Fixed
---

### Fixed

- labs-preregister.sh acepta cualquier linea `L<n>` (n entero positivo) y la comprueba contra labs/ROADMAP.md de la cupula; linea inexistente, Labs ausente o ROADMAP ausente fallan cerrados con mensaje claro (antes rechazaba todo lo que no fuera L1-L19)
- labs-preregister.sh ya no traga el fallo del commit: si el commit en Labs falla sale con codigo distinto de 0 y lo dice, en vez de informar exito sin registro
- Tests propios en tests/bats/test-labs-preregister.bats con un repo de Labs simulado
