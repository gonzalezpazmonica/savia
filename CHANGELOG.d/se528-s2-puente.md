---
version_bump: minor
section: Security
---

### Security

- SE-528 S2: el puente solo acepta credenciales por la cabecera Authorization o por una sesión opaca en cookie HttpOnly; ?token= y similares responden 401 desde la entrega.
- Puente sin token configurado y sin modo abierto: fallo cerrado (401 registrado, sin contar en el límite); --no-auth solo arranca en bucle local.
- CSRF/CORS, Host permitido y límite de intentos por cliente (X-Forwarded-For solo desde proxies de confianza).
- savia-web deja de guardar el token en cookies legibles: sesión por cookie del puente o token solo en memoria; los enlaces antiguos con credencial llevan al formulario con la razón.
- La cookie de sesión solo se emite si la web es https y del mismo host que el puente (la web lo comprueba también); entre sitios distintos, token en memoria. Un login simultáneo a revocar o rotar el token ya no obtiene sesión.
- Cabecera Authorization vacía: 401 contabilizado, nunca cae a la cookie. Origen https://[::1] admitido por defecto. /auth/session cuenta cookies inválidas en el límite.
- GET /logs?type=server exige rol admin y el log de arranque ya no escribe el token completo.
- Cambio incompatible: --no-auth exige --host de bucle local (127.0.0.1, ::1 o localhost); con el host por defecto (0.0.0.0) sale con código 2.
