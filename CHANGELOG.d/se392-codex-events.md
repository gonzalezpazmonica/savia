---
version_bump: minor
section: Added
---

### Added

- SE-392 S3: codex-hook.py despacha los 12 eventos de Codex a los handlers de settings.json con la semántica de savia-gates en OpenCode (bloqueo solo en PreToolUse/UserPromptSubmit, PermissionRequest solo deniega, ciclo de vida consultivo, async desacoplado, contexto solo N1). El stdout en texto plano de un evento no autoritativo deja de bloquear en ambos núcleos: SessionStart en OpenCode ejecuta ya sus 6 hooks.

