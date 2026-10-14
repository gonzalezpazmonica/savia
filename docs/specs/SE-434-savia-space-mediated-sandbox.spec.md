---
status: APPROVED
approved_at: 2026-10-07
approved_by: "gonzalezpazmonica — spec: AskUserQuestion 2026-10-05 «Apruebo, pero S1 y S2 a la vez»; delta FS-6b (D-MED-9): 2026-10-07, aprobado con condición APTO de rev-fs6b REV5"
delta_approved: "gonzalezpazmonica 2026-10-07, FS-6b (D-MED-9), aprobado con condición APTO de rev-fs6b REV5"
priority: P0
developer_type: agent-team
created: 2026-10-05
author: Savia
phase: A
risk: L3
related_specs: [SE-428, SE-429, SE-432]
origin: "Decisiones de la operadora del 2026-10-05 (AskUserQuestion): D-MED-1 sandbox propio de Space como frontera del modo mediado; D-MED-2 credenciales por proxy que inyecta; D-MED-3 desbloqueo (registro, ampliar el entorno, intención explícita, móvil); D-MED-4 MCP fuera del sandbox y el resto por lista derivada de la configuración de Savia, con acceso garantizado a cúpulas, repos, conexiones, MCP, A2A y APIs; D-MED-5 sandbox transparente para quien opera; D-MED-6 agnóstico a la máquina (software libre). Decisiones del 2026-10-07: D-MED-9 el motor corre con las máscaras N2, el bash del agente por intermediario sin anidar y FS-6b acotado al sistema de ficheros con el riesgo del IPC del host escrito. Diseño completo en Savia Labs (privado)."
resource: https://code.claude.com/docs/en/sandboxing.md
timeline:
  - from: "2026-10-07"
    learned: "2026-10-07"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-434 — Savia Space: modo mediado con sandbox propio como frontera

## Problema

En modo mediado, Space decide cada permiso del motor (SE-428): lo deniega, lo aprueba solo o lo pregunta a la operadora. Hoy, para bash, lo decide analizando el texto de la orden con su deny-list. Ese modelo falla de dos maneras:

- **Deja a la operadora sin bash.** Con un plugin de sandbox de terceros activo, cada orden llega envuelta en su arranque. El proxy de red de ese arranque usa `socat` contra un socket Unix, y la deny-list lo juzga como una orden más y lo deniega. Resultado: se rechaza todo bash.
- **Space no es dueño de la frontera que juzga.** Reconocer por texto la estructura de un envoltorio ajeno es frágil (depende de la versión del plugin) y debilita la deny-list.

Claude Code lo resuelve de otra forma. El aislamiento lo impone el sistema operativo, no el análisis del texto: dentro de un sandbox verificado, bash se autoaprueba, y lo que necesita salir se pregunta.

- **Las herramientas de ficheros del motor siguen enlaces.** `read`, `edit` y `list` de OpenCode corren en el proceso del motor, fuera del sandbox de bash. La superposición de permisos (FS-6, `harden_for_n2`) niega las cúpulas N2 por patrón de ruta, pero la ruta pedida no se canoniza: con un enlace `sub/atajo -> vaults/privada` en el worktree, `read sub/atajo/n.md` entrega el contenido de la cúpula y `edit` escribe en ella, mientras la ruta directa sigue denegada. Se rompen la confidencialidad y la integridad.
- **La limpieza de enlaces no cierra la ventana.** Los enlaces a N2 se retiran tras cada orden y en cada sonda (cada 30 s como mucho). Quedan dos ventanas que controla el agente:
  1. una orden larga (`ln -s vaults/privada x; sleep 120`) mantiene vivo el enlace mientras el modelo llama a `read x/n.md` en paralelo;
  2. los enlaces que ya están en el worktree al arrancar (versionados o de una sesión que murió): `Sandbox::prepare` no los retira, así que el primero en hacerlo es la primera sonda o la primera orden.
- **Corregir la semántica de rutas no basta.** Canonizar antes de abrir deja una carrera entre la comprobación y la apertura (TOCTOU). Solo es sólido que el proceso del motor **no vea** las N2 a nivel de sistema operativo.
- **El bwrap del agente no se puede anidar en Ubuntu.** Con la restricción de AppArmor activa, los hijos de un `bwrap` corren con un perfil que niega capacidades, y un `bwrap` anidado no crea su espacio. Por eso el bash del agente no puede lanzarse desde dentro del espacio del motor.

## Objetivo

Que el modo mediado sea **seguro y funcional**:

- bash utilizable sin preguntar por cada orden;
- acceso a los recursos ya configurados de Savia: cúpulas, repositorios, remotos git, MCP, A2A y APIs;
- ninguna credencial al alcance del agente;
- ninguna denegación sin salida.

## Diseño

### 1. Sandbox propio de Space (D-MED-1, D-MED-6)

> **D-MED-6. Agnóstico a la máquina.** Savia es software libre, así que el sandbox no puede depender de una máquina concreta. Cada plataforma tiene su backend, con el mismo contrato y la misma sonda: bwrap en Linux y Seatbelt en macOS. Si no hay ningún backend utilizable, todo bash pregunta, y el doctor y el instalador explican cómo arreglarlo en esa distribución: perfil de AppArmor en Ubuntu, sysctl en otras, WSL2 en Windows. Nunca se confía en binarios que el usuario pueda modificar.

En mediado, Space lanza el bash del agente dentro de **su propio** bubblewrap, con el binario de confianza. En ese modo no se cargan plugins de sandbox de terceros.

| Ámbito | Política |
|---|---|
| Sistema de ficheros | Lo que da el entorno (§2, D-MED-5): el worktree, la raíz de Savia y sus proyectos, y las cúpulas, con el mismo acceso que fuera; de `$HOME`, solo lo que el entorno declare. Nunca ficheros de credenciales (lista cerrada, comprobada en la sonda) ni el estado privado de Space |
| Red | Namespace de red propio. Única salida: el proxy de Space (§3), por un socket montado por Space |
| Procesos e IPC | Namespace de PID propio. Sin acceso a los sockets de Space ni a `/proc` del host. La contraseña del motor no está presente |

- **Verificación (`isolation.state`).** Al arrancar y de forma periódica, una sonda desde dentro comprueba que lo prohibido falla y que lo permitido funciona. **Solo con `LIVE` se autoaprueba bash.** En cualquier otro estado, todo bash pregunta.
- **Prohibiciones duras.** Sobreviven al sandbox y las aplica la deny-list determinista: `sudo`, force push, borrados masivos fuera del worktree y lectura de credenciales. Nada las supera.
- **Orden de decisión**, como en `permissions` y el auto mode de Claude Code:
  1. prohibición dura → deny;
  2. `ask` explícito;
  3. `allow` explícito;
  4. dentro del sandbox `LIVE` → auto;
  5. si necesita salir del sandbox → preguntar.

### 2. Entorno derivado de la configuración de Savia (D-MED-4, D-MED-5)

> **D-MED-5. El sandbox es transparente para quien opera.** Quien opera trabaja con Savia como siempre: sus ficheros y carpetas, todas las cúpulas de su ordenador (descubiertas, no declaradas), sus MCP y sus APIs. El sandbox solo hace tres cosas: oculta las credenciales y el estado interno de Space, limita la red a los destinos configurados y aplica las prohibiciones duras. Donde la tabla siguiente choque con esto, prevalece D-MED-5.

El entorno se **genera** desde la configuración real de Savia; no se escribe a mano. Se guarda con su hash, el doctor lo muestra y se regenera cuando cambia la configuración.

| Recurso | Acceso desde el modo mediado |
|---|---|
| Repositorio del workspace | Worktree en lectura y escritura; git local dentro del sandbox |
| Remotos git y GitHub | Por el proxy, solo hacia los hosts de los remotos y la API de GitHub, con credencial inyectada (§3) |
| Cúpulas (SaviaVaults) | Lectura dentro del sandbox. Escritura solo por la herramienta MCP, mediada |
| MCP | **Fuera del sandbox**: los lanza el motor y cada llamada pasa por la mediación de permisos |
| A2A y servicios locales | Solo los puertos de loopback **declarados** en la configuración de Savia, por el proxy |
| APIs | Por el proxy, con lista de dominios y credencial inyectada |
| Estado de Savia | No entra, salvo subrutas concretas declaradas y revisadas |

### 3. Proxy de red con inyección de credenciales (D-MED-2)

- El proceso del sandbox **no ve ningún secreto**: ni en el entorno ni en ficheros.
- El proxy de Space:
  - permite solo los destinos del entorno;
  - añade la credencial de cada destino;
  - termina TLS con una CA local en la que solo confía el sandbox.
- Una credencial nunca va a un destino que no le corresponde. Un destino no permitido se deniega con `[Red no permitida]` y queda registrado.
- Los remotos ssh se reescriben a HTTPS por el proxy; ssh no entra en el sandbox.

### 4. Desbloqueo (D-MED-3)

- **Registro de denegaciones.** Un panel muestra la orden, la sesión y el motivo entre corchetes: `[Credenciales]`, `[Red no permitida]`, `[Fuera del worktree]` o `[Prohibición dura]`. Se alimenta del registro de decisiones existente.
- **Ampliar el entorno desde la UI.** Con un toque desde una denegación se añade el dominio o la ruta al entorno del workspace. El alcance es explícito y queda registrado; nunca hay «siempre» global.
- **Intención explícita.** Una prohibición blanda (por ejemplo, `git push` a una rama propia) se supera si la operadora lo escribe expresamente en el chat de esa sesión, y la cita queda registrada.
  - Solo cuentan los mensajes tecleados en la UI por la sesión emparejada, nunca las salidas de herramientas.
  - Las prohibiciones duras no se superan.
- **Móvil.** Lo que se pregunta llega como aviso al cliente móvil (SE-430), con Permitir una vez y Rechazar.

### 5. El motor con máscaras N2 (D-MED-9)

> **D-MED-9. El motor corre con las máscaras N2.**
> - El proceso del motor, y todo lo que lance (PTY, MCP, LSP, formatters), corre en su propio espacio de usuario, de montaje y de PID con las mismas máscaras N2 que el sandbox del agente. Para el motor, las cúpulas N2 no existen en el sistema de ficheros, así que deja de importar la semántica de rutas: enlaces simbólicos, `..` y carreras entre comprobar y abrir. La superposición de permisos de FS-6 se mantiene como defensa en profundidad, no como frontera.
> - **El bash del agente no se anida:** se lanza desde Space, fuera del espacio del motor, a petición de un intermediario acotado (§5.7).
> - **Alcance: el sistema de ficheros.** El IPC del host queda fuera, con el riesgo escrito y visible en el doctor (§5.8).

