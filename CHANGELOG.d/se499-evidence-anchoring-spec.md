---
version_bump: patch
section: Added
---

### Added

- Spec SE-499 (PROPOSED): las cadenas de evidencia por hash de merge-sprint, del Effect Ledger (SE-493) y de Yema dejan de verificarse solo contra sí mismas. Propone un punto de anclaje común, un verificador que da FAIL si la cadena se ha reescrito, truncado o borrado respecto de un ancla, tres transportes con su coste (comentario en un issue de anclas, rama protegida en un repo privado, firma de la operadora con clave fuera del equipo), un registro de altas en `origin/main` que impide bajar de FAIL a UNANCHORED ocultando el ancla, y el texto que declara el límite mientras tanto. Solo la spec, con un comprobador de su coherencia interna.

