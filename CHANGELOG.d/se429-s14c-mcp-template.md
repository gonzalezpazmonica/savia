---
version_bump: patch
section: Added
---

### Added

- mcp-templates: ficha `savia-space` desactivada en `.opencode/mcp-templates/` para registrar Savia Space como servidor MCP local (SE-429 S14c, parcial). Scope por defecto de solo lectura, token leído de un fichero 0600 y no del repositorio, y bloque equivalente para Claude Code en el comentario. Queda marcada como bloqueada hasta que exista el subcomando `savia-space mcp`; `opencode.json` no se modifica.
