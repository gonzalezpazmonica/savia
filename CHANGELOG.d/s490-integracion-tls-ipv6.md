---
version_bump: patch
section: Fixed
---

### Fixed

- soul-continuity: la identidad del servidor se comprueba contra los SAN IP del certificado con X509Certificate.checkIP; en Node 22.23.2/22.23.3 tls.checkServerIdentity rechazaba ::1 aunque estuviera en los SAN. La validacion TLS sigue activa y es fail-closed.

