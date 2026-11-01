---
version_bump: patch
section: Fixed
---

### Fixed

- SE-490 Soul Continuidad: el almacén de credenciales de los adaptadores en Windows usa Credential Manager (advapi32 por PowerShell, sin módulos nativos ni PasswordVault) y reparte el valor en varias entradas, así que los tokens de Entra (más de 5 KB) caben; prueba real en el job de Windows de la CI.

