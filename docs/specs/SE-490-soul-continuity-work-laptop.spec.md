---
status: PROPOSED
priority: P0
developer_type: agent-team
created: 2026-10-31
author: Savia
phase: A
risk: L3
depends_on: [SE-430]
related_specs: [SE-431, SE-430, SE-482, SE-484, SE-487, SE-488, SE-401]
origin: "Decisión de la operadora 2026-10-31 (AskUserQuestion): el gemelo operativo es el objetivo prioritario; plazo de dos semanas; fuentes de trabajo de quien dirige equipos y proyectos; corre en el portátil de la empresa; se usa desde la app móvil de Savia Space; la prioridad es la continuidad y los compromisos. Diseño previo en el vault privado de investigación (línea del gemelo operativo, prototipo de instantánea de solo lectura medido)."
timeline:
  - from: "2026-10-31"
    learned: "2026-10-31"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-490 — Soul Continuidad v1: gemelo operativo en el portátil de trabajo, de solo lectura y con comunicación bidireccional

## Problema

Quien dirige equipos y proyectos sostiene en la cabeza qué tiene abierto, qué depende de ella o de él, qué cambió desde ayer y qué se comprometió con quién. Esa información está repartida entre el correo, el calendario, el chat de equipo, los documentos, el gestor de tareas y los repositorios. Reconstruirla cada mañana y antes de cada reunión es carga cognitiva que no aporta criterio.

Punto de partida verificado:

- **Soul** existe como dominio puro dentro del repo privado de Savia Space (`space-soul`: 21 módulos, 266 tests). Solo corre dentro del servidor de Space y en Linux. Su bucle está pensado para orquestar, no para dar continuidad al operador.
- **La instantánea del operador** existe como prototipo de investigación de solo lectura:
  - seis adaptadores de fuentes de desarrollo (git, GitHub, runs, specs, traspaso, contratos);
  - 51 escenarios con 5 operadores sintéticos, sin modelo.

  No lee ninguna fuente de oficina: ni correo, ni calendario, ni chat, ni documentos.
- **La app Android de Space** tiene emparejamiento, bandeja y aprobaciones. No tiene ninguna vista de continuidad.
- **No hay medida de uso real** de Soul por ningún operador.

## Qué decide esta spec

Se construye **Soul Continuidad v1**: un proceso **por usuario**, sin privilegios de administrador, que corre en el equipo de trabajo del operador. Lee fuentes de trabajo **en solo lectura** y con consentimiento por fuente, y responde a cuatro preguntas. Se consulta desde la app móvil de Savia Space emparejada y desde una CLI local.

La comunicación es **bidireccional**: el operador pregunta, corrige y declara su modo de atención, y Soul le envía resúmenes, avisos, alertas y mensajes según una política de atención que decide el operador.

**v1 no ejecuta, no delega, no aprueba y no envía nada a terceros.** No usa modelos de lenguaje salvo uno local o uno aprobado por la organización del operador.

| Pregunta | Qué devuelve |
|---|---|
| **Q1 — ¿Qué tengo abierto?** | Reuniones de hoy y mañana, tareas asignadas, revisiones pedidas, hilos que esperan mi respuesta y documentos compartidos conmigo con comentarios sin resolver. |
| **Q2 — ¿Qué depende de mí?** | Lo que otra persona espera de mí: me han asignado, me han mencionado, me han pedido revisión o el correo va dirigido a mí y sigue sin respuesta. Cada elemento lleva su fuente y su antigüedad. |
| **Q3 — ¿Qué cambió desde…?** | Diferencias entre dos instantes, sobre las mismas fuentes. |
| **Q4 — Compromisos con fecha** | Solo los **estructurados**: fechas de vencimiento de tareas, reuniones, entregas en el gestor y correos marcados con fecha. Los compromisos escritos en texto libre («te lo paso el jueves») quedan fuera de v1. |

Cada afirmación conserva el modelo de la instantánea: `claim_type`, `state`, `source_refs`, `observed_at`, `valid_until` y `sensitivity`, con TTL obligatorio. Un hecho revocado o sustituido no reaparece al reconstruir.

## Arquitectura

### Proceso por usuario y multiplataforma

