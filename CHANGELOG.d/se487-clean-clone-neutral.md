---
version_bump: patch
spec: SE-487
section: Security
---

### Security

- SE-487 R1-R3: los ficheros versionados que se cargan al arrancar (CLAUDE.md, sus @imports, AGENTS.md, .opencode/CLAUDE.md, docs/critical-facts.md) ya no llevan identidad ni rutas de ninguna persona; generate-critical-facts.sh no lee el perfil local; nueva guardia scripts/clean-clone-guard.sh en la CI de PR y en validate-ci-local.sh.

