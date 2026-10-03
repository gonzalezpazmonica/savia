---
version_bump: patch
section: Fixed
---

### Fixed

- savia-dual: el proxy ya no reenvía credenciales a Ollama, no cae a local ante 4xx ni en rutas distintas de POST /v1/messages, retransmite en streaming y señala los streams cortados, y solo escucha en loopback; el instalador exige doble opt-in para servicio y shell rc, rechaza argumentos desconocidos y nunca deja local_model vacío

