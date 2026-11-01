---
version_bump: patch
section: Security
---

### Security

- SE-490 adaptadores: la identidad del remitente solo cuenta la cabecera Authentication-Results del receptor (authserv-id exigido en Gmail), los enlaces de paginación //host o /\host y un delta manipulado en caché ya no sacan el token a otro host, un 403 de GitHub por límite es unavailable y revocar comprueba el borrado y aclara que la concesión del proveedor sigue vigente.

