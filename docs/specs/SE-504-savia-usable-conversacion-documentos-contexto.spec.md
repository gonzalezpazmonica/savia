---
status: PROPOSED
priority: P0
developer_type: agent-team
created: 2026-11-03
author: Savia
phase: A
risk: L4
related_specs: [SE-428, SE-429, SE-430, SE-431, SE-436, SE-490, SE-496]
origin: "Mandato de la operadora del 2026-11-03 tras probar la app en su móvil: «hay que cambiar completamente esta app para hacer algo que realmente merezca la pena ser usado por humanos… necesitamos poder hablar con la máquina, que nos conteste, conversación humana natural, poder revisar, ver imágenes, informes, .md, pdf… necesitamos poder ver contexto… necesitamos poder usar Savia». Encargo de la orquestadora, plan intensivo. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-504 — Savia usable: conversación natural, documentos y contexto en Savia Space

## Problema (auditado el 2026-11-03)

La app de Savia Space se puede instalar y es segura, pero una persona normal no la puede usar. La auditoría de la app actual (Android `0.1.0`, `origin/main` de Space, probada en un teléfono real) encontró 32 fricciones, 10 de ellas bloqueantes. Las más graves:

| Fricción | Texto real que ve la persona |
|---|---|
| Hay que aprender la gramática de Soul | «Solo órdenes cortas (por ejemplo «q1» o «modo foco durante:2h»). Soul no interpreta texto libre aquí.» |
| Jerga del modelo de niveles | «Detalle: títulos (máximo: títulos)» |
| Estados vacíos sin causa ni salida | «Ahora no hay nada aquí.» |
| Con el teléfono emparejado solo con Soul, tres de las cuatro entradas dan error | «Este teléfono no está conectado a Space. Conecta en Ajustes.» |
| Órdenes de desarrollo en mensajes de usuario | «Comprueba que Space está en marcha y que adb reverse está activo.» |
| «Huella» significa tres cosas | huella del certificado, huella dactilar y huella de la clave de aprobación |
| Nombres de enum en pantalla | `api`, `VIGENTE`, `N4`, `github: 3` |
| Dos superficies llamadas «Soul» que no comparten nada | la pestaña Soul (Space, con chat que no responde) y la sección Soul de Continuidad (portátil, solo órdenes) |

Faltan además capacidades básicas:
- **No hay conversación que responda.** El chat con Soul de Space convierte el texto en un evento; nadie contesta.
- **No hay visor de documentos.** El md solo se ve en el ordenador, el PDF no existe, las imágenes solo se suben y los informes de Savia no tienen ruta hacia el móvil.
- **No hay contexto visible.** La persona no ve qué sabe Savia ni de dónde.
- **La instalación pidió seis órdenes de terminal,** tres con `sudo`, y un Node distinto del de Ubuntu.
- **Las capturas de pantalla están bloqueadas** (`FLAG_SECURE`) en 10 pantallas sin que nadie lo pidiera.

La causa no es el pulido visual sino el modelo de interacción. La app es una consola de órdenes con pestañas. Los referentes del mercado (Claude, ChatGPT, Gemini con Notebooks, Perplexity, Notion Agents, Slack AI, Microsoft 365 Copilot, Linear, Superhuman, Things) convergen en otra cosa: **una conversación en lenguaje natural con adjuntos y voz, respuestas con citas que abren un visor dentro de la app y un contenedor que hace visible qué sabe la máquina.** Ninguno pide sintaxis a la persona ni bloquea capturas por defecto. Las órdenes con efecto aparecen como acciones propuestas que la persona confirma.

Las piezas de seguridad para esa conversación ya existen en Space y no hay que reinventarlas:
- el carril hacia Claude con filtro por nivel (`soul_cloud`, `cloud_gate`);
- adjuntos N2 con confirmación, hash del contenido y recibo (`attachments.rs`);
- la mediación de permisos del motor y los recibos firmados (SE-428, perfil mediado);
- aprobaciones con biometría desde el móvil (SE-430);
- Q1–Q4, «¿por qué lo sé?» y correcciones de Soul Continuidad (SE-490).

Lo que falta es la superficie: un chat que conteste, rutas de dispositivo para enviar texto y leer documentos, y una app organizada alrededor de la conversación.

Fuentes: auditoría de la app actual (informe interno del plan intensivo, 2026-11-03) y estudio de referentes de mercado (informe de investigación de Savia Labs del 2026-11-03, privado). Esta spec recoge las conclusiones necesarias y no depende de que se lean.

## Objetivo

Que una persona sin conocimientos técnicos instale Savia Space, empareje su móvil y encuentre en Inicio a un gemelo que ya le dice qué importa hoy y le propone trabajo; que le pregunte con sus palabras, reciba una respuesta con fuentes, abra un informe y apruebe o descarte lo que el gemelo propone, sin ayuda y sin ver una sola orden de terminal ni un identificador interno. Y que lo prefiera, o lo valore igual, frente a los asistentes que ya usa.

Las garantías no bajan: la autoridad sigue en la persona, N3 y superiores nunca salen por el carril personal, N2 sale con recibo, los datos N4 de la empresa solo van al proveedor que la organización haya declarado (también con recibo) y nada con efecto ocurre sin una confirmación visible.

## Qué decide esta spec

