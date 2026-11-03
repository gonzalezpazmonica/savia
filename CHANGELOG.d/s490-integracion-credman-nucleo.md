---
version_bump: patch
section: Fixed
---

### Fixed

- SE-490 Soul Continuidad: con el almacén único de credenciales, el backend de Windows del núcleo reparte el valor en varias entradas de Credential Manager con cabecera y hash (como #1450 hacía en el adaptador), así que los tokens de Graph de más de 5 KB caben también cuando los adaptadores guardan por keyed().

