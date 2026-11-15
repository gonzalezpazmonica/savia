---
version_bump: minor
section: Changed
---

### Changed

- soul doctor en macOS (y Windows) prueba el almacén de credenciales con un elemento de prueba en vez de darlo por bueno, comprueba ~/Library/LaunchAgents y explica la falta de VPN (SE-490); un paso que no responde mata su proceso y doctor devuelve el control; un almacén que no borra es FALLO; LaunchAgents bloqueado es AVISO (el arranque automático es opcional)