**FS-6b (requisito).** Con un motor de nube y al menos una cúpula N2 o superior:
- ninguna herramienta del motor ni ningún proceso hijo suyo puede leer, listar ni escribir el contenido de una cúpula N2 **a través del sistema de ficheros**, por ninguna ruta: directa, relativa, con `..`, a través de un enlace simbólico del worktree (a la cúpula, a algo dentro o a algo que la contiene), por otro punto de montaje de la misma cúpula ni a través de `/proc`;
- ninguna superficie de Space alcanzable desde el espacio del motor, intermediario incluido, entrega ni escribe contenido de una cúpula N2;
- en mediado con motor de nube y alguna cúpula N2, el motor no ejecuta formatters ni servidores LSP: son los hijos del motor que cargan configuración del repositorio, que el agente escribe (§5.8);
- el motor sigue funcionando sobre su worktree, su configuración y su estado.

El IPC del host (servicios del usuario que corren fuera del espacio) queda fuera de FS-6b (§5.8).

#### 5.1 Qué ve el motor

El espacio del motor es la vista del host **menos las N2**: no restringe nada más (D-MED-5, transparencia). Lo que el motor necesita, y que el arranque comprueba por `/proc/<pid>/root` que sigue visible antes de usarlo (§5.2, paso 6):

| Recurso | Acceso | Se comprueba al arrancar |
|---|---|---|
| Worktree de la sesión (raíz del repositorio) | Lectura y escritura, salvo las cúpulas N2 que cuelguen de él | Sí |
| Configuración del motor: `$XDG_CONFIG_HOME/opencode` (o la configuración global derivada sin plugins de sandbox) y la copia anclada de `OPENCODE_CONFIG_DIR` (EN-1) | Lectura | Sí |
| Estado del motor: `$XDG_DATA_HOME/opencode` (sesiones, `auth.json`) y `$XDG_STATE_HOME/opencode` | Lectura y escritura | Sí |
| Caché del motor: `$XDG_CACHE_HOME/opencode` (dependencias de plugins, catálogo de modelos) | Lectura y escritura | Sí |
| Directorio de ejecución de Space (`runtime_dir`): plugin de aislamiento, emisor de hooks, cliente del intermediario (`SHELL`), directorio del socket del intermediario | **Solo lectura**, impuesta con un montaje propio dentro del espacio (`--ro-bind`; en `userns`, `MS_BIND` y remontaje `MS_RDONLY`). Conectar a un socket no necesita escritura en el sistema de ficheros | Sí: crear un fichero da EROFS (paso 6) |
| Subdirectorio de salidas de las sondas de aislamiento (`runtime_dir/probe-out/`, donde escriben `probe_exposure_pty` y `probe_exposure_mcp`) | Lectura y escritura, montado aparte sobre el de solo lectura. No contiene nada que se ejecute | Sí |
| Directorio del socket del intermediario (§5.7). Debe existir **antes** de lanzar el motor: un montaje del espacio no ve lo que se cree después en una ruta que aún no existía | Conexión al socket | Sí |
| Fichero de endpoint de hooks en el estado de Space (D-ORCA-5) | Lectura | Sí |
| Directorio del socket del proxy de Space (§3), creado también antes del lanzamiento | Conexión al socket | Sí |
| Binario de OpenCode fijado (el de `EngineSpec::bin`) y sus bibliotecas | Lectura y ejecución | Sí |
| Binario de Space (lanzador interior, §5.3) | Lectura y ejecución | Sí |
| `/tmp` y `$TMPDIR` del motor: **compartidos con el host** | Lectura y escritura | No (los da la vista del host) |
| Dependencias y binarios de los MCP configurados (en mediado con motor de nube y alguna N2 no hay formatters ni LSP, §5.8) | Como en el host | No: si faltan, el MCP falla con su error, como hoy |
| `/run/user/$UID` (`$XDG_RUNTIME_DIR`): sockets de servicios del usuario | Como en el host (§5.8) | No |
| `/dev` del host, con `/dev/pts` y `/dev/ptmx` (PTY del motor) | Como en el host | No |
| `/proc` **propio** del espacio de PID del motor | Solo sus procesos | Sí (paso 6) |
| Red: la del host. Loopback para que Space hable con `opencode serve`, salida al proveedor de modelos | Sin espacio de red propio | No |
| Cúpulas N1 | Como en el host | Una de control |
| Cúpulas N2 o superiores: todas las formas de su ruta (la declarada y la canónica) y todo otro punto de montaje cuya raíz quede dentro de una N2 | **Montaje vacío de solo lectura** | Sí (paso 6) |

En la tabla de §2, la fila MCP pasa a decir: «**Fuera del sandbox de bash, dentro del espacio del motor** (§5): los lanza el motor y cada llamada pasa por la mediación de permisos».

#### 5.2 Cómo se construye el espacio del motor

1. **Clasificar** las cúpulas con `space_environment::domes::classify`, como hoy en `Sandbox::prepare`. El conjunto N2 es el mismo `N2Dirs` que usa el sandbox del agente: una sola fuente.
2. **Alias de montaje.** Leer `/proc/self/mountinfo` y añadir al conjunto de máscaras todo punto de montaje cuya raíz quede dentro de una cúpula N2. El conjunto resultante lo usan **los dos** espacios: el del motor y el sandbox del agente que lanza el intermediario. Si `mountinfo` no se puede leer o un alias no se puede tapar, en mediado se falla cerrado (§5.5).
3. **Retirar los enlaces N2 del worktree antes de lanzar el motor.** `Sandbox::prepare` retira todo enlace del worktree que apunte a una cúpula N2, a algo dentro o a algo que la contenga (mismo criterio que `n2_links`; solo se salta `.git`).
   - Se implementa en Rust sobre descriptores de directorio (`openat` con `O_NOFOLLOW | O_DIRECTORY`, `unlinkat`), sin resolver rutas en cada paso y sin depender de la implementación de `find`.
   - Si el directorio que contiene el enlace no es escribible se le da `u+w`, como el envoltorio.
   - Lo retirado se dice en la nota de arranque, con la ruta relativa al worktree.
4. **Crear el intermediario** (§5.7) y su socket antes de lanzar el motor.
5. **Lanzar el motor dentro de su espacio** con un lanzador (§5.3) que:
   - crea espacios nuevos de usuario, de montaje y de PID; **no** crea espacio de red;
   - monta un `/proc` nuevo **sobre `/proc`** (nunca en otra ruta), de modo que `/proc/<pid de Space>/root` y los demás procesos del host no existen dentro;
   - monta sobre cada máscara un directorio vacío de solo lectura (el mismo patrón que las máscaras del agente);
   - fija los ancestros de cada cúpula N2 que cuelguen de algo escribible, montando cada uno sobre sí mismo (`PinDir`, como FS-3 en el sandbox del agente): dentro del espacio no se pueden renombrar;
   - tiene un init mínimo como PID 1 del espacio, que recoge hijos y lanza OpenCode como su único hijo directo;
   - entrega la contraseña del motor por un descriptor y la pone en el entorno de OpenCode al hacer `execve`; nunca en el entorno ni en `argv` del lanzador;
   - **no** usa `--die-with-parent` ni `PR_SET_PDEATHSIG`: el motor sobrevive a la muerte de Space, como hoy, y se reengancha (paso 8).
6. **Identificar los procesos y medir desde fuera** antes de usar el motor, antes de la salud y del pin.

   Space registra **dos PID del host**:
   - el del init del espacio (`child-pid` de `--info-fd` en bwrap; el hijo del `fork` en el respaldo `userns`);
   - el de OpenCode: **solo en el lanzamiento**, el único hijo del init (`/proc/<init>/task/<init>/children`), validado con `is_engine_process` y su `start_time`. Si el init tiene cero o más de un hijo, o la validación falla, el arranque falla. Nunca se vuelve a derivar así después: con el motor en marcha, los huérfanos de MCP o PTY se reasignan al init y dejaría de ser el único hijo.

   `is_engine_process`, X1, la autenticación del intermediario y el registro de ejecución usan el PID de OpenCode. **Parar** sigue la escalera de hoy sobre OpenCode (`/instance/dispose`, SIGTERM) y termina matando el init con SIGKILL, que se lleva todo el espacio de PID: no quedan MCP, PTY ni LSP huérfanos. El registro de ejecución guarda los dos PID y sus `start_time`.

   La medida, sobre el PID de OpenCode, comprueba que:
   - `/proc/<pid>/ns/mnt` es distinto del de Space;
   - cada máscara vista por `/proc/<pid>/root/<ruta>` es un directorio vacío en el que no se puede crear nada (EROFS);
   - `runtime_dir` es de solo lectura dentro del espacio: crear `/proc/<pid>/root/<runtime_dir>/x` y reescribir en el sitio el cliente fijado dan EROFS;
   - `/proc/<pid>/root/proc` contiene solo PID del espacio: no existe `/proc/<pid>/root/proc/<pid de Space en el espacio del host>` y el número de entradas numéricas coincide con los procesos del espacio;
   - una cúpula N1 de control sigue legible y los recursos marcados «Sí» en §5.1 son visibles;
   - se lee el perfil de seguridad efectivo de OpenCode (`/proc/<pid>/attr/current`; en Ubuntu con la restricción, `bwrap//&unpriv_bwrap`), que se guarda y muestra el doctor. No decide nada: es información para diagnosticar.

   Si algo falla, el motor se para y no se usa.
7. Después sigue el arranque de hoy: salud, aislamiento del entorno (X1, sobre el PID de OpenCode), pin y superposición.
8. **Reenganche.** Un motor que lanzó un arranque anterior de Space solo se reengancha en mediado si su registro tiene los dos PID con sus `start_time`, esos PID siguen vivos con el mismo `start_time`, el de OpenCode pasa `is_engine_process` y es descendiente del init registrado, y pasa la medida del paso 6. Los PID se toman **del registro**; no se vuelven a derivar por «único hijo del init». Space vuelve a crear el intermediario en la misma ruta del socket (su directorio ya existía cuando se creó el espacio). Si no pasa la medida, el motor se para y se lanza de nuevo.
9. **Cúpula N2 nueva con el motor en marcha.** La reclasificación de cada sonda (30 s) la detecta.
   - El sandbox del agente la tapa desde la siguiente orden, como hoy.
   - El espacio del motor no se amplía en caliente: Space marca el motor `DEGRADED`, lo reinicia con la máscara nueva (las sesiones persisten en el estado del motor) y lo dice en la nota y en el registro de decisiones.
   - Hasta que el motor reiniciado pasa el paso 6, el sandbox de bash no es `LIVE`.
