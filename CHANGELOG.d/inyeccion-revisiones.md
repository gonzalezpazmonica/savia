---
version_bump: patch
section: Security
---

### Security

- El registro de revisiones de `merge-sprint.sh` (S-MS1) aceptaba identificadores con comillas y otros caracteres: un informe bien elegido podía añadir campos a la línea, hacer constar a la autora como revisora o dejar un APPROVE donde había un rechazo. Ahora `reviewer` y `author` solo admiten `[A-Za-z0-9._-]` en ASCII, la línea se codifica con un codificador JSON y, si el registro no se puede escribir, la orden falla sin anunciar «registrada». La suite que lo demostraba sale de `tests-pending/` y se activa: contra el ejecutor anterior fallaban 6 de 8.
