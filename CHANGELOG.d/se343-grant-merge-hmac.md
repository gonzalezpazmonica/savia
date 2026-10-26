---
version_bump: patch
section: Security
---

### Security

- SE-343 (P1): `operator-grant.sh grant --scope merge` exige prueba de persona (terminal de la operadora o ticket de un solo uso del diálogo del arnés vía `operator-grant.sh guard`) y firma el grant con HMAC-SHA256; `check` rechaza grants de merge sin firma válida. LAW-HUMAN-002 deja de satisfacerse sin la operadora.

