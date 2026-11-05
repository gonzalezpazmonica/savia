---
status: APPROVED
priority: P0
developer_type: agent-team
created: 2026-11-03
approved_at: 2026-11-03
approved_by: "operadora, pregunta interactiva 2026-11-03 («Aprobada, empieza ya»), con el prototipo `docs/specs/assets/SE-504-prototipo.html` como contrato visual; la aprobación se formaliza al fusionar esta PR (SE-488)"
author: Savia
phase: A
risk: L4
human_surface: true
related_specs: [SE-428, SE-429, SE-430, SE-431, SE-436, SE-488, SE-490, SE-496, SE-505]
origin: "Mandato de la operadora del 2026-11-03 tras probar la app en su móvil: «hay que cambiar completamente esta app para hacer algo que realmente merezca la pena ser usado por humanos». Arquitectura de información fijada el mismo día: «copia a Claude y ChatGPT, déjate de innovar nada». Encargo de la orquestadora, plan intensivo. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "APPROVED"
    source: "operadora: pregunta interactiva 2026-11-03, «Aprobada, empieza ya», con el prototipo como contrato visual; se formaliza al fusionar la PR (SE-488)"
---
# SE-504 — Savia usable: una app como la de Claude o ChatGPT, conectada a Soul y Space

## Lo que he entendido

### Escenas

Derivadas del prototipo aprobado (`docs/specs/assets/SE-504-prototipo.html`):

1. Son las 8:30 y abres la app. Ves «Buenos días» en el centro, tres sugerencias («¿Qué tengo hoy?», «¿Qué espera respuesta?», «Resume mi semana») y el campo «Escribe a Savia» abajo. Es lo mismo que ves al abrir la app de Claude o la de ChatGPT.
2. Tocas el menú de arriba a la izquierda y se abre el cajón lateral. Arriba están Buscar, Nuevo chat, Tareas y Proyectos. Debajo, tus chats agrupados por «Hoy» y «Ayer»: «Tu día con Savia» tiene un punto azul porque Savia lo ha escrito sin que preguntaras. Abajo del todo, tu nombre y «Portátil conectado».
3. Abres «Tu día con Savia». Savia te dice tres cosas para hoy y te enseña una respuesta al proveedor ya redactada, dentro de una tarjeta con Enviar, Editar y Descartar. Hasta que no tocas Enviar no sale nada. Al tocarlo, la tarjeta cambia a «Enviado a las 9:02».
4. Escribes «¿Y el informe semanal?». Tu mensaje sale a la derecha en una burbuja gris. La respuesta de Savia aparece sin burbuja y trae una tarjeta «Resumen semanal · Documento · 1 página». Debajo de cada respuesta están copiar, me gusta y repetir.
5. Tocas la tarjeta del documento y se abre a pantalla completa, con cerrar a la izquierda y compartir a la derecha. Cierras y vuelves al chat donde estabas. Si el móvil está en modo oscuro, la app también lo está.

### Palabras de la persona

> «Hay que cambiar completamente esta app para hacer algo que realmente merezca la pena ser usado por humanos… necesitamos poder hablar con la máquina, que nos conteste, conversación humana natural, poder revisar, ver imágenes, informes, .md, pdf… necesitamos poder ver contexto… necesitamos poder usar Savia.» — 2026-11-03

> «Necesitamos un Savia activo que viva y trabaje con los operadores como su gemelo operativo.» — 2026-11-03

> «Copia a Claude y ChatGPT, déjate de innovar nada. Solo necesito que hagas algo que pueda sincronizar con Soul, Space, etc., pero que se parezca a la app de Claude o la de ChatGPT, simplemente eso.» — 2026-11-03

> «La inferencia de la empresa es responsabilidad de la empresa. Si la tienen contratada es porque pueden. No somos responsables de esa parte, no se trata de inferencia contratada por mí.» — 2026-11-03

### Qué SÍ será

- Una app con la estructura de la de Claude y la de ChatGPT: barra superior, cajón lateral, chat y compositor abajo.
- Un chat que contesta de verdad, con Savia y con Soul detrás, en lenguaje natural.
- Savia escribe primero cuando hay algo que importa, como un chat nuevo con punto de no leído.
- Nada con efecto ocurre sin que la persona toque Enviar en una tarjeta de permiso.
- Documentos (md, PDF, imágenes) como tarjeta dentro del chat que abre un visor a pantalla completa.
- Paleta neutra, tipografía del sistema y tema claro u oscuro según el sistema.

### Qué NO será

- Una barra inferior de destinos, ni Inicio, Contexto o Conversaciones como pestañas.
- Una identidad visual propia, un color de marca en la interfaz ni animaciones de autor.
- Una consola de órdenes: nadie escribe «q1» ni aprende la gramática de Soul.
- Pantallas con «Continuidad», «Soul», niveles como código (`N4`) ni órdenes de terminal.
- Un agente que actúa sin permiso o que instala skills de terceros.

### Confirmación

- fecha: 2026-11-03
- respuesta: «Aprobada, empieza ya»

La operadora respondió a la pregunta interactiva de aprobación después de ver el prototipo y sus capturas. Las escenas de arriba describen ese prototipo pantalla a pantalla y no añaden nada que no esté en él. El prototipo anterior, con barra de cuatro destinos y estética propia, quedó rechazado.

## Slice S0 — Prototipo navegable

