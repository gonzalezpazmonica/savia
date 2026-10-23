---
version_bump: patch
section: Changed
---

### Changed

- Las plantillas de skill (`_template`, `_template_python`) salen de `.claude/skills/` a `templates/skills/`: el cliente ya no las descubre como skills (menos tokens por sesión) y no incumplen el estándar de nombre. Referencias, tests e índices actualizados; entropía de capacidades 1623 → 1619; el baseline se queda en 1623 a propósito (margen reservado a las dos skills en cola).

