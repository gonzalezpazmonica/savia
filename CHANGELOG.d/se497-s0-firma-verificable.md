---
version_bump: patch
section: Security
---

### Security

- SE-497 S0: `learning-lifecycle.sh` deja de aceptar texto libre como firma humana. `--human-trailer` debe casar entero con `sha:<40 hex>` o `se488:<id>` y se valida antes de tocar el fichero; un valor con salto de línea o metacaracteres ya no reescribe la lección ni ejecuta órdenes. La cabecera se edita y el registro se codifica sin interpolar argumentos (antes, `sed` y concatenación). `canary → active` exige las dos métricas numéricas y sale con 5 si faltan o hay regresión. Repetir una transición sin efecto no añade fila. Las lecciones ya activas con firma antigua se siguen leyendo. Límite: el formato no prueba que firme una persona; eso queda para S5 y S6.
