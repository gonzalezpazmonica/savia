---
version_bump: patch
section: Fixed
---

### Fixed

- El guard de firmantes del grant de fusión ya no bloquea un heredoc de python3 o cat que solo contiene llaves o comodines como datos; sigue bloqueando cualquier escritura real en los firmantes y los heredocs que ejecuta un shell. Nueva medición de decisiones (allow y block, sin la orden) en output/guard-decisions/.

