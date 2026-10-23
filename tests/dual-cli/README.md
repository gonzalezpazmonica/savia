# Runtime dual CLI — evidencia S1 y núcleo experimental

Contrato: `docs/specs/SPEC-dual-cli-runtime.spec.md`.

Ejecutar tests herméticos (biblioteca estándar, sin hooks reales ni red):

```bash
python3 -m unittest discover -s tests/dual-cli -v
python3 scripts/dual-cli/audit.py
```

El auditor termina en 1 cuando el inventario es válido pero no certificado;
2 si las fuentes faltan o su estructura es inválida. No ejecuta comandos
del inventario. Omite cuerpos de hooks, URLs y prompts en la salida.
La revisión SHA-256 cubre exclusivamente las dos fuentes indicadas en
`revision_scope`; no representa todavía una revisión completa del runtime.

## Cobertura pendiente

| AC | Evidencia requerida todavía pendiente |
|---|---|
| AC1 | Mapping de recursos, guards TS, handlers y capacidades por CLI |
| AC2 | Replay y bloqueo real de comando y edición en ambos CLI |
| AC3 | 100 publicaciones, ACK y p95 de notificación |
| AC4 | 100 carreras, Git, shell persistente, patches y symlinks |
| AC5 | SIGKILL, recuperación y reserva hasta fin del escritor |
| AC6 | Fallos HTTP/prompt/MCP, timeout y aislamiento de operaciones |
| AC7 | Contratos MCP y escritura/lectura cruzada de memoria |
| AC8 | Revocación de confianza, preflight y sandbox operativo |
| AC9 | Roles, skills y comandos en sesiones reales y subagentes |
| AC10 | Instalación idempotente, rollback y cambios de versión |

Las pruebas unitarias verdes no acreditan estos AC. El inventario conserva
todos los handlers como `untested` y nunca declara equivalencia.
El arranque aislado observado en esta sesión falla con
`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`.
Ejecutar las pruebas fuera de ese aislamiento no satisface AC8.


## Núcleo experimental S2

`protocol.py` valida el evento v1, tamaño, tipos, claves duplicadas y números
no finitos. `policy.py` interpreta resultados de gates críticos: bloquea
crash, timeout, JSON inválido y solicitudes de permiso humano.
`state.py` conserva revisión, ACK, journal y una reserva global en SQLite
con transacciones `BEGIN IMMEDIATE` y `synchronous=FULL`.
Una llamada terminada no obtiene otra reserva con la misma identidad.

`runtime.py` expone un socket Unix privado, valida el UID del cliente y
entrega tokens de sesión. Implementa hello, ack, status, close y dispatch.
Dispatch devuelve siempre deny/UNSUPPORTED_CAPABILITY: todavía no hay
adaptadores de ejecución. Acquire/release no se exponen por socket hasta
implementar supervisión de escritores y todos sus descendientes.
Los tokens separan sesiones cooperativas; no aíslan procesos hostiles del
mismo usuario, que comparten acceso a archivos privados.

Evidencia ejecutada: 58 tests, incluyendo 100 carreras de reservas entre
conexiones, SIGKILL de un escritor después de reservar, persistencia al
reabrir SQLite, socket real, bloqueo de suplantación por token y rechazo de
un segundo runtime sobre el socket activo. No se instalaron hooks nativos.

Límites pendientes: reservas no se recuperan automáticamente; un socket
remanente tras un crash impide arrancar. Falta supervisor de procesos,
recuperación del daemon, cursores de journal por consumidor, publicación de
manifiestos completos, ejecución de handlers, matchers y adaptadores reales.
La revisión del proceso se recibe como argumento experimental; todavía no
se calcula desde todo el contenido de política ni se acredita confianza.
El journal deduplica registros, no acredita idempotencia de efectos externos.
El parser de hooks se prueba aislado; no está conectado a dispatch.
S1 y S2 siguen incompletos; estos tests no cierran AC1–AC10.

## Autonomía Codex

La policy común clasifica ejecución, criterio, efecto externo, ampliación de
scope y escalada de riesgo. La proyección exige `workspace-write`, red cerrada,
probe de sandbox y enforcement antes de generar un perfil. `approval_policy =
"never"` sólo se genera cuando los gates L3/L4 están demostrados; sin esa
evidencia, la configuración aborta sin tocar el fichero personal.

El doctor y el evidence package actuales informan `DEGRADED_SAFE`. Los tests
con probes sintéticos validan lógica e idempotencia; no cuentan como canaries
reales de Codex. El runner real termina en 2 mientras falle el sandbox.

