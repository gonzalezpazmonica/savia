---
version_bump: patch
section: Fixed
---

### Fixed

- Guard block-gitignored-references (port TS de OpenCode): aplica la regla de referencias a proyectos del hook bash y permite un proyecto autorizado por la operadora (línea exacta en .claude/.project-authorizations del repo del fichero editado), con fallo cerrado. El hook de commit protect-project-privacy bloquea también un git mv hacia un proyecto no whitelisteado; tests que demuestran que sed -i o tee sobre .gitignore se paran al commitear.

