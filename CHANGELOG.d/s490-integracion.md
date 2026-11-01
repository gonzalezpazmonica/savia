---
version_bump: minor
section: Added
---

### Added

- SE-490 integración: el núcleo registra los adaptadores reales que activa el operador (connectors.enabled; nada por defecto, web solo si se nombra).
- Un único almacén de credenciales con índice: revoke borra caché delta y tokens de todas las variantes, uninstall borra los de todos los adaptadores y el perfil web.
- Canal: DPoP verificado con la clave del móvil ligada en el primer uso, correcciones ligadas al dispositivo (corrections, undo-device), tokens con caducidad y límites de conexión.
- Estado de atención de la API persistente por operador y compartido con soul mode; cursor estable entre reinicios.
- soul init y soul login; guía de instalación local para cualquier operador y prueba de punta a punta.

