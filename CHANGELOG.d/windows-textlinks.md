---
version_bump: patch
section: Fixed
---

### Fixed

- Windows: los 15 enlaces del repositorio (`.opencode/hooks`, `.opencode/skills`, `skills`, contratos BATS…) se extraían como ficheros de texto con `core.symlinks=false` y todos los hooks fallaban con "Not a directory". Nuevo `scripts/windows-links.sh check|repair`: directorio → junction, fichero → hard link, destino leído del índice y confinado al repositorio, `skip-worktree` para mantener `git status` limpio y reapuntado de junctions que apuntaban a otro clon. Se ejecuta en SessionStart, en `install.ps1` y tras `/update install`; no-op fuera de Windows.
