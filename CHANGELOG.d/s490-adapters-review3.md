---
version_bump: patch
section: Fixed
---

### Fixed

- SE-490 adaptadores (tercera revisión): GitHub identifica cada elemento por owner/repo#n; dos organizaciones con un repositorio homónimo ya no se fusionan en silencio.
- SE-490 Teams resuelve el id de Entra con GET /me (permiso Chat.Read + User.Read) si no llega params.m365_user_id, y falla cerrado con error si no puede; antes daba ok con cero menciones contra Graph real.
- SE-490 correo M365: los enviados se fechan por sentDateTime y un enviado sin fecha legible falla cerrado, en vez de dejar abierta una espera ya respondida.
- SE-490 OAuth: AADSTS65004 (la persona rechazó el consentimiento) pasa a no_credential, no a admin_consent_required.
- SE-490 transporte: el POST de lectura exige la ruta de la base (no otra organización del mismo host) y la respuesta tiene un tope de 16 MiB.
- SE-490 Google: las direcciones de From/To/Cc se separan respetando comillas, comentarios y <>.
- SE-490 almacén de credenciales: dos lecturas simultáneas comparten una sola renovación del token.

