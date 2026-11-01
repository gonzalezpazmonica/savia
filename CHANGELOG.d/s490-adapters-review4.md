---
version_bump: patch
section: Fixed
---

### Fixed

- SE-490 adaptadores (cuarta revisión): integra main tras el squash del núcleo (#1440); el diff contiene solo los adaptadores y no toca banco, contrato ni núcleo.
- SE-490 GitHub usa la clave del contrato <repo>#<n>; una colisión entre propietarios y un 200 con incomplete_results: true devuelven unavailable en vez de datos ambiguos o incompletos.
- SE-490 transporte: la ruta relativa siempre lleva el prefijo de la base (un proyecto de ADO llamado como la organización ya no se pierde), se rechazan segmentos . y .. (también %2e) y ningún método sale fuera de la ruta de la base.
- SE-490 Teams ignora mensajes borrados (deletedDateTime): ni cuentan como mención pendiente ni como respuesta.

