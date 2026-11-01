---
version_bump: minor
section: Added
---

### Added

- SE-490 emparejamiento directo app ↔ Soul (soul-pair-v1): soul pair abre una ventana de 10 min con código de un solo uso; challenge/complete con HMAC del código sobre nonces y SPKI; el dispositivo queda ligado a su clave al emparejar; PAIR_EXPIRED/BAD_PROOF/LOCKED/RATE; vectores comunes con la app.
- La API decide con Politica de src/attention (H-11) y persiste su estado con estadoATexto.
- Sondeo: cursor de otra época da 410 y los ids de mensaje no se repiten entre reinicios (D4, D5); Q3 sin lectura anterior usa la primera guardada (D6); proyectos, personas y reglas de alerta salen de los adaptadores y del perfil (D8).
- DPoP exige coordenadas canónicas; H-5 exige el socket del bus.

