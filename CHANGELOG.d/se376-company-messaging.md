---
version_bump: patch
section: Fixed
---

### Fixed

- company-messaging calibrada (SE-376): savia-branch.sh ya no traga pushes fallidos (write/ensure-orphan devuelven error) ni pierde mensajes cuando la rama local está obsoleta (base en origin y reintento ante rechazo); send resuelve el directorio en formato tabla con coincidencia exacta y valida handles; inbox ya no aborta (CYAN) ni duplica rutas; read mueve de unread a read sin reentrega; broadcast con IDs únicos; savia-crypto cifra textos con forma de opción, vacío sin leer stdin y descifra por stdin paquetes >128 KB; privacy-check detecta claves PEM (grep -e), se aplica en send/announce y escanea por rama. tests/test-company-messaging.bats (35 tests, auditor 88).

