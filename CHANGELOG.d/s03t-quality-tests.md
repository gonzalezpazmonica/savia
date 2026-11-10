---
version_bump: patch
section: Security
---

### Security

- dynamic-web-security-test: la primera línea del fichero de autorización debe ser exactamente `AUTHORIZED`, igual que en network-recon; «UNAUTHORIZED», «NOT AUTHORIZED», «NOT YET AUTHORIZED» o «AUTHORIZED by owner» ya no autorizan el escaneo, y una autorización con fecha futura ya no es eterna (S03t).
- engagement-separation-proof: `client:acme-corp` dentro del espacio de `acme` se detecta como contaminación (antes pasaba por coincidencia de prefijo); `verify --json` ya no devuelve `verified:true` con contaminación; `all` ya no da «SEPARATION INTACT» si una prueba no se puede leer (fail-closed, nuevo campo `parse_errors`); `all` sin engagements activos da `separation_intact:false` y exit 1; el slug se compara literalmente (no como regex) y los nombres llegan a Python por argv (sin inyección con comillas).
- engagement-wall-check: una etiqueta de otro cliente detrás de la propia en memoria de engagement, perfiles, federación o artefactos ya cuenta como violación, y en semántica, grafo, cúpulas y briefs una etiqueta de cliente sin engagement detrás de una conocida también (antes solo se miraba la primera etiqueta).
- docs-identity-check, wall-check, separation-proof y dynamic-web: pruebas de comportamiento S03t en árbol aislado (4 ficheros de test bajo 80).
