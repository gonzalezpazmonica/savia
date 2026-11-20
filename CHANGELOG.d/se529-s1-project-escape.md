---
version_bump: patch
section: Security
---

### Security

- memory-store: el campo project se escapa al escribir la línea JSONL; un valor con comillas ya no inyecta claves (p. ej. valid_to) en el almacén permanente.

