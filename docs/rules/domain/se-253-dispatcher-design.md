# Despachador PreToolUse: contrato de fallo cerrado

> SE-253 S4 (diseño) y SE-510 D3 (contrato). El despachador `hooks/dispatchers/dispatch-pretooluse.sh` lee `hooks/routing-pretooluse.tsv`, que se GENERA desde `.claude/settings.json` con `python3 scripts/dispatch-table.py write`. `check` (y un test) falla si difieren.

## Contrato

Salida 0 (permitir) o 2 (bloquear). Nada más. Un hook bloqueante que sale con cualquier otro código, o cualquier fallo del propio despachador, bloquea con el motivo en stderr (clase POLÍTICA: ante la duda, política).

| Situación | Resultado |
|---|---|
| Tabla ausente o ilegible | 2 |
| stdin vacío, JSON roto o sin nombre de herramienta | 2 |
| Fila de la tabla mal formada, modo distinto de `spawn` o matcher que no es regex válida | 2 |
| Hook bloqueante registrado que no existe | 2 |
| Hook bloqueante con exit distinto de 0 y 2 (incluido 1) | 2 |
| Hook bloqueante que excede el tiempo | 2 |
| Hook no bloqueante que falla | 0, con aviso |

El JSON se parsea una vez; cada hook recibe la misma entrada por stdin. Primero corren los bloqueantes en orden de tabla y el primer exit 2 corta la cadena; después, los no bloqueantes. Un mismo comando corre una vez por acción aunque aparezca en dos filas (Claude Code deduplica comandos idénticos). El matcher se evalúa como regex anclada, igual que en Claude Code (`mcp__.*` casa con `mcp__github__create_issue`).

## Decisiones

- Un hook `command` de settings.json entra como bloqueante salvo que tenga `async: true`: en Claude Code un hook asíncrono no puede bloquear, así que sale `bloqueante=no`. La tabla anterior, escrita a mano, marcaba como no bloqueantes otros hooks (`plan-gate`, `auto-grill-me`…) sin respaldo en settings.json; ahora manda settings.json.
- El generador solo acepta matchers en `[A-Za-z0-9_|.*]` (donde la regex de Claude Code y la de bash coinciden) y argumentos literales; un `&&`, `;`, `|`, `$(...)`, redirección o glob aborta la generación en vez de perder el segundo comando en silencio.
- Solo existe el modo `spawn`: `source` no se puede acotar con `timeout` y un `exit` interno escaparía al contrato. `timeout` manda TERM al grupo de procesos del hook y, 5 s después, KILL; si vence el tiempo, el despachador mata el grupo entero, de modo que ningún hijo que ignore TERM queda vivo. La entrada llega a cada hook desde un fichero temporal, no por tubería: un hook que sale 0 sin leer stdin no provoca un SIGPIPE que se confunda con un fallo.
- Los hooks `prompt` no se despachan por shell: salen en la tabla como `# EXCLUIDO(...)`.
- Tiempo por hook: 100 s uniforme (el mayor `timeout` de settings.json); el generador rechaza un settings con un timeout mayor o no numérico. `DISPATCH_HOOK_TIMEOUT` solo admite un entero de 1 a 100: `0` desactivaría el límite.
- El exit 1 de un hook suelto es no bloqueante en Claude Code y bloqueante aquí: esa diferencia es buscada y es lo que el modo sombra (S3 restante) debe inventariar antes de sustituir registros (AC-9).
