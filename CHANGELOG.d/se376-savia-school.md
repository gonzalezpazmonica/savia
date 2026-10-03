---
version_bump: patch
section: Fixed
---

### Fixed

- savia-school: las evaluaciones cifradas ahora se pueden descifrar (antes el IV se perdia y una clave ausente cifraba con ceros), evaluate y forget llaman al script de seguridad correcto, forget y check-isolation rechazan alias con traversal, carpetas en 0700 y auditoria 0600 sin contenido (SE-376).

