---
version_bump: patch
section: Fixed
---

### Fixed

- Memoria: guardar ya no escribe líneas inválidas (salto de línea en el título, comillas, corte a mitad de carácter), no borra la entrada de un tema al actualizarlo con un contenido que ya tenía otro tema, trabaja bajo cerrojo y escribe de forma atómica; `consolidate` mueve a cuarentena en lugar de borrar; el taint de turno de SE-352 lee el identificador de sesión que da el runtime (`CLAUDE_CODE_SESSION_ID`) y falla cerrado sin él.

