---
version_bump: patch
section: Security
---

### Security

- SE-528 S3: la clave de firma de autorizaciones de las cúpulas solo se crea si no existe; cualquier otro error de lectura o una longitud inválida falla cerrado, se registra con el código del sistema y no rota la clave (503 KEY_UNAVAILABLE en HTTP).

