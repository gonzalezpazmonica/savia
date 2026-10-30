---
version_bump: minor
section: Added
---

### Added

- Onboarding adaptativo (SE-484): catálogo de capacidades `docs/onboarding/capabilities.yaml` con esquema y motor determinista `scripts/onboarding-plan.py` (present, questions, plan, apply); simulación sin confirmación, reentrada que solo propone cambios y escritura limitada al directorio de perfiles ignorado por git.
- `profile-onboarding.md` describe el protocolo adaptativo y referencia la fuente única de identidad (SE-483) sin copiarla; sin emojis.
- Plantilla de perfil: claves nuevas en `preferences.md` (capacidades, proveedores, prerregistro, confidencialidad, papel docente, vertical, dominios) y `workflow.md` (lenguajes).

- `/profile-setup` y `/onboard` pasan la interpretación por stdin (`--input -`) y no la escriben en disco; el motor rechaza un `--profile-dir` que sea un enlace, sale con código 5 (sin traza) ante errores de E/S o bytes no UTF-8, limpia el temporal si falla la sustitución, conserva los permisos del fichero y añade una clave ausente aunque su valor coincida con el default.
