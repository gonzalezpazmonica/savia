---
version_bump: patch
section: Security
---

### Security

- Alerta #116 (js/polynomial-redos): el guard de rutas protegidas de OpenCode (`savia-gates/lib/shell-targets.ts`) y su gemelo de Codex (`scripts/dual-cli/shell_targets.py`) casan los globs de `find -name` con un matcher lineal sin retroceso. Antes `find .claude -name 'a*a*…*b' -delete` colgaba el guard contra un nombre largo; ahora 30 `*` contra 5 000 caracteres resuelven en milisegundos con las mismas respuestas que la regex anterior.
- El mismo guard falla cerrado cuando el patrón de `find -name`/`-iname` lleva una expansión (`"$PATTERN"`, `${P}.sh`, `$(cmd)`): no se conoce hasta ejecutar, así que cuenta como «alcanza» en vez de compararse como literal. Entre comillas simples el `$` sigue siendo literal.
- `find -name '[]h]ooks' -delete` (y `[!]x]ooks`) ya no salta el guard de OpenCode: como en fnmatch y find, un `]` justo tras `[` o `[!` es literal si otro `]` cierra la clase. Antes TS generaba la clase vacía `[]` y dejaba pasar el borrado, y Python lo rechazaba; ahora los dos gemelos alcanzan la puerta y coinciden con `find` real.

### Fixed

- `savia-gates/lib/v1-adapter.ts`: si `config.get` lanzaba de forma síncrona o no había cliente, el temporizador de 3 s quedaba armado y su rechazo llegaba sin manejador. Era el fallo intermitente de la suite («config.get timeout» en un test ajeno); ahora el temporizador se limpia siempre.
