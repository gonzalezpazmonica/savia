---
version_bump: patch
section: Fixed
---

### Fixed

- ast-comprehend.sh: el JSON incluye por fin la estructura extraída (clases, funciones, imports), el fallback grep funciona sin gawk y escapa JSON, meta.tool dice la verdad, complejidad 0 sin errores, exit 1/2 en target inexistente o argumento inválido, escritura --output atómica; un fichero ilegible sale con exit 3 y structure.error=unreadable en vez de un éxito vacío; --output a un directorio se rechaza. SKILL.md enlaza y documenta el script.