1. **Savia es un gemelo operativo activo, no un panel.** El gemelo es Soul (SE-490) convertido en un agente persistente que vive y trabaja con la persona: habla primero cuando hay algo que importa, propone, prepara trabajo y hace seguimiento. La persona aprueba. «Continuidad» desaparece como palabra y como pantalla (§0).
2. **La app arranca en Inicio**, con cuatro destinos al estilo de las apps de Claude y ChatGPT: Inicio, Conversaciones, Tareas y Contexto. Ajustes, desde el avatar. El chat ocupa el centro de la experiencia (§1).
3. **Poco texto por pantalla.** Una acción principal por pantalla, como máximo 3 elementos en «Lo importante ahora» y ningún párrafo explicativo (§1.3).
4. **La persona habla en lenguaje natural; el gemelo propone órdenes estructuradas.** Ni Soul ni ningún ejecutor interpretan texto libre como orden. Un intérprete traduce la frase a una **tarjeta de acción** que la persona confirma, edita o descarta. Qué modelo hace de intérprete depende de los datos (punto 7).
5. **Cada mensaje y cada documento llevan su origen visible**: «nube · recibo» o «en tu ordenador · no salió». Tocarlo abre el detalle y el recibo.
6. **Capturas permitidas por defecto** (decisión de la operadora del 2026-11-03, implementada en la PR #15 del repo de Space). Bloquear capturas es un interruptor opcional de la persona o una política impuesta por la instancia.
7. **Los datos del trabajo los procesa el proveedor que contrate la organización** (decisión D1 de la operadora, 2026-11-03: «la inferencia de la empresa es responsabilidad de la empresa»). La conversación sobre datos N4 de la empresa usa solo el proveedor de inferencia de la organización, configurado y auditado por instalación (AC-4d de SE-490). Sin él, la conversación de trabajo se limita a la variante A. La inferencia personal de la persona (su contrato propio con Claude) nunca recibe datos N4 de la empresa.
8. **Una sola voz llamada Savia.** Desaparecen las dos «Soul» del móvil: el gemelo habla como Savia, y Space y el portátil pasan a ser lugares donde trabaja, con su nombre humano («tu portátil de trabajo», «tu ordenador»).
9. **Prototipo antes que código.** Ningún slice de código empieza sin un prototipo navegable aprobado por la operadora (S0).

## Diseño

### 0. El gemelo operativo: un agente que habla primero

Mandatos de la operadora del 2026-11-03: «La pantalla actual de Continuidad no nos vale. "Continuidad" es un concepto que un humano no entiende. Tenemos que arrancar en un home, tenemos que tener opción de gestionar sesiones… Tiene que ser intuitivo, como la app de Claude o la de ChatGPT… Nada de grandes cantidades de texto». Y después: «Necesitamos un Savia activo que viva y trabaje con los operadores como su gemelo operativo».

El gemelo **no es una fuente de contexto ni un panel de consultas** (eso es lo que se rechazó: Q1–Q4 como botones). Es Soul (SE-490) actuando como agente persistente:

| Rasgo | Qué hace | Límite |
|---|---|---|
| **Iniciativa** | Abre la conversación cuando hay algo que importa: «Tienes 3 correos esperando respuesta desde ayer; te propongo borradores». Prepara el día y el cierre, avisa de cambios y recuerda compromisos. | Presupuesto de avisos y política de atención de SE-490 AC-4b; modo concentración y descanso. Si no hay nada que importe, calla. |
| **Trabajo** | Prepara borradores, resúmenes, informes, planes y respuestas. Ejecuta tareas y flujos dentro de su autoridad. | Toda acción con efecto externo se propone como tarjeta y la persona la aprueba en la conversación. Nada irreversible sin grant (SE-343, SE-362, SE-496). |
| **Conversación en las dos direcciones** | La persona le habla como a un colega; él responde, pregunta, propone y da seguimiento. | Habla como Savia, nunca como «Soul» ni con órdenes. |
| **Memoria** | Recuerda lo hablado, los compromisos y el contexto del trabajo (SE-490 como base operativa) y aprende las preferencias de la persona. | Todo lo que recuerda se ve y se corrige en Contexto (§4). |

**Ciclo de iniciativa.** Un latido periódico en el portátil (por defecto cada 30 minutos, configurable, y además en los momentos de inicio y cierre del día) evalúa las fuentes de SE-490 con reglas deterministas: compromisos que vencen, respuestas que esperan, cambios desde la última vez. Si nada supera el umbral de la política de atención, no hace nada y no deja rastro visible. Si algo lo supera, el gemelo redacta **un** mensaje con como máximo 3 asuntos y una propuesta por asunto. La selección de qué decir se hace en el portátil sin modelo; redactar o preparar un borrador sobre datos del trabajo sigue la regla de carriles de §5.

**Referentes estudiados (2026-11-03, documentación pública, sin ejecutar nada).**

| Referente | Patrón que se toma | Qué se evita y cómo |
|---|---|---|
| OpenClaw (agente personal persistente que habla por los canales del usuario) | Latido periódico (30 min por defecto) que responde «nada que hacer» en silencio; trabajos programados para preparar el día; empezar los trabajos programados por comprobaciones de solo lectura con entrega privada, y exigir aprobación antes de editar datos, enviar mensajes externos o gastar presupuesto | Sus riesgos públicos: inyección de instrucciones por correo con acceso amplio y sin paso de confirmación (extracción de claves), decenas de miles de instancias expuestas en Internet (CVE-2026-25253, ejecución remota) y cientos de skills maliciosas en su marketplace (campaña ClawHavoc). Savia: texto de terceros inerte y sin tarjetas (AC-4), ningún efecto sin tarjeta confirmada (AC-3), escucha solo en VPN con emparejamiento, y **sin marketplace de skills ni instalación de skills por el gemelo** |
| Hermes Agent (Nous Research, MIT) | Memoria curada por el agente que sobrevive entre sesiones, con consolidación periódica; búsqueda en conversaciones pasadas; procedimientos aprendidos como skills reutilizables; memoria independiente del modelo | Aprendizaje opaco: en Savia, lo que el gemelo aprende de la persona aparece en Contexto con origen y fecha y se corrige en un toque; un procedimiento aprendido es una propuesta que la persona aprueba antes de usarlo sin preguntar |
| «Orca» | No se identificó un agente personal proactivo con ese nombre: el nombre lo usan un entorno local de agentes de programación, una plataforma de seguridad en la nube y un asistente en apps de mensajería | Se registra como no verificado; no condiciona el diseño |
| Apps de Claude y ChatGPT | Arranque limpio, lista de conversaciones con buscar, fijar, renombrar y archivar; chat como centro; adjuntos con «+» | Su pasividad: no inician. El gemelo sí, con presupuesto |

Fuentes: documentación de arquitectura del latido de OpenClaw (clawdocs.org/architecture/heartbeat), guía de automatización proactiva (tenten.co/openclaw, módulo 6), recopilaciones de riesgos de seguridad (techradar.com, morphllm.com/openclaw-security, clawdocs.org/security/known-vulnerabilities), documentación de Hermes Agent (hermes-agent.nousresearch.com/docs). Las cifras de instancias expuestas y de skills maliciosas varían según la fuente; se citan como orden de magnitud.

### 1. Arquitectura de información

#### 1.1 Navegación

Barra inferior con 4 destinos, icono y texto (Material 3 *navigation bar*; en tablet y escritorio, *navigation rail*). Ajustes, desde el avatar arriba. Actualizar, deslizando hacia abajo. Ninguna etiqueta se parte ni se corta, tampoco con letra al 200 %.

| Destino | Qué es para la persona | Contenido |
|---|---|---|
| **Inicio** (pantalla de arranque) | «Lo que Savia te dice ahora y lo que hace por ti» | El último mensaje del gemelo; «Lo importante ahora» (máximo 3 tarjetas con una propuesta cada una); acceso a «Qué está haciendo por ti»; campo «Pregúntale a Savia» que abre una conversación nueva |
| **Conversaciones** | Las sesiones con el gemelo | Lista con buscar, fijar, renombrar y archivar; «Nueva conversación» como acción principal; las conversaciones que abrió el gemelo llevan su marca |
| **Tareas** | Lo que el gemelo lleva entre manos y lo que espera de ti | Tres grupos: «Espera tu respuesta», «En curso» y «Programado» (procesos y flujos recurrentes). Cada elemento abre su conversación |
| **Contexto** | Lo que Savia sabe y de dónde | Lo que sabe de ti, proyectos, fuentes conectadas y documentos; todo con origen y fecha, corregible |

Sustituye la barra superior actual de pestañas de texto, que no cabe en un móvil normal («Ajustes» sale partido en vertical), y la pantalla «Continuidad».

#### 1.2 Pantallas

- **Inicio.** Arriba, el saludo del gemelo en una frase («Buenos días. Tres cosas hoy»). Debajo, como máximo 3 tarjetas: asunto en una línea, propuesta en un botón («Ver borradores»). Si no hay nada, una sola línea: «Nada pendiente. Te aviso si cambia algo». Debajo, la fila «Savia está haciendo 2 cosas por ti ›». Abajo, el campo de entrada.
- **Hoja «Qué está haciendo por ti».** Se abre desde Inicio y desde la cabecera del chat. Dos listas cortas: **«Trabajando»** (cada tarea con verbo y objeto, desde cuándo y Parar) y **«Esperando»** (lo que espera de la persona o de otros, con desde cuándo). Un toque abre la conversación donde nació. Es el destino Tareas en formato hoja; no duplica datos.
- **Conversación.** Chat a pantalla completa (§2). Cabecera con título, «Qué está haciendo por ti» y origen de las fuentes. El gemelo puede abrir una conversación nueva con un mensaje suyo; la persona la ve en Inicio y en Conversaciones.
- **Visor.** md, PDF e imágenes a pantalla completa (§3), abierto desde una cita, un adjunto o Contexto.
- **Ajustes** (desde el avatar): cuenta y emparejamiento, notificaciones y atención (concentración, descanso, presupuesto de avisos), privacidad (capturas), apariencia, «Comprobar mi instalación».

#### 1.3 Densidad (límites medibles)

- **Una acción principal por pantalla**, visualmente destacada (botón relleno o FAB); el resto, secundarias.
- **Inicio: como máximo 3 elementos** en «Lo importante ahora». Si hay más, el tercero dice «y 4 más» y lleva a Tareas.
- **Sin párrafos explicativos**: ningún texto de interfaz fuera del chat y los visores supera 2 líneas a 360 dp con letra al 100 %. Las explicaciones largas solo existen si la persona toca «por qué».
- **Mensajes del gemelo por iniciativa propia**: como máximo 3 asuntos y 1 propuesta por asunto.
- **Listas**: una línea de título y una de detalle por elemento, como máximo.

#### 1.4 Estándares de referencia

Material 3 (componentes y navegación de Android), Apple Human Interface Guidelines (patrones de navegación y lenguaje claro, aplicados también a la web), WCAG 2.2 AA (contraste, objetivos táctiles de 48 dp o más, orden de foco), las 10 heurísticas de Nielsen (evaluación del prototipo y de cada slice), SUS y UEQ-S (medición con personas). Cada uno se traduce en un AC medible (AC-E1 a AC-E5).

### 2. Conversación natural con Savia (móvil y escritorio)

**Superficie.** Un hilo por conversación, agrupado opcionalmente por proyecto. El campo de entrada tiene texto, botón «+» de adjuntos y micrófono. Es el mismo componente en la app de Android y en la web de Space del escritorio.

**Streaming con estado intermedio.**
- La respuesta aparece mientras se genera, por SSE (Space ya recibe así los eventos del motor).
- Durante el uso de herramientas se ve el paso actual en lenguaje humano: «leyendo 3 notas de la cúpula del proyecto», «consultando tu portátil de trabajo».
- Un botón **Parar** siempre visible mientras hay algo en curso. Corta la generación y, si hay una ejecución, la detiene con la misma semántica de PARA de SE-431.

**Adjuntos.** Imagen (cámara o galería), PDF, md, texto y ficheros de una cúpula o de un proyecto.
- Antes de enviar, la tarjeta del adjunto muestra su nivel y qué va a pasar con él.
- N1: sale sin más.
- N2: sale tras confirmar dentro del hilo y genera recibo (reutiliza `attachments.rs`: `payloadHash`, consentimiento y recibo).
- N3 o superior: no sale. La tarjeta lo dice («Este documento es N3: no sale de tu ordenador») y ofrece las alternativas reales: preguntar en el ordenador, o usar el modelo local si la instalación lo tiene.
- El nivel lo calcula Space con las reglas existentes (cúpula, proyecto, clasificador). La persona puede **subirlo**, nunca bajarlo desde el móvil.

**Voz opcional.**
- Dictado con el reconocedor del sistema, que escribe en el campo. Lo dictado queda como texto revisable antes de enviar.
- El permiso de micrófono se pide al pulsar el micrófono por primera vez, con el porqué. Si se denegó para siempre, el mensaje lleva a Ajustes del sistema.
- Lectura en voz alta de una respuesta con el sintetizador del sistema, a petición.
- La voz conversacional continua queda fuera de esta spec.

**Respuestas con fuentes.**
- Toda afirmación que viene de un dato (nota de cúpula, informe, elemento de la memoria operativa del gemelo, fichero de proyecto) lleva una cita numerada y tocable.
- La cita abre el documento en el visor, en el sitio citado, o la hoja «¿por qué lo sé?» con fuente, antigüedad y caducidad (`source_refs`, `observed_at` y `valid_until` de SE-490).
- Una respuesta sin fuentes se marca como «sin fuentes: es razonamiento de Savia».
- Tras cada respuesta, 2–3 sugerencias de seguimiento en frases humanas.

**Acciones propuestas frente a ejecutadas.**
- Toda petición con efecto produce una **tarjeta de acción** con verbo, objeto, alcance, nivel y riesgo, y tres botones: *Confirmar*, *Editar* y *Descartar*. Ejemplo: «concéntrate dos horas» produce «Modo foco hasta las 19:40 en tu portátil de trabajo · Confirmar».
- Estados visibles de la tarjeta: *propuesta*, *en curso* (con Parar), *hecha* (con hora y «deshacer» si la acción lo admite), *rechazada* y *fallida* (con motivo humano).
- Confirmar emite la orden estructurada al ejecutor que corresponda: gramática de Soul (`POST /ordenes`), comando rápido de Space o tarea mediada (SE-428). El ejecutor aplica sus propias reglas; la tarjeta no las sustituye.
- **Riesgo determinista.** El riesgo de la acción lo calcula Space con la función de SE-429, nunca el modelo. Riesgo medio o alto exige biometría al confirmar, igual que hoy en Aprobaciones.
- **Ningún efecto sin grant.** Confirmar una tarjeta es el grant de esa acción concreta: queda registrado con la persona, la hora, el hash de la orden y el dispositivo, y no vale para ninguna otra. Las acciones que hoy exigen grant (merge, aprobación de spec, cambios de ajustes de seguridad, publicación) no se confirman desde una tarjeta: la tarjeta lleva a la aprobación existente con los bytes exactos y la biometría, y si la acción exige un grant expreso de la operadora, lo dice y no ofrece atajo.
- Las aprobaciones pendientes de Space aparecen en la conversación como tarjetas, además de en Tareas («Espera tu respuesta»).

**Texto de terceros inerte.** El texto que no escribió la persona ni Savia (asuntos de correo, comentarios de PR, notas importadas) entra al prompt marcado como dato no fiable y se pinta en la respuesta con una barra lateral «de un tercero», sin enlaces activos ni HTML. Nunca genera una tarjeta de acción por sí mismo: una tarjeta nace siempre de una petición de la persona en ese mismo turno.

**Dónde se ejecuta la inferencia.** Hay dos carriles y nunca se mezclan en un mismo envío:

- **Carril personal** (datos de Savia y de la persona: cúpulas N1/N2, proyectos de Savia, informes). Sigue la decisión de inferencia vigente desde 2026-10-15: modelos de Claude en la nube por defecto, resueltos por tier (`model_tier`) y nunca fijados en el código; modelo local solo si la instalación lo activa. El contexto pasa por `cloud_gate`: N1 sí, N2 con recibo, N3 y superiores nunca.
- **Carril de la organización** (datos del trabajo, N4, que leen los adaptadores de oficina de SE-490). Solo existe si la instalación tiene configurado un proveedor de la organización (§5). El hilo enseña en cada mensaje qué carril y qué proveedor respondió.

Un turno que necesita datos N4 va entero por el carril de la organización y solo lleva datos del trabajo y la frase; no arrastra memoria personal, cúpulas personales ni adjuntos N2 de la persona. Un turno sin datos N4 va por el carril personal. Si un turno necesitara las dos cosas, Savia lo parte en dos respuestas, cada una con su proveedor visible.

### 3. Visores en la app

Un visor a pantalla completa, común para todos los documentos, que se abre desde una cita, un adjunto, la lista de documentos de un proyecto o una cúpula, o un informe de Savia.

| Tipo | Cómo se muestra | Motor |
|---|---|---|
| md generado por Savia o de una cúpula | Renderizado con índice de encabezados, búsqueda en el texto y tablas con desplazamiento horizontal | Renderizador Markdown de la app, sin HTML embebido ni enlaces remotos automáticos |
| md o texto de un tercero | Renderizado con la marca «de un tercero»; los enlaces se muestran como texto y abrirlos pide confirmación | El mismo, en modo inerte |
| PDF | Páginas con zoom, búsqueda si el PDF tiene texto, salto a página | `PdfRenderer` de Android; en la web, el visor PDF del navegador en un iframe aislado |
| Imagen (PNG, JPEG, WebP) | Zoom y desplazamiento; el texto alternativo, si existe | Decodificador del sistema; los bytes se comprueban por número mágico como ya hace `mobile_inbox.rs` |
| Tabla (CSV, tablas md) | Rejilla con cabecera fija, ordenar por columna, copiar celda | Componente de la app |
| Informe de Savia (`output/`, resúmenes de inicio y cierre, investigaciones publicadas) | Igual que md, con su fecha, su autor (Savia o un agente) y su nivel | El mismo |

En cada visor:
- **«Pregunta sobre esto»** abre la conversación con el documento ya adjunto, con su nivel aplicado.
- **Compartir** con la hoja del sistema y **exportar** a `.md` o PDF. El diálogo dice el nivel antes de compartir («contiene N2: quien lo reciba lo verá entero»). N3 y superiores no se comparten fuera de la app sin una segunda confirmación que lo nombre. Nunca se generan enlaces públicos.
- La cabecera lleva el origen (proyecto, cúpula o fuente) y su nivel en lenguaje humano.

**Rutas de dispositivo nuevas en Space**, acotadas por el alcance del dispositivo (patrón de `mobile_scope.rs`) y por nivel: listar documentos de un proyecto o cúpula, leer un documento por id con su hash y su nivel, y listar informes de Savia. Hoy no existen (el teléfono no ve cúpulas ni informes). Los PDF se sirven tal cual; su texto, si hace falta para preguntar, se extrae en el ordenador y hereda el nivel del documento.

### 4. Tareas y Contexto

**Tareas (lo que el gemelo lleva entre manos).**
- Tres grupos: «Espera tu respuesta» (propuestas y aprobaciones pendientes), «En curso» (lo que el gemelo está haciendo, con Parar) y «Programado» (procesos y flujos recurrentes: preparar el día, cierre semanal; cada uno con próxima ejecución, pausar y editar mediante tarjeta).
- Las aprobaciones de Space aparecen aquí y en la conversación de origen; nunca en un destino aparte.
- La hoja «Qué está haciendo por ti» (§1.2) es una vista compacta de «En curso» y «Espera tu respuesta».

**Contexto (lo que Savia sabe y de dónde).**
- **Lo que sabe de ti:** memoria agrupada por temas, cada entrada con su origen y su fecha. Se corrige o se borra en un toque, y también diciéndolo en la conversación («olvida esto», «eso ya no es así»), que produce una tarjeta de acción. Lo que el gemelo ha aprendido por su cuenta (preferencias, procedimientos) aparece marcado como aprendido, con la conversación de origen.
- **Proyectos y documentos:** lo que Savia tiene de cada proyecto (documentos, cúpulas, estado e informes), que se abren en el visor.
- **Fuentes conectadas:** tu portátil de trabajo, tu ordenador, el servicio de IA de tu empresa si lo hay; cada una con su estado real («al día, comprobado a las 18:40») y qué sale de ella.
- **Cabecera del hilo:** fuentes que el gemelo usa en esa conversación; tocarla deja quitar fuentes de esa conversación.
- **Conversación sin rastro:** un modo que no escribe memoria ni guarda el hilo. Dice la verdad sobre lo que sí queda: los recibos de los adjuntos N2 y las acciones ejecutadas siguen registrándose.
- **«¿Por qué lo sé?»** disponible en cada respuesta y en cada elemento.

### 5. El gemelo con los datos del trabajo (SE-490)

Lo que SE-490 llamaba Continuidad es ahora **la memoria operativa del gemelo**. No tiene pantalla propia ni nombre visible:

- El gemelo usa esos datos para su iniciativa (§0): preparar el día, avisar de compromisos y respuestas que esperan, proponer borradores.
- La persona pregunta con palabras («¿qué tengo hoy?», «¿qué depende de mí?», «¿qué cambió desde ayer?», «¿qué vence esta semana?»). La respuesta es una lista corta con citas y «¿por qué lo sé?».
- Las correcciones (resuelto, no aplica, es mío, no es mío) se dicen con palabras o desde el menú del elemento y salen como tarjeta de acción.
- Ninguna pantalla enseña la gramática de Soul, un ejemplo como «q1» ni la palabra «Continuidad».

**Quién procesa los datos del trabajo (D1, resuelta por la operadora el 2026-11-03).** SE-490 trata como N4 todo lo que leen los adaptadores de oficina y solo deja que suba de nivel hacia un modelo si la instalación declara ese proveedor como aprobado por la organización para N4, en configuración local y auditada (AC-4d de SE-490). La operadora decidió: «La inferencia de la empresa es responsabilidad de la empresa. Si la tienen contratada es porque pueden. No se trata de inferencia contratada por mí.» De ahí salen dos modos, que elige la configuración de cada instalación y no la persona en cada mensaje:

**Modo con proveedor de la organización (conversación completa sobre el trabajo).**

- *Configuración por instalación.* Un bloque local `inferencia_organizacion` (fuera de cualquier repo) declara: tipo de adaptador, dirección del servicio, modelo o despliegue, referencia a la credencial en el llavero del sistema (nunca la credencial en claro), `aprobado_para: N4`, quién lo declara y cuándo. Solo se declara o cambia desde el ordenador, con confirmación local; el móvil puede verlo, no cambiarlo. Cada alta, cambio o baja queda en el registro de auditoría local con fecha, persona y hash de la configuración resultante. Sin esa declaración el carril no existe: tener una credencial configurada no basta.
- *Adaptadores mínimos.* (1) **Compatible con OpenAI**, que cubre OpenAI, Azure OpenAI (con despliegue y versión de API) y las pasarelas corporativas que exponen esa API; (2) **Anthropic**, para Claude contratado por la organización (Claude Enterprise o API de empresa). Ambos detrás de un único contrato interno (enviar mensajes, recibir en streaming, cancelar), para añadir otros sin tocar la conversación. Copilot u otros productos sin API compatible quedan como adaptadores futuros.
- *Recibo local de cada envío.* Cada petición a ese proveedor genera un recibo en el ordenador: hora, proveedor y modelo, dirección del servicio, nivel máximo enviado, número de elementos y de bytes, `source_refs` de los elementos incluidos y hash del cuerpo enviado. El recibo no copia el contenido. Se abre desde la marca del mensaje. Sin recibo escrito, la petición no sale (fail-closed).
- *Aviso visible de quién responde.* La cabecera del hilo y la marca de cada mensaje dicen el proveedor en lenguaje humano: «responde el servicio de IA de tu empresa (Azure OpenAI) · datos del trabajo · recibo». Si en el mismo hilo cambia el proveedor, se ve en el mensaje donde cambia.
- *Responsabilidad.* Savia no asume el tratamiento que haga el proveedor de la organización; lo dice en la configuración y en la primera conversación de trabajo («tus datos del trabajo los procesa el proveedor que eligió tu empresa; Savia guarda qué se envió y cuándo»). Lo que sí garantiza Savia es qué se envía, a quién y el recibo.
- *Sin caída hacia el carril personal.* Si el proveedor de la organización falla, no responde o su declaración caduca, la petición no se reintenta por el carril personal ni por ningún otro: la conversación pasa a la variante A y lo avisa.

**Modo sin proveedor de la organización (variante A, conversación limitada).**

A la nube solo sale **la frase de la persona** y la lista cerrada de órdenes de la gramática con sus argumentos tipados; ningún dato de trabajo. El intérprete (modelo local si la instalación lo tiene; si no, el carril personal) devuelve una orden estructurada o «no lo entiendo, ¿te refieres a…?». Soul valida la orden con su gramática determinista, la ejecuta si es de lectura o la presenta como tarjeta si tiene efecto, y la respuesta con los datos se construye **en el portátil** a partir del resultado estructurado, con plantillas, sin modelo. Activa el valor `proveedor_aprobado` de `texto_libre` en `/estado` solo para traducir frases, y lo dice («Savia entiende tu frase en la nube; tus datos del trabajo no salen. Para conversar sobre ellos, tu empresa tiene que configurar su proveedor de IA»). La persona puede elegir no enviar ni la frase y usar solo las sugerencias tocables.

**La inferencia personal nunca recibe N4 de la empresa.** Ni en un modo ni en el otro: ningún elemento leído por los adaptadores de oficina (`title`, `attrs`, afirmaciones, remitentes, asuntos) llega al carril personal. Lo comprueba un test sobre la petición saliente (AC-S4, AC-S9).

En el resto de fuentes (cúpulas N1/N2, proyectos de Savia, informes) la conversación usa el carril personal con `cloud_gate`.

### 6. Primera experiencia sin terminal

- **Instalación en el ordenador:** un instalador por plataforma (paquete o AppImage en Linux, instalador en macOS y Windows) que deja Space y Soul como servicios de usuario, sin `sudo` en el camino normal, con su runtime incluido para no depender del Node del sistema. Lo que sí necesite privilegios (por ejemplo, una interfaz de VPN gestionada por NetworkManager) se detecta y se explica con la orden exacta para copiar; nunca se ejecuta a ciegas.
- **Diagnóstico:** «Comprobar mi instalación» en la interfaz (y `soul doctor` / `savia-space doctor` en la CLI) revisa runtime, llavero, VPN, dirección de escucha, puerto y reloj, y dice qué falta en una línea por problema.
- **Emparejamiento guiado:** el ordenador enseña un QR y **palabras de verificación** (3–4 palabras, no hexadecimal). El móvil escanea y la persona compara las palabras con dos botones grandes («Coinciden» / «No coinciden»). «Huella» queda reservada para el dedo. Lo manual (dirección, puerto, código) va en «¿No puedes escanear?».
- **La app llega por un canal que el teléfono acepte:** APK de release firmada por el canal que decida la operadora (D3, abierta), y una guía de «instalar apps desconocidas» por fabricante (incluido HyperOS, que rechazó el APK abierto desde otra app).
- **Inicio refleja la conexión real.** Hoy Inicio dice «Este teléfono no está conectado a Space. Conecta en Ajustes» aunque el teléfono está emparejado con Soul y funciona: es un falso error en la primera pantalla. El estado de conexión se calcula por destino (Soul, Space) y se muestra lo que hay; lo que falta se ofrece como opción, no como error.
- **Tras emparejar, la primera pantalla es Inicio** con el primer mensaje del gemelo («Hola, soy Savia. Ya veo tu portátil de trabajo. ¿Te preparo el día?») y el campo de entrada. La app funciona en modo solo portátil (sin Space) y en modo con Space: lo que no esté disponible en un modo se explica («las aprobaciones llegan desde Savia Space en tu ordenador; no lo tienes emparejado · Emparejar»), nunca como error.
- **Estados vacíos con causa y salida,** en tres variantes: «al día (comprobado a las 18:40)», «falta conectar X · Conectar» y «sin contacto con tu portátil desde las 18:40 · Qué hacer».
- **Ningún texto de la compilación de release menciona `adb`, `sudo`, ni una orden de terminal,** salvo dentro de un bloque «copiar orden» explicado.

### 7. Privacidad visible sin estorbar

- **Capturas permitidas por defecto** en toda la app (decisión de la operadora). Ya implementado en la PR #15 del repo de Space (abierta a 2026-11-03): `SecureScreen` solo pone `FLAG_SECURE` si el ajuste está encendido, y mientras el ajuste no se ha leído bloquea (fail-closed) para no exponer a quien lo encendió. Esta spec lo da por hecho y solo exige que las pantallas nuevas (conversación, visores) sigan el mismo mecanismo.
- **Interruptor «Bloquear capturas de pantalla»** en Ajustes → Privacidad (PR #15): apagado por defecto; encendido, bloquea capturas, grabaciones y la vista previa en Recientes en todas las pantallas protegidas. El alcance «solo cuando se ve algo N3 o una credencial» queda como mejora opcional, no necesaria para cerrar esta spec.
- **Política de la instancia:** la instalación puede imponer ese ajuste (por política de la organización de la persona); la app lo enseña como impuesto y por quién.
- **El nivel se ve donde actúa:** marca discreta por mensaje y adjunto, y tocarla abre el recibo.
- **Notificaciones en pantalla de bloqueo** según el nivel de detalle que permita SE-490: con detalle reducido, solo cifras («Savia tiene 2 cosas para ti»).
- **Avisos del gemelo** sujetos al presupuesto de atención (SE-490 AC-4b): fuera de concentración y descanso, y como máximo el número diario configurado.

### 8. Temas y accesibilidad

- Claro, oscuro y sistema, con **sistema por defecto**; color de acento y contraste alto. Ya existen `ThemeMode` y `AccentColor` en la app.
- **Diseño propio, no plantilla.** Hoy la app tiene el aspecto de la plantilla Material morada por defecto, sin diseño ni temas propios. Esta spec exige una identidad visual de Savia (tipografía, paleta por tema, iconografía, forma de las tarjetas y del hilo) definida como tokens de tema, que ninguna pantalla use el color de plantilla y que el acento lo elija la persona.
- El texto sigue el tamaño de letra del sistema hasta el 200 % sin cortes ni solapes.
- Ningún estado solo por color: icono y texto siempre. Iconos reales con `contentDescription` en lugar de «⚠» y «●» de texto.
- Todos los controles alcanzables con TalkBack y con teclado (en la web), en orden lógico. Áreas táctiles de al menos 48 dp.
- Contraste WCAG 2.2 AA en los dos temas.
- Ortografía completa en español (tildes y «ñ»), con test.
- Lenguaje: una palabra por concepto («tu portátil de trabajo», «tu ordenador», «palabras de verificación»), segunda persona, ningún identificador del contrato en pantalla («títulos», «recuentos», «Q3», `N4` como código, nombres de enum).

### Hallazgos en el dispositivo real (2026-11-03)

La orquestadora recorrió la app en el teléfono de la operadora. Captura: `~/.savia/intensivo/runs/w-ux-asis/capturas/inicio-20261103.png` (local, fuera del repo). Cuatro hallazgos, cada uno con su criterio (AC-V1 a AC-V4):

1. Inicio muestra «Este teléfono no está conectado a Space. Conecta en Ajustes» con el teléfono emparejado con Soul y funcionando: falso error en la primera pantalla.
2. La barra superior de pestañas de texto no cabe: «Ajustes» se parte en vertical.
3. Aspecto de plantilla Material morada por defecto, sin diseño ni temas propios.
4. No hay ninguna superficie de conversación.

## Decisiones para la operadora

| # | Decisión | Estado |
|---|---|---|
| D1 | Quién procesa los datos del trabajo en la conversación | **Resuelta (operadora, 2026-11-03).** El proveedor de inferencia que contrate la organización, configurado y auditado por instalación (AC-4d de SE-490), con recibo local y aviso visible. Sin él, variante A. La inferencia personal nunca recibe N4 de la empresa. |
| D2 | Capturas de pantalla | **Resuelta.** Permitidas por defecto, con interruptor opcional «Bloquear capturas de pantalla» (alcance «siempre»), implementado en la PR #15 del repo de Space. El alcance «solo N3 y credenciales» es mejora opcional, no bloquea. |
| D3 | Canal de distribución de la APK | **Abierta.** Ver opciones abajo. |

**Opciones de D3 (canal de la APK).** La decide la operadora; S1 puede empezar sin ella porque el recorrido de AC-U5 instala por el canal de desarrollo, pero S5 no cierra sin ella.

| Opción | Cómo llega a la persona | A favor | En contra |
|---|---|---|---|
| a) Enlace de descarga | Página con la APK firmada, abierta desde el navegador del móvil | Lo más simple; funciona hoy; HyperOS lo acepta desde el navegador | Actualizar es manual: la persona tiene que volver a la página; la guía por fabricante es imprescindible |
| b) Repositorio F-Droid propio | La persona instala F-Droid (o un cliente compatible) y añade el repositorio de Savia | Actualizaciones automáticas con firma verificada; canal soberano sin tienda comercial | Dos instalaciones en vez de una; hay que mantener el repositorio y su firma; más pasos para una persona no técnica |
| c) Los dos | Enlace para la primera instalación; F-Droid propio para quien quiera actualizaciones | Cubre a las dos personas tipo | Doble mantenimiento; hay que mantener la misma firma en ambos canales |
| d) Tienda comercial (Google Play) | Instalación normal desde la tienda | Lo más fácil para una persona no técnica; actualizaciones automáticas | Depende de una cuenta de desarrollador y de la revisión de un tercero; choca con el principio de soberanía; no cubre teléfonos sin servicios de Google |