- prototipo: `docs/specs/assets/SE-504-prototipo.html`, un solo fichero HTML sin dependencias que se abre en el navegador del móvil. Muestra la pantalla vacía de nuevo chat, el chat «Tu día con Savia» con la tarjeta de permiso y la del documento, el cajón lateral y el visor. Con `?s=chat`, `?s=drawer` y `?s=doc` se abre directamente en cada estado. Es una copia del prototipo que vio la operadora con el nombre de la persona sustituido por uno genérico.

### Confirmación del prototipo

- fecha: 2026-11-03
- respuesta: «Aprobada, empieza ya»

## Problema (auditado el 2026-11-03)

La app de Savia Space se puede instalar y es segura, pero una persona normal no la puede usar. La auditoría de la app actual (Android `0.1.0`, probada en un teléfono real) encontró 32 fricciones, 10 de ellas bloqueantes:

| Fricción | Texto real que ve la persona |
|---|---|
| Hay que aprender la gramática de Soul | «Solo órdenes cortas (por ejemplo «q1» o «modo foco durante:2h»). Soul no interpreta texto libre aquí.» |
| Jerga del modelo de niveles | «Detalle: títulos (máximo: títulos)» |
| Estados vacíos sin causa ni salida | «Ahora no hay nada aquí.» |
| Falso error con el teléfono emparejado solo con Soul | «Este teléfono no está conectado a Space. Conecta en Ajustes.» |
| Órdenes de desarrollo en mensajes de usuario | «Comprueba que Space está en marcha y que adb reverse está activo.» |
| Nombres de enum en pantalla | `api`, `VIGENTE`, `N4`, `github: 3` |
| Barra superior de pestañas de texto que no cabe | «Ajustes» sale partido en vertical |
| Dos superficies llamadas «Soul» que no comparten nada | la pestaña Soul de Space, cuyo chat no responde, y la sección Soul de Continuidad, que solo admite órdenes |

Faltan además capacidades básicas: no hay conversación que responda, no hay visor de documentos, la instalación pidió seis órdenes de terminal (tres con `sudo`) y las capturas de pantalla estaban bloqueadas sin que nadie lo pidiera.

La causa es el modelo de interacción: la app es una consola de órdenes con pestañas. Las apps de Claude y ChatGPT resuelven lo mismo con una estructura que millones de personas ya conocen, y la operadora ha decidido copiarla tal cual.

Las piezas de seguridad ya existen en Space y no se reinventan: el carril hacia Claude con filtro por nivel (`soul_cloud`, `cloud_gate`), los adjuntos N2 con confirmación, hash y recibo (`attachments.rs`), la mediación de permisos y los recibos firmados (SE-428), las aprobaciones con biometría (SE-430) y la memoria operativa de Soul (SE-490). Falta la superficie.

## Objetivo

Que una persona sin conocimientos técnicos abra la app y la use sin aprender nada nuevo, porque se maneja como la de Claude o la de ChatGPT. Que Savia le escriba primero cuando algo importa, le conteste con sus datos de Soul y de Space, le enseñe documentos y le pida permiso antes de hacer nada. Todo ello sin ver una orden de terminal ni un identificador interno.

Las garantías no bajan: la autoridad sigue en la persona, N3 y superiores nunca salen por el carril personal, N2 sale con recibo, los datos N4 de la empresa solo van al proveedor que haya declarado la organización y nada con efecto ocurre sin una confirmación visible.

## Qué decide esta spec

