---
category: Fixed
spec: SE-037
---
- Corrige el benchmark de hooks para seguir el enlace simbólico canónico de
  `.opencode/hooks` y fallar explícitamente cuando no descubre ningún hook, en
  lugar de generar un PASS vacío.
- Cruza la convención de hooks críticos con los eventos realmente registrados,
  impide reutilizar informes antiguos si el benchmark falla y restaura a 5 la
  última baseline válida anterior al cambio defectuoso de universo de medición.