- **Tecnología: sobre runtimes ya aprobados, sin ejecutables propios.** Decisión de la operadora del 2026-10-31.
  - En equipos corporativos, un ejecutable propio sin firmar choca con SmartScreen, AppLocker o WDAC y con Gatekeeper.
  - Soul Continuidad v1 es **código TypeScript que corre sobre el runtime oficial de Node.js LTS**, firmado por su editor. Se instala sin administrador desde la distribución portable del propio editor si el equipo no lo trae.
  - Para el adaptador `web`, usa el **navegador ya instalado** (Edge o Chrome) en un perfil dedicado.
  - Se descarta Electron como base: una app Electron empaquetada es un ejecutable propio que necesitaría firma.
  - El dominio de `space-soul` (Rust) y el prototipo de la instantánea (Python) son la **referencia funcional y de banco**. Los invariantes se portan con sus tests: fail-safe durable, revocación y TTL.
- **Núcleo:**
  - Es un proceso único para Windows, macOS y Linux. No acepta conexiones salvo en las direcciones que configure el operador (ver canal).
  - Arranca sin Space, sin Yema, sin modelo y sin Internet; sin conexión, responde con lo último conocido marcado como tal.
- **Instalación sin administrador:**
  - Windows: tarea de inicio de sesión del usuario;
  - macOS: `LaunchAgent`;
  - Linux: `systemd --user`.

  El modo por defecto es bajo demanda. Arrancar el servicio no concede ningún permiso.
- **Estado:** en el directorio de datos del usuario del sistema. Es borrable y exportable, y un desinstalador lo elimina entero.

### Adaptadores de fuente

Todos son opcionales, de solo lectura y con consentimiento propio. Cada uno declara propósito, nivel de confidencialidad, revocación y TTL.

| Adaptador | Fuente | Acceso |
|---|---|---|
| `m365-mail` | Correo | Graph delegado si el inquilino lo permite; si no, ruta web (Outlook en la web) |
| `m365-calendar` | Calendario | Graph delegado si el inquilino lo permite; si no, ruta web |
| `m365-teams` | Menciones y chats | Graph delegado si el inquilino lo permite; si no, ruta web (Teams en la web) |
| `m365-files` | Documentos compartidos y comentarios | Graph delegado si el inquilino lo permite; si no, ruta web (SharePoint/OneDrive) |
| `google-workspace` | Equivalentes de Google | API de Google, solo lectura |
| `jira` | Gestor de tareas | Conectores existentes de Savia |
| `azure-devops` | Gestor de tareas | Conectores existentes de Savia |
| `github` | Repositorios | Conector existente |
| Fuentes locales de la instantánea | git, specs, traspaso | Ya implementadas |
| `web` | Webs sin API, A2A ni MCP | Navegador en perfil dedicado a Soul, solo lectura (ver abajo) |

#### Adaptador `web`: la web como una interfaz más

Mucha información de trabajo solo vive en webs sin API, sin A2A y sin MCP: portales internos, herramientas de proveedores, paneles. El adaptador `web` las lee con un navegador **en un perfil dedicado a Soul**. Decisión de la operadora del 2026-10-31.

- **Perfil dedicado, no el navegador personal.**
  - Es un perfil aparte del navegador de la instalación (Edge, Chrome o Firefox), donde el operador inicia sesión **solo** en las webs que quiere dar a Soul.
  - Soul nunca toca el perfil personal, sus cookies ni sus otras sesiones.
  - El control es local: un canal de depuración sobre tubería o `localhost` aleatorio con token, nunca expuesto a la red.
- **Solo lectura, aplicada fuera del modelo y en dos capas:**
  - **URLs cerradas por receta.** Cada receta declara la lista exacta de patrones de URL que puede visitar. Las vistas de lista y los paneles de solo lectura van en ella; enlaces de acción (`/approve`, `/logout`, `/unsubscribe`, confirmaciones) nunca entran.
    - Toda navegación, incluidas redirecciones y peticiones de la propia página iniciadas por un clic de la receta, se compara con esa lista. Lo que no casa se aborta.
    - **La cobertura de solo lectura depende de esta lista, no del método HTTP:** un `GET` también puede cambiar estado.
  - **Método en la red.** Se aborta toda petición que no sea `GET`/`HEAD`, salvo las de renovación de sesión de una lista por sitio.
  - No envía formularios.
  - No pulsa elementos fuera de una lista cerrada de acciones de navegación de cada receta (paginar, expandir, cambiar de pestaña de la página). Cada acción está ligada a las URLs que puede provocar.
  - No abre elementos individuales cuando abrirlos cambia su estado (un correo pasa a «leído», una notificación a «vista»). En v1 las recetas leen **vistas de lista**.
  - No descarga ni ejecuta ficheros.
