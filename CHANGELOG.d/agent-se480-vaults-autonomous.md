---
version_bump: minor
section: Added
---

### Added

- savia-vaults: RAG autónomo (SE-480). El MCP y A2A releen el registro de cúpulas al cambiar (recarga en caliente, conserva el último válido si el fichero es inválido y expone registry.error), serve --transport a2a --rag-autosync <min> sincroniza el índice de las cúpulas habilitadas con el lock existente (alerta autosync-failing tras 3 fallos) y deploy/savia-vaults.service con Restart=always

