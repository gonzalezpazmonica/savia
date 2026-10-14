---
version_bump: minor
section: Fixed
---

### Fixed

- savia-gates: el contexto que los hooks de `UserPromptSubmit` añaden al prompt ya no se envía a un proveedor de nube. Sin nivel declarado cuenta como N3; solo se adjunta si `SAVIA_GATES_ENGINE_LANE` no dice nube y todos los proveedores del turno están en `SAVIA_GATES_LOCAL_PROVIDERS`. El contexto declarado `N1` (`saviaLevel`) se adjunta siempre. Se registra `prompt-context-withheld`.
- savia-gates: el registro de auditoría sigue `SAVIA_AUDIT_DIR` en cada escritura, no solo al cargar el módulo.
