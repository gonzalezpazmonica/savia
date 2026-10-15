---
version_bump: patch
section: Changed
---

### Changed

- SE-436: con proveedor en la nube, el motor no puede leer cúpulas N3, N4 o N4b (se deniega sin pregunta); las de N2 piden confirmación y dejan recibo, también por las tools `vault_*`. Spec, sin código.
- SE-431: con perfil en la nube, Soul nunca envía contenido N3+ y solo envía N2 con confirmación y recibo; el Relay va por la app móvil de Savia Space.
- SE-429: A2A apagado por defecto y sin notificaciones push A2A en 0.4.
- SE-435: los paquetes y releases públicas (D2–D4) van al final; `savia-space setup` (D1) sigue primero.
- SE-406: aparcada; los avisos van por la app móvil de Savia Space.
