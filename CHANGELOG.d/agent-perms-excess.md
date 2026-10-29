---
version_bump: patch
section: Fixed
---

### Fixed

- validate-agent-permissions.sh detecta herramientas por encima del nivel L0-L4 (antes solo las que faltaban, exit 0 con exceso). Línea base transitoria con responsable y caducidad (2026-11-10) para 15 agentes pendientes de decisión. El frontmatter se lee como YAML real y falla en cerrado (YAML inválido, `tools:` ausente, valores no booleanos, sin nivel = L0); la CI de cada PR ejecuta el gate. Corrige el YAML de `memory-agent` y `expertise-asymmetry-judge`, que no era válido.
- Tras la revisión independiente: `memory:` cuenta como `Read`/`Write`/`Edit` implícitos; `Agent` se trata como `Task` y `Tool(args)` como `Tool`; lista de tools vacía = ERROR; herramientas repetidas cuentan una vez; el nivel no puede inyectar registros en el protocolo interno; se validan agentes en subdirectorios; el test del conjunto autorizado lee también la última línea sin salto. PyYAML fijado con hash en el lock de CI y la línea base y su test, en CODEOWNERS.
