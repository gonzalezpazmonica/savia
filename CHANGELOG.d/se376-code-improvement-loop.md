---
version_bump: patch
section: Fixed
---

### Fixed

- code-improvement-loop: coherence-court.sh valida enteros antes de evaluar (cerraba ejecución de órdenes vía subíndice aritmético en score/gate/umbrales), rechaza flujos con '/' (escritura fuera del directorio de premisas) y escapa el YAML del skeleton; savia-double-optin-check.sh resuelve operator-grant.sh y el audit log desde la raíz del repo (un script plantado en el cwd concedía el factor de intención). 26 tests nuevos; 25/25 mutantes muertos.