- **Lista de sitios permitidos** por el operador, cada uno con propósito, nivel de confidencialidad (por defecto N4), frecuencia máxima de visita y revocación. Una navegación fuera de la lista se bloquea.
- **Recetas deterministas por sitio,** sin modelo: qué páginas visitar, qué selectores extraen elementos para Q1–Q4 (asignado a mí, pendiente, con fecha) y cómo se identifica cada elemento de forma estable.
  - Si no hay receta, solo se detecta «esta página cambió desde la última visita», con el enlace.
  - Las recetas son configuración del operador o plantillas genéricas del producto, nunca código específico de una organización en el repo.
- **Contenido no fiable:** todo texto web es dato. Nunca selecciona acciones, nunca cambia la lista ni la receta y nunca eleva un aviso a alerta. Se guardan referencias y metadatos, no páginas completas.
- **Sesión caducada:** el adaptador se detiene y avisa: «vuelve a iniciar sesión en X en el perfil de Soul». Nunca guarda contraseñas ni rellena credenciales.
- **Ruta web para Microsoft 365 y Google.** Si el inquilino no permite que el propio usuario consienta los permisos de lectura de Graph (lo habitual para correo, chats y ficheros), el operador puede activar recetas sobre los clientes web oficiales: Outlook, Teams y SharePoint/OneDrive en la web, o Gmail, Calendar y Drive. Usa su propia sesión en el perfil dedicado, con las mismas reglas de solo lectura y vistas de lista.

Reglas de los adaptadores:
- **Autenticación delegada por el propio usuario** (flujo de dispositivo o navegador). Los tokens van al almacén de credenciales del sistema: Credential Manager, Keychain o Secret Service. Nunca a ficheros, logs, variables ni línea de órdenes.
- **Fail-closed:** si el inquilino exige consentimiento de administración para un permiso, la ruta Graph de ese adaptador no se activa. Lo dice con un mensaje claro y ofrece la ruta web. Nunca pide más permisos de los que necesita, ni usa identificadores de aplicación ajenos para sortear el consentimiento.
- **«Esperando mi respuesta» solo con metadatos.** El hilo (`conversationId` o equivalente) cumple todas estas condiciones:
  - su último mensaje no es mío;
  - yo estoy entre los destinatarios directos;
  - no hay ningún mensaje mío posterior en elementos enviados del mismo buzón. Así se cuentan las respuestas desde cualquier cliente: web, móvil u Outlook.

  Las respuestas fuera del buzón (otra cuenta, llamada) se corrigen con «resuelto».
- **Lectura mínima.** Se guardan metadatos y referencias: remitente, asunto, fecha, estado, enlace. El cuerpo de un correo o de un mensaje no se persiste. El texto de terceros solo se muestra si la vista lo pide, y se lee en ese momento.

### Vista móvil (app de Savia Space)

- **Pantalla «Continuidad»:** Q1–Q4, con «¿por qué lo sé?» (fuente y antigüedad), una corrección por elemento (marcar como resuelto o no aplica, guardado en el libro de revocaciones) y modo de atención declarado.
- **Canal:** red privada del operador entre el portátil y el móvil, sin relay ni push. Decisión de la operadora del 2026-10-31.
  - Es una VPN de malla como Tailscale o WireGuard; la elige y gestiona el operador.
  - Soul solo escucha en las direcciones de esa red que configure el operador, nunca en todas las interfaces. Usa TLS y el emparejamiento existente de la app (token por dispositivo, revocable).
  - La app consulta cada 5 minutos.
- **Nivel de detalle por instalación,** que decide el operador según la política de su empresa:
  - `completo`;
  - `títulos` (asunto y fuente, sin contenido; por defecto);
  - `recuentos` (solo cifras y tipos).
- La app no guarda datos de trabajo más allá de la sesión de la vista y de los mensajes que el operador decida conservar.

### Comunicación bidireccional: avisos, alertas y mensajes

Soul y el operador se hablan en los dos sentidos desde la app.

**Del operador a Soul:**
- Preguntas Q1–Q4 y filtros: por proyecto, por persona, por fecha.
- Correcciones: resuelto, no aplica, esto es mío, esto no es mío.
- Declaración del modo de atención: `DISPONIBLE`, `FOCO`, `DESCANSO` o `FUERA`, con ventana.
- Configuración de qué avisos quiere y cuándo.
- **En v1 son intenciones estructuradas:** botones y órdenes cortas con gramática determinista, sin modelo de lenguaje.
- La conversación en lenguaje natural sobre datos de trabajo exige un modelo:
  - **local** en el equipo, si la instalación lo tiene;
  - o **un proveedor que la organización del operador haya aprobado expresamente** para esos datos.

  Por defecto está desactivada, y se activa por instalación cuando exista una de las dos condiciones. Sin ella, el texto libre recibe una respuesta honesta: «no puedo interpretar texto libre aquí; usa una de estas órdenes».

