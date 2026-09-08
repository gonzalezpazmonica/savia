---
version_bump: patch
section: Fixed
---
- **Era 250 · skill discovery**: corrige seis frontmatters YAML inválidos y añade validación global para impedir regresiones de carga.
- **SE-396 I01**: reserva ejecuciones antes del efecto, evita reejecutar retries ambiguos y confirma journal/liberación en una sola transacción durable.
- **OpenCode Shield**: ejecuta el gate HTTP local con autenticación, timeout y bloqueo fail-closed; una configuración asíncrona ya no puede degradar el control de autorización.
