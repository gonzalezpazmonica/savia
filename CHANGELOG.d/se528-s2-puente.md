---
version_bump: minor
section: Security
---

### Security

- SE-528 S2: el puente solo acepta credenciales por la cabecera Authorization o por una sesión opaca en cookie HttpOnly; ?token= y similares responden 401 desde la entrega.
- Puente sin token configurado y sin modo abierto: fallo cerrado (401 registrado, sin contar en el límite); --no-auth solo arranca en bucle local.
- CSRF/CORS, Host permitido y límite de intentos por cliente (X-Forwarded-For solo desde proxies de confianza).
- savia-web deja de guardar el token en cookies legibles: sesión por cookie del puente o token solo en memoria; los enlaces antiguos con credencial llevan al formulario con la razón.

