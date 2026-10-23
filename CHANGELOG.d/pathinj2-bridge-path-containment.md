---
version_bump: patch
section: Security
---

### Security

- Savia Bridge contiene bajo el workspace las rutas que llegan del cliente (/files, /files/content, /projects, /backlog, /kanban, /timelog, /approvals): realpath + prefijo con separador; antes ../savia-other/ escapaba (CodeQL py/path-injection).