Ninguna opción cambia el diseño de la app; solo cambia S5 (canal, guía y prueba de instalación de AC-U1).

## Criterios de aceptación

### Usabilidad (obligatorios: sin ellos la spec no se cierra)

- **AC-U1 Tareas completas sin ayuda.** Al menos **3 personas no técnicas** (que no programan ni administran sistemas, y que no han visto Savia antes) completan, cada una en su propio ordenador y su propio móvil, sin ayuda de nadie: (1) instalación, (2) emparejamiento, (3) primera pregunta con respuesta, (4) apertura de un informe desde una cita, (5) aceptar o descartar una propuesta que el gemelo hizo por iniciativa propia en Inicio, y (6) encontrar y reabrir una conversación anterior. Se registra por tarea éxito/fracaso, tiempo y cada intervención pedida; una intervención cuenta como fracaso de esa tarea. Pasa si las 3 completan las 6 tareas. Las sesiones las conduce la orquestadora con un guion fijo; las personas las elige la operadora.
- **AC-U2 SUS ≥ 80.** Cuestionario SUS (System Usability Scale, 10 ítems) al terminar cada sesión de AC-U1. Pasa si la media es ≥ 80 y ninguna persona puntúa por debajo de 68.
- **AC-U3 UEQ-S medido.** Cuestionario UEQ-S (8 ítems) en la misma sesión. Se publica la media de las escalas pragmática y hedónica. Pasa si las dos son > 0,8 (por encima del umbral neutral del instrumento); si no, la spec documenta qué falló y el siguiente slice lo ataca.
- **AC-U4 Comparación cara a cara con 2 referentes.** Las mismas personas hacen la tarea (3) y la (4) en Savia y en dos asistentes del mercado (por defecto, la app de Claude y la de ChatGPT), en orden contrabalanceado, con un documento equivalente de nivel N1. Se mide tiempo, éxito y la preferencia declarada con su motivo. Pasa si Savia no es peor en éxito y la diferencia de tiempo mediana es ≤ 25 %; se publica el resultado tal cual, también si sale peor.
- **AC-U5 Recorrido previo en el dispositivo real.** Antes de cada sesión con personas, la orquestadora recorre las 6 tareas en un teléfono real (UI Automator o capturas) y adjunta las capturas en claro y en oscuro. Sin ese recorrido no se convoca a nadie.
- **AC-U6 Vocabulario interno prohibido.** Un test recorre todos los textos de la app (recursos de Android y textos de la web) y falla si aparece un identificador del contrato (`q1`–`q4`, `titulos`, `recuentos`, `completo` como nivel, `N1`–`N4` fuera de las marcas de nivel diseñadas, nombres de enum, «Continuidad», «Soul»), `adb`, `sudo` o una orden de terminal fuera de un bloque «copiar orden». Caso negativo: una cadena con «q1» introducida a propósito hace fallar el test.
- **AC-U7 Ortografía.** Un test falla si un texto en español contiene una palabra de la lista de formas sin tilde prohibidas («telefono», «peticion», «aprobacion», «Sesion»…). Caso negativo incluido.
- **AC-U8 Estados vacíos.** Ninguna lista muestra un vacío sin causa: test de UI que, con fuente al día, sin fuente y sin contacto, comprueba los tres textos y sus acciones.

