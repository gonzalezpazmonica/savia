---
version_bump: patch
section: Security
---

### Security

- dynamic-web-security-test: un fichero de autorización «UNAUTHORIZED» o «NOT AUTHORIZED» ya no autoriza el escaneo, y una autorización con fecha futura ya no es eterna (S03t).
- engagement-separation-proof: `client:acme-corp` dentro del espacio de `acme` se detecta como contaminación (antes pasaba por coincidencia de prefijo); `verify --json` ya no devuelve `verified:true` con contaminación; `all` ya no da «SEPARATION INTACT» si una prueba no se puede leer (fail-closed, nuevo campo `parse_errors`).
- engagement-wall-check: una etiqueta de otro cliente detrás de la propia en memoria de engagement, perfiles, federación o artefactos ya cuenta como violación (antes solo se miraba la primera etiqueta).
- docs-identity-check, wall-check, separation-proof y dynamic-web: pruebas de comportamiento S03t en árbol aislado (4 ficheros de test bajo 80).
