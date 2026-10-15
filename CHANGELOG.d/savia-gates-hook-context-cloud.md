---
version_bump: minor
section: Fixed
---

### Fixed

- savia-gates: el contexto que los hooks de `UserPromptSubmit` añaden al prompt ya no se envía a un proveedor de nube. Sin nivel declarado cuenta como N3; solo se adjunta si `SAVIA_GATES_ENGINE_LANE` no dice nube y todos los proveedores del turno (incluidos los modelos de los agentes internos `title`, `summary` y `compaction`) están en `SAVIA_GATES_LOCAL_PROVIDERS`. El contexto declarado `N1` (`saviaLevel`) se adjunta siempre. Se registra `prompt-context-withheld`.
- savia-gates: el registro de auditoría sigue `SAVIA_AUDIT_DIR` en cada escritura, no solo al cargar el módulo.
- savia-gates: la configuración del motor se consulta solo si hay contexto que filtrar y con un límite de 3 s; si no responde, el turno cuenta como nube.
