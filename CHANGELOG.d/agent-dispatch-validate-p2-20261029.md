---
version_bump: patch
section: Fixed
---

### Fixed

- agent-dispatch-validate (perfil strict): los prompts de solo lectura que mencionan CHANGELOG, commands, skills o rules ya no se bloquean; los que escriben siguen validándose

- agent-dispatch-validate: los verbos de escritura con prefijo (reescribe, sobrescribe, regenera), sin tildes o cortos (pon, set, haz) ya no cuelan un prompt de escritura como de solo lectura
