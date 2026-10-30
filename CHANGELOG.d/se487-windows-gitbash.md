---
version_bump: patch
section: Fixed
---

### Fixed

- Windows (SE-487 R4): `install.ps1` localiza `bash.exe` de Git for Windows (Program Files, x86, LOCALAPPDATA, derivado de `git.exe`), fija `CLAUDE_CODE_GIT_BASH_PATH` (usuario) si Claude Code no lo encontraría por PATH y falla con un mensaje claro si no existe. README (todos los idiomas) y CLAUDE.md explican el error «Git Bash wasn't found».