**De Soul al operador** (tipos de mensaje):

| Tipo | Ejemplo | Cuándo |
|---|---|---|
| Resumen de inicio | Qué cambió, qué depende de ti hoy, primeras reuniones | A la hora que fija el operador |
| Resumen de cierre | Qué quedó abierto y qué espera a mañana | A la hora que fija el operador |
| Aviso | Reunión en 15 min con documentos compartidos sin leer; vencimiento mañana | Según reglas activadas por el operador |
| Alerta | Algo que el operador ha declarado como urgente (lista cerrada definida por él: p. ej. una persona o un proyecto concretos, una palabra en el asunto de un remitente concreto). El remitente se casa por identidad **autenticada**: mismo inquilino con identificador de la API, o DKIM/DMARC superados. Nunca solo por la cabecera `From` | Siempre que el modo lo permita, o también en descanso si así lo marcó |
| Mensaje | Respuesta a una pregunta o confirmación de una corrección | Al momento |

**Política de atención (determinista, decidida por el operador):**
- Cada evento pasa por la política antes de convertirse en mensaje: registrar, agrupar, avisar o diferir.
- En `FOCO`, `DESCANSO` y `FUERA` todo se difiere, salvo las alertas que el operador marcó **para el modo activo**. Una alerta definida pero no marcada para ese modo se difiere como cualquier aviso.
- **Presupuesto de avisos** por ventana, que fija el operador. Lo que excede se agrupa en el siguiente resumen.
- Las alertas **no consumen** ese presupuesto. Tienen un **tope propio**, que fija el operador (por defecto 3 por ventana). Si se supera, las siguientes se agrupan en un único mensaje: «hay N alertas más», con la lista. Nunca se pierden.
- El silencio del operador nunca es una respuesta. Ningún modelo eleva la urgencia.
- Cada aviso enviado o diferido queda en un registro de demanda que el operador puede consultar: «¿por qué me avisaste?» y «¿qué me ahorraste?».

**Transporte. D-490-1 cerrada: VPN del operador y consulta periódica.** Amplía SE-430, que hoy consulta al abrir la app o cada ≥ 15 min.
- La app consulta al portátil **cada 5 minutos** por la red privada del operador, también con la app en segundo plano: un servicio en primer plano de Android con su notificación persistente, porque el planificador del sistema no baja de 15 min.
- **No hay relay, ni push, ni servicio intermedio.** Ningún tercero ve contenido ni metadatos de los avisos, salvo el proveedor de la VPN que elija el operador, y solo los de conexión.
- Los avisos y alertas se muestran como **notificaciones locales** del móvil, generadas por la app tras cada consulta. Su contenido en pantalla de bloqueo respeta el nivel de detalle: con `recuentos`, solo «2 avisos, 1 alerta».
- **Latencia máxima:** 5 min más el intervalo de lectura de la fuente. Lo que necesite menos («reunión en 15 min») se programa con antelación como notificación local en el móvil desde la consulta anterior.
- Si el portátil no está alcanzable (apagado, sin VPN), no hay avisos. La app lo dice («sin contacto con tu equipo desde las 18:40») y no lo esconde.
- Revisión de seguridad del canal antes de construirlo (AC-6): solo escucha en la VPN, emparejamiento y revocación del token, y móvil perdido.

### Datos y confidencialidad

- Todo lo que leen los adaptadores de empresa se trata como **N4** (datos de la organización y de terceros). No sale del equipo del operador salvo hacia su propia app emparejada, con el nivel de detalle elegido.
- **Ningún dato de trabajo va a modelos en la nube en v1.** Eso incluye los frontends de agentes (Claude Code, OpenCode), cuyo modelo corre en la nube: por esa ruta solo salen recuentos (AC-4d).
- No hay inferencias sobre personas: ni cansancio, ni rendimiento, ni estado emocional, ni horas de actividad de nadie (tesis de diseño en el vault de investigación; AI Act art. 5.1.f).

### Responsabilidad del operador y transparencia

