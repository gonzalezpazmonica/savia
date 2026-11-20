---
version_bump: patch
section: Security
---

### Security

- SE-528 S2b: el puente ya no arranca sin cifrar fuera de bucle local cuando TLS falla (sin openssl o certificado que no carga); sale con código 2 y dice cómo arreglarlo. En bucle local arranca en HTTP con aviso SECURITY. --no-tls explícito no cambia.

