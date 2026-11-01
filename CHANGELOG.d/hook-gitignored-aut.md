---
version_bump: patch
section: Fixed
---

### Fixed

- Guard block-gitignored-references (hook bash de Claude Code y port TS de OpenCode): permite un proyecto autorizado por la operadora (línea exacta en .claude/.project-authorizations del repo del fichero editado), con fallo cerrado. El port TS gana la regla de referencias a proyectos, que no tenía, y usa la whitelist del workspace si el repo del fichero no declara ninguna. El hook de commit protect-project-privacy bloquea también un git mv hacia un proyecto no whitelisteado y compara nombres como literales (grep -F); tests que demuestran que sed -i o tee sobre .gitignore se paran al commitear.

