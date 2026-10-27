---
version_bump: patch
section: Fixed
---

### Fixed

- S03m: pruebas de comportamiento para 8 ficheros de test (hooks y scripts); rule-usage-analyzer.sh --output ahora escribe el fichero y learning-capture-hook.sh no descarta capturas con rutas de evidencia inexistentes

- S03m (revisión): rule-usage-analyzer.sh --output falla con exit 2 si la ruta no es escribible; learning-capture-hook.sh fija su locale y conserva evidencias ruta:hash
