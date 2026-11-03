---
version_bump: patch
section: Security
---

### Security

- soul-continuity: la API ya no liga la clave DPoP en el primer uso (un dispositivo sin clave ligada debe volver a emparejarse), DEVICE_REVOKED solo se responde tras una prueba válida y un fallo en el tic de refresco no tumba serve.