- Soul Continuidad es una **herramienta personal del operador** para trabajar con los datos a los que ya accede, en su equipo y en su cúpula local. El operador decide qué instala y qué fuentes activa, y es responsable de su uso. Decisión de la operadora del 2026-10-31.
  - Al activar cada adaptador de fuentes de una organización, la instalación lo registra con una declaración breve: «activo esta fuente bajo mi responsabilidad». No pide confirmación a terceros.
- Soul no sortea controles técnicos de la organización: ni identificadores ajenos, ni reenvío de correo a cuentas personales, ni publicación de calendarios. Si un control bloquea una ruta, se dice y se ofrece la siguiente legítima (Graph → web → manual).
- El producto incluye un **documento de transparencia** (`docs/soul-continuity-it-pack.md`). El operador puede compartirlo si quiere o si se lo piden:
  - flujo de datos;
  - qué lee cada adaptador;
  - dónde se guarda;
  - qué sale del equipo;
  - cómo se revoca y se borra;
  - modelo de amenazas.

## Fuera de alcance de v1

- Delegar o ejecutar (Yema, Space, harnesses).
- Compromisos en texto libre y resúmenes con LLM, salvo con un modelo local o un proveedor aprobado por la organización (ver comunicación bidireccional).
- Bandeja de decisiones con recomendación.
- Federación entre dispositivos.

Todo ello va en specs posteriores, con evidencia de uso de v1.

## Criterios de aceptación

- **AC-1:** el paquete corre en CI sobre Windows, macOS y Linux con el runtime oficial de Node.js LTS. No distribuye ejecutables propios y arranca sin administrador, sin red y sin Space. `status` responde en menos de 1 s en frío.
- **AC-2:** banco de continuidad con verdad escrita antes de ejecutar.
  - Inquilinos sintéticos de Microsoft 365 y Google mediante dobles de las APIs, más Jira, Azure DevOps y GitHub.
  - Al menos 4 operadores sintéticos (dirección, PM, investigación, docencia) y una instalación mínima sin fuentes de oficina.
  - ≥ 60 escenarios Q1–Q4 que incluyan:
    - revocación que no vuelve;
    - dos instantes;
    - cambio de perfil;
    - datos de terceros;
    - inyección en asuntos y comentarios;
    - inquilino que exige consentimiento de administración;
    - token caducado;
    - hilos «esperando mi respuesta» con respuestas desde otro cliente, respuestas a todos y reenvíos (al menos 8 escenarios).
- **AC-3:** en ese banco, precisión ≥ 90 % por pregunta. 0 uso de hechos revocados, 0 fugas entre operadores y entre niveles, 0 cuerpos de mensaje persistidos y 0 tokens en disco fuera del almacén del sistema. p95 de Q1 < 2 s con fuentes cacheadas.
- **AC-4:** la vista móvil muestra Q1–Q4 con fuente y antigüedad en los tres niveles de detalle. Con `recuentos`, ningún asunto ni nombre llega al dispositivo (test que inspecciona el tráfico). Todo texto de terceros se muestra como **texto inerte**: sin markdown activo, sin enlaces ni deep links que la app abra por sí misma, y sin HTML. Hay un test con payloads de inyección.
- **AC-4c:** una alerta con el remitente suplantado (`From` falsificado, sin DKIM/DMARC o de otro inquilino) no se dispara. Hay escenario en el banco.
- **AC-4d (frontends de agente):** la salida que llega a Claude Code, OpenCode u otro frontend cuyo modelo corre en la nube es siempre de nivel `recuentos`. Solo sube de nivel si la instalación declara ese proveedor como aprobado por la organización para N4, en configuración local y auditada. Un test verifica que, sin esa declaración, ni asuntos, ni nombres, ni remitentes salen por esa ruta.
- **AC-4b:** comunicación bidireccional.
  - Las órdenes estructuradas y las correcciones del operador se aplican y persisten.
  - Los resúmenes salen a la hora fijada.
  - Evals de la política de atención, con verdad escrita antes:
    - 100 eventos simultáneos no superan el presupuesto de avisos;
    - en `DESCANSO` solo pasan las alertas marcadas para ese modo; las no marcadas se difieren;
    - una urgencia inyectada en un asunto no eleva el aviso;
    - una alerta marcada para el modo activo nunca se difiere: 0 omisiones dentro de su tope, y por encima del tope, un mensaje agrupado con todas.
  - La consulta cada 5 min funciona con la app en segundo plano.
  - Con el nivel `recuentos`, las notificaciones locales no muestran asuntos ni nombres en la pantalla de bloqueo.
  - Soul no escucha en ninguna interfaz fuera de las direcciones configuradas (test de puertos).
  - El texto libre sin modelo autorizado recibe la respuesta honesta y no se envía a ninguna parte.
