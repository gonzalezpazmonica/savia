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
arranca el CLI (`SAVIA_PROMPT_HOOK_CMD`, prompt renderizado por stdin, veredicto:
un objeto JSON con `ok` booleano y `reason` opcional string; otras claves se ignoran). Sin evaluador, crash, timeout, prosa
alrededor del JSON u `ok` no booleano bloquean; una llamada que el matcher no
selecciona continúa. `test_prompt_transport.py` replica el mismo corpus
(`fixtures/prompt_replay_corpus.json`, 20 casos) en Codex y en OpenCode con las
mismas decisiones y motivos.

Al preparar ese replay apareció un hueco mayor: savia-gates leía `Bash(git commit*)`
como regex (un grupo) y no casaba nunca, así que `block-commit-to-main.sh`,
`compliance-gate.sh`, `prompt-hook-commit.sh`, `pr-summary-gate.sh` y el handler
`prompt` no corrían en OpenCode. Y el núcleo Python solo aceptaba una estrella final:
`Bash(bash*memory-store*save*)` exigía estrellas literales y `memory-write-sanitize.sh`
no corría en Codex. Ahora `Herramienta(orden)` es un glob literal en los dos, también
dentro de alternativas con `|`; un test compara cada matcher de `settings.json`
contra 15 llamadas en ambos núcleos (cero divergencias).

`PROTECTED_GATE_PATH` se aplica también en OpenCode (`write`, `edit`, `apply_patch`),
sin depender de `SAVIA_GATES_PIN`; la lista es la misma en los dos núcleos (test de
paridad) y añade `.opencode/plugins`, `scripts/opencode-plugin`, `opencode.json` y
`.opencode/package.json`. En OpenCode también mira `notebook_path`. El motivo del
bloqueo (`PROTECTED_GATE_PATH`) se comprueba en los dos núcleos, no solo que bloquee.
Los handlers de OpenCode tampoco heredan los interruptores que apagan hooks de
seguridad (`SAVIA_PAT_BLOCK`, `SAVIA_SHIELD_ENABLED`, `SAVIA_HOOK_PROFILE`), igual
que en Codex.

Pendiente en S3: binario Codex en vivo, despacho por el socket del runtime
(requiere decisión de la operadora sobre revisión de política y confianza del
daemon).

El matcher de OpenCode usa ya los mismos candidatos que el núcleo Python: nombre de
herramienta y, con comando, `Tool(cmd)`, `Tool:cmd` y `Tool cmd`; el payload serializado
solo cuando no hay herramienta. Antes probaba siempre el payload: en 40 de 168 pares
matcher × llamada (entradas que nombran otras herramientas) corrían hooks solo en OpenCode,
p.ej. los de `Bash` con un `Read` de `docs/Bash-notes.md` o `Bash(git commit*)` con una
búsqueda MCP. Ahora 0 (`test_tool_inputs_that_name_other_tools_select_the_same_hooks`).
Sigue igual en los dos, y no se ha decidido cambiarlo: la búsqueda es sin anclar y sin
mayúsculas, así que `Edit|Write` también corre en un `Bash` cuyo comando contiene «write».

### Rutas protegidas desde `bash`

