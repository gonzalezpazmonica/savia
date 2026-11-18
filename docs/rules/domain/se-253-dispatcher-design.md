# Despachador PreToolUse: contrato de fallo cerrado

> SE-253 S4 (diseño) y SE-510 D3 (contrato). El despachador `hooks/dispatchers/dispatch-pretooluse.sh` lee `hooks/routing-pretooluse.tsv`, que se GENERA desde `.claude/settings.json` con `python3 scripts/dispatch-table.py write`. `check` (y un test) falla si difieren.

## Contrato

Salida 0 (permitir) o 2 (bloquear). Nada más. Un hook bloqueante que sale con cualquier otro código, o cualquier fallo del propio despachador, bloquea con el motivo en stderr (clase POLÍTICA: ante la duda, política).

| Situación | Resultado |
|---|---|
| Tabla ausente o ilegible | 2 |
| stdin vacío, JSON roto o sin nombre de herramienta | 2 |
| Fila de la tabla mal formada | 2 |
| Hook bloqueante registrado que no existe | 2 |
| Hook bloqueante con exit distinto de 0 y 2 (incluido 1) | 2 |
| Hook bloqueante que excede el tiempo | 2 |
| Hook no bloqueante que falla | 0, con aviso |

El JSON se parsea una vez; cada hook recibe la misma entrada por stdin. El primer exit 2 corta la cadena.

## Decisiones

- Todo hook `command` de settings.json entra como bloqueante: Claude Code bloquea con exit 2 en cualquiera. Declarar uno no bloqueante exige un cambio explícito en el generador y una revisión (aún no hay ninguno).
- Los hooks `prompt` no se despachan por shell: salen en la tabla como `# EXCLUIDO(...)`.
- Tiempo por hook: 100 s uniforme (el mayor `timeout` de settings.json); el generador rechaza un settings con un timeout mayor.
- El exit 1 de un hook suelto es no bloqueante en Claude Code y bloqueante aquí: esa diferencia es buscada y es lo que el modo sombra (S3 restante) debe inventariar antes de sustituir registros (AC-9).
