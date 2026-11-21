---
version_bump: minor
section: Fixed
---

### Fixed

- SE-510 S2 (parte independiente del resolvedor de gh, separada de #1596): el guard de destino en bash y TS ve git add partido por continuaciones de línea (también CRLF), trata git stage como add y, sin resolvedor, bloquea un ejecutable variable seguido de commit.
- SE-510 S2: paridad de veredictos bash/TS sobre el corpus (guard-corpus --ts, exit 4); una divergencia gana a un bloqueo falso conocido en vez de quedar tapada; lista BEFORE_GUARDS en .opencode/plugins/lib/before-guards.ts y matriz de cobertura que la lee.
- SE-510 S2: registro local de bloqueos (scripts/guard-blocks.sh record|mark|report|wrap) con redacción de credenciales que cruza continuaciones y comillas, motivo por el entorno, log 0600 sin seguir enlaces.
- SE-510 S2: plantilla docs/templates/pr-summary.md y aviso del encabezado exigido en pr-plan; propuesta de rediseño del gate del resumen en docs/propuestas/SE-510-rediseno-resolvedor.md (sin implementar).
