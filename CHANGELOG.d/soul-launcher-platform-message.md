---
type: fix
scope: soul-continuity
spec: SE-490
---

El mensaje de instalación del lanzador usa rutas POSIX cuando la plataforma
solicitada es Linux, también al ejecutar sus pruebas desde Windows. Conserva
las comprobaciones negativas de selección de Node y no cambia la ruta Windows.
