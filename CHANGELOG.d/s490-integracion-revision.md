---
version_bump: patch
section: Fixed
---

### Fixed

- SE-490 integración al día con main (#1442, #1443): almacén único con la renovación única de main; banco del núcleo con m365_user_id para Teams.
- El almacén único relee tras guardar y tras borrar: un llavero que trunca o un Credential Manager que no borra ya no pasan en silencio.
- El adaptador web arranca solo el navegador de SOUL_NAVEGADOR o de las rutas conocidas, nunca el de config.json.
- Restaurar attention-state.json con campos mal tipados conserva los de la semilla en vez de dar 503; serve avisa una vez de un attention.json sin «at»; franjas de presupuesto cacheadas.