### Hallazgos del dispositivo real (captura `~/.savia/intensivo/runs/w-ux-asis/capturas/inicio-20261103.png`)

- **AC-V1 Sin falso error de conexión en Inicio.** Con el teléfono emparejado solo con Soul, Inicio no muestra «no está conectado a Space» ni ningún error: muestra lo que da Soul y ofrece «Emparejar con Savia Space» como opción. Test de UI con tres estados: solo Soul (sin error), solo Space (sin error) y ninguno (mensaje con causa y acción). Caso negativo: con solo Soul, el texto «no está conectado» presente hace fallar el test. Se comprueba además en el recorrido de AC-U5 con captura.
- **AC-V2 La navegación cabe.** No queda barra superior de pestañas de texto; la barra inferior muestra Inicio, Conversaciones, Tareas y Contexto, cada etiqueta completa en una línea. Test de capturas a 360 dp de ancho con letra al 100 % y al 200 %: falla si una etiqueta se parte en más de una línea o se recorta (la etiqueta «Ajustes» partida en vertical de la captura es el caso negativo que debe fallar).
- **AC-V3 Diseño propio.** El tema de la app define sus tokens (colores por tema, tipografía, formas) y ninguna pantalla usa el esquema de color por defecto de la plantilla Material. Test que falla si el esquema de color efectivo coincide con el de la plantilla o si una pantalla no toma el tema de la app; capturas en claro y en oscuro adjuntas al recorrido de AC-U5.
- **AC-V4 Arranca en Inicio y hay conversación.** Tras emparejar, la primera pantalla es Inicio con un mensaje del gemelo y el campo de entrada; una frase escrita ahí abre una conversación y recibe respuesta en el hilo. Test instrumentado de arranque (la pantalla inicial es Inicio, no una lista ni Ajustes) y recorrido en el dispositivo real con captura. Caso negativo: una pantalla inicial sin campo de entrada hace fallar el test.