10. **Cúpula N2 que desaparece de su ruta.** Si una cúpula N2 que estaba en el conjunto ya no está en su ruta (se movió en el host o se borró), no se quita del conjunto.
    - En mediado, el siguiente arranque o reinicio del motor falla cerrado (§5.5) hasta que la operadora la confirme en su nueva ruta o la retire del registro.
    - El motor en marcha pasa a `DEGRADED`.
    - Así una cúpula movida no queda tapada por su ruta vieja y visible por la nueva.

#### 5.3 Backends del espacio del motor

| Backend | Cuándo | Cómo |
|---|---|---|
| **bwrap** (principal, Linux) | El mismo `bwrap` de confianza que elige la detección de S1/S5 (`detect_bwrap`, hash fijado, nunca de un directorio escribible por el usuario) | `--unshare-user --unshare-pid --dev-bind / / --proc /proc`, una máscara por ruta de §5.1, un `PinDir` por ancestro, `--info-fd` para el PID del init. Sin `--unshare-net`, **sin** `--die-with-parent` y sin `--as-pid-1` (el init de bwrap recoge hijos). Dentro corre el **lanzador interior**: el binario de Space (`savia-space engine-exec`, el mismo binario fijado que ya corre). Lee la contraseña del descriptor, la pone en el entorno de OpenCode, cierra todo descriptor salvo 0, 1 y 2, y hace `execve` de OpenCode. No hay shell en medio |
| **userns** (respaldo, Linux) | Sin bwrap utilizable, pero con user namespaces sin privilegios permitidos para el propio Space. No sirve en Ubuntu con `apparmor_restrict_unprivileged_userns=1`: ahí el respaldo no tiene capacidades para montar. Su valor se limita a distribuciones sin bwrap | Re-ejecución monohilo del binario de Space como lanzador, antes de crear ningún hilo del runtime. Hace `PR_SET_NO_NEW_PRIVS`, `unshare(CLONE_NEWUSER \| CLONE_NEWNS \| CLONE_NEWPID)`, mapa de uid/gid a sí mismo con `setgroups deny`, propagación privada y `fork`. El hijo es el **init mínimo** (PID 1): monta `/proc` sobre `/proc`, las máscaras con `MS_BIND` y remontaje `MS_RDONLY` y los `PinDir`; hace `fork` de OpenCode y se queda recogiendo hijos y reenviando SIGTERM a OpenCode. Antes del `execve` de OpenCode se cierran todos los descriptores salvo 0, 1, 2 y el de la contraseña; ese se lee y se cierra, y los que el runtime de Rust hubiera abierto se cierran con `close_range(3, ~0)`. El PID de OpenCode se obtiene igual que en bwrap (§5.2, paso 6) |
| **Seatbelt** (macOS) y sin backend | — | Fuera de alcance de FS-6b. En mediado con N2 presentes rige el fallo cerrado (§5.5 y AC15/AC16 modificados) |

En los dos backends de Linux:

- El proceso OpenCode no tiene capacidades efectivas en su espacio de usuario: su uid dentro es el mismo uid no nulo, así que `execve` las retira. No puede desmontar una máscara.
- No se pasa `--disable-userns`. El agente ya no se anida (§5.7), pero algunos hijos del motor pueden necesitar user namespaces (por ejemplo, un navegador con sandbox propio en un MCP). En Ubuntu con la restricción activa, el motor y sus hijos corren bajo `bwrap//&unpriv_bwrap`, sin capacidades, así que esos hijos no podrán crearlos: es esperable, no afecta al intermediario y el doctor muestra el perfil efectivo (§5.2, paso 6). Un hijo que cree un espacio anidado (`unshare -Urm`) hereda las máscaras **bloqueadas** (`MNT_LOCKED`) y no puede desmontarlas. Medido con `bwrap` real; se prueba en AC27.
- El descriptor de la contraseña protege frente a **otros procesos del mismo uid en el host**: dentro del espacio de PID, los hijos del motor ya no ven el entorno del lanzador. Es lo que mide AC28.

#### 5.4 Modos

| Modo | FS-6b |
|---|---|
| **Mediado** | **Hermético y obligatorio.** Con N2 presentes y motor de nube, el motor solo arranca dentro de su espacio con las máscaras medidas (§5.2, paso 6), y el bash del agente va por el intermediario |
| **Interactivo** | **Mejor esfuerzo** (D-MODEL-3: «hermético solo en mediado»). Si un backend funciona, el motor arranca con las mismas máscaras. Si no, arranca como hoy, con la superposición de cúpulas de `interactive_vault_overlay`, y avisa al arrancar y en el doctor. Nunca impide arrancar. En interactivo no hay sandbox de bash de Space ni intermediario |
| **Carril local** (`SAVIA_SPACE_ENGINE_LANE=local`) | No aplica: no se tapa por nivel (FS-6) |
| **Sin cúpulas N2** | No hace falta el espacio: el motor arranca como hoy y el doctor lo dice («sin cúpulas N2 que tapar»). En mediado, el bash del agente usa el mismo intermediario, para tener un solo camino |

#### 5.5 Fallo cerrado

En modo mediado, con motor de nube y al menos una cúpula N2, el motor no arranca si ocurre alguna de estas cosas:
- el espacio con máscaras no se puede crear;
- el espacio no pasa la medida del paso 6;
- no se pueden identificar sus dos PID;
- un alias de montaje no se puede tapar;
- una cúpula del conjunto desapareció de su ruta.

En ese caso:

- el motor **no arranca** con las N2 visibles: no hay reintento sin máscaras ni caída al modo interactivo;
- el estado del motor es `UNAVAILABLE`, con la causa (`ENGINE_N2_MASKS: <motivo>`) y el arreglo para esa distribución, reutilizando las causas y remedios de `sandbox_detect` (AppArmor, `unprivileged_userns_clone`, límite de namespaces, contenedor);
- `doctor` y la UI muestran la causa y el arreglo, y distinguen «el motor no tiene espacio con máscaras» de «el sandbox de bash no es `LIVE`»;
- un motor en marcha cuya medida falle después (reenganche, cúpula nueva o movida) pasa a `DEGRADED` solo durante su parada o reinicio; nunca sigue sirviendo herramientas en ese estado más allá de lo que tarde en pararse.

El fallo cerrado del intermediario está en §5.7.

#### 5.6 Información y doctor

- `info` y `doctor` añaden `engineN2` con estos campos:
  - el estado: `HERMETIC` (máscaras medidas), `BEST_EFFORT_OFF` (interactivo sin backend), `NOT_NEEDED` (sin N2 o carril local) o `UNAVAILABLE` (mediado sin espacio);
  - el backend usado (`bwrap` o `userns`) y el perfil de seguridad efectivo del motor;
  - `formatters: off` y `lsp: off` en mediado con motor de nube y alguna N2 (§5.8);
  - las rutas tapadas, en la forma de `n2Masked`;
  - los dos PID;
  - `ipcHost: "fuera de alcance"`, que el doctor explica en una línea (§5.8).
- `info` y `doctor` añaden `bashBroker`: `UP` o `DOWN` con motivo, y el número de órdenes en curso frente al límite.
- En `docs/SANDBOX-BOUNDARY.md` de Savia Space, FS-6 deja de decir que las herramientas del motor corren sin máscaras y se añaden las filas FS-6b y PR-7 (Anexo A).

#### 5.7 El bash del agente por intermediario, sin anidar (D-MED-9)

**Motivo, medido:** en Ubuntu con `apparmor_restrict_unprivileged_userns=1` y el perfil `bwrap-userns-restrict` del paquete `apparmor`, los hijos de un `/usr/bin/bwrap` corren como `bwrap//&unpriv_bwrap`, con `audit deny capability`. Un `bwrap` anidado falla con «No permissions to create new namespace». Por eso el sandbox del agente no se lanza desde dentro del espacio del motor: lo lanza Space en el host, exactamente como hoy, a petición del motor.

**Piezas:**

- **Cliente.** El `SHELL` del motor deja de ser el guion envoltorio: pasa a ser una copia del binario de Space, fijada por hash, en `<runtime>/savia-space-sandbox-*/bash` (0500, directorio 0700). Al arrancar como `bash` actúa como cliente:
  - recibe `-c <orden>` (herramienta bash, endpoint `shell` y PTY con orden) o ningún argumento (la PTY interactiva de la terminal de la operadora, que Space crea sin `command`, como hoy);
  - con cualquier otra combinación de argumentos, o sin argumentos y con un descriptor 0 que no es un terminal, escribe `Savia Space: [Sandbox no disponible] argumentos no admitidos` y termina con 126 sin conectar;
  - se conecta al socket del intermediario;
  - envía la petición con sus descriptores 0, 1 y 2;
  - reenvía señales y tamaño de terminal;
  - termina con el código que le devuelve el intermediario.
  - **Nunca ejecuta la orden por su cuenta** ni busca otro `bash`.
- **Intermediario.** Tarea de Space, fuera del espacio del motor, que escucha en `<runtime>/savia-space-broker-*/broker.sock`: socket Unix `SOCK_SEQPACKET`, 0600, en un directorio 0700 creado antes de lanzar el motor (§5.2, paso 4). Por cada petición aceptada, ejecuta en el host el envoltorio de hoy (`wrapper_script`: comprobación del cwd, limpieza FS-5 y N2, `bwrap` del agente) con los descriptores recibidos como 0, 1 y 2. El sandbox del agente es el ya medido en S1, con el conjunto de máscaras de §5.2, paso 2.

**Acotado a peticiones de ejecución.** El protocolo tiene una única petición, `exec`, en dos formas (de orden e interactiva), y dos mensajes de control; cualquier otra cosa cierra la conexión sin ejecutar nada y queda registrada (`broker_rejected`, con motivo y sin la orden).

