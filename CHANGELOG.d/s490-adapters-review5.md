---
version_bump: patch
section: Fixed
---

### Fixed

- SE-490 adaptadores (quinta revisión): los tests del almacén de credenciales pasan en Windows (dobles .cjs lanzados con Node; SecretToolBackend acepta commandArgs).
- SE-490 AADSTS65001 se clasifica como no_credential (nuevo inicio de sesión) en vez de admin_consent_required, sin guardar una marca de administración falsa.
- SE-490 GitHub devuelve unavailable si lo recogido no llega a total_count (la búsqueda trunca en 1000).
- SE-490 la caché delta valida tipos y ausencia de cuerpos al cargar; el correo descarta una caché con otra forma y resincroniza, y un mensaje recibido sin fecha legible falla cerrado.
- SE-490 el transporte rechaza %2f y %5c en la ruta.

