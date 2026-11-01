---
version_bump: minor
section: Added
---

### Added

- SE-490 · adaptador web de Soul Continuidad (projects/soul-continuity/src/web): formato soul-receta-web/1 con validador, cortafuegos de tres capas sobre playwright-core y el Chrome o Edge instalado, perfil dedicado persistente sin gestor de contraseñas, vigilancia de «página cambiada» sin receta, recetas experimentales de Outlook, Teams y OneDrive/SharePoint en la web desactivadas hasta validarlas contra el tráfico grabado del operador, batería AC-4e con 22 mutantes (cada uno muere solo por una comprobación de su defensa) y el `SourceAdapter` `web` del contrato compartido (afirmaciones `web:*`, estados `session_expired`/`recipe_disabled`, fail-closed). Endurecido tras revisión independiente: recetas validadas en la frontera del adaptador, `estable` sin recibo solo en el banco local, endpoints de operaciones solo por `POST` con la operación de la URL cotejada, huellas de vigilancia confirmadas solo si el adaptador entrega y fallos de red como `error` transitorio. Segunda revisión: `soloConsultas` tokeniza GraphQL en una pasada (un comentario con comilla ya no esconde una mutación), la URL concreta se coteja con los verbos de acción y el comodín no cruza separadores codificados, la exención de recibo de las `estable` locales solo la da el código del banco, huella de receta canónica, páginas vigiladas con HTTP de error y almacén de huellas ilegible como `error`, y lockfile del adaptador versionado.