| Mensaje | Contenido | Reglas |
|---|---|---|
| `exec` de orden (primero y único) | versión, `argv`, cwd, filas y columnas si hay TTY; con `SCM_RIGHTS`, exactamente tres descriptores | `argv` es exactamente `["-c", <orden>]`. La orden ocupa como mucho 256 KiB y no lleva bytes NUL. El cwd es absoluto y, resuelto en el host, queda dentro del worktree y fuera de toda máscara. Cada descriptor es una tubería, un socket, `/dev/null` o un terminal (`fstat`): nunca un directorio, un fichero regular ni un descriptor `O_PATH`. No se acepta entorno: el del sandbox es la lista cerrada de PR-4 |
| `exec` interactivo (primero y único) | versión, `argv` vacío, cwd, filas y columnas; con `SCM_RIGHTS`, exactamente tres descriptores | `argv` es exactamente `[]`. El descriptor 0 **tiene que ser** un terminal: un dispositivo de caracteres de `/dev/pts` en el que `TCGETS` funciona. Los descriptores 1 y 2, el cwd y la ausencia de entorno siguen las reglas del `exec` de orden. Exige una ficha de terminal (abajo). Dentro del sandbox se lanza `/bin/bash -i` con la misma `Spec` |
| `signal` | número de señal | Solo `SIGINT`, `SIGTERM`, `SIGHUP`, `SIGQUIT`; se entrega al grupo de procesos del `bwrap` de esa petición, nunca a otro |
| `winsize` | filas y columnas | Solo si el descriptor 0 es un terminal; se aplica con `TIOCSWINSZ` a ese terminal y se envía `SIGWINCH` al grupo de esa petición |
| respuesta `exit` (del intermediario) | código | El de la orden; si murió por una señal, `128 + n`, como bash |

**Recepción.** Un mensaje con datos de control truncados (`MSG_CTRUNC`) o datos truncados (`MSG_TRUNC`) se rechaza. Todo descriptor recibido, sobre o no, se cierra antes de rechazar. El tipo de cada descriptor se decide con `fstat`, nunca por lo que diga el mensaje.

**La política la decide Space, nunca el cliente.** La petición solo trae la orden (o nada, si es interactiva), el cwd, los descriptores 0, 1 y 2 y el tamaño de terminal. Todo lo demás lo fija Space desde su `Spec`, igual que hoy el envoltorio:
- montajes y máscaras;
- entorno (lista cerrada de PR-4);
- red (solo el proxy);
- seccomp y límites de recursos;
- backend y binario `bwrap`.

El protocolo no tiene campo para pedir otra cosa. Un cliente que pudiera elegir cualquiera de ellos convertiría el socket en una escalada.

**El cwd validado no es frontera.** Space resuelve el cwd y comprueba que queda dentro del worktree y fuera de las máscaras. Después, el envoltorio hace `pwd -P` y `bwrap --chdir`, y entre los dos pasos un componente del camino puede cambiar. No importa para N2, porque `--chdir` se resuelve dentro de la vista del sandbox, con las máscaras puestas. La frontera es el sandbox. La validación del cwd sirve para dar un error claro y para el registro, y ningún cambio puede relajar el sandbox apoyándose en ella.

**Autenticación del llamante.** Al aceptar, el intermediario obtiene las credenciales del par con `SO_PEERCRED`; el núcleo traduce el PID al espacio de PID de Space. Si el núcleo tiene `SO_PEERPIDFD`, lo usa para que el PID no se pueda reutilizar; si no, comprueba el `start_time` antes y después de decidir.

Requisito mínimo, siempre:
- el uid es el de Space;
- el espacio de PID del par (`/proc/<pid>/ns/pid`) es el del espacio del motor registrado. Así se rechaza a cualquier otro proceso del mismo uid en el host.

Comprobaciones adicionales:
- su ejecutable (`/proc/<pid>/exe`, por dispositivo e inodo) es la copia fijada del cliente;
- su padre es el PID de OpenCode registrado.

Si OpenCode lanza `$SHELL` con un proceso intermedio, la regla del padre se mide en S6 y se ajusta en este delta antes de implementarse. Nunca se relaja en código.

Lo que esto demuestra es «proceso del espacio del motor, hijo de OpenCode, ejecutando el cliente fijado». **No demuestra** que la orden pasara por `permission.asked`: un MCP hijo directo de OpenCode podría ejecutar el cliente.
- No es una escalada, por esta invariante: lo que lanza el intermediario nunca ve más que su llamante, porque el sandbox del agente es más estrecho que el espacio del motor (sin red salvo el proxy, sin credenciales, sin `$HOME`, con las mismas máscaras N2).
- Para que tampoco sea una vía sin control ni auditoría, rige lo siguiente.

**Prohibiciones duras, ficha y registro.** Cada orden que llega al intermediario pasa por estos tres pasos, en este orden.
1. **Deny-list de prohibiciones duras, siempre.** La misma deny-list determinista del orden de decisión de §1 (`sudo`, force push, borrados masivos fuera del worktree, lectura de credenciales). Una orden que la incumple no se ejecuta, termina con 126 y `[Prohibición dura]` y se registra. Se aplica haya ficha o no: es barata y no depende de que la decisión de permisos se tomara bien.
2. **Ficha de la llamada aprobada.** Cuando Space aprueba (sola o con la operadora) un `permission.asked` de bash, deja una ficha con:
   - sesión e id de la llamada;
   - la orden exacta;
   - la hora;
   - una caducidad de 120 s.

   El intermediario busca una ficha sin usar con la orden idéntica byte a byte y la consume, ligando la ejecución a esa llamada.

   Sin ficha (por ejemplo, la sonda y el `shell` de la operadora, que no piden permiso, o un MCP que ejecuta el cliente), la orden solo se ejecuta si además pasa la **deny-list completa del modo mediado**. Es el orden de decisión de §1 entero, evaluado con el sandbox `LIVE` como contexto:
   1. prohibición dura → `deny`;
   2. `ask` explícito de la configuración de la operadora → **sin ficha no hay a quién preguntar: se rechaza** con 126 y `[Sin aprobación]`;
   3. `allow` explícito → se ejecuta;
   4. dentro del sandbox `LIVE` → se ejecuta;
   5. cualquier otro resultado (sandbox no `LIVE`, necesita salir del sandbox) → se rechaza con 126 y `[Sin aprobación]`.

   Así una orden sin ficha nunca se salta una regla `ask` que la operadora configuró.

   Si en S6 la orden que llega a `$SHELL -c` no coincide byte a byte con la de `permission.asked`, ninguna orden tendrá ficha y todas irán por la deny-list completa. Es seguro, pero se corrige en este delta antes de cerrar S6.
   **`exec` interactivo y ficha de terminal.** Cuando la operadora abre una terminal en la UI de Space en mediado, Space crea la PTY del motor sin `command` (como hoy) y deja una **ficha de terminal**. La ficha lleva la sesión emparejada que la pidió, el id de la PTY y la hora, caduca a los 10 s y se usa una sola vez.
   - El intermediario solo acepta un `exec` interactivo si consume una ficha de terminal sin usar. Sin ella, se rechaza con 126 y `[Sin aprobación]`. Así un MCP o el agente no se abren una shell interactiva en el sandbox por su cuenta, que esquivaría la deny-list.
   - La deny-list se aplica a la petición, y en una petición interactiva no hay orden que evaluar. Lo que la operadora teclea dentro de la shell **no** pasa por la deny-list, igual que hoy en la terminal de Space. Lo acotan el sandbox del agente (sin credenciales, sin `$HOME`, sin N2, `no_new_privs`, así que `sudo` no funciona) y el alcance del proxy (PX-7: nada de force push ni de escribir ramas ajenas). Es el mismo comportamiento de hoy: la shell de la operadora corre dentro del sandbox del agente.
   - Si dos `exec` interactivos compiten por una misma ficha, uno la consume y el otro se rechaza. El registro dice quién la consumió.

3. **Registro, siempre.** Cada petición, aceptada o rechazada, deja una entrada `broker_exec` en el registro de decisiones con:
   - hora;
   - PID, `start_time`, PID del padre y ejecutable del llamante (para distinguir la herramienta bash de OpenCode de un MCP que ejecute el cliente);
   - forma de la petición (`orden` o `interactiva`);
   - ficha (sesión e id de llamada) o `ninguna`;
   - resultado de la deny-list;
   - cwd;
   - la orden, con el mismo tratamiento de secretos que el registro de decisiones de hoy;
   - código de salida o motivo del rechazo.

   Las entradas sin ficha aparecen en el panel de denegaciones de §4 como «orden sin llamada aprobada», aunque se ejecuten.

**El socket no es visible desde el sandbox del agente.** El directorio del socket vive en `runtime_dir`, que el sandbox del agente no monta (PR-4, «sin acceso a los sockets de Space»). La sonda de AC4 lo comprueba: la ruta no existe dentro y conectar falla (AC4 modificado).

**Límites:**
- 16 órdenes en curso por motor. La 17.ª se rechaza con `[Sandbox ocupado]` y código 126, sin ejecutar nada.
- 5 s para recibir la petición `exec` completa tras conectar. Si no llega, se cierra.
- 256 KiB por orden y 64 bytes por mensaje de control.
- 100 mensajes de control por segundo por conexión. Por encima se descartan y se registra una sola vez.
- La salida de la orden no pasa por el intermediario (va por los descriptores recibidos), así que no hay búfer que crezca.
- Los límites de recursos del sandbox (`prlimit`) siguen como hoy.

**Cancelación y ciclo de vida, sin huérfanos.** Las órdenes del agente corren en el host, fuera del espacio del motor, así que el init del motor no las barre. Las barre el intermediario:
- **El cliente muere o cierra la conexión** (aborto de la herramienta, sesión borrada, motor parado o caído): el intermediario ve EOF, envía `SIGTERM` al grupo de procesos de esa petición y `SIGKILL` a los 5 s. La limpieza del envoltorio (FS-5, enlaces N2) corre igual que con un `SIGTERM` de hoy.
- **Space para el motor:** cierra el intermediario y termina cada orden en curso igual, antes de matar el init.
- **Space muere:** sus órdenes mueren con él, por una cadena de dos eslabones.
  - El envoltorio de cada petición se lanza con `PR_SET_PDEATHSIG(SIGTERM)` desde un hilo propio del intermediario, que vive lo que vive Space. No sale de `spawn_blocking`: `PDEATHSIG` se dispara cuando muere el hilo que hizo el `fork`, no el proceso.
  - El `bwrap` del agente conserva `--die-with-parent` respecto del envoltorio, como hoy.

  No quedan órdenes del agente sin dueño en el host.
- Cada petición vive en su propio grupo de procesos y su propio `bwrap`: una señal o una cancelación nunca toca otra petición.

