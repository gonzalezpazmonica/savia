---
version_bump: patch
section: Fixed
---

### Fixed

- S03n, primer slice: focal-checkin conserva los campos del estado, serializa lectura y escritura y propaga errores de bloqueo y persistencia. Rechaza argumentos inválidos y excluye cambios futuros de la ventana de carga. Pruebas de comportamiento y comparación de 14 mutantes ejecutados; no certifica el grupo completo.
