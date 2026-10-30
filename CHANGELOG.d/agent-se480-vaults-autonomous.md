---
version_bump: minor
section: Added
---

### Added

- savia-vaults: RAG autónomo (SE-480). El MCP y A2A releen el registro de cúpulas al cambiar (recarga en caliente, conserva el último válido si el fichero es inválido y expone registry.error), serve --transport a2a --rag-autosync <min> sincroniza el índice de las cúpulas habilitadas con el lock existente (alerta autosync-failing tras 3 fallos) y deploy/savia-vaults.service con Restart=always

- savia-vaults: el estado del autosync se persiste en el rag-home (autosync-state.json); `vault_rag_status`, `rag status` y `/health` de cualquier proceso muestran `autosync-failing`. Las variables SAVIA_VAULTS_RELOAD_MS y SAVIA_RAG_AUTOSYNC_DELAY_MS no numéricas usan el valor por defecto