**Fallo cerrado:**
- Si la conexión se establece pero el intermediario no responde en 5 s o rechaza la petición, el cliente escribe en stderr `Savia Space: [Sandbox no disponible] <motivo>` y termina con 126 sin ejecutar nada.
- El intermediario caído deja `bashBroker: DOWN` y el aislamiento distinto de `LIVE`: todo bash pregunta, y lo aprobado falla con 126.
- La sonda de aislamiento recorre el mismo camino (`$SHELL` → cliente → intermediario → `bwrap`), así que `LIVE` mide el camino real.
- **Space no disponible es un estado explícito, no un error genérico.** Si el socket no existe o nadie escucha (Space caído o parándose, o el intermediario parado), el cliente escribe `Savia Space: [Space no disponible] bash vuelve cuando Space se reenganche` y termina con 126. El motor sigue vivo (§5.2, paso 5). Al reengancharse, Space registra `broker_gap` con el intervalo sin intermediario y la UI muestra que bash no estuvo disponible en ese tramo.

**Qué cambia respecto de S1.** El guion envoltorio y el `bwrap` del agente son los mismos; cambia quién los lanza (el intermediario, en el host, en lugar del motor). D-MED-6 no necesita perfil de AppArmor nuevo: en Ubuntu basta el `bwrap` de confianza que ya detecta S5.

#### 5.8 Alcance frente al IPC del host (D-MED-9)

**Hecho medido:**
- El espacio del motor no tiene espacio de red propio y conserva el IPC del host: sockets de la sesión del usuario, del gestor de servicios del usuario y de agentes del usuario.
- Desde dentro del espacio con máscaras, un proceso hijo pidió a un servicio del host, que corre fuera del espacio, que leyera la cúpula, y el contenido volvió. Las máscaras tapan rutas del sistema de ficheros, no a quien ya está fuera.
- Los hijos del motor (MCP, LSP, formatters y lo que ejecuten) corren ahí sin el sandbox del agente.
- **Los formatters y los LSP no son solo código de la operadora.** EN-1 y EN-3 hacen que sus órdenes salgan de la configuración anclada. Pero el formatter o el servidor LSP leen configuración del propio repositorio, que el agente escribe:
  - un `.prettierrc` con plugins;
  - un `build.rs` o un `proc-macro` que el servidor LSP de Rust compila y ejecuta;
  - un `pyproject.toml` con hooks.

  Por esa vía, el **agente** ejecuta código en el espacio del motor, sin el sandbox de bash, y alcanza el IPC del host. No hace falta un MCP con inyección de prompt.

**Decisión: FS-6b se acota al sistema de ficheros.** El IPC del host queda fuera de alcance, con el riesgo asumido y escrito (Bloque 6). El doctor lo dice (`engineN2.ipcHost`), y AC31 fija el comportamiento para que no se dé por cerrado sin medirlo.
- **Endurecimiento que acompaña a la decisión:** en mediado con motor de nube y alguna N2, la superposición del motor desactiva los formatters (`"formatter": false`) y los servidores LSP (`"lsp": false`). La comparación final de configuración los exige, como con `permission` (T-NEVER-LOOSEN), y el doctor lo muestra.
  - Hoy la herramienta `lsp` ya se niega si una N2 cuelga del worktree, pero los servidores LSP se siguen lanzando para los diagnósticos tras cada edición. Por eso se desactivan del todo.
  - Coste: sin formateo automático ni diagnósticos del LSP tras editar en ese modo. El agente puede formatear y compilar por bash, dentro de su sandbox.
- **Lo que esto cierra:** el hueco de origen. Las herramientas `read`, `edit` y `list`, que el modelo maneja directamente, ya no alcanzan una N2 por ninguna ruta. Con formatters y LSP desactivados, el agente tampoco llega al espacio del motor por configuración del repositorio.
- **Lo que no cierra:** un hijo del motor que hable con un servicio del host capaz de leer ficheros o ejecutar órdenes. Con formatters y LSP desactivados, solo quedan los MCP. EN-3 fija qué MCP se ejecutan, no lo que hacen, así que un MCP bajo inyección de prompt que ejecute órdenes puede usar esta vía.
- **Por qué no tapar los sockets del usuario:** no sería completo sin espacio de red (quedan los sockets abstractos y el loopback TCP), chocaría con D-MED-5 y rompería los MCP que usan la sesión del usuario.
- **El cierre completo** es un espacio de red propio para el motor, con el proveedor por el proxy y Space por socket. Va en un requisito aparte.

## Slices

Cada slice es un PR Draft independiente, con TDD y con verificación contra el motor real.

| Slice | Contenido | Aceptación |
|---|---|---|
| S1 | Sandbox propio de bash en mediado, sonda de aislamiento y orden de decisión | AC1–AC4 |
| S2 | Entorno derivado y `doctor --environment` | AC5–AC6 |
| S3 | Proxy con lista de destinos e inyección de credenciales | AC7–AC9 |
| S4 | Desbloqueo: registro, ampliar el entorno, intención explícita y móvil | AC10–AC13 |
| S5 | Detección de backend, Seatbelt en macOS y guía del doctor y del instalador por plataforma (D-MED-6) | AC15–AC16 |
| S6 | FS-6b, por partes: limpieza de enlaces N2 en `Sandbox::prepare`; alias de montaje; lanzador del motor con máscaras y `PinDir` (bwrap y `userns`); dos PID y medida desde fuera; reenganche; cúpula nueva o movida; fallo cerrado; intermediario del bash (`exec` de orden e interactivo, política de Space, autenticación, deny-list, ficha y registro, ciclo de vida); formatters y LSP desactivados en mediado con motor de nube y alguna N2; `engineN2` y `bashBroker` en el doctor | AC17–AC45, AC4, AC15 y AC16 modificados |
| Cierre | Validación de experiencia con el modo mediado activo, sobre la integración de S1–S5 | AC14 |

Orden: S1 y S2 en paralelo (decisión de la operadora al aprobar); S3 sobre S1 y S2; S4 sobre S3; S5 sobre S1; S6 sobre S1 y S5. S6 bloquea dar FS-6 por cumplido y anunciar el modo mediado con motor de nube.

## Criterios de aceptación

- **AC1:** en mediado, con el sandbox `LIVE`, una orden del workspace (`python3 --version`, `cargo test`) se ejecuta sin preguntar.
- **AC2:** con el sandbox en otro estado distinto de `LIVE` (sonda fallida, binario no fiable), todo bash pregunta. Se prueba falseando la sonda.
- **AC3:** las prohibiciones duras se deniegan siempre, aunque el sandbox ya las impidiera. Se prueba con el corpus del red team de la deny-list, sin fugas.
- **AC4:** la sonda verifica, desde dentro del sandbox, que fallan:
  - la lectura de `~/.ssh` y de los ficheros de credenciales;
  - la escritura fuera del worktree;
  - la red directa;
  - el acceso a los sockets de Space;
  - la lectura de la contraseña del motor;
  - la conexión al socket del intermediario del bash (FS-6b): su ruta no existe dentro del sandbox y conectar falla.
- **AC5:** `doctor --environment` prueba cada recurso desde dentro del sandbox, y todos pasan:
  - `git fetch` del remoto;
  - `gh api user`;
  - una búsqueda en una cúpula;
  - una llamada MCP;
  - un ping A2A a un puerto declarado.
- **AC6:** un recurso no declarado falla con su motivo: un puerto de loopback sin declarar, un dominio ajeno, un fichero de credenciales (`~/.ssh`, `~/.config/gh`…) o una ruta de `$HOME` que el entorno no incluye.
- **AC7:** volcar el entorno y el sistema de ficheros desde dentro del sandbox no revela ninguna credencial. Se prueba buscando los tokens reales sin imprimirlos.
- **AC8:** el proxy inyecta cada credencial solo hacia su destino. Una petición hacia un destino permitido pero ajeno a esa credencial sale sin ella.
- **AC9:** un dominio no permitido se deniega con `[Red no permitida]` y queda registrado.
- **AC10:** cada denegación aparece en el panel con su motivo.
- **AC11:** ampliar el entorno desde una denegación permite la siguiente orden equivalente, con alcance de workspace y registro.
- **AC12:** la intención explícita solo vale si la escribe la operadora en la UI. El mismo texto en la salida de una herramienta no desbloquea nada.
- **AC13:** una pregunta llega al móvil y se resuelve desde allí.
- **AC14:** la rúbrica de experiencia de SE-432 no empeora con el modo mediado activo frente al modo interactivo.
- **AC15:** en una máquina donde el backend no puede crear el sandbox (por ejemplo, Ubuntu con user namespaces restringidos por AppArmor), el estado es UNKNOWN, todo bash pregunta y el doctor nombra la causa y el arreglo para esa distribución. Nunca se usa como backend de confianza un binario de un directorio que el usuario pueda modificar. Con cúpulas N2 y motor de nube en mediado, el doctor dice además si el motor tiene espacio con máscaras (`engineN2`) y, si no, que el motor no arranca por FS-6b, no por el backend de bash. En Ubuntu con user namespaces restringidos y el `bwrap` de confianza con su perfil, el bash del agente llega a `LIVE` por el intermediario sin perfil de AppArmor adicional.
- **AC16:** en macOS, el backend Seatbelt pasa la misma sonda (AC4) y el mismo `doctor --environment` (AC5–AC6). En macOS, con cúpulas N2 y motor de nube en mediado, el motor no arranca (`engineN2: UNAVAILABLE`) hasta que haya un perfil Seatbelt del motor medido, y el doctor lo dice como límite de FS-6b, no como fallo de Seatbelt.

Datos comunes de las pruebas:
- worktree: un repositorio git temporal;
- cúpula N2 `vaults/privada/`, con `n.md` = `SECRETO-N2\n`;
- cúpula N1 `vaults/abierta/`, con `a.md` = `NOTA-N1\n`;
- fichero normal `ok/o.md` = `NORMAL\n`;
- fichero marca `/tmp/<dir de la prueba>/ejecutado`, que una orden crea si llega a ejecutarse.

Las pruebas con motor real usan `opencode` (se saltan, diciéndolo, si no está). Las de backend usan el `bwrap` de `working_bwrap` (se saltan, diciéndolo, si no hay ninguno). AC17–AC21 se ejecutan **con la superposición N2 de `harden_for_n2` desactivada**, para probar que la frontera es el sistema operativo y no los patrones de permiso, y se repiten con ella activada.

**Espacio del motor**

