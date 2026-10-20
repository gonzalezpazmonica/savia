---
version_bump: patch
section: Fixed
---
- savia-gates en OpenCode 1: `chat.message` entregaba a los hooks de `UserPromptSubmit` el registro del mensaje (sin texto) en lugar de lo escrito, así que un hook de prompt nunca veía el texto (comprobado contra OpenCode 1.19.3: un prompt vetado llegaba al modelo). Ahora se lee de las partes `text` no sintéticas.
- `install.sh` / `install.ps1` instalaban `@opencode-ai/cli`, que no es OpenCode (`0.0.0-beta`): los paquetes son `@opencode/cli` (OpenCode 2) y `opencode-ai` (OpenCode 1). `opencode-install.sh` usaba `npm install opencode@…`, tampoco válido, y registraba `"plugin": ["savia-gates"]` (nombre de paquete npm, no el directorio enlazado).
- `scripts/agent-hook-runner.sh` llamaba a `opencode run --no-interactive`, opción que no existe ni en OpenCode 1 ni en 2 (en 1 `run` ya es no interactivo). En OpenCode 2 usa `--standalone`: sin él `run` habla con el servicio en segundo plano de la usuaria (49374).
- `.opencode/package.json` y `savia-gates/package.json`: el SDK de plugins (`@opencode-ai/plugin`, `@opencode/plugin`) es peer opcional; solo aporta tipos y el anfitrión no debe instalar nada para cargar el plugin.
- `scripts/opencode-migration-smoke.sh`: acepta OpenCode 1 >= 1.18.29 y 2, explica que `opencode upgrade` no cruza de versión mayor, y en OpenCode 2 cuenta agentes y comandos desde los ficheros (su `debug agents` arranca el servicio en segundo plano). Si OpenCode 1 rechaza `opencode.json` por usar claves V2 (`permissions`), lo dice.