1. **La estructura es la de Claude y ChatGPT, sin variaciones de autor.** Lo que no esté en el prototipo o en esas dos apps no se añade sin una decisión nueva de la operadora.
2. **Savia es un gemelo activo.** Soul (SE-490) actúa como agente persistente: escribe primero cuando hay algo que importa, propone y prepara trabajo. Lo hace en la misma interfaz de chat, como un chat nuevo con punto de no leído; no tiene pantalla propia.
3. **Una sola voz llamada Savia.** En la interfaz no aparecen «Soul» ni «Continuidad». El portátil y el ordenador se nombran con palabras humanas («tu portátil», «tu ordenador»).
4. **Lenguaje natural; efectos solo con tarjeta de permiso.** Ni Soul ni ningún ejecutor interpretan texto libre como orden. La frase se traduce a una propuesta estructurada que la persona envía, edita o descarta.
5. **Dos carriles de inferencia que nunca se mezclan**: el personal (Claude de la persona, con `cloud_gate`) y el de la organización (solo si la instalación lo declara). Decisión D1 de la operadora.
6. **Capturas permitidas por defecto** (decisión de la operadora, PR #15 del repo de Space), con un interruptor opcional para bloquearlas.

## Diseño

### 1. Arquitectura de información (calcada de Claude y ChatGPT)

Una sola pantalla principal, el chat, con tres piezas fijas y dos superficies superpuestas.

| Pieza | Qué tiene | Referente |
|---|---|---|
| **Barra superior** | Menú (abre el cajón) a la izquierda, título del chat en el centro y Nuevo chat a la derecha | Igual en las dos apps |
| **Cajón lateral** | Buscar; Nuevo chat, Tareas y Proyectos; chats agrupados por fecha («Hoy», «Ayer», «Últimos 7 días», «Anteriores»), con punto de no leído en los que escribió Savia; abajo, la cuenta con el estado del portátil («Portátil conectado») | Igual en las dos apps (ChatGPT llama Proyectos a lo mismo) |
| **Chat** | Mensajes de la persona a la derecha en burbuja gris; respuestas de Savia a todo el ancho, sin burbuja; bajo cada respuesta, copiar, valorar y repetir | Igual en las dos apps |
| **Compositor** | Abajo, una caja redondeada con adjuntar (+), el texto «Escribe a Savia», dictar (micrófono) y enviar | Igual en las dos apps |
| **Pantalla de nuevo chat** | Saludo centrado con el nombre de la persona y de 2 a 4 sugerencias en píldora | Igual en las dos apps |
| **Visor** | Documento a pantalla completa con cerrar y compartir en la barra superior | Visor de artefactos y ficheros de ambas |

**Gestión de chats.** Una pulsación larga sobre un chat del cajón ofrece renombrar, fijar, archivar y eliminar, igual que en ChatGPT. Buscar encuentra por título y por contenido.

**Tareas.** Desde el cajón. Una lista con dos grupos: «Esperan algo de ti» (propuestas y aprobaciones pendientes) y «En curso» (lo que Savia está haciendo, con Parar). Cada elemento abre el chat donde nació. Las tareas programadas (preparar el día, cierre semanal) se listan en un tercer grupo, «Programadas», con su próxima ejecución, y se pausan o editan con tarjeta. Es el equivalente de las tareas programadas de ChatGPT.

**Proyectos.** Desde el cajón. Cada proyecto agrupa sus chats y sus documentos, y se abre como una lista de chats con sus ficheros arriba, igual que los proyectos de Claude y ChatGPT.

**Cuenta y ajustes.** Tocar la cuenta abre Ajustes: emparejamiento y estado del portátil y del ordenador, notificaciones y modo concentración, **memoria** (lo que Savia sabe de la persona, con origen y fecha, corregible y borrable, como «Memoria» en Claude y ChatGPT), privacidad (bloquear capturas), apariencia (sistema, claro u oscuro) y «Comprobar mi instalación».

**Escritorio.** La web de Space usa la misma estructura con el cajón fijo a la izquierda, como las versiones web de Claude y ChatGPT.

### 2. Aspecto: sin innovación visual

- **Paleta neutra.** Blanco y grises en claro, y gris oscuro (no negro puro) en oscuro, como en el prototipo. Botón principal en el color del texto, con el texto invertido. Ningún color de marca en la interfaz. Solo el estado del portátil lleva un punto verde, siempre acompañado de texto.
- **Tipografía del sistema** (la familia por defecto de Android, y la del sistema en la web). Ningún tipo propio.
- **Tema según el sistema** por defecto, con «claro» y «oscuro» en Ajustes.
- **Iconos de trazo** como los del prototipo, todos con etiqueta accesible.
- **Sin animaciones de autor.** Solo las del sistema, y ninguna si la persona pidió reducir el movimiento.
- Los tokens de tema del prototipo (`--bg`, `--fg`, `--muted`, `--line`, `--bubble`, `--panel`, `--btn`) son la referencia de color para Android y la web.

### 3. Savia escribe primero

El gemelo vive en el portátil y revisa sus fuentes (SE-490) con un latido periódico: por defecto cada 30 minutos, configurable, y además al empezar y al acabar el día. Usa reglas deterministas: compromisos que vencen, respuestas que esperan y cambios desde la última vez.

- Si nada supera el umbral de la política de atención, no hace nada y no deja rastro.
- Si algo lo supera, abre o continúa un chat («Tu día con Savia») con **un** mensaje de como máximo 3 asuntos, con una propuesta por asunto. El chat aparece arriba en el cajón con punto de no leído y, si la política de atención lo permite, con una notificación.
- La selección de qué decir se hace en el portátil sin modelo. Redactar un borrador sobre datos del trabajo sigue la regla de carriles (§6).
- Respeta el modo concentración, el descanso y el presupuesto diario de avisos (SE-490 AC-4b). Lo que no notifica lo deja en el chat.
- No instala ni carga skills, plugins ni herramientas de terceros. Lo que aprende de la persona (preferencias, procedimientos) aparece en Ajustes → Memoria marcado como aprendido, y un procedimiento aprendido no se usa sin preguntar hasta que la persona lo aprueba.

### 4. Conversación

- **Streaming.** La respuesta aparece mientras se genera, por SSE. Mientras Savia usa herramientas se ve una línea gris con el paso en lenguaje humano («consultando tu portátil»). Mientras hay algo en curso, el botón de enviar se convierte en Parar, como en las dos apps; corta la generación y detiene la ejecución con la semántica de PARA de SE-431.
- **Acciones bajo cada respuesta:** copiar, me gusta / no me gusta y repetir. Repetir genera otra respuesta; nunca repite una acción ya enviada.
- **Sugerencias.** En la pantalla de nuevo chat, como píldoras. Tras una respuesta, solo si ayudan, como en las dos apps.
- **Fuentes.** Una afirmación que viene de un dato (documento, nota de cúpula o elemento de la memoria operativa) lleva una cita tocable. La cita abre el documento en el visor o una hoja «¿por qué lo sé?» con fuente, antigüedad y caducidad (`source_refs`, `observed_at` y `valid_until` de SE-490).
- **Quién responde.** Tocar los tres puntos de una respuesta muestra quién la generó («Claude, tu cuenta personal», «modelo local de tu ordenador» o «el servicio de IA de tu empresa (Azure OpenAI)»), con el recibo si lo hay. Cuando responde el servicio de la empresa, una línea gris discreta lo dice en el propio mensaje, y también donde el proveedor cambia dentro del chat.
- **Texto de terceros inerte.** El texto que no escribió la persona ni Savia (asuntos de correo, comentarios de PR, notas importadas) entra al modelo marcado como dato no fiable, se pinta con una barra lateral gris, sin enlaces activos ni HTML, y nunca genera una tarjeta de permiso.

### 5. Tarjeta de permiso

Toda petición con efecto, venga de la persona o de la iniciativa del gemelo, produce una tarjeta dentro de la respuesta, como en el prototipo:

- Una línea gris con qué y a quién («Enviar correo a Proveedor · Asunto: Plazos de entrega») y el contenido exacto que saldrá.
- Tres botones: el principal con el verbo de la acción (**Enviar**, **Activar**, **Mover**), **Editar** y **Descartar**.
- Estados: propuesta, en curso (con Parar), hecha («Enviado a las 9:02», con deshacer si la acción lo admite), descartada y fallida (con el motivo en una frase).
- Al confirmar, se emite la orden estructurada al ejecutor que corresponde: gramática de Soul (`POST /ordenes`), comando rápido de Space o tarea mediada (SE-428). El ejecutor aplica sus propias reglas.
- **El riesgo lo calcula Space** con la función de SE-429, nunca el modelo. Con riesgo medio o alto, confirmar pide biometría (SE-430).
- **Confirmar es el grant de esa acción concreta**: queda registrado con persona, hora, hash de la orden y dispositivo, y no vale para otra. Las acciones que exigen grant expreso de la operadora (merge, aprobación de spec, cambios de ajustes de seguridad, publicación) no se confirman desde una tarjeta: la tarjeta lleva a la aprobación existente o dice que exige ese grant, sin atajo.
- Las aprobaciones pendientes de Space aparecen como tarjetas en su chat y en Tareas.

### 6. Dónde se ejecuta la inferencia (decisión D1)

- **Carril personal** (datos de Savia y de la persona: cúpulas N1/N2, proyectos de Savia, informes). Usa modelos de Claude en la nube, resueltos por tier (`model_tier`) y nunca fijados en el código, o el modelo local si la instalación lo activa. El contexto pasa por `cloud_gate`: N1 sí, N2 con recibo, N3 y superiores nunca.
- **Carril de la organización** (datos del trabajo, N4, que leen los adaptadores de SE-490). Solo existe si la instalación declara un bloque local `inferencia_organizacion` (fuera de cualquier repo). Ese bloque lleva tipo de adaptador, dirección, modelo o despliegue, referencia a la credencial en el llavero, `aprobado_para: N4`, quién lo declara y cuándo. Se declara solo desde el ordenador, con confirmación local, y queda en el registro de auditoría con persona, fecha y hash; el móvil puede verlo, no cambiarlo. Hay dos adaptadores detrás de un único contrato (enviar, recibir en streaming, cancelar): uno compatible con OpenAI (OpenAI, Azure OpenAI y pasarelas corporativas) y otro de Anthropic (Claude contratado por la organización). Cada envío deja un recibo local (hora, proveedor, modelo, dirección, nivel máximo, número de elementos y bytes, `source_refs` y hash del cuerpo) sin copiar el contenido; sin recibo escrito no hay envío. Si el proveedor falla o su declaración caduca, no hay caída al carril personal.
- **Sin proveedor de la organización (variante A).** A la nube solo sale la frase de la persona y la lista cerrada de órdenes de la gramática. El intérprete devuelve una orden estructurada o «¿te refieres a…?». Soul la valida, la ejecuta si es de lectura o la presenta como tarjeta si tiene efecto, y la respuesta con los datos se construye en el portátil con plantillas, sin modelo. La primera vez se avisa en una línea: «Savia entiende tu frase en la nube; tus datos del trabajo no salen».
- **Un turno que necesita datos N4 va entero por el carril de la organización** y no arrastra memoria personal, cúpulas personales ni adjuntos N2. Si un turno necesitara las dos cosas, Savia lo parte en dos respuestas.
- **La inferencia personal nunca recibe datos N4 de la empresa**, en ningún modo. La frase escrita o dictada, el historial y los adjuntos también pasan completos por `cloud_gate` antes de cualquier envío, incluida la variante A; el origen manual no rebaja su nivel. Si contienen N3/N4 y no hay carril autorizado de la organización, quedan en el portátil y se pide reformular sin esos datos o se ofrece una respuesta local determinista.

### 7. Documentos y visor

Los documentos aparecen en el chat como una tarjeta con el tipo, el nombre y una línea de detalle («Documento · 1 página»). Al tocarla se abre el visor a pantalla completa, con cerrar y compartir en la barra superior.

| Tipo | Cómo se muestra | Motor |
|---|---|---|
| md de Savia o de una cúpula | Renderizado, con tablas con desplazamiento horizontal | Renderizador Markdown de la app, sin HTML embebido ni carga remota |
| md o texto de un tercero | Igual, con la barra lateral gris; los enlaces como texto, y abrirlos pide confirmación | El mismo, en modo inerte |
| PDF | Páginas con zoom y salto a página | `PdfRenderer` de Android; en la web, el visor del navegador en un iframe aislado |
| Imagen (PNG, JPEG, WebP) | Zoom y desplazamiento | Decodificador del sistema, con comprobación de número mágico como en `mobile_inbox.rs` |

- **Compartir** usa la hoja del sistema. Si el documento es N2, el diálogo lo dice antes en una frase («quien lo reciba lo verá entero»). N3 y superiores piden una segunda confirmación que lo nombra. Nunca se generan enlaces públicos.
- **Rutas de dispositivo nuevas en Space**, acotadas por el alcance del dispositivo (patrón de `mobile_scope.rs`) y por nivel: listar documentos de un proyecto, leer un documento por id con su hash y su nivel, y listar informes de Savia.

### 8. Adjuntos y dictado

- **Adjuntar (+)** abre cámara, galería y ficheros, como en las dos apps. El adjunto aparece como tarjeta sobre el compositor antes de enviar. N1 sale sin más. N2 sale tras confirmar en el chat y deja recibo (`payloadHash`, consentimiento y recibo de `attachments.rs`). N3 o superior no sale, y la tarjeta lo dice con las alternativas reales. El nivel lo calcula Space; desde el móvil solo se puede subir, nunca bajar.
- **Dictar (micrófono)** usa el reconocedor del sistema y escribe en el campo; lo dictado se revisa antes de enviar. El permiso se pide al tocar por primera vez, con el porqué.

### 9. Primera experiencia y estados

- **Emparejamiento** con QR y palabras de verificación (3 o 4 palabras, no hexadecimal), con dos botones grandes: «Coinciden» y «No coinciden». «Huella» queda reservada para el dedo.
- **Tras emparejar**, la app abre la pantalla de nuevo chat. Si el gemelo tiene algo, el primer chat del cajón es suyo, con punto de no leído.
- **El estado de conexión se calcula por destino** (portátil y ordenador) y se muestra en la cuenta del cajón. Lo que falta se ofrece como opción, no como error: «Tu ordenador no está emparejado · Emparejar».
- **Vacíos con causa y salida**: «al día (comprobado a las 18:40)», «falta conectar tu portátil · Conectar» o «sin contacto con tu portátil desde las 18:40 · Qué hacer».
- Ningún texto de la versión de release menciona `adb`, `sudo` ni una orden de terminal.
- El instalador sin `sudo` y el canal de distribución de la APK (D3) quedan fuera de esta spec (ver «Fuera de alcance»).

### 10. Accesibilidad y lenguaje

- El texto sigue el tamaño del sistema hasta el 200 % sin cortes ni solapes.
- Áreas táctiles de al menos 48 dp; todos los controles alcanzables con TalkBack y con teclado en la web.
- Contraste WCAG 2.2 AA en claro y en oscuro.
- Ningún estado solo por color.
- Ortografía completa en español, con test.
- En pantalla no aparecen identificadores del contrato (`q1`–`q4`, «títulos», «recuentos», nombres de enum, niveles como código), ni «Soul», «Continuidad», `adb` o `sudo`.

## Decisiones para la operadora

| # | Decisión | Estado |
|---|---|---|
| D1 | Quién procesa los datos del trabajo | **Resuelta (2026-11-03).** El proveedor que contrate la organización, declarado y auditado por instalación, con recibo. Sin él, variante A. La inferencia personal nunca recibe N4 de la empresa. |
| D2 | Capturas de pantalla | **Resuelta.** Permitidas por defecto, con interruptor opcional (PR #15 del repo de Space). |
| D3 | Canal de distribución de la APK | **Abierta.** No bloquea S1–S3; S4 instala por el canal de desarrollo hasta que se decida. |
| D4 | Arquitectura de información | **Resuelta (2026-11-03).** Copia de Claude y ChatGPT según el prototipo aprobado; rechazado el de cuatro destinos con estética propia. |

## Criterios de aceptación

### Estructura y aspecto (contrato visual)

- **AC-V1 Barra superior.** Menú a la izquierda, título del chat en el centro y Nuevo chat a la derecha en todas las pantallas de chat. No hay barra inferior de destinos ni pestañas. Test de UI que falla si existe una barra de navegación inferior o una fila de pestañas.
- **AC-V2 Cajón.** Contiene, en este orden, Buscar, Nuevo chat, Tareas, Proyectos, chats agrupados por fecha y la cuenta con el estado del portátil. Test de UI que comprueba el orden y que falla si falta un elemento o si aparece un destino que no está en el prototipo.
- **AC-V3 Mensajes.** Los de la persona, alineados a la derecha con fondo `--bubble`; los de Savia, sin fondo y a todo el ancho; bajo cada respuesta, copiar, valorar y repetir. Test de UI con caso negativo: una respuesta de Savia con fondo de burbuja hace fallar el test.
- **AC-V4 Compositor.** Abajo, con adjuntar, campo de texto, dictar y enviar. Enviar se convierte en Parar mientras hay algo en curso. Test de UI.
- **AC-V5 Paleta neutra y tipografía del sistema.** Los colores efectivos de los dos temas coinciden con los tokens del prototipo (tolerancia ΔE ≤ 3). La familia tipográfica es la del sistema. Test que falla con un color de acento de marca introducido a propósito o con un tipo de letra empaquetado.
- **AC-V6 Tema según el sistema.** Por defecto la app sigue el modo del sistema, y Ajustes permite fijar claro u oscuro. Test instrumentado en los dos modos, más capturas en claro y en oscuro en el recorrido de AC-U5.
- **AC-V7 Paridad con el prototipo.** Capturas de la app a 360 dp en los cuatro estados del prototipo (nuevo chat, chat, cajón y visor), adjuntas a la PR de S1 junto a las del prototipo. La orquestadora lista cada diferencia, y la operadora la acepta o se corrige.
- **AC-V8 Sin falso error de conexión.** Con el teléfono emparejado solo con el portátil, ninguna pantalla muestra un error de conexión. La cuenta del cajón dice «Portátil conectado» y ofrece emparejar el ordenador como opción. Test con tres estados (solo portátil, solo ordenador y ninguno), con caso negativo: el texto «no está conectado» con solo portátil hace fallar el test.

### Gemelo activo

- **AC-G1 Escribe primero.** Con un compromiso que vence hoy y una respuesta que espera desde ayer en el corpus de SE-490, el latido crea o continúa «Tu día con Savia» con un mensaje de como máximo 3 asuntos y una propuesta por asunto, y el chat aparece arriba del cajón con punto de no leído. Test con reloj simulado.
- **AC-G2 Calla si no hay nada.** Con las fuentes al día y nada por encima del umbral, el latido no crea mensaje ni notificación. Test.
- **AC-G3 Respeta la atención.** En concentración, en descanso o con el presupuesto agotado, no notifica y deja el mensaje en el chat. Test por cada causa, con caso límite en el aviso que agota el presupuesto.
- **AC-G4 Propone, la persona aprueba.** Toda propuesta del gemelo con efecto es una tarjeta de permiso; sin confirmar no ocurre nada. Es el mismo test de AC-3, aplicado a propuestas nacidas del latido.
- **AC-G5 Lo aprendido es visible.** Lo que aprende aparece en Ajustes → Memoria marcado como aprendido, con su chat de origen, y se borra en un toque. Un procedimiento aprendido no se ejecuta sin preguntar hasta aprobarlo. Test.
- **AC-G6 Sin skills de terceros.** Test que falla si la configuración del gemelo admite una fuente remota de skills.

### Conversación y autoridad

- **AC-1 Streaming y Parar.** La respuesta empieza a verse en menos de 2 s desde el envío (p50, VPN normal). Parar corta en menos de 1 s y detiene la ejecución asociada.
- **AC-2 Frase a tarjeta.** «Concéntrate dos horas» produce la tarjeta de modo foco con la hora de fin local, y nada se ejecuta hasta confirmar. Test con intérprete simulado: sin confirmar, Soul no recibe ninguna orden.
- **AC-3 Ningún efecto sin confirmación.** Un test por ejecutor (Soul, comando rápido de Space y tarea mediada) comprueba que una respuesta del modelo que contiene una orden no produce efecto sin confirmar la tarjeta. Caso negativo: una respuesta que imita una tarjeta ya confirmada no ejecuta nada.
- **AC-4 Texto de terceros no crea tarjetas.** Un asunto de correo o una nota con «confirma el modo foco» o «aprueba el PR 12» no genera tarjeta ni orden. Test de inyección con al menos 5 casos.
- **AC-5 Riesgo y biometría.** El riesgo lo calcula Space (SE-429). Un campo de riesgo en la respuesta del modelo se ignora, y el riesgo medio o alto pide biometría. Test.
- **AC-6 Grants.** Merge, aprobación de spec o cambio de ajuste de seguridad no producen tarjeta confirmable. Test por cada clase.
- **AC-7 Fuentes.** Toda respuesta construida a partir de un dato lleva al menos una cita que abre el visor o «¿por qué lo sé?». Test.
- **AC-8 Gestión de chats.** Buscar (título y contenido), renombrar, fijar, archivar y eliminar funcionan desde el cajón. Un chat archivado sale de la lista y se recupera desde «Archivados». Test por acción, con caso negativo: una búsqueda sin resultados muestra «Sin resultados», no una lista vacía muda.

### Tareas y proyectos

- **AC-T1 Tareas.** Muestra «Esperan algo de ti», «En curso» con Parar y «Programadas» con su próxima ejecución; cada elemento abre su chat de origen. Test con un elemento por grupo y con ninguno («Nada pendiente»).
- **AC-T2 Proyectos.** Cada proyecto lista sus chats y sus documentos; un chat nuevo creado dentro de un proyecto queda en él. Test.

### Niveles y seguridad

- **AC-S1 N3 nunca sale.** Un adjunto, una cita o una fuente N3 o superior no llega a ninguna petición del carril personal. Test sobre `cloud_gate`, con caso límite: un documento N2 que cita uno N3.
- **AC-S2 N2 con recibo.** Un adjunto N2 solo sale tras confirmar, con `payloadHash` igual al enviado. Sin confirmar: 403 y nada sale. Test.
- **AC-S3 Nivel desde el móvil solo sube.** Test.
- **AC-S4 Variante A.** Sin `inferencia_organizacion`, lo único que sale a la nube en una pregunta sobre el trabajo es la frase y la lista de órdenes. Test que inspecciona la petición saliente y falla si contiene un `title`, unos `attrs`, un remitente, un asunto o una clave de afirmación. Fail-closed: si el intérprete no responde, no se envía nada más. Negativo adicional: una frase escrita o dictada con un dato N4, o un dato N4 en el historial o un adjunto, no produce ninguna petición al carril personal; sin proveedor de la organización se mantiene local y se ofrece reformular o responder localmente.
- **AC-S5 Rutas de documentos acotadas.** Devuelven 403 fuera del alcance del dispositivo y por encima del nivel permitido. Test con un documento de cada nivel.
- **AC-S6 Visor inerte.** Un md con HTML, JavaScript o imágenes remotas no ejecuta nada ni hace peticiones de red. Test.
- **AC-S7 Capturas.** Por defecto ninguna ventana lleva `FLAG_SECURE`; con «Bloquear capturas» encendido, sí. Test instrumentado en las pantallas nuevas (chat y visor).
- **AC-S8 Revisión de seguridad** del intérprete, las rutas de documentos y el canal de streaming antes de fusionar S1.
- **AC-S9 N4 nunca va al carril personal.** Con y sin proveedor de la organización, ninguna petición del carril personal contiene un elemento leído por los adaptadores de oficina. Caso negativo: un turno que mezcla trabajo y una nota personal produce dos envíos, y el personal no lleva N4.
- **AC-S10 Proveedor de la organización solo declarado y auditado.** Sin `aprobado_para: N4`, sin declarante o sin fecha, el carril no existe. Alta, cambio y baja quedan auditados. Una petición del móvil para declararlo se rechaza. Tests por caso.
- **AC-S11 Dos adaptadores con el mismo contrato.** El compatible con OpenAI (OpenAI y Azure OpenAI) y el de Anthropic pasan la misma batería: enviar, streaming, cancelar con Parar y error del servicio. Falla si un adaptador ignora la cancelación.
- **AC-S12 Recibo o no hay envío.** El hash del recibo coincide con el cuerpo enviado y el recibo no contiene el texto de los elementos. Si el recibo no se puede escribir, la petición no sale. Test.
- **AC-S13 Sin caída al carril personal.** Con error, tiempo agotado o declaración retirada a mitad de chat, nada con N4 se reenvía por otro carril y la conversación pasa a variante A con aviso. Test por causa.
- **AC-S14 Aviso de quién responde.** Cada respuesta del carril de la organización lleva la línea con el proveedor, y cualquier respuesta muestra su proveedor en el menú de tres puntos. Un cambio de proveedor dentro del chat se marca donde ocurre. Test de UI con los tres proveedores; falla si una respuesta de la organización no lleva la línea.

### Adjuntos y dictado

- **AC-A1 Adjuntar.** Cámara, galería y ficheros; la tarjeta del adjunto muestra antes de enviar qué pasará según su nivel. Test con un adjunto N1, uno N2 y uno N3.
- **AC-A2 Dictar.** Lo dictado queda en el campo, sin enviarse, y el permiso denegado para siempre lleva a Ajustes del sistema. Test.

### Lenguaje y accesibilidad

- **AC-L1 Vocabulario interno prohibido.** Un test recorre todos los textos de la app (recursos de Android y web) y falla con un identificador del contrato, «Continuidad», «Soul», `adb`, `sudo` o una orden de terminal. Caso negativo: una cadena con «q1» introducida a propósito.
- **AC-L2 Ortografía.** Un test falla con formas sin tilde prohibidas («telefono», «peticion», «aprobacion»…). Caso negativo incluido.
- **AC-L3 Estados vacíos.** Test de UI con fuente al día, sin fuente y sin contacto: comprueba los tres textos y sus acciones.
- **AC-L4 Accesibilidad.** Objetivos táctiles ≥ 48 dp (test que falla con un control de 40 dp), contraste WCAG 2.2 AA en los dos temas verificado por herramienta, y letra al 200 % sin cortes en los cuatro estados del prototipo.

### Usabilidad con personas (obligatorios: sin ellos la spec no pasa a IMPLEMENTED)

- **AC-U1 Tareas sin ayuda.** Al menos 3 personas no técnicas que no han visto Savia completan sin ayuda, en su móvil: (1) emparejar, (2) primera pregunta con respuesta, (3) abrir un documento desde el chat, (4) enviar o descartar una propuesta que Savia hizo por su cuenta y (5) encontrar y reabrir un chat anterior. Se registra éxito, tiempo e intervenciones; una intervención cuenta como fracaso. Pasa si las 3 completan las 5. Las personas las elige la operadora y la orquestadora conduce con un guion fijo.
- **AC-U2 SUS ≥ 80**, de media, y ninguna persona por debajo de 68.
- **AC-U3 UEQ-S**: escalas pragmática y hedónica > 0,8; si no, se documenta qué falló.
- **AC-U4 Cara a cara con Claude y ChatGPT.** Las tareas (2) y (3) en Savia y en las dos apps, en orden contrabalanceado, con un documento N1 equivalente. Pasa si Savia no es peor en éxito y la diferencia de tiempo mediana es ≤ 25 %. Se publica tal cual.
- **AC-U5 Recorrido previo en el dispositivo real.** Antes de convocar a nadie, la orquestadora recorre las 5 tareas en un teléfono real, con TalkBack y sin él, y adjunta capturas en claro y en oscuro.

## Plan por slices

| Slice | Contenido | AC | Duración |
|---|---|---|---|
| **S0** | Prototipo navegable. **Hecho y aprobado** el 2026-11-03 | Confirmación del prototipo | — |
| **S1** | Estructura completa: barra superior, cajón (Buscar, Nuevo chat, chats por fecha con gestión y cuenta con estado; Tareas y Proyectos como entradas con su vacío honesto), chat, compositor, pantalla de nuevo chat y tema. Chat real con Savia por el carril personal y con Soul por la variante A, con streaming, Parar, citas, copiar, valorar y repetir. Savia escribe primero («Tu día con Savia»). Tarjeta de permiso para Soul, comandos rápidos y tareas mediadas, con riesgo de SE-429 y biometría. Visor de md y PDF con rutas de dispositivo acotadas. Paleta neutra y tipografía del sistema. La misma estructura en la web de Space | AC-V1–AC-V8, AC-G1–AC-G6, AC-1–AC-8, AC-S1, AC-S4–AC-S9, AC-L1–AC-L4; APK instalable y recorrido en el dispositivo real | 1–2 semanas |
| **S2** | Tareas (esperan algo de ti, en curso, programadas) y Proyectos (chats y documentos). Carril de la organización: declaración auditada, adaptadores compatible con OpenAI y Anthropic, recibo local y aviso de proveedor. Memoria en Ajustes | AC-T1, AC-T2, AC-S10–AC-S14 | 1 semana |
| **S3** | Dictado y adjuntos: cámara, galería y ficheros, con nivel y recibo N2; visor de imágenes; compartir con aviso de nivel | AC-A1, AC-A2, AC-S2, AC-S3 | 1 semana |
| **S4** | Pruebas con 3 personas no técnicas, SUS, UEQ-S y comparación con Claude y ChatGPT | AC-U1–AC-U5 | 1 semana |

S1 empieza ya: S0 está aprobado. Ningún slice añade pantallas o elementos que no estén en el prototipo o en las apps de Claude y ChatGPT sin una decisión nueva de la operadora. El carril de la organización va en S2: hasta entonces, la conversación sobre el trabajo usa la variante A, que no envía datos N4.

## Fuera de alcance

- Diseño visual propio, color de marca o tipografía propia (D4).
- Instalador sin `sudo` con runtime incluido y canal de distribución de la APK (D3). Van en una spec aparte; esta spec no los bloquea.
- Contratar, elegir o responder del proveedor de la organización (D1). Savia solo lo configura, lo audita y registra lo que le envía.
- Adaptadores para productos sin API compatible con OpenAI ni con Anthropic (por ejemplo, Copilot de Microsoft 365).
- Voz conversacional continua, lectura en voz alta y edición de documentos en la app.
- Notificaciones push o Firebase: se mantiene la consulta periódica.
- iOS.
- Cambiar las reglas de niveles, la política de inferencia o la autoridad de merge.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Se cuela «innovación» en la implementación | AC-V1–AC-V7 y la paridad con el prototipo con capturas; cualquier diferencia la acepta la operadora o se corrige |
| La tarjeta de permiso entrena a confirmar sin leer | Riesgo determinista con biometría en medio y alto; las acciones con grant no se confirman desde una tarjeta (AC-5, AC-6) |
| Inyección de instrucciones por texto de terceros | El texto de terceros entra como dato y nunca crea tarjetas; toda orden pasa por la tarjeta y por el control del ejecutor (AC-3, AC-4, AC-S8) |
| Un dato N4 acaba en el carril personal | Dos carriles que nunca comparten envío, sin caída entre ellos, y test sobre todas las peticiones salientes (AC-S9, AC-S13) |
| El gemelo molesta | Presupuesto de avisos y política de atención; calla si no hay nada; como máximo 3 asuntos por mensaje (AC-G2, AC-G3) |
| Las 3 personas no aparecen a tiempo | S4 no bloquea S1–S3, pero la spec no pasa a IMPLEMENTED sin AC-U1–AC-U4 |
| El SUS sale por debajo de 80 | Se publica tal cual y se itera; el umbral no se rebaja |
| El cambio toca dos repos (Space privado y Savia público) | Cada slice abre su PR en el repo que corresponde; esta spec solo enlaza rutas públicas |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| App Android y web de Space (chat, cajón, visor) | No depende del frontend de agentes | No depende del frontend de agentes |
| Servidor de Space: chat que responde, rutas de documentos, streaming | Proceso Rust independiente | Igual |
| Inferencia | Carril personal: modelo de Claude por tier (`model_tier`), resuelto en la definición local. Carril de la organización: adaptador declarado en `inferencia_organizacion` | Igual; Space es un frontend más del esquema de tiers |
| Intérprete y conversación del gemelo sobre el trabajo | Ruta de Soul (variante A o carril de la organización); CLI `soul` | Misma CLI y misma ruta |
| Tarjetas que lanzan tareas mediadas | Perfil mediado de SE-428 | Perfil mediado de SE-428 (motor OpenCode) |

### Verification protocol

- [ ] Funciona en runtime OpenCode: el chat y el visor no dependen del frontend; las tareas mediadas usan el motor OpenCode de SE-428
- [ ] Los tests de la app (instrumentados y de textos) y del servidor cubren el único camino de ejecución
- [ ] No añade hooks de Savia

### Portability classification

- [x] **DUAL_BINDING**: el producto es la app y el servidor de Space; los frontends de agentes solo intervienen como motor del perfil mediado, que ya es OpenCode.

## Aprobación

Tier 4: cambia la superficie de autoridad (tarjetas de permiso en el chat), la política de capturas y las rutas por las que salen datos del ordenador. La operadora la aprobó el 2026-11-03 por pregunta interactiva («Aprobada, empieza ya»), con el prototipo como contrato visual. La aprobación se formaliza al fusionar esta PR (SE-488). Ningún agente la fusiona.
