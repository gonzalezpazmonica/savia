---
version_bump: patch
section: Fixed
---

### Fixed

- El guard de firmantes del grant de fusión ya no bloquea un heredoc de `cat` o `python3 -` que solo contiene llaves o comodines como datos. La poda es una lista cerrada: delimitador entre comillas y un solo heredoc por línea, lector por su nombre desnudo, imports de python3 de una lista cerrada y sin indirección (el cuerpo se analiza con `ast`: ni `from pathlib import os`, ni `pathlib.os`, ni llamadas de proceso por alias), y ninguna otra orden fuera de los cuerpos. Cualquier otra forma se analiza entera, como antes. Nueva medición de decisiones (allow y block, con código de motivo y sin la orden) en output/guard-decisions/, y las suites del guard corren en CI. La medición se registra en un subshell después de decidir, así que no puede cambiar la decisión del guard; su librería pasa a gobernanza (tier 4) y no sigue enlaces simbólicos, tampoco en `output/`.
