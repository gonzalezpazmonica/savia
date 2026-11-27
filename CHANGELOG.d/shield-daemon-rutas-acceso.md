---
version_bump: patch
section: Fixed
---

### Fixed

- El daemon del Shield solo lee, para la detección de credencial partida, ficheros cuya ruta resuelta con `realpath` queda dentro del workspace (relativas, `..` y enlaces simbólicos incluidos), y ya no arranca en acceso abierto: crea el token 0600 si falta y, si no puede, se niega a arrancar. Cierra las alertas CodeQL #30, #31 y #32 (py/path-injection)