## Gates compartidos y adaptador Codex (S3, parcial)

`gates.py` lee `.claude/settings.json`, ejecuta los handlers `command` en su
propio grupo de procesos y bloquea ante exit distinto de 0, timeout (mata el
grupo), JSON inválido, `ask`, configuración ilegible o un handler `http`/`prompt`
que aún no sabe ejecutar. `codex-hook.py` traduce un PreToolUse de Codex a esa
política (bloqueo = exit 2) y descompone `apply_patch` en operaciones por
archivo (alta, edición, renombrado, borrado). `.codex/hooks.json` no se ha
modificado: la confianza del hook es decisión nativa de Codex.

Evidencia: `test_gates.py` incluye un replay del mismo corpus
(`fixtures/replay_corpus.json`) contra los hooks reales por el núcleo Codex y por
`shell-bridge.ts` de OpenCode (vía bun): decisiones idénticas. Cubre la mitad
de comando de AC2; la edición real, el binario Codex en vivo y el despacho por
el socket del runtime siguen pendientes. (Este párrafo decía que
`Bash(git commit*)` se bloqueaba en ambos núcleos por su handler `prompt`: era
falso en OpenCode, donde ese matcher nunca casaba; ver abajo.)

### Mitad de edición de AC2 (replay)

`test_edit_replay.py` envía las mismas ediciones como las manda cada CLI:
Codex, `apply_patch` a `codex-hook.py`; OpenCode, `write`/`edit` con `filePath`
y `apply_patch` con `patchText` al camino de producción de savia-gates
(`lib/hook-vocabulary.ts` → `runPreToolUse`). Corpus en
`fixtures/edit_replay_corpus.json`: 5 bloqueos reales (tdd-gate,
block-pat-file-write, parche multiarchivo, parche ilegible) y 3 permitidos.
Antes de este cambio OpenCode dejaba pasar 4 de los 5 bloqueos: los hooks
comparan `tool_name == "Edit"` y leen `.tool_input.file_path`, y `apply_patch`
no coincidía con ningún matcher Edit|Write. El puente traduce ahora nombres y
claves al vocabulario de Claude Code (conserva las originales) y descompone el
parche por archivo con el mismo algoritmo que `gates.py`; la paridad del parser
se prueba contra Python (`PatchParserParityTests`).

### Handlers `prompt` (AC6), matchers y rutas protegidas

Ambos núcleos ejecutan ya los handlers `prompt` con el evaluador que declara quien
arranca el CLI (`SAVIA_PROMPT_HOOK_CMD`, prompt renderizado por stdin, veredicto
exacto `{"ok": bool, "reason"?: string}`). Sin evaluador, crash, timeout, prosa
alrededor del JSON u `ok` no booleano bloquean; una llamada que el matcher no
selecciona continúa. `test_prompt_transport.py` replica el mismo corpus
(`fixtures/prompt_replay_corpus.json`, 10 casos) en Codex y en OpenCode con las
mismas decisiones y motivos.

Al preparar ese replay apareció un hueco mayor: savia-gates leía `Bash(git commit*)`
como regex (un grupo) y no casaba nunca, así que `block-commit-to-main.sh`,
`compliance-gate.sh`, `prompt-hook-commit.sh`, `pr-summary-gate.sh` y el handler
`prompt` no corrían en OpenCode. Y el núcleo Python solo aceptaba una estrella final:
`Bash(bash*memory-store*save*)` exigía estrellas literales y `memory-write-sanitize.sh`
no corría en Codex. Ahora `Herramienta(orden)` es un glob literal en los dos, también
dentro de alternativas con `|`; un test compara cada matcher de `settings.json`
contra 12 llamadas en ambos núcleos (cero divergencias).

`PROTECTED_GATE_PATH` se aplica también en OpenCode (`write`, `edit`, `apply_patch`),
sin depender de `SAVIA_GATES_PIN`; la lista es la misma en los dos núcleos (test de
paridad) y añade `.opencode/plugins` y `scripts/opencode-plugin`.

Pendiente en S3: binario Codex en vivo, despacho por el socket del runtime
(requiere decisión de la operadora sobre revisión de política y confianza del
daemon), escrituras a rutas protegidas desde `bash` en ambos núcleos, y la
divergencia restante del matcher de OpenCode, que además prueba el payload
serializado como candidato (Python solo lo hace sin nombre de herramienta).