- **AC17:** con el motor real en su espacio, `read` no entrega `SECRETO-N2` por ningún enlace del worktree:
  - `sub/atajo -> ../vaults/privada`, pidiendo `sub/atajo/n.md` en forma relativa y absoluta;
  - `f -> vaults/privada/n.md` (enlace al fichero);
  - `v -> vaults` (enlace a lo que la contiene), pidiendo `v/privada/n.md`;
  - un enlace absoluto a la ruta canónica de la cúpula.
  Control: el mismo `read` sin el espacio del motor entrega `SECRETO-N2` (la prueba mide algo). Test: `the_real_engine_cannot_read_an_n2_dome_through_a_link_inside_its_namespace`, junto a `the_real_engines_read_tools_cannot_read_an_n2_dome_with_the_overlay_and_can_without_it` (space-engine/src/process.test.rs).
- **AC18:** `edit` y `write` por `sub/atajo/n.md` y por `sub/atajo/nueva.md` fallan; después, en el host, el SHA-256 de `vaults/privada/n.md` no ha cambiado y `vaults/privada/nueva.md` no existe.
- **AC19:** `list` de `sub/atajo` y de `v/privada` no muestra `n.md`.
- **AC20:** las rutas directas y con `..` no entregan `SECRETO-N2`: `vaults/privada/n.md` (relativa y absoluta), `ok/../vaults/privada/n.md`, `sub/atajo/../atajo/n.md` y `/proc/<pid de Space en el host>/root/<ruta absoluta de la cúpula>/n.md`.
- **AC21:** carrera de la orden larga. Una orden de bash `ln -s ../vaults/privada x && sleep 60` sigue en marcha mientras el motor ejecuta `read x/n.md`, `edit x/n.md` y `list x`; ninguna entrega ni modifica el contenido de la cúpula.
- **AC22:** con `sub/atajo -> ../vaults/privada`, `f -> vaults/privada/n.md` y `bien -> ok` creados antes de arrancar (y otro enlace a la cúpula dentro de un directorio 0o555), `Sandbox::prepare` retira los enlaces a la cúpula antes de lanzar el motor, deja `bien` y la nota de arranque nombra lo retirado. Una prueba con un `find` falso en el `PATH` comprueba que la limpieza no lo ejecuta.
- **AC23:** con las máscaras activas, el motor funciona:
  - salud y `/config` correctos;
  - `read` de `ok/o.md` entrega `NORMAL`;
  - `edit` crea `ok/nuevo.md` en el host, y `list ok` lo muestra;
  - `read vaults/abierta/a.md` entrega `NOTA-N1`;
  - la sonda del sandbox de bash, por el intermediario, llega a `LIVE`;
  - una petición del motor a un proveedor de prueba en loopback llega;
  - el socket del proxy es alcanzable;
  - una sesión creada sobrevive a un reinicio del motor;
  - el perfil de seguridad efectivo de OpenCode (`/proc/<pid>/attr/current`) queda registrado y el doctor lo muestra; en Ubuntu con la restricción es `bwrap//&unpriv_bwrap` y la sonda de bash sigue en `LIVE`.
- **AC24:** la medida desde fuera (§5.2, paso 6) pasa con el espacio correcto y falla, sin usar el motor, en cada uno de estos casos falseados:
  - sin espacio de montaje propio (`/proc/<pid>/ns/mnt` igual al de Space);
  - una forma de la cúpula sin máscara;
  - la máscara escribible;
  - lanzado sin `--proc /proc`: `/proc/<pid>/root/proc/<pid de Space>` existe, o hay más entradas numéricas que procesos del espacio.
- **AC25:** fallo cerrado. En mediado, con una cúpula N2 y sin backend (lista de candidatos vacía y user namespaces denegados por la prueba), el motor no arranca, el estado es `UNAVAILABLE` con `ENGINE_N2_MASKS` y el doctor nombra causa y arreglo. Con la misma máquina y sin cúpulas N2, el motor arranca y `engineN2` es `NOT_NEEDED`.
- **AC26:** en interactivo sin backend, el motor arranca, `engineN2` es `BEST_EFFORT_OFF` y hay aviso; con backend, `engineN2` es `HERMETIC` y AC17 pasa también en interactivo.
- **AC27:** desde una PTY del motor creada **con `command` explícito** (`/bin/sh -c …`, como `probe_exposure_pty`, para que corra en el espacio del motor y no en el sandbox del agente) y desde un servidor MCP del motor (la vía de `probe_exposure_mcp`), `cat vaults/privada/n.md`, `cat sub/atajo/n.md` y `unshare -Urm sh -c 'umount <cúpula>; cat <cúpula>/n.md'` no entregan `SECRETO-N2`.
- **AC28:** procesos.
  - El registro de ejecución tiene dos PID con sus `start_time`: el del init y el de OpenCode.
  - El de OpenCode **no** es el `child-pid` de `--info-fd`: es su único hijo en el lanzamiento y pasa `is_engine_process`.
  - La contraseña del motor no aparece en `/proc/<pid>/environ` ni en `/proc/<pid>/cmdline` del lanzador exterior ni del init.
  - X1 (`check_environ_hidden`) pasa sobre el PID de OpenCode.
  - Tras parar el motor no queda ningún proceso del espacio. Se comprueba por los `start_time` registrados y con un MCP de prueba lanzado antes de parar.
- **AC29:** el backend `userns`, forzado sin bwrap en una máquina que lo permite, pasa AC17–AC24, AC27, AC28 y AC32. Además:
  - OpenCode no es PID 1 dentro del espacio;
  - un hijo zombi de un MCP de prueba se recoge;
  - `NoNewPrivs: 1` aparece en `/proc/<pid de OpenCode>/status`;
  - OpenCode no tiene abiertos más descriptores que los suyos: ninguno heredado del lanzador apunta a un directorio.
  En una máquina que no lo permite, el motivo aparece en el doctor y rige AC25.
- **AC30:** cúpula nueva. Una cúpula N2 creada con el motor en marcha deja el motor `DEGRADED` y reiniciado con la máscara nueva en la siguiente reclasificación; después, AC17 pasa sobre esa cúpula.
- **AC31 (IPC del host, riesgo asumido):** la prueba arranca, fuera del espacio y en un `$XDG_RUNTIME_DIR` temporal, un servicio de eco de ficheros por socket Unix (`fs6b-eco.sock`): recibe una ruta y devuelve su contenido. Desde un servidor MCP del motor se le pide `vaults/privada/n.md` por su ruta absoluta.
  - El contenido vuelve: la prueba fija el riesgo asumido, para que no se dé por cerrado sin medirlo.
  - `engineN2.ipcHost` es `"fuera de alcance"` y el doctor lo explica.
  - Si un cambio futuro cierra esta vía, la prueba falla y obliga a actualizar este AC y el riesgo.
- **AC32:** cúpula movida.
  - Dentro del espacio, renombrar el directorio `vaults` o `vaults/privada` desde una PTY del motor creada con `command` explícito (`/bin/sh -c 'mv …'`, como `probe_exposure_pty`) falla, y la máscara sigue en su sitio.
  - Con el motor parado, mover en el host `vaults/privada` a `vaults/otra`: el siguiente arranque en mediado falla cerrado con `ENGINE_N2_MASKS` y nombra la cúpula desaparecida; no arranca con `vaults/otra/n.md` legible.
  - Con el motor en marcha, el mismo movimiento deja el motor `DEGRADED` y parado en la siguiente reclasificación.
- **AC33:** supervivencia y reenganche.
  - Matar Space con SIGKILL deja el motor vivo: los dos PID del registro siguen con su `start_time`.
  - Matar Space con una orden `sleep 300` en curso no deja ningún proceso de esa orden en el host: se busca por el grupo de procesos registrado.
  - Mientras Space está caído, una orden de bash termina con 126 y `[Space no disponible]`, sin crear la marca.
  - El siguiente arranque de Space lo reengancha solo si pasa la medida del paso 6, recrea el intermediario y la siguiente orden funciona. Además queda un `broker_gap` con el intervalo.
  - Reenganche con huérfanos: antes de matar Space, un MCP de prueba deja un nieto huérfano que el init adopta. El init tiene entonces dos hijos, y aun así el reenganche usa los PID y `start_time` del registro y funciona. Control: con el registro alterado a un PID que no es descendiente del init, el reenganche se rechaza.
  - Un motor lanzado sin máscaras por un arranque anterior no se reengancha en mediado: se para y se relanza con ellas.
  - Lanzar el motor desde un hilo de `spawn_blocking` que después termina no mata al motor.
- **AC34:** superficie de Space. Desde un servidor MCP del motor, ninguna superficie de Space alcanzable desde el espacio entrega ni escribe `SECRETO-N2`:
  - el endpoint de hooks, al que se envían eventos con rutas de la cúpula;
  - el proxy de red, con una petición `CONNECT` a un loopback no declarado y con una URL `file://`;
  - el intermediario, con `cat /ruta/absoluta/vaults/privada/n.md` y con un cwd dentro de la cúpula: el sandbox del agente no lo entrega y el cwd se rechaza;
  - la herramienta MCP de cúpulas mediada por Space: con motor de nube, leer o escribir en `vaults/privada` se deniega aunque la operadora apruebe la llamada.
- **AC35:** alias de montaje. La prueba crea, en su propio espacio de usuario y de montaje, un bind de `vaults/privada` en `alias/`.
  - Lanzado el motor desde ahí, `read alias/n.md` no entrega `SECRETO-N2`, y `alias` aparece en `n2Masked`.
  - `cat alias/n.md` por bash, a través del intermediario, tampoco lo entrega.
  - Si `mountinfo` no se puede leer (falseado), el arranque en mediado falla cerrado.

**Intermediario del bash**

- **AC36 (acotado):** cada uno de estos casos cierra la conexión sin ejecutar nada (la marca no se crea) y deja un `broker_rejected` con su motivo y sin el texto de la orden:
  - un tipo de mensaje desconocido, o una versión distinta;
  - un `signal` o un `winsize` antes del `exec`, o un segundo `exec`;
  - `argv` distinto de `["-c", <orden>]` y de `[]`, por ejemplo `["-i"]`, `["-l"]`, `["--login"]`, `["-c"]` o `["-c", "x", "y"]`;
  - `argv` vacío con un descriptor 0 que no es un terminal: una tubería, `/dev/null` o un socket;
  - `argv` vacío con un dispositivo de caracteres en el que `TCGETS` falla, como `/dev/zero`;
  - un mensaje con `MSG_CTRUNC` (más descriptores de los que caben en el búfer de control): se rechaza y, en `/proc/<pid del intermediario>/fd`, no queda ningún descriptor recibido abierto;
  - una orden de 256 KiB + 1 byte, o con un byte NUL;
  - un cwd relativo, fuera del worktree, en `vaults/privada` o en un enlace que lleva allí;
  - dos o cuatro descriptores;
  - un descriptor de directorio, de fichero regular o `O_PATH`;
  - una señal fuera de la lista (`SIGKILL`, `SIGSTOP`, `SIGUSR1`).
