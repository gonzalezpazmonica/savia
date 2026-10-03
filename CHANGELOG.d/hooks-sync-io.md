---
version_bump: patch
section: Fixed
---

### Fixed

- Hooks de arranque sin esperas de red: session-init y shield-autostart sondean Ollama y Shield en segundo plano (estado para el siguiente arranque) y ya no retienen stdout con tareas de fondo; pr-summary-gate acota la conexión al proxy LLM a 3 s (respuesta configurable con PR_SUMMARY_LLM_TIMEOUT, 90 s por defecto) y deja de usar un fichero compartido en /tmp; un sondeo de más de 24 h no se anuncia como activo.

