---
version_bump: minor
section: Changed
---

### Changed

- SE-510 S3 (parcial): despachador PreToolUse con fallo cerrado y tabla de despacho generada desde settings.json (AC-5, AC-6); sin registro en settings.json ni modo sombra

- SE-510 S3: tras revisión, el despachador evalúa el matcher como regex (el guard MCP vuelve a dispararse), bloquea ante un matcher inválido o el modo `source`, no expande globs en los argumentos, ejecuta una vez cada comando y deja los no bloqueantes al final; el generador lleva `async: true` a `bloqueante=no` y rechaza matchers y comandos con metacaracteres
