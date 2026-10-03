---
version_bump: patch
section: Fixed
---

### Fixed

- epistemic-humility: el hook anti-adulación Layer 1 (sycophancy-strip.sh) no detectaba nada en producción porque escaneaba el sobre JSON de Claude Code en vez del texto del subagente; ahora extrae tool_response (cadena, bloques content[] o output), pasa el borrador por stdin (borradores >128 KB), registra FAIL_OPEN y NO_TEXT, y cubre '¡Buena pregunta!', 'Por supuesto.' y aperturas en negrita sin falsos positivos con 'Absolutamente todos…'.

