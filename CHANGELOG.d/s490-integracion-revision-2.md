---
version_bump: patch
section: Security
---

### Security

- soul-continuity: el verificador DPoP falla cerrado sin huella ligada; serve registra (una vez por dispositivo) los rechazos por falta de clave ligada o token caducado y soul devices marca los que hay que volver a emparejar.
- soul-continuity: connectors.bases de Graph y Google solo admite sus hosts oficiales o loopback, para que quien edite config.json no desvíe sus tokens.
- soul-continuity: deshacer un dispositivo conserva la atribución del estado previo puesto por otro dispositivo; el estado de atención valida el modo al restaurar y no se reescribe si no cambió.