### Prototipo, navegación y densidad

- **AC-P1 Prototipo aprobado antes de codificar (S0).** Existe un prototipo navegable de Inicio, Conversaciones, la hoja «Qué está haciendo por ti», Tareas, Contexto, una conversación con propuesta del gemelo y el visor; la operadora lo recorre en su móvil y lo aprueba por escrito. Ningún slice de código (S1 en adelante) abre PR de implementación sin esa aprobación registrada. El prototipo pasa la evaluación heurística de AC-E4 antes de enseñarlo.
- **AC-N1 Cuatro destinos.** La navegación principal tiene exactamente Inicio, Conversaciones, Tareas y Contexto; Ajustes solo desde el avatar. Test de UI que falla con un quinto destino o sin uno de los cuatro.
- **AC-N2 Gestión de conversaciones.** Buscar (por título y contenido), fijar, renombrar y archivar funcionan desde la lista; una conversación archivada desaparece de la lista principal y se recupera desde «Archivadas». Test por cada acción, con caso negativo: buscar un texto inexistente muestra «sin resultados» con salida, no una lista vacía muda.
- **AC-N3 «Qué está haciendo por ti».** La hoja se abre desde Inicio y desde la cabecera del chat; muestra «Trabajando» con Parar y «Esperando» con desde cuándo; cada elemento abre su conversación de origen. Test de UI con una tarea en curso, una espera y ninguna (texto «Nada en marcha»).
- **AC-D1 Una acción principal.** Test de UI por pantalla que cuenta los botones de estilo principal (relleno o FAB) y falla si hay más de uno.
- **AC-D2 Inicio con 3 como máximo.** Con 7 elementos importantes en las fuentes, «Lo importante ahora» muestra 3, el tercero con «y 5 más» que lleva a Tareas. Caso límite: con exactamente 3, no aparece «y 0 más». Test.
- **AC-D3 Sin párrafos.** Un test recorre los textos de interfaz (fuera del contenido del chat y de los visores) y falla si alguno ocupa más de 2 líneas a 360 dp con letra al 100 %. Caso negativo: un texto de ayuda de 3 líneas introducido a propósito lo hace fallar.