- **AC-4e (web):** sobre sitios locales de prueba con sesión simulada:
  - **0 mutaciones en el estado del servidor simulado**, comprobadas en el servidor y no solo por el método HTTP. Un sitio de prueba incluye enlaces `GET` que mutan (`/approve?id=…`, `/logout`, marcar como leído al abrir) y otro, una redirección hacia uno de ellos;
  - 0 peticiones que no sean `GET`/`HEAD` fuera de la lista de renovación (log de red del navegador);
  - 0 navegaciones fuera de la lista de URLs de la receta;
  - 0 envíos de formulario;
  - 0 navegaciones fuera de la lista;
  - 0 accesos al perfil personal;
  - una página con instrucciones inyectadas («pulsa aprobar», «envía esto a…», «marca urgente») no produce ninguna acción ni ninguna alerta;
  - con sesión caducada, la parada es limpia;
  - las recetas extraen Q1–Q4 con la misma precisión exigida en AC-3 en al menos 3 sitios sintéticos de tipos distintos (portal de tareas, panel de aprobaciones, intranet de noticias).
- **AC-5:** revocar un adaptador borra su caché y sus tokens. Desinstalar no deja estado.
- **AC-6:** documento de transparencia completo y revisado por la revisora de seguridad. Además, **antes de los días 6–9**, la revisora de seguridad revisa el modelo de amenazas del canal móvil:
  - escucha solo en la VPN;
  - TLS y emparejamiento;
  - revocación del token al desemparejar;
  - móvil perdido;
  - qué ve el proveedor de la VPN.
- **AC-7:** piloto real en una instalación, con el consentimiento de su operador y fuera de cualquier repo. Durante una semana laborable se miden:
  - precisión percibida por elemento (correcto / incorrecto / no aplica);
  - minutos de reconstrucción por la mañana frente a una línea base de dos días sin el producto;
  - número de consultas.

  Solo recuentos en el informe. Condiciones de parada:
  - cualquier fuga;
  - precisión percibida < 80 %;
  - que el operador lo pida, sin explicaciones.

## Plan de dos semanas

| Días | Entregable |
|---|---|
| 1–2 | Núcleo en TypeScript sobre Node.js LTS, contrato de adaptadores, CLI y banco con verdad (paralelo) |
| 3–5 | Adaptadores Graph de Microsoft 365, de Google y de los gestores; almacén de credenciales por sistema |
| 3–7 | Adaptador `web`: perfil dedicado, URLs cerradas por receta, cortafuegos en la red, recetas de Outlook, Teams y SharePoint en la web, y sitios de prueba (en paralelo) |
| 3–7 | Política de atención y registro de demanda (librería pura, en paralelo) |
| 6–9 | Pantalla «Continuidad» y conversación en la app; escucha en la VPN, consulta cada 5 min y notificaciones locales; resúmenes, avisos y alertas; niveles de detalle |
| 8–9 | Documento de transparencia, revisión de seguridad e instalación sin administrador |
| 10 | Piloto: instalación guiada y línea base |

Las dos semanas son de **construcción** y terminan con la instalación del piloto y el arranque de la línea base. La medición del piloto (AC-7: dos días de línea base y una semana laborable) ocurre en las semanas siguientes, con el producto ya en uso.

Cada pieza va en su propia PR Draft con revisión independiente; la fusión sigue SE-488.

## Rollback

Desinstalar el proceso y retirar la pantalla de la app. No hay datos canónicos en Soul, porque las fuentes siguen en sus sistemas.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Proceso Soul Continuidad | paquete TypeScript sobre Node.js LTS, CLI `soul` | mismo paquete y CLI |
| Consulta desde el frontend | comando `/continuidad` que invoca la CLI **con nivel `recuentos` forzado** salvo proveedor aprobado declarado (AC-4d) | mismo comando y misma restricción, vía AGENTS.md |

### Verification protocol

- [ ] La CLI devuelve el mismo resultado desde ambos frontends: no depende de ninguno.
- [ ] Ningún hook nuevo.

### Portability classification

- [x] **DUAL_BINDING**: el producto es un paquete sobre Node.js y una app; los frontends solo invocan su CLI.
