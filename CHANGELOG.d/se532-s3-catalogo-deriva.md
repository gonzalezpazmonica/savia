---
version_bump: minor
section: Added
---

### Added

- SE-532 S3: `pulse catalogo` compara el catálogo de agentes con sus copias y anota en el ledger de Pulse los eventos `catalogo_deriva` (solo nombres, huellas y motivo) y `catalogo_resuelto`; `pulse status` deriva «con deriva», «sin deriva» o «sin datos». El esquema de eventos solo añade tipos; el validador admite `minItems`. No toca agentes ni retirada (S2).

- SE-532 S3 (revisión): `pulse catalogo` rechaza con mensaje claro nombres de agente fuera de `[a-z0-9_-]{1,64}` y más de 200 desajustados; `status` aclara que «sin deriva» cubre solo agentes de nivel superior.