### El gemelo activo

- **AC-G1 Habla primero.** Con un compromiso que vence hoy y una respuesta que espera desde ayer en el corpus de SE-490, el latido produce un mensaje del gemelo en Inicio sin que la persona escriba nada, con como máximo 3 asuntos y una propuesta por asunto. Test con reloj simulado.
- **AC-G2 Calla si no hay nada.** Con las fuentes al día y nada por encima del umbral, el latido no crea mensaje ni notificación. Test (caso negativo de AC-G1).
- **AC-G3 Respeta la atención.** En modo concentración o descanso, o con el presupuesto diario de avisos agotado (SE-490 AC-4b), el gemelo no notifica; lo acumula para Inicio. Test por cada causa y caso límite en el aviso que agota el presupuesto.
- **AC-G4 Propone, la persona aprueba.** Toda propuesta del gemelo con efecto externo (enviar un borrador, mover una cita, cerrar un elemento) es una tarjeta de acción; sin Confirmar no ocurre nada (mismo test que AC-3 aplicado a propuestas nacidas del latido). Una propuesta originada por texto de un tercero no se crea (AC-4).
- **AC-G5 Lo aprendido es visible.** Toda preferencia o procedimiento que el gemelo aprende aparece en Contexto marcado como aprendido, con su conversación de origen, y se borra en un toque; un procedimiento aprendido no se ejecuta sin preguntar hasta que la persona lo aprueba. Test.
- **AC-G6 Sin skills de terceros.** El gemelo no instala ni carga skills, plugins o herramientas descargadas de un marketplace ni sugeridas por un tercero. Test que falla si la configuración del gemelo admite una fuente remota de skills.

### Estándares