`echo {} > .claude/settings.json`, `sed -i` sobre un hook, `git checkout -- .codex/hooks.json`
o un borrado recursivo de `.claude` llegaban al CLI en Codex y en OpenCode, aunque la
misma escritura con `write`/`edit`/`apply_patch` se denegaba. `shell_targets.py` (y su
port `lib/shell-targets.ts`) lee el texto del comando, sin ejecutarlo, y extrae los
destinos de escritura: redirecciones (`>`, `>>`, `&>`, `<>`), `rm/mv/cp/ln/install/tee/
touch/truncate/chmod -R/...`, `sed/perl -i` (también en clusters: `-Ei`, `-pi`), `dd of=`,
subcomandos de `git` que reescriben el árbol, `xargs`, `find -delete/-exec`, y el texto de
`bash -c` (y `-lc`, `-ec`…), `eval`, `env -S`, `$(...)`, backticks, `<(...)`/`>(...)` y del
heredoc o here-string que se pasa a un shell, de forma recursiva; una sustitución se juzga desde
el directorio del comando que la contiene (`cd .claude/hooks && echo $(rm x)`). Los heredocs de otros comandos se
saltan (un mensaje de commit que menciona un hook no bloquea). Los borradores también se
deniegan sobre un directorio que contiene una ruta protegida; los globs se comparan
componente a componente y las llaves se expanden (`{.claude,tmp}`). `$'\x2e…'` se decodifica
y `((x<<2))` es aritmética, no heredoc. Un texto que el tokenizador no cierra se deniega
siempre: su texto crudo esconde lo que el tokenizador habría decodificado (`.cl''aude`,
`$'\x2e'codex`, un `cd` previo), así que ninguna búsqueda de subcadenas sobre él es fiable
(revisión de seguridad de #1391). Medido sobre 23 029 órdenes Bash reales de sesiones locales:
solo 2 quedan sin analizar, y bash también las rechaza (una línea `EOF` cierra el heredoc antes
de tiempo).

Base de las rutas relativas: el `cwd` del payload, movido por `cd`/`pushd`/`popd` (un
subshell `( … )` lo restaura), `git -C`/`--work-tree`, `env -C` y la opción de directorio de
la elevación de privilegios. Tras un `cd` a un sitio desconocido (`cd "$D"`, `cd -`, `cd ~`), una
ruta literal se deniega si es un gate visto desde cualquier directorio camino de uno, o si
existe dentro de uno (así `cd "$D" && rm -f settings.json` se deniega aunque `$D` fuera otro
sitio). `~` y `$HOME` se expanden con `HOME`; `~+` es el directorio actual y `~-` uno
desconocido (`$OLDPWD`); `~usuario` queda fuera del repositorio. Los pathspecs de `git checkout/restore/rm/clean/
reset/stash` alcanzan su árbol (`git checkout -- .`, `git restore scripts`); los que solo tocan
el índice no escriben (`git restore --staged`, `git reset` sin `--hard/--merge/--keep`,
`git rm --cached`) y el valor de `checkout -b/-B/--orphan` es una rama, no un pathspec. `find` con
`-delete` o `-exec` de un escritor alcanza el árbol de sus rutas de inicio salvo que solo lo
estrechen `-name`/`-iname` cuyos patrones no casan con ningún nombre de gate (sin contar
`__pycache__` ni `node_modules`), también si empieza dentro de un gate
(`find .claude/hooks -name __pycache__ -exec rm -rf {} +`) siempre que la ruta exista y se haya
recorrido; con `-o`, `!`, `-path`, `-mtime`… se deniega. En `-exec`, solo un destino que empieza
por `{}` es el fichero encontrado: `-exec cp {} /tmp/ \;` lee el árbol y `-exec cp {} .claude/x \;`
escribe `.claude/x`. `cp`/`mv` a un
directorio escriben `dest/basename(src)`; una copia recursiva alcanza ese árbol
(`cp -r /tmp/x/. .`); `install -d` crea todos sus argumentos. Las opciones con valor de los
envoltorios (`-u root`, `env -u X`, `timeout -s KILL`) y de `xargs` (también largas:
`--max-args 1`) se saltan. Una variable seguida de un padre de gate en un borrado
(`rm -rf "$R"/scripts`) se deniega por si `$R` es la raíz; coste medido: 3 de las 23 029
órdenes (`rm -rf "$d"/.claude` sobre un temporal) pasan a denegarse.

`test_shell_targets.py`: corpus de 143 casos (`fixtures/shell_targets_corpus.json`) con las
mismas respuestas en los dos núcleos (36 de los 51 añadidos tras la primera revisión de #1391
fallan con el núcleo anterior; los otros 15 son negativos; de los 31 `r1391b-*` de la segunda,
20 fallan con el núcleo anterior), casos que dependen del árbol en disco,
`cwd` en un subdirectorio, symlink a `.claude/hooks`, y réplica por `codex-hook.py` y por
savia-gates con los hooks reales: 4/4 escrituras denegadas (`PROTECTED_GATE_PATH`) frente a
4/4 permitidas en el núcleo de `e7224df97`. Sin ese commit en el clon, la línea base falla en
modo estricto (`SAVIA_DUAL_CLI_STRICT=1`) en vez de saltarse.

No cubierto, y así consta: código de otros intérpretes (`python -c "open(...,'w')"`,
`node -e`), variables cuyo valor no está en el texto (`rm -r $X` con `X=.claude`,
`rm -rf $(printf .claude)`, `rm -rf "$R"/hooks` con `R=.claude`: de una palabra con variable solo
se mira la cola literal), rutas
que llegan por stdin a `xargs`, texto que llega a un shell por tubería (`… | bash`), lo que
un script ejecutado escriba, globs tras un `cd` desconocido, y escritores sin destino
literal: `patch -p1 < x.diff`, `git apply/am` (se miran sus argumentos, no las rutas que trae
el parche), `git reset --hard` sin rutas, `git stash pop`, `git pull/merge/rebase/switch`,
`tar -x -C`, `unzip -d`, `curl -o`, `wget -O`. Cualquier escritor que no está en la lista de
arriba se permite. Estos traen contenido versionado o de un fichero
que el texto no muestra; denegarlos bloquearía el flujo normal de git. Es un gate cooperativo
contra reescrituras del agente, no aislamiento frente a procesos hostiles.

### Resto de eventos de Codex (S3)

`codex-hook.py` despacha por `hook_event_name` (`codex_events.py`) los 12 eventos
de Codex 0.163 a los handlers del mismo nombre en `.claude/settings.json`. Lo que
puede hacer cada decisión sigue lo que savia-gates hace con ese evento en OpenCode:
PreToolUse y UserPromptSubmit bloquean (exit 2); PermissionRequest solo deniega,
nunca emite `allow`; SessionStart, SubagentStart, PostToolUse, Pre/PostCompact,
Stop y SubagentStop son consultivos (un fallo es `systemMessage`, nunca fuerza
continuación ni corta la compactación); `Interrupt` no tiene equivalente. Los
handlers `async` se lanzan desacoplados, sin esperar, como en OpenCode.
El contexto solo sale si el hook lo declara N1 (`saviaLevel`), la regla de
savia-gates para proveedores no declarados locales; Codex no informa del proveedor.

Paridad corregida en ambos núcleos: el stdout en texto plano de un evento no
autoritativo ya no es salida inválida. En SessionStart, UserPromptSubmit y
SubagentStart es contexto (sin nivel); en el resto se ignora. PreToolUse y
PermissionRequest siguen exigiendo JSON o nada. Antes `session-init.sh` imprimía
texto, el bucle de SessionStart se cortaba ahí y los 5 hooks siguientes nunca
corrían en OpenCode. `test_codex_events.py` repite el mismo corpus de ciclo de vida
por `gates.py` y por `shell-bridge.ts`: decisiones y contextos idénticos.

Pendiente: activar estos eventos en `.codex/hooks.json` (revisión nativa de
confianza en Codex), binario Codex en vivo y despacho por el socket del runtime.
