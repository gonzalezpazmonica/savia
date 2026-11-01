# Soul Continuidad v1 — documento de transparencia para TI

> Producto: Soul Continuidad v1 (spec SE-490). Este documento lo puede compartir el operador con el equipo de TI de su organización si quiere o si se lo piden.
> Describe lo que hace el código publicado en `projects/soul-continuity/`, no lo que se planea. Cada afirmación lleva su referencia al código en el [anexo](#anexo-referencias-al-código). Lo que la spec promete y el código aún no cumple está en [Huecos conocidos](#huecos-conocidos), no en el texto principal.
> Estado del código revisado: rama de integración (`agent/s490-integracion-20261023`), que reúne el núcleo, los adaptadores de API, el adaptador web, la política de atención y este documento. Los huecos H-1 a H-5 de la revisión anterior están cerrados en ella (ver [Huecos conocidos](#huecos-conocidos)).

## En una frase

Soul Continuidad es una herramienta personal: un proceso de **solo lectura**, sin privilegios de administrador, que corre con la cuenta del propio operador en su portátil. Lee las fuentes de trabajo a las que esa persona ya tiene acceso y le responde cuatro preguntas: qué tiene abierto, qué depende de ella, qué cambió y qué compromisos con fecha hay. Se consulta desde una línea de órdenes local y desde la app móvil de Savia Space emparejada, a través de la VPN que gestiona el propio operador.

No envía nada a terceros, no aprueba, no responde correos y no ejecuta acciones en ninguna fuente. No usa modelos de lenguaje.

## 1. Qué es técnicamente

- Código TypeScript que corre sobre el **runtime oficial de Node.js** (versión 22.6 o superior), firmado por su editor. No hay ejecutables propios ni módulos nativos compilados. [A1]
- Las dependencias de ejecución son cero en el núcleo. El adaptador web usa `playwright-core` para manejar el navegador **ya instalado** (Chrome o Edge); no descarga navegadores. [A2]
- Un único proceso por usuario. Por defecto funciona bajo demanda: cada orden arranca, responde y termina. Solo si el operador lo pide (`soul autostart install`) queda como servicio de su sesión. [A3]

## 2. Qué lee y de qué fuentes

Cada fuente es opcional y necesita configuración explícita del operador: un **propósito** escrito y una **fecha de consentimiento**. Sin propósito o sin consentimiento vigente, la fuente no se lee. [A4]

| Adaptador | Fuente | Permisos delegados que pide | Qué lee | Qué no guarda nunca |
|---|---|---|---|---|
| `m365-mail` | Correo de Microsoft 365 (Graph) | `Mail.Read` (o `Mail.ReadBasic` si se renuncia a las alertas por remitente) | Metadatos de la bandeja de entrada y de enviados del propio buzón | Cuerpos de correo |
| `m365-calendar` | Calendario (Graph) | `Calendars.ReadBasic` | Reuniones del calendario propio, de ayer a 14 días | Cuerpos ni notas de la reunión |
| `m365-teams` | Chats de Teams (Graph) | `Chat.Read` | Mensajes de los chats del operador de los últimos 7 días, para detectar menciones sin respuesta | Texto de los mensajes |
| `m365-files` | OneDrive/SharePoint (Graph) | `Files.Read.All` | Documentos compartidos con el operador y sus comentarios | Contenido de documentos y comentarios |
| `google-workspace` | Gmail, Calendar, Drive, Tasks | `gmail.metadata`, `calendar.readonly`, `drive.readonly`, opcional `tasks.readonly` | Cabeceras de Gmail, calendario principal, Drive compartido, tareas | Cuerpos |
| `jira` | Jira Cloud | `read:jira-work` | Incidencias asignadas al operador y no terminadas | Descripciones y comentarios |
| `azure-devops` | Azure DevOps | `vso.work`, `vso.code` | Elementos asignados en estado abierto y PR con revisión pedida | Descripciones, comentarios y diffs |
| `github` | GitHub | `repo:read` | Revisiones pedidas, asignaciones y menciones abiertas | Cuerpos de incidencias, PR y comentarios |
| `web` | Webs sin API (portales, paneles) | La sesión que el operador abre a mano en un perfil de navegador dedicado | Vistas de lista declaradas en una receta | Páginas completas |

Detalles que importan a TI [A5]:

- **Solo metadatos.** Las peticiones a Graph usan `$select` de metadatos y Gmail se lee con `format=metadata`. Si la API devolviera cuerpos de todos modos, el adaptador los descarta.
- **Identificadores de aplicación propios.** La autenticación es delegada (flujo de dispositivo o navegador con PKCE) y exige un identificador de aplicación registrado por el operador o por su organización. Los identificadores de aplicaciones conocidas de Microsoft y Google se rechazan antes de hacer ninguna petición: Soul no los usa para sortear el consentimiento.
- **Consentimiento de administración.** Si el inquilino exige consentimiento de administración para un permiso, el adaptador no llama a la API, dice por qué y ofrece la ruta web. No pide más permisos de los de la tabla.
- **Solo lectura en la red.** El transporte deja salir `GET` y `HEAD`. Un `POST` solo pasa si es una lectura de una lista cerrada: hoy solo la consulta WIQL de Azure DevOps. No sigue redirecciones y solo habla HTTPS. [A6]

## 3. Con qué permisos corre

- **Cuenta del operador, sin administrador.** No pide elevación, no instala servicios del sistema y no toca otras cuentas. [A3]
- **Arranque automático opcional y por usuario.** En Linux, una unidad `systemd --user` con `NoNewPrivileges=yes`. En macOS, un `LaunchAgent` del usuario. En Windows, una tarea de inicio de sesión con `LeastPrivilege`. [A7]
- **Arrancar el servicio no concede nada.** Las fuentes siguen dependiendo de su consentimiento propio. [A4]
- **Parada de emergencia.** `soul stop` deja un fichero STOP que sobrevive a reinicios. Mientras existe, no se lee ninguna fuente y la API responde 503. Un STOP ilegible cuenta como STOP. Solo `soul resume` lo levanta. [A8]

## 4. Qué guarda, dónde, cuánto tiempo y cómo se borra

**Dónde.** En el directorio de datos del usuario: [A9]

- Linux: `~/.local/share/savia/soul-continuity` (o `$XDG_DATA_HOME/savia/soul-continuity`);
- macOS: `~/Library/Application Support/Savia/soul-continuity`;
- Windows: `%LOCALAPPDATA%\Savia\soul-continuity`.

Los directorios que crea Soul llevan permisos 0700 y los ficheros 0600 en Linux y macOS. En Windows heredan los permisos del perfil del usuario. Las escrituras son atómicas. [A9]

**Qué.**

| Fichero | Contenido | Cuánto tiempo |
|---|---|---|
| `config.json` | Perfil del operador, fuentes con propósito y consentimiento, nivel de detalle, direcciones de escucha. Nunca tokens | Hasta que el operador lo cambie o desinstale |
| `op-<hash>/snapshot.json` | Última lectura: por elemento, tipo, estado, fuente, referencia, enlace y **título** (asunto o nombre), con fecha de observación y caducidad. Sin cuerpos | Se reescribe en cada lectura. Cada afirmación caduca como máximo a las 24 h [A10] |
| `op-<hash>/history/*.json` | Lecturas anteriores, para responder «qué cambió desde…» | Todo lo de las últimas 2 h y una lectura por hora durante 7 días; lo más antiguo se borra [A11] |
| `op-<hash>/ledger.jsonl` | Correcciones del operador («resuelto», «no aplica»…) | Hasta desinstalar |
| `op-<hash>/attention.json` | Modo de atención declarado | Hasta desinstalar |
| `op-<hash>/adapters/<adaptador>/` | Caché de sincronización delta del correo: enlace delta y metadatos mínimos (id, hilo, remitente, destinatarios, asunto, fecha) | Hasta revocar el adaptador o desinstalar [A12] |
| `devices.json` | Dispositivos emparejados: nombre, fecha y **hash SHA-256** del token, nunca el token | Hasta desinstalar; un dispositivo revocado se queda marcado [A13] |
| `tls/` | Certificado propio y su clave privada (0600) | Se renueva al arrancar si cambian las direcciones o quedan menos de 30 días [A14] |
| `audit.jsonl` | Cada llamada desde un frontend de agente (Claude Code, OpenCode): orden, nivel y recuento. Nunca contenido | Hasta desinstalar |
| `failsafe.jsonl` | Cada STOP y cada reanudación | Hasta desinstalar |
| `credentials-index.json` | Nombres de servicio con credencial guardada, para poder borrarlas. Sin secretos | Hasta desinstalar |

**Tokens de las fuentes.** Van solo al almacén de credenciales del sistema: Credential Manager en Windows, Llavero en macOS y Secret Service en Linux. El secreto viaja por la entrada estándar de la herramienta del sistema, nunca en la línea de órdenes, en variables de entorno, en ficheros ni en logs. Si no hay almacén disponible, el token no se guarda en ningún otro sitio. [A15] El núcleo descarta entera la lectura de un adaptador que devuelva el token en su resultado, antes de escribir nada en disco. [A16]

**Logs.** El servicio solo escribe en la salida estándar las direcciones de escucha y la huella del certificado. Los errores se registran por su tipo, sin datos de trabajo. [A17]

**Exportar.** `soul export` vuelca todo el estado local en JSON. Ese fichero contiene títulos de elementos (datos de la organización): queda donde el operador lo guarde y es su responsabilidad. Un frontend de agente no puede exportar. [A18]

**Borrar.**

- `soul revoke <adaptador>` retira el consentimiento, borra de la caché y del historial las afirmaciones de ese adaptador, su caché de sincronización y sus tokens en todas las variantes de permisos. Para `web`, borra todo `<datos>/web` (perfil del navegador con sus sesiones, huellas y recibos). [A34]
- `soul uninstall --yes` borra las credenciales del índice, retira el arranque automático y borra todo el estado de Soul del directorio de datos. Lo que no es de Soul en ese directorio se conserva y se dice. Sin `--yes` solo enseña lo que borraría. [A19]
- El código del programa (la carpeta del paquete) y el runtime de Node.js no los borra `uninstall`: se borran como cualquier carpeta del usuario.

## 5. Qué escucha en la red y qué nunca sale del equipo

**Qué escucha.**

- **La API para la app móvil (`soul serve`)** escucha solo en las direcciones IP que el operador escribe en `api.listen`, que deben ser las de su VPN. No hay valor por defecto: sin direcciones, no arranca. Las escrituras que equivalen a «todas las interfaces» (`0.0.0.0`, `::` y sus variantes) y los nombres de host se rechazan. El puerto por defecto es 8787. [A20]
- Solo HTTPS con TLS 1.3 y un certificado propio de la instalación (EC P-256), que la app fija por huella. [A14]
- Solo responde a dispositivos emparejados. Para emparejar, el operador ejecuta `soul pair` en su terminal: abre una ventana de 10 minutos y muestra una **clave de emparejamiento** de un solo uso (`soulpk_…`, 178 bits aleatorios) en texto y en un QR. La app la usa contra `/v1/pair/challenge` y `/v1/pair/complete` (protocolo soul-pair-v2), sin enviarla nunca: cada lado demuestra que la conoce con un HMAC. 3 pruebas fallidas invalidan la clave. [A46]
- Por qué 178 bits: quien esté en la VPN durante la ventana puede pedir un reto y probar claves sin conexión. Con un millón de GPU durante los 10 minutos se prueban unas 2^62 claves de 2^178: probabilidad ≈ 2^-116. La versión anterior (código de 10 caracteres, 2^50) se retiró por eso y el servicio la rechaza con un error que pide actualizar la app. La clave está en claro en `pairing.json` (0600) solo mientras la ventana está abierta, porque es la clave del HMAC. El detalle está en el modelo de amenazas del canal (`projects/soul-continuity/docs/canal-amenazas.md`, punto 3 bis).
- **Durante un inicio de sesión con navegador** (OAuth con PKCE), un servidor temporal escucha en `127.0.0.1`, en un puerto aleatorio. Solo acepta la respuesta con el `state` esperado y se cierra al terminar o a los 5 minutos. [A21]
- El navegador del adaptador web se controla por una tubería local, no por un puerto. [A22]

**Qué sale del equipo.**

- Hacia las fuentes: las peticiones de lectura de la sección 2, por HTTPS, a los servicios que el operador configuró.
- Hacia la app emparejada: las respuestas a sus consultas, con el nivel de detalle que decida el operador dentro del máximo de la instalación: `recuentos` (solo cifras), `títulos` (asunto y fuente; por defecto) o `completo`. [A23]
- No hay telemetría, ni servicios intermedios, ni relay, ni push. Fuera de los transportes citados, el código no hace ninguna otra conexión de red. [A24]

**Qué nunca sale.**

- Ningún dato de trabajo va a un modelo de lenguaje en la nube. Cuando la línea de órdenes la invoca un frontend de agente cuyo modelo corre en la nube (Claude Code, OpenCode), la respuesta se rebaja a `recuentos`, salvo que la configuración local declare ese proveedor como aprobado por la organización para estos datos, con quién y cuándo lo aprobó. Ver H-7 sobre el límite de esta protección. [A25]
- El texto libre que escriba el operador en la app no se interpreta, no se guarda y no se envía a ninguna parte: recibe una respuesta fija con las órdenes disponibles. [A26]

## 6. Cómo se desinstala

1. `soul autostart uninstall` (si se activó) y después `soul uninstall --yes`. La segunda orden ya incluye la primera. [A19]
2. Borrar la carpeta del paquete.
3. Si se usó el adaptador web: `soul uninstall` ya borra el perfil dedicado (`<datos>/web`). Las grabaciones de tráfico que el operador haya guardado fuera de esa carpeta las borra él. [A35]
4. Retirar en el proveedor (Microsoft, Google, Atlassian, GitHub) el acceso concedido a la aplicación. Borrar el token en local **no** invalida la concesión en el proveedor. [A27]
5. Retirar el portátil de la VPN, si solo estaba ahí para Soul.

## 7. Qué hace el adaptador web y con qué límites

El adaptador `web` lee webs que no tienen API con el navegador ya instalado, **en un perfil dedicado a Soul**. [A22]

- **Perfil dedicado.** Soul rechaza arrancar sobre un perfil personal de Chrome, Edge, Chromium o Firefox, o dentro de uno. El perfil dedicado lleva una marca y vive en el directorio de datos. El proceso del navegador corre con su propio `HOME` dentro del perfil. El operador inicia sesión a mano, solo en las webs que quiere dar a Soul. Soul no guarda contraseñas, no rellena credenciales y no inyecta cookies.
- **Recetas cerradas.** Cada sitio tiene una receta que declara la lista exacta de URL que puede visitar y los selectores que extraen elementos. Toda navegación, redirección o petición de la página que no case con la lista se corta en la red. [A28]
- **Solo lectura en la red.** Se corta toda petición que no sea `GET` o `HEAD`, salvo las de renovación de sesión de una lista por sitio y, en clientes que leen por `POST` (Outlook, Teams y SharePoint en la web), las operaciones de lectura declaradas por nombre. Una operación desconocida desactiva la receta y avisa. Los WebSocket solo reciben; los envíos se cortan salvo los de mantenimiento. [A28]
- **No envía formularios, no descarga ficheros y no arranca workers.** [A28]
- **Vistas de lista.** No abre elementos individuales cuando abrirlos cambia su estado («leído», «visto»).
- **Páginas sin receta.** Solo se detecta «esta página cambió», guardando una huella SHA-256 del texto, nunca el texto. [A29]
- **Contenido no fiable.** El texto de la web es dato: no elige acciones, no cambia la receta y nunca produce una alerta, como mucho un aviso. [A30]
- **Sesión caducada.** El adaptador se detiene y pide volver a iniciar sesión en el perfil de Soul. [A30]
- **Recetas de clientes reales.** Las plantillas de Outlook, Teams y SharePoint en la web vienen marcadas como `experimental` y no se ejecutan sin un recibo local. Ese recibo sale de validar la receta contra una grabación del tráfico real del propio operador. La grabación contiene datos de la organización: se guarda fuera de cualquier repositorio y se borra tras validar. El recibo no va firmado: protege de un error, no de alguien con acceso a la cuenta del operador. [A31]

## 8. Responsabilidad del operador

Soul Continuidad es una herramienta personal para trabajar con datos a los que el operador ya accede, en su equipo. El operador decide qué instala y qué fuentes activa, y responde de su uso. Soul no sortea controles de la organización: no usa identificadores de aplicación ajenos, no reenvía correo, no publica calendarios. Si un control bloquea una ruta, lo dice y ofrece la siguiente legítima (Graph, luego web, luego manual). [A5]

## Huecos conocidos

Lo que la spec SE-490 promete y el código revisado aún no cumple. No se describe arriba como hecho.

| Id | Prioridad | Hueco | Qué falta o cómo se cerró |
|---|---|---|---|
| H-1 | Cerrado | Ningún adaptador estaba registrado en el núcleo | `productionAdapters` registra solo los que el operador nombra en `connectors.enabled`; nada por defecto; `web` solo si se nombra [A32] [A39] |
| H-2 | Cerrado | Dos almacenes de credenciales; `uninstall` no veía los tokens de los adaptadores | Un único almacén con índice de servicio y cuenta; los adaptadores guardan a través de él y `uninstall` borra todo lo indexado. Test de AC-5 con tokens de dos adaptadores [A33] |
| H-3 | Cerrado | `soul revoke` no borraba los tokens por servicio y permisos ni la caché delta | `soul revoke` llama a `revokeSource`: caché delta y tokens de todas las variantes [A34] |
| H-4 | Cerrado | El adaptador web usaba otro directorio de datos y `uninstall` no borraba `web/` | Mismo directorio que el núcleo, `web` en la lista de lo propio y perfil fijado por el núcleo dentro de `<datos>/web` [A35] |
| H-5 | Cerrado, con riesgo residual | En Linux el perfil cifraba sus cookies con la clave fija de Chromium | El perfil persistente usa `--password-store=gnome-libsecret` y no se abre sin bus de sesión. Residual: si el llavero no responde, Chromium puede caer a la clave fija sin avisar; no verificado contra un llavero real [A36] |
| H-6 | P2 | La declaración «activo esta fuente bajo mi responsabilidad» existe en el contrato, pero es opcional: una fuente con propósito y fecha de consentimiento se lee aunque no la lleve [A37] | Exigir `consent.statement` al activar una fuente de organización |
| H-7 | P2 | La rebaja a `recuentos` para frontends de agente se basa en variables de entorno y en `--frontend`. Protege del uso normal, no de un agente que borre esas variables [A38] | Lo dice el README del núcleo; sin arreglo previsto en v1 |
| H-8 | P2 | Las credenciales en Windows y macOS solo se han probado con un doble, no contra el almacén real. En Windows, bajo Constrained Language Mode, `Add-Type` falla y el almacén da error (sin guardar el token en otro sitio) | CI multiplataforma de AC-1 |
| H-9 | P2 | Las «fuentes locales de la instantánea» (git, specs, traspaso) que lista la spec no son un adaptador del núcleo | Fuera de esta versión del núcleo |
| H-10 | — | El modelo de amenazas del canal tiene sus propios P1 y P2. P1-1 (DPoP), P1-2 (correcciones por dispositivo), P2-8 (caducidad de tokens) y P2-9 (límites de conexión) están cerrados en la integración [A40] [A41] [A42] | Ver `projects/soul-continuity/docs/canal-amenazas.md` |
| H-11 | Cerrado | La API decidía avisos y alertas con la aproximación de Labs del servidor, no con la librería de atención `src/attention/` | La API decide con `Politica` de `src/attention/` y su estado se persiste con `estadoATexto` dentro del estado de atención. Sin franjas de descanso declaradas: el contrato de la app no las tiene todavía [A44] [A45] |

Este documento **no** está revisado todavía por la revisora de seguridad. AC-6 lo exige.

## Anexo: referencias al código

Rutas relativas a `projects/soul-continuity/`, sobre el código integrado (núcleo, adaptadores de API, adaptador web y política de atención en la misma rama).

- **A1** `package.json` (`engines.node >=22.6`, sin `dependencies`); `bin/soul.mjs:1-9`.
- **A2** `src/web/package.json`; `src/web/adaptador/navegador.ts:54-68` (`executablePath` del navegador instalado).
- **A3** `src/startup/autostart.ts:1-10`; `src/cli/cli.ts:390-398`.
- **A4** `src/core/engine.ts:55-62` (`consentProblem`: sin propósito o sin consentimiento vigente, no se lee).
- **A5** `src/adapters/descriptors.ts:42-99` (propósito, nivel, TTL, permisos, qué no guarda); `src/adapters/m365.ts:85,155` (`$select`); `src/adapters/google.ts:111` (`format=metadata`); `src/adapters/oauth.ts:104-115` (identificador propio, ajenos rechazados), `:80-101` (listas de ajenos).
- **A6** `src/core/runtime.ts:12-13,39-56` (núcleo); `src/adapters/http-transport.ts:21,100-104,120` (`READ_POSTS`, `redirect: "manual"`).
- **A7** `src/startup/autostart.ts:59-61` (`Restart=on-failure`, `NoNewPrivileges`), `:87`, `:105-106` (`LogonTrigger`, `LeastPrivilege`).
- **A8** `src/core/failsafe.ts:33-41` (STOP ilegible = STOP); `src/api/serve.ts:46`; `src/api/server.ts:643`.
- **A9** `src/core/store.ts:33-38` (rutas), `:40-43` (0700), `:46-57` (atómico, 0600).
- **A10** `src/contract/claims.ts:53` (`TTL_MAX_S` = 24 h), `:64-87` (forma de la afirmación); `src/core/engine.ts:174`.
- **A11** `src/core/engine.ts:66-74` (`HISTORY_DETAIL_MS`, `HISTORY_DAYS`, `saveHistory`).
- **A12** `src/adapters/delta-cache.ts:1-11,45-53`.
- **A13** `src/api/devices.ts:46-54` (token de 256 bits, solo el hash en disco, caducidad), `:79-87` (verificación en tiempo constante).
- **A14** `src/api/cert.ts:63-86` (EC P-256, SAN con las IP), `:95-113` (renovación); `src/api/server.ts:695` (TLS 1.3).
- **A15** `src/credentials/store.ts:30-42` (secreto por stdin), `:95` (`security -i`), `:108,140` (`-EncodedCommand` sin secretos), `:176-304` (índice sin secretos).
- **A16** `src/core/engine.ts:114-124,156-159`.
- **A17** `src/api/serve.ts:125-126`; `src/api/server.ts:786`.
- **A18** `src/cli/cli.ts:68` (órdenes permitidas a un agente), `:372-388`.
- **A19** `src/cli/cli.ts:138-157`; `src/core/store.ts:111-124` (lista de lo propio, `web` incluido; lo ajeno se conserva); `test/cli.test.ts:283,351`.
- **A20** `src/core/config.ts:66` (sin direcciones por defecto, puerto 8787); `src/api/listen.ts:24-39,57`; `src/api/serve.ts:36`; `test/listen.test.ts:34`.
- **A21** `src/adapters/oauth.ts:241-283` (`127.0.0.1`, puerto 0, `state`, 300 000 ms, `srv.close()`).
- **A22** `src/web/cortafuegos/perfil.ts:10-24` (perfiles personales conocidos), `:91-102` (perfil dedicado, marca, rechazo); `src/web/adaptador/navegador.ts:45-68`.
- **A23** `src/core/config.ts:59-68` (por defecto `titulos`); `src/api/server.ts:379,482-486`; `test/api/contrato.test.mjs:103,142`.
- **A24** Búsqueda de `fetch`, `listen(`, `http.request`, `net.connect` y `dgram` en `src/` integrado: solo `src/core/runtime.ts`, `src/adapters/http-transport.ts` (por `fetchFn`), `src/adapters/oauth.ts` (salida), y `src/api/listen.ts` y `src/adapters/oauth.ts:253` (escucha). Además `src/web/banco/servidor.ts`, que sirve los sitios sintéticos del banco y solo se usa en pruebas. El navegador del adaptador web sale solo por su cortafuegos.
- **A25** `src/core/config.ts:138-144` (`agentLevel`); `src/cli/cli.ts:111-117,188-205`.
- **A26** `src/api/server.ts:585`; `test/api/contrato.test.mjs:607`.
- **A27** `src/adapters/README.md`, sección «Revocación (AC-5)».
- **A28** `src/web/cortafuegos/cortafuegos.ts:1-20,39-43`; `src/web/cortafuegos/decision.ts:215-220`.
- **A29** `src/web/adaptador/vigilancia.ts:1-6,59`.
- **A30** `src/web/adaptador/ejecutor.ts:1-6,27-28,251`; `src/attention/README.md` (en la ruta web ninguna regla produce alerta).
- **A31** `src/web/adaptador/activacion.ts:1-5,57-63`; `src/web/README.md`, sección de grabación y recibos.
- **A32** `src/core/connectors.ts:148-157` (`productionAdapters`: solo lo que nombra `connectors.enabled`); `src/core/engine.ts:132-136` (sin adaptador registrado: «no instalado»).
- **A33** `src/credentials/store.ts:176-304` (almacén único: índice de servicio y cuenta, `keyed()` para los adaptadores, `forgetAll`); `src/adapters/credential-store.ts:1-14,37-40` (`entryKey`, sobre `keyed()` en producción).
- **A34** `src/cli/cli.ts:356-370`; `src/core/connectors.ts:166-176` (`revokeSource`); `src/adapters/revoke.ts:25-36`; `test/ac5-integracion.test.ts`.
- **A35** `src/web/cortafuegos/perfil.ts:26-29` (directorio de datos del núcleo); `src/core/connectors.ts:121-143` (perfil y ficheros del web dentro de `<datos>/web`); `src/core/store.ts:111`.
- **A36** `src/web/cortafuegos/perfil.ts:31-48` (`almacenClaves`); `src/web/adaptador/navegador.ts:51,64`; `src/web/README.md` («Claves de las cookies (Linux)»).
- **A37** `src/contract/adapter.ts:64-69`; `src/core/engine.ts:55-62`.
- **A38** `src/cli/cli.ts:111-117`; `README.md` del proyecto, «Límites conocidos».
- **A39** `src/core/connectors.ts:54-85` (validación de `connectors`: adaptadores del contrato, bases solo HTTPS o loopback), `:92-96` (transporte de solo lectura con bases por servicio); `test/connectors.test.ts`.
- **A40** `src/api/dpop.ts:58-84` (prueba DPoP: ES256, `htm`, `htu`, `iat`, `jti`, `ath`); `src/api/serve.ts:64-81` (clave ligada en el primer uso); `src/api/devices.ts:57-66`; `test/dpop.test.ts`, `test/serve.test.ts`.
- **A41** `src/core/engine.ts:188,311-333` (dispositivo en el libro; listar y deshacer); `src/cli/cli.ts:426-454`; `test/device-corrections.test.ts`.
- **A42** `src/api/server.ts:152-162` (`maxConnections` 32 y tiempos de espera), `:695`; `test/serve.test.ts`.
- **A43** `src/cli/login.ts:21-29` (`init` sin fuentes ni adaptadores), `:83-107` (`login`: flujo de dispositivo o token por stdin al almacén); `test/login.test.ts`, `test/instalar.test.ts`.
- **A44** `src/api/serve.ts:86-89` (estado de atención en disco), `:97-122` (`soul mode` en caliente); `src/api/server.ts:251-268,280-288`; `test/serve.test.ts`.
- **A45** `src/api/server.ts:218-229` (`Politica` configurada por operador), `:260-262` (cada evento lo decide la política); `test/server.test.ts` (H-11).
- **A46** `src/api/pairing.ts:45,76` (clave de 30 base62 de un CSPRNG), `:60-74` (checksum CRC32 y validación), `:101-102` (HMAC soul-pair-v2), `:118-125` (ventana en `pairing.json`, borrado), `:163` (rechazo de v1 con 426); `src/api/qr.ts:242` (QR propio); `src/cli/cli.ts:429` (`soul pair`); `test/pairing.test.ts`, `test/qr.test.ts`.