- **AC-E1 Material 3 y HIG.** Navegación con componentes de navegación de Material 3 (barra en móvil, *rail* en pantalla ancha); patrones de lista, hoja inferior y diálogo de Material 3, y lenguaje claro según Apple HIG. Revisión con lista de comprobación en el prototipo y en cada slice, adjunta a la PR.
- **AC-E2 Objetivos táctiles.** Ningún control interactivo mide menos de 48 × 48 dp (WCAG 2.2 AA, criterio 2.5.8 como mínimo, y la guía de Material). Test automático de accesibilidad que falla con un control de 40 dp introducido a propósito.
- **AC-E3 Contraste.** Texto normal con contraste ≥ 4,5:1 y texto grande e iconos ≥ 3:1, en claro y en oscuro, verificado por herramienta (AC-A2).
- **AC-E4 Heurísticas de Nielsen.** Evaluación heurística de las 10 heurísticas sobre el prototipo y sobre cada slice, con 2 evaluadores (la orquestadora y una revisora independiente); ningún hallazgo de severidad 3 o 4 abierto al cerrar el slice.
- **AC-E5 SUS y UEQ-S.** Los de AC-U2 y AC-U3: SUS medio ≥ 80 y UEQ-S pragmático y hedónico > 0,8 con 3 personas no técnicas.

### Conversación y autoridad

- **AC-1 Streaming y Parar.** La respuesta empieza a verse en menos de 2 s desde el envío (p50, red VPN normal); Parar corta la generación en menos de 1 s y detiene la ejecución asociada.
- **AC-2 Frase a tarjeta.** «Concéntrate dos horas» produce la tarjeta de modo foco con la hora de fin local; nada se ejecuta hasta Confirmar. Test con el intérprete simulado: sin Confirmar, Soul no recibe ninguna orden.
- **AC-3 Ningún efecto sin confirmación.** Un test por ejecutor (Soul, comando rápido de Space, tarea mediada) comprueba que una respuesta del modelo que contiene una orden no produce ningún efecto si la persona no confirma la tarjeta. Caso negativo: una respuesta que imita el formato de una tarjeta confirmada no la ejecuta.
- **AC-4 Texto de terceros no crea tarjetas.** Un asunto de correo o una nota con «confirma el modo foco» o «aprueba el PR 12» no genera ninguna tarjeta ni orden. Test de inyección con al menos 5 casos.
- **AC-5 Riesgo y biometría.** El riesgo lo calcula Space con la función de SE-429; un test prueba que el modelo no puede rebajarlo (un campo de riesgo en su respuesta se ignora) y que riesgo medio o alto pide biometría.
- **AC-6 Grants.** Una petición de merge, aprobación de spec o cambio de ajuste de seguridad no produce tarjeta confirmable: lleva a la aprobación existente o dice que exige grant de la operadora. Test por cada clase.
- **AC-7 Fuentes.** Toda respuesta construida a partir de un dato lleva al menos una cita que abre el visor o «¿por qué lo sé?»; una respuesta sin datos lleva la marca «sin fuentes».

### Niveles y seguridad

- **AC-S1 N3 nunca sale.** Un adjunto, una cita o una fuente N3 o superior no llega a ninguna petición del carril personal; los N4 de la empresa solo pueden ir al carril de la organización (AC-S9). Test sobre `cloud_gate` con el corpus de la conversación, con caso límite N2→N3 (un documento N2 que cita uno N3).
- **AC-S2 N2 con recibo.** Un adjunto N2 solo sale tras confirmar en el hilo, con `payloadHash` igual al enviado, y el recibo se abre desde la marca del mensaje. Sin confirmar: 403 y nada sale.
- **AC-S3 Nivel desde el móvil solo sube.** Una petición del móvil que intenta bajar el nivel de un documento se rechaza. Test.
- **AC-S4 Datos del trabajo sin proveedor de la organización (variante A).** Sin `inferencia_organizacion` declarada, lo único que sale hacia la nube en una pregunta sobre datos del trabajo es la frase y la lista de órdenes; un test inspecciona la petición saliente y falla si contiene un `title`, un `attrs`, un remitente, un asunto o una clave de afirmación. Fail-closed: si el intérprete no responde, la app ofrece las sugerencias tocables y no envía nada más.
- **AC-S9 N4 nunca va al carril personal.** Con y sin proveedor de la organización, ninguna petición del carril personal contiene un elemento leído por los adaptadores de oficina. Test con el corpus de SE-490 que inspecciona todas las peticiones salientes del carril personal. Caso negativo: un turno que mezcla una pregunta de trabajo y una nota personal produce dos envíos separados, y el del carril personal no lleva datos N4.
- **AC-S10 Proveedor de la organización solo declarado y auditado.** Con una credencial configurada pero sin `aprobado_para: N4`, sin quién lo declara o sin fecha, el carril de la organización no existe y la conversación de trabajo es variante A. Alta, cambio y baja de la declaración quedan en el registro de auditoría local con persona, fecha y hash de la configuración. Una petición del móvil para declarar o cambiar el proveedor se rechaza. Tests por cada caso, incluido el de declaración incompleta.
- **AC-S11 Dos adaptadores con el mismo contrato.** El adaptador compatible con OpenAI (probado contra OpenAI y contra Azure OpenAI con despliegue y versión de API) y el de Anthropic pasan la misma batería: enviar, recibir en streaming, cancelar con Parar y error del servicio. Tests contra servidores simulados; la batería falla si un adaptador ignora la cancelación.
- **AC-S12 Recibo de cada envío o no hay envío.** Cada petición al proveedor de la organización deja un recibo local con hora, proveedor, modelo, dirección del servicio, nivel máximo, número de elementos y de bytes, `source_refs` y hash del cuerpo; el hash coincide con el cuerpo realmente enviado (test con servidor simulado que recalcula el hash). El recibo no contiene el texto de los elementos. Fail-closed: si el recibo no se puede escribir, la petición no sale (test con almacén de recibos sin escritura).
- **AC-S13 Sin caída al carril personal.** Si el proveedor de la organización da error, no responde en el tiempo límite o su declaración se retira a mitad de un hilo, ninguna petición con datos N4 se reenvía por el carril personal ni por otro proveedor; la conversación pasa a variante A con un aviso. Test por cada causa.
- **AC-S14 Aviso de quién responde.** Cada mensaje de respuesta lleva la marca del carril y el nombre humano del proveedor («el servicio de IA de tu empresa (Azure OpenAI)», «Claude, tu cuenta personal», «modelo local de tu ordenador»); un cambio de proveedor dentro del hilo se marca en el mensaje donde ocurre. Test de UI con los tres proveedores y con un cambio a mitad del hilo; falla si un mensaje no tiene marca.
- **AC-S5 Rutas de documentos acotadas.** Las rutas nuevas de dispositivo devuelven 403 fuera del alcance del dispositivo y para niveles por encima del permitido. Tests con un documento de cada nivel.
- **AC-S6 Visor inerte.** Un md con HTML, JavaScript o imágenes remotas no ejecuta nada ni hace peticiones de red al renderizarse. Test.
- **AC-S7 Capturas.** Por defecto, ninguna ventana lleva `FLAG_SECURE`; con «Bloquear capturas de pantalla» encendido, sí. Lo cubre la PR #15 de Space para las pantallas actuales; esta spec exige el mismo test en las pantallas nuevas (conversación y visores) y, con política de instancia, que la app no deje apagar el interruptor. Test instrumentado.
- **AC-S8 Revisión de seguridad** del intérprete (superficie de inyección), de las rutas de documentos y del canal de streaming, antes de fusionar S3.

### Accesibilidad

- **AC-A1** Las 6 tareas de AC-U1 se completan con TalkBack activado (recorrido de la orquestadora) y con letra al 200 % sin texto cortado (test de capturas).
- **AC-A2** Contraste WCAG 2.2 AA en claro y en oscuro, verificado por herramienta en cada pantalla.

## Plan por slices

