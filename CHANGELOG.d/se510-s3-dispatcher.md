---
version_bump: minor
section: Changed
---

### Changed

- SE-510 S3 (parcial): despachador PreToolUse con fallo cerrado y tabla de despacho generada desde settings.json (AC-5, AC-6); sin registro en settings.json ni modo sombra

- SE-510 S3: tras revisión, el despachador evalúa el matcher como regex (el guard MCP vuelve a dispararse), bloquea ante un matcher inválido o el modo `source`, no expande globs en los argumentos, ejecuta una vez cada comando y deja los no bloqueantes al final; el generador lleva `async: true` a `bloqueante=no` y rechaza matchers y comandos con metacaracteres

- SE-510 S3: segunda revisión. El despachador pasa la entrada a cada hook por fichero (un hook que sale 0 sin leer una entrada grande ya no provoca un bloqueo falso por SIGPIPE), mata con KILL el grupo del hook que ignora TERM y valida `DISPATCH_HOOK_TIMEOUT` (1..100). El generador sale 2 ante un timeout no numérico, un grupo con forma inesperada, una ruta con `..` o cualquier error imprevisto

- SE-510 S3: tercera revisión. El despachador lee el stdout JSON de cada hook bloqueante: `deny`, `decision:"block"` o `continue:false` bloquean (antes se perdían y, por ejemplo, el deny de merge de `mcp-effect-guard` dejaba pasar la acción); `ask`, `allow`, `updatedInput`, `additionalContext` y `systemMessage` se fusionan en un único JSON y el stdout de los no bloqueantes se descarta. Bloquea también una tabla vacía o truncada (línea de control `# filas=N` que escribe el generador) y una ruta de hook absoluta o con `..`