- **AC37 (autenticación):** se rechazan, sin ejecutar nada:
  - un proceso del host fuera del espacio del motor, con el mismo uid, que ejecuta el cliente fijado: su `/proc/<pid>/ns/pid` no es el del motor (requisito mínimo);
  - una petición que intenta fijar política: un `exec` con campos de entorno, montajes, red o binario. El protocolo no los tiene, así que es un mensaje malformado;
  - un proceso del espacio del motor que habla el protocolo sin ser el cliente, por ejemplo un guion de Python;
  - el cliente fijado lanzado por un proceso que no es OpenCode (un MCP que lo ejecuta desde un hijo suyo);
  - una copia del cliente con otro inodo.
  Se acepta la orden de la herramienta bash del motor real. El socket es 0600 en un directorio 0700. Con `SO_PEERPIDFD` no disponible (falseado), la comprobación de `start_time` rechaza un PID reutilizado entre la conexión y la decisión.
- **AC38 (señales y código de salida):**
  - `exit 7` devuelve 7.
  - `kill -TERM $$` dentro del sandbox devuelve 143.
  - Abortar desde el motor una herramienta bash con `sleep 300` (el motor envía SIGTERM al cliente) deja el grupo del sandbox terminado en 5 s y la limpieza FS-5 hecha: un `rebase-merge` creado por la orden no queda.
  - SIGINT al cliente devuelve 130.
  - SIGKILL al cliente: el intermediario ve EOF y el sandbox termina en 5 s como mucho.
  - Una señal enviada en una conexión no llega nunca al sandbox de otra conexión concurrente.
  - Ciclo de vida sin huérfanos: parar el motor con tres órdenes `sleep 300` en curso no deja procesos de ninguna en el host 5 s después de matar el init. Lo mismo al borrar la sesión que las lanzó.
- **AC39 (TTY):**
  - Con el descriptor 0 en una PTY del motor de 40×120, `stty size` dentro del sandbox devuelve `40 120`.
  - Tras un `winsize` a 50×100, devuelve `50 100`.
  - Sin terminal, `printf 'hola' | <orden wc -c>` devuelve 4, y stdout y stderr llegan cada uno a su descriptor.
  - Dentro del sandbox no se puede inyectar entrada en el terminal del motor (`TIOCSTI` falla, por `--new-session` como hoy).
- **AC40 (límites):**
  - Con 16 órdenes `sleep 30` en curso, la 17.ª termina con 126 y `[Sandbox ocupado]` sin crear la marca; al acabar una, la siguiente se acepta.
  - Una conexión que no envía el `exec` en 5 s se cierra.
  - 10 000 mensajes `winsize` en un segundo no hacen crecer la memoria del intermediario más de 1 MiB, y se registran una sola vez.
- **AC41 (fallo cerrado):** una orden de bash aprobada termina con 126, sin crear la marca, y el aislamiento no es `LIVE`:
  - con el socket borrado o el intermediario parado, con `[Space no disponible]`;
  - con el intermediario que no responde en 5 s, con `[Sandbox no disponible]`;
  - con un `PATH` que contiene un `bash` falso que crearía la marca: el cliente nunca lo ejecuta.
  En todos los casos, si Space está vivo, `bashBroker` es `DOWN` con su motivo.
- **AC42 (equivalencia con S1):** por el intermediario pasan, sin cambios en sus aserciones:
  - la sonda de AC4;
  - las baterías `fs_battery_*`;
  - el corpus de AC3;
  - los tests de FS-5 y de enlaces N2 del envoltorio.

  El sandbox que lanza el intermediario usa el conjunto de máscaras de §5.2, paso 2, alias incluidos.
- **AC43 (prohibiciones duras, ficha y registro):**
  - Enviada directamente al socket por un cliente válido sin ficha, `sudo true` termina con 126 y `[Prohibición dura]`, sin crear la marca, y deja un `broker_exec` con `ficha: ninguna`, resultado `deny` y motivo. Con una ficha válida para esa misma orden, el resultado es el mismo: la deny-list se aplica siempre.
  - Una orden aprobada por `permission.asked` (`touch <marca>`) consume su ficha: el `broker_exec` lleva su sesión y su id de llamada. Repetir la misma petición ya no encuentra ficha.
  - Una ficha caducada (más de 120 s) no se usa.
  - Sin ficha, `touch <marca>` se ejecuta solo si pasa la deny-list completa del modo mediado. Queda registrada como «orden sin llamada aprobada» y aparece en el panel de §4. Una orden sin ficha que cae en una regla `ask` explícita de la configuración de prueba (`ask: "git push *"`, con `git push origin agent/x`) termina con 126 y `[Sin aprobación]`, sin ejecutarse. La misma orden con su ficha se ejecuta.
  - Ninguna entrada del registro contiene el valor de un token de prueba incluido en la orden.
  - Robo de ficha: un MCP de prueba, hijo directo de OpenCode, ejecuta el cliente con la misma orden que una llamada aprobada en curso y consume su ficha. El `broker_exec` del MCP lleva su ejecutable y su padre, distintos de los de la herramienta bash. La llamada real queda registrada sin ficha y por la deny-list completa.
- **AC44 (formatters y LSP desactivados):** la configuración anclada declara un formatter `probe` y un servidor LSP `probe` que crean cada uno su marca al ejecutarse.
  - En mediado con motor de nube y una N2, tras `edit` de `ok/x.fmt`, ninguna marca existe; `/config` del motor muestra `formatter: false` y `lsp: false`; el doctor muestra `formatters: off` y `lsp: off`.
  - Una superposición que los reactivara hace fallar la comparación final de configuración y el motor no se usa.
  - Control: sin cúpulas N2 o en interactivo, las dos marcas aparecen (la prueba mide algo).
- **AC45 (terminal de la operadora por `exec` interactivo):**
  - En mediado, abrir una terminal desde la UI de Space crea la PTY del motor sin `command`, y la shell corre dentro del sandbox del agente:
    - `test -t 0` es verdadero y `stty size` devuelve el tamaño de la terminal de la UI;
    - tras redimensionar en la UI, `stty size` devuelve el tamaño nuevo;
    - `cat vaults/privada/n.md`, `ls ~/.ssh` y `sudo true` fallan;
    - `exit 3` cierra la PTY y el código que ve la UI es 3;
    - el `broker_exec` dice `interactiva`, con la sesión emparejada y el id de la PTY de su ficha.
  - Cerrar la terminal desde la UI con un `sleep 300` en primer plano no deja procesos de esa shell en el host 5 s después.
  - Sin ficha de terminal, un `exec` interactivo con un terminal válido (un MCP de prueba que abre su propia PTY y ejecuta el cliente sin argumentos) termina con 126 y `[Sin aprobación]` y no lanza shell. Lo mismo con una ficha caducada (más de 10 s) y con una ficha ya usada.
  - Dos `exec` interactivos sobre una sola ficha: se acepta uno y se rechaza el otro, y el registro dice cuál consumió la ficha.
  - El cliente sin argumentos y con el descriptor 0 en una tubería termina con 126 y `argumentos no admitidos` sin conectar al socket: el intermediario no registra ninguna conexión.

## Fuera de alcance

- El modo interactivo: sigue con la configuración del motor de la operadora, salvo las máscaras N2 del motor de mejor esfuerzo (§5.4).
- Un juez con modelo para decidir permisos, descartado en D-MED-1.
- Windows: el diseño de la DACL va aparte.
- **IPC del host** (D-MED-9, §5.8): servicios del usuario que corren fuera del espacio y a los que un hijo del motor puede pedir que lean una cúpula. Riesgo asumido y escrito; AC31 lo fija.
- **Espacio de red propio para el motor**, que cerraría el IPC del host del todo: requisito aparte.
- **Seatbelt para el motor en macOS.** Seatbelt sigue sin ejecutarse en un Mac (AC16 pendiente). En mediado con N2 presentes en macOS rige el fallo cerrado de §5.5 hasta que haya un perfil del motor medido en una máquina macOS (AC16 modificado).
- **Tapar en el espacio del motor algo más que las N2:** credenciales del host o el estado privado de Space (alarma `DEGRADED` de RUN-LINUX). El espacio lo haría posible, pero cada exclusión choca con lo que el motor necesita y va en su propio requisito.
- **Reabrir `grep`, `glob` y `lsp`.** Hoy se niegan enteros si una N2 cuelga del worktree. Con las máscaras podrían volver, pero eso se decide tras medir FS-6b, no en este slice.
- **Ampliar el espacio del motor en caliente** con una cúpula nueva (entrar en sus namespaces desde Space). Se reinicia el motor (§5.2, paso 9).
- **Exigir ficha a toda orden sin excepción.** La sonda y el `shell` de la operadora no pasan por `permission.asked`. Las órdenes sin ficha van por la deny-list completa y el registro (§5.7, AC43); no se bloquean.
- **Formateo automático y diagnósticos del LSP en mediado con motor de nube y alguna N2.** Se desactivan (§5.8). Volver a tenerlos exige lanzarlos dentro del sandbox del agente, lo que es un requisito aparte.
- **Contenido N2 ya copiado fuera de la cúpula**, incluidos enlaces duros previos a ficheros de la cúpula: las máscaras tapan rutas, no inodos. Sigue como en FS-6.

## Riesgos

- **CA local:** es una superficie nueva. Solo confía en ella el sandbox, nunca el host, y hay que diseñar su rotación.
- **Recursos de Savia que no hablan HTTP** (sockets Unix de daemons): se inventarían y se decide uno a uno.
- **Rendimiento:** un bwrap por orden frente a un sandbox persistente por sesión. Se mide en S1.
- **IPC del host (asumido).** Un hijo del motor puede obtener contenido N2 a través de un servicio del host capaz de leer ficheros o ejecutar órdenes, incluido el gestor de servicios del usuario. El doctor lo dice y AC31 lo mide.
  - **Los formatters y los LSP abren esta vía al agente.** Cargan configuración del repositorio, que el agente escribe, así que el agente ejecutaría código en el espacio del motor sin el sandbox de bash. Por eso se desactivan en mediado con motor de nube y alguna N2 (§5.8, AC44). Si alguna vez se reactivan, el residuo de IPC vuelve a estar al alcance del agente y no solo de un MCP.
  - Con ellos desactivados, queda una sola vía: los MCP. EN-1 y EN-3 limitan qué orden de MCP se ejecuta, no lo que ese MCP haga después. Un MCP que ejecute órdenes bajo inyección de prompt sigue pudiendo usar el IPC del host. No hay mitigación técnica en FS-6b para eso: es el riesgo asumido.