| Slice | Contenido | Entregable | Duración |
|---|---|---|---|
| **S0** | Prototipo navegable (no código de producto) de Inicio, Conversaciones, hoja «Qué está haciendo por ti», Tareas, Contexto, conversación con una propuesta del gemelo y visor, en claro y oscuro, a 360 dp. En curso en el plan intensivo (`~/.savia/intensivo/runs/w-prototipo-app/`, local). Evaluación heurística y aprobación de la operadora en su móvil | AC-P1, AC-E4 sobre el prototipo | 2–3 días |
| **S1** | Inicio (con el mensaje del gemelo construido en el portátil con plantillas a partir de SE-490, sin modelo), Conversaciones (lista con buscar, fijar, renombrar y archivar) y chat básico (texto, streaming, Parar, citas) sobre el carril personal existente, sin acciones. Visor de md y PDF. Rutas de dispositivo para listar y leer documentos con nivel. Barra inferior de 4 destinos (Tareas y Contexto con su estado vacío honesto). Inicio sin falso error de conexión. Las pantallas nuevas siguen el ajuste de capturas de la PR #15 de Space | AC-1, AC-7, AC-N1, AC-N2, AC-D1–AC-D3, AC-G1–AC-G3, AC-S1, AC-S5–AC-S7, AC-U6, AC-V1, AC-V2, AC-V4, AC-E2; APK instalable y recorrido en el dispositivo real (AC-U5) | **1 semana** |
| S2 | Tareas y procesos (espera tu respuesta, en curso, programado) y la hoja «Qué está haciendo por ti». Contexto (lo que sabe de ti, aprendido, proyectos y documentos, fuentes conectadas, sin rastro). Datos del trabajo en la conversación: variante A y carril de la organización (declaración auditada, adaptadores compatible con OpenAI/Azure y Anthropic, recibo local, aviso de proveedor, sin caída al carril personal) | AC-N3, AC-G5, AC-G6, AC-S4, AC-S9–AC-S14 | 1–2 semanas |
| S3 | Acciones con aprobación dentro del chat: tarjetas de acción para Soul, comandos rápidos y tareas mediadas; propuestas del gemelo como tarjetas; biometría; aprobaciones en el hilo; texto de terceros inerte | AC-2 a AC-6, AC-G4, AC-S8 | 1–2 semanas |
| S4 | Adjuntos (imagen, PDF, md) con nivel y recibo N2; visor de imágenes y tablas; dictado y lectura en voz alta; compartir y exportar; «pregunta sobre esto» | AC-S2, AC-S3 | 1 semana |
| S5 | Primera experiencia: instalador sin `sudo` con runtime incluido, diagnóstico, emparejamiento con QR y palabras de verificación, canal de la APK (según D3), estados vacíos. Escritorio: la misma app en la web de Space | AC-U7, AC-U8 | 1–2 semanas |
| S6 | Diseño propio y temas, accesibilidad completa; pruebas con 3 personas no técnicas, SUS, UEQ-S y comparación con 2 referentes | AC-U1 a AC-U4, AC-V3, AC-A1, AC-A2, AC-E1, AC-E3, AC-E5 | 1 semana |

D1 y D2 están resueltas. S1 no empieza sin S0 aprobado (AC-P1). S1 se puede empezar sin D3; S5 no cierra sin ella. Las pruebas de usabilidad de S6 se pueden adelantar con un subconjunto de tareas tras S3, y una prueba de pasillo con el prototipo de S0 es recomendable.

## Fuera de alcance

- Contratar, elegir o recomendar el proveedor de la organización, y responder de su tratamiento: es responsabilidad de la organización (D1). Savia solo lo configura, lo audita y registra qué le envía.
- Adaptadores para productos sin API compatible con OpenAI ni con Anthropic (por ejemplo, Copilot de Microsoft 365): quedan como adaptadores futuros sobre el mismo contrato interno.
- El alcance «solo N3 y credenciales» del bloqueo de capturas: mejora opcional (D2).
- Voz conversacional continua (hablar y escuchar sin pulsar).
- Edición de documentos dentro de la app: los visores son de lectura.
- Notificaciones push o Firebase: se mantiene la decisión vigente de consulta periódica sin push.
- iOS: esta spec cubre Android y la web del escritorio.
- Cambiar las reglas de niveles, la política de inferencia o la autoridad de merge.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| El intérprete recibe texto de terceros dentro del contexto (inyección) | Solo propone; toda orden con efecto pasa por la tarjeta y por el control de efectos del ejecutor; el texto de terceros entra marcado como dato (AC-4, AC-S8) |
| Las tarjetas de acción entrenan a confirmar sin leer | Riesgo determinista con biometría en medio y alto; las acciones con grant no se confirman desde una tarjeta (AC-6); deshacer visible donde existe |
| Retirar `FLAG_SECURE` expone datos en capturas | Es la decisión de la operadora, ya implementada en la PR #15 de Space; queda el interruptor opcional y la política de instancia (AC-S7) |
| Un dato N4 acaba en el carril personal por un error de enrutado o por una caída del proveedor de la organización | Dos carriles que nunca comparten envío; sin caída al carril personal; test sobre todas las peticiones salientes (AC-S9, AC-S13) |
| Se configura un proveedor que la organización no aprobó | El carril solo existe con declaración completa y auditada desde el ordenador; Savia no lo verifica ante la empresa y lo dice; la responsabilidad de esa declaración es de quien la hace (AC-S10) |
| En variante A, la propia frase de la persona contiene datos del trabajo | Se avisa de que la frase sale; modelo local preferente si existe; la persona puede usar solo las sugerencias tocables sin enviar nada |
| La conversación se percibe lenta en la VPN | AC-1 mide la latencia en red real; el estado intermedio se ve desde el primer evento |
| El gemelo activo molesta: avisa demasiado o en mal momento | Presupuesto de avisos y política de atención de SE-490; calla si no hay nada; como máximo 3 asuntos por mensaje (AC-G2, AC-G3, AC-D2) |
| El gemelo, con acceso amplio, repite los fallos de seguridad de los agentes personales (inyección por correo, instancias expuestas, skills maliciosas) | Ningún efecto sin tarjeta; texto de terceros inerte; escucha solo en VPN con emparejamiento; sin marketplace de skills (AC-3, AC-4, AC-G6, AC-S8) |
| Se codifica antes de validar la arquitectura de información | S0 obligatorio con aprobación de la operadora (AC-P1) |
| Las 3 personas no técnicas no aparecen a tiempo | S6 no bloquea S1–S5, pero la spec no pasa a IMPLEMENTED sin AC-U1 a AC-U4 |
| El SUS sale por debajo de 80 | Se publica tal cual, se itera sobre las fricciones registradas y se repite; no se rebaja el umbral |
| El cambio toca dos repos (Space privado y Savia público) | Cada slice abre su PR en el repo que corresponde; esta spec solo enlaza rutas públicas |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| App Android y web de Space (conversación, visores, contexto) | No depende del frontend de agentes | No depende del frontend de agentes |
| Servidor de Space: chat que responde, rutas de dispositivo de documentos, streaming | Proceso Rust independiente | Igual |
| Inferencia de la conversación | Carril personal: modelo de Claude por tier (`model_tier`), resuelto en la definición local. Carril de la organización: adaptador declarado en `inferencia_organizacion`, independiente del frontend | Igual: Space es un frontend más del esquema de tiers; el motor del perfil mediado es OpenCode (SE-428) |
| Intérprete de frases y conversación del gemelo sobre datos del trabajo | Ruta de Soul que usa el proveedor de la organización si está declarado y, si no, la variante A; CLI `soul` | Misma CLI y misma ruta |
| Ejecución de tarjetas: tareas mediadas | Perfil mediado de SE-428 | Perfil mediado de SE-428 (motor OpenCode) |

### Verification protocol

- [ ] Funciona en runtime OpenCode: la conversación y los visores no dependen del frontend; las tareas mediadas usan el motor OpenCode de SE-428
- [ ] Tests de la app (instrumentados y de textos) y del servidor cubren el único camino de ejecución
- [ ] No añade hooks de Savia

### Portability classification

- [x] **DUAL_BINDING**: el producto es la app y el servidor de Space; los frontends de agentes no intervienen salvo como motor del perfil mediado, que ya es OpenCode.

## Aprobación

Tier 4: cambia la superficie de autoridad (tarjetas de acción y aprobaciones en la conversación), la política de capturas y las rutas por las que salen datos del ordenador. La revisa y la decide la operadora; D1 y D2 ya las decidió, D3 sigue abierta. Ningún agente la aprueba ni la fusiona.
