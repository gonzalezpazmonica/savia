---
version_bump: patch
section: Security
---

### Security

- credential-egress: `run` entrega el secreto por /dev/fd/N y la clave del store va a openssl por descriptor (`-pass fd:3`); el valor y la clave ya no aparecen en /proc/<pid>/cmdline. Blobs del formato anterior se migran a `v2:` al resolverse.