- **Intermediario como superficie nueva.** Es un socket alcanzable desde el espacio del motor que lanza procesos en el host. Lo acotan:
  - un solo tipo de petición;
  - la autenticación del par;
  - la invariante «nunca ve más que su llamante»;
  - los límites.
  Un fallo en el análisis de la petición es crítico: el analizador es pequeño, sin dependencias nuevas y con pruebas de mensajes malformados (AC36).
- **Robo de ficha entre llamantes válidos.** Un MCP hijo directo de OpenCode pasa la autenticación. Si ejecuta el cliente con el mismo texto que una llamada aprobada en sus 120 s, consume esa ficha. No gana acceso: el sandbox es el mismo y la llamada real sigue por la deny-list completa. Pero la ficha queda atribuida a quien no era. El registro lleva el ejecutable y el padre del llamante para distinguirlo (AC43).
- **Otros hijos del motor que leen configuración del repositorio.** Formatters y LSP se desactivan, y los MCP salen de la configuración anclada. En S6 se inventaría el resto. El primer candidato es el git de instantáneas de OpenCode, que corre en el espacio del motor sobre el worktree.
  - El motor mediado ya lo lanza sin fsmonitor ni hooks (`engine_env`).
  - Queda medir si carga otra configuración que el agente controle (filtros de `.gitattributes`, `include` de la configuración del repositorio).
  - Si la carga, se neutraliza o se añade a este riesgo antes de cerrar S6.
- **Lo tecleado en la terminal de la operadora no pasa por la deny-list.** Ocurre también hoy. Lo acotan el sandbox del agente y el alcance del proxy, y la shell solo se abre con una ficha de terminal creada por la UI (AC45).
- **Órdenes sin ficha.** La sonda, el `shell` de la operadora o un MCP que ejecute el cliente llegan sin llamada aprobada. Pasan por la deny-list completa y quedan registradas y visibles en el panel (AC43): hay control y auditoría, no aprobación previa por llamada. Si en S6 la orden de `$SHELL -c` no coincide con la de `permission.asked`, todas irán por ese camino hasta corregirlo.
- **Regla del padre del cliente.** Si una versión de OpenCode interpone un proceso entre él y `$SHELL`, la autenticación rechaza todo bash: falla cerrada, pero deja el modo mediado sin bash. Se detecta en el pin de la API del motor y en la sonda (`bashBroker`).
- **Alias de montaje que aparece después de arrancar.** El paso 2 de §5.2 cubre los que existen al arrancar.
  - Uno creado después por la operadora en el host no entra en un espacio ya creado (la propagación es privada), así que no es visible dentro.
  - Uno creado antes y no detectado por `mountinfo` sería visible. Por eso se falla cerrado si `mountinfo` no se lee.
- **Ventana de una cúpula nueva.** Hasta 30 s entre que aparece y la reclasificación, más el reinicio del motor. Es la misma ventana que FS-2a para las credenciales y la nota la dice.
- **Reinicio del motor.** Reiniciar por una cúpula nueva corta las llamadas en curso. Las sesiones persisten, pero lo que estaba ejecutándose se interrumpe y se registra.
- **Dos PID.** Los caminos que hoy usan el PID del hijo (`is_engine_process`, el registro de ejecución, X1, la parada) pasan a usar el de OpenCode, y la parada termina en el init. Un fallo aquí deja motores huérfanos o apunta a bwrap; lo cubren AC28 y AC33.
- **Respaldo `userns` como código nuevo de bajo nivel** (`unshare`, mapas de uid, init mínimo, cierre de descriptores). Se mantiene mínimo, monohilo y separado del servidor, y pasa las mismas pruebas que el backend bwrap (AC29).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Mediación de permisos de Space | No aplica (Space orquesta el motor por API) | Space configura `permission` del motor y responde a `permission.asked` |
| Sandbox de bash | No aplica (Claude Code tiene su propio `/sandbox`) | Space envuelve bash en su bwrap; en mediado no se carga el plugin de sandbox de terceros |
| Guards de Savia (savia-gates) | Hooks `PreToolUse` | Plugin savia-gates fijado, como hoy |
| Arranque del motor con máscaras N2 | No aplica (Space no lanza Claude Code como motor) | Space lanza `opencode serve` dentro de su espacio de usuario, montaje y PID (bwrap o lanzador `userns`), con un init mínimo, la contraseña por descriptor y los dos PID registrados |
| Herramientas de ficheros del motor (`read`, `edit`, `list`) | No aplica: el `/sandbox` de Claude Code cubre bash, no sus herramientas de lectura | Sin cambios en OpenCode: no ven las N2 porque el proceso no las tiene montadas. La superposición de `harden_for_n2` se mantiene como defensa en profundidad |
| Bash del agente | No aplica | `SHELL` del motor = cliente fijado de Space. Envía `-c <orden>` y sus descriptores al intermediario, que lanza el `bwrap` del agente en el host; no hay anidamiento |
| Limpieza de enlaces N2 al preparar | No aplica | `Sandbox::prepare` en space-server, antes de lanzar el motor |
| Formatters y LSP del motor | No aplica | `"formatter": false` y `"lsp": false` en la superposición de mediado con motor de nube y alguna N2, exigidos por la comparación final de configuración |

### Verification protocol

- [ ] Funciona en runtime OpenCode (motor real, modo mediado)
- [ ] Tests cubren ambos paths (dentro del sandbox LIVE y fuera de LIVE)
- [ ] Si añade hooks: registrados en plugin `savia-gates`
- [ ] Prueba con el motor real (`opencode debug agent build --tool …`) dentro del espacio, con y sin la superposición N2 (AC17–AC21)
- [ ] Tests cubren los dos backends de Linux (bwrap y `userns`) y los dos modos (mediado hermético, interactivo de mejor esfuerzo)
- [ ] Bash del motor real por el intermediario en Ubuntu con `apparmor_restrict_unprivileged_userns=1`, con la sonda en `LIVE` (AC23, AC42)
- [ ] Sin hooks nuevos: no hay nada que registrar en `savia-gates`

### Portability classification

- [x] **SINGLE_BINDING_DEFERRED**: Space es el cliente de orquestación sobre OpenCode (SE-428). Claude Code ya tiene su sandbox y su auto mode nativos, de los que este diseño toma el modelo. No hay port pendiente: cada motor usa su mecanismo nativo.

## Anexo A — Filas para `docs/SANDBOX-BOUNDARY.md` de Savia Space

Tras FS-6, en «1. Sistema de ficheros»:

| Id | Invariante | Dónde se impone | Prueba |
|---|---|---|---|
| FS-6b | **El motor corre con las máscaras N2** (D-MED-9).<br>Con motor de nube y alguna cúpula N2, el proceso del motor y sus hijos (PTY, MCP, LSP, formatters) corren en su propio espacio de usuario, montaje y PID, con un init mínimo y `/proc` propio. Cada forma de cada cúpula N2 y cada alias de montaje lleva encima un montaje vacío de solo lectura, y sus ancestros están fijados.<br>Ninguna ruta del sistema de ficheros alcanza esas cúpulas: ni directa, ni con `..`, ni por enlace, ni por alias, ni por `/proc/<pid>/root`. Ninguna superficie de Space alcanzable desde el espacio entrega contenido N2.<br>Space registra el PID del init y el de OpenCode, mide desde fuera antes de usar el motor y al reengancharlo, y para matando el init. Los enlaces N2 del worktree se retiran en `Sandbox::prepare`, sobre descriptores, antes de lanzar el motor.<br>En mediado con motor de nube y alguna N2, el motor no ejecuta formatters ni LSP. En mediado, sin espacio no hay motor (`UNAVAILABLE`); en interactivo es de mejor esfuerzo. Una cúpula N2 nueva reinicia el motor; una que desaparece de su ruta impide arrancar.<br>El IPC del host queda **fuera de alcance** (riesgo asumido, `ipcHost` en el doctor) | `Sandbox::prepare`, lanzador del motor (bwrap, `userns`), medida desde fuera, superposición (`formatter`, `lsp`), `engineN2` | AC17–AC35 y AC44 de SE-434 (nombres de test al implementar S6) |

Tras PR-6, en «2. Proceso»:

| Id | Invariante | Dónde se impone | Prueba |
|---|---|---|---|
| PR-7 | **El bash del agente va por intermediario, sin anidar** (D-MED-9).<br>El `SHELL` del motor es un cliente fijado que nunca ejecuta la orden por sí mismo. El intermediario de Space, fuera del espacio del motor, acepta solo `exec` con `["-c", <orden>]`, o `exec` interactivo con `argv` vacío, el descriptor 0 en un terminal y una ficha de terminal de la UI, tres descriptores que no son directorios ni ficheros, y un cwd dentro del worktree y fuera de las máscaras. La política (montajes, entorno, red, límites) la fija Space, nunca la petición. Solo acepta a un par del espacio del motor (`SO_PEERCRED` y `ns/pid`), hijo de OpenCode, que ejecuta el cliente fijado. El socket no es visible desde el sandbox del agente.<br>Aplica siempre la deny-list de prohibiciones duras. Liga cada orden a la ficha de su llamada aprobada o, sin ficha, le aplica la deny-list completa. Registra toda petición. Mata el grupo de procesos de la orden si el cliente desaparece, y sus órdenes mueren con Space.<br>Reenvía cuatro señales y el tamaño de terminal solo a su petición. Respeta los límites de concurrencia, tiempo y tamaño. Si falla, el cliente termina con 126 y el aislamiento no es `LIVE` | cliente del intermediario, intermediario, `wrapper_script` | AC36–AC43 y AC45 de SE-434, AC4 modificado |

Y en la fila FS-6, sustituir «**Las herramientas de lectura del motor** (`read`, `edit`, `list`, `grep`, `glob`, `lsp`) corren fuera del sandbox:» por «**Las herramientas de lectura del motor** (`read`, `edit`, `list`, `grep`, `glob`, `lsp`) corren fuera del sandbox de bash, pero dentro del espacio del motor con las máscaras N2 (FS-6b); además, como defensa en profundidad,».
