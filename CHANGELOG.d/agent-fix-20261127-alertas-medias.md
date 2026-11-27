---
version_bump: patch
section: Fixed
---

### Fixed

- Alertas medias reales de code scanning (triaje SE-442, SE-465 S1-S4): imagen de contención fijada por digest (#71); `npm ci` contra el lock en `install.sh` y `.opencode/install.sh` (#79, #81); OpenCode y Claude Code con versión exacta (#80, #95); savia-vaults se instala desde la fuente con su lock en vez de un nombre sin publicar, y su instalador define `SCRIPT_DIR` (#83); Ollama ya no se instala con `curl | sh`: instalador de una etiqueta fija verificado por SHA-256 en `scripts/lib/verified-installer.sh` (#84, #93, también `setup-savia-dual.sh`); OpenCode v1 sin `opencode.ai/install | bash`, por npm con versión (#89); Presidio con `--require-hashes` contra `scripts/requirements/shield-presidio.lock.txt` (#94); el servidor HTTP del firmware zeroclaw escucha solo en la IP STA y exige `http_token` en `/status` y `/cmd` (#25); `SECURITY.md` enlaza el reporte privado de vulnerabilidades (#59).
