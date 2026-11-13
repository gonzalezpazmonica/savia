---
status: APPROVED
priority: P1
developer_type: agent-team
created: 2026-11-12
author: Savia
phase: D
risk: L4
human_surface: true
depends_on: [SE-493, SE-498, SE-507, SE-513, SE-514]
related_specs: [SE-362, SE-431, SE-433, SE-488, SE-490, SE-493, SE-498, SE-500, SE-507, SE-512, SE-513, SE-514, SE-517]
origin: "Análisis de arquitectura previo del antiguo «reconciliador» (TO-BE recomendado C y corte en slices). Escenas confirmadas por la operadora antes de escribir esta spec (SE-505)."
timeline:
  - from: "2026-11-12"
    learned: "2026-11-12"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "APPROVED"
    source: "operadora, pregunta interactiva; D3 y D7 a la opción prudente"
---

# SE-518 — Pulse: el latido de la planta de trabajo

Pulse es el bucle que mantiene viva la planta de trabajo de una instalación de Savia: mira los trabajos en marcha, las propuestas de cambio abiertas, las pruebas y la cuota, y lanza solo el siguiente paso que toca. Hoy existe como un script privado de una sola instalación, sin voz, sin freno y sin telemetría. Esta spec lo convierte en un componente público, determinista y por operador, que publica lo que pasa y deja que Soul hable.

## Lo que he entendido

### Escenas

Las diez escenas confirmadas (E1–E10) se agrupan en cinco momentos para cumplir el formato de la puerta de comprensión; el contenido de cada escena no cambia, salvo E3 y E8, que se ajustaron después de la primera confirmación y quedaron confirmadas de nuevo (ver «Confirmación»). Están en tercera persona y sin detalles de ninguna instalación concreta. Las horas son de ejemplo. «(P+S)» marca las escenas en las que intervienen Pulse y Soul.

1. **Saber qué pasó y qué pasa.**
   - **E1 (P+S). La mañana.** El operador abre el móvil a primera hora. Ve una sola tarjeta, de Soul, con lo que Pulse hizo desde la noche anterior, con como mucho tres asuntos: «Anoche terminaron 4 trabajos y 2 quedaron parados. Hay 3 propuestas de cambio que solo puedes revisar tú y 2 que pueden fusionarse en lote. Parado: el trabajo X, porque la cuota del modelo pesado se agotó de madrugada; vuelve a las 9:00.» Cada asunto lleva su porqué; al tocarlo ve el detalle. No pasa: una lista de veinte líneas, avisos sueltos por separado, ni nada que obligue a abrir un fichero.
   - **E2 (P+S). Un trabajo termina.** Un trabajo acaba a media tarde. En menos de dos minutos le llega una frase: «El trabajo del recorte de contexto terminó bien y abrió la propuesta N. No necesitas hacer nada hasta la revisión.» Si falló: «Falló porque lo interrumpieron (el equipo se durmió). Lo relancé una vez; sin coste para el límite de intentos.» Si pregunta por voz o texto «¿Está funcionando?»: «Sí. Última comprobación hace 40 segundos. Tres trabajos en marcha; el más antiguo lleva 25 minutos y dio señales hace 1 minuto. Nada espera tu respuesta.» No pasa: enterarse de que algo terminó porque preguntó él, ni que lo rutinario le interrumpa en modo concentración.
2. **Freno y volante.**
   - **E3 (P+S). El freno.** Desde el móvil, un gesto: «Para todo». En segundos: «Todo parado. 4 trabajos detenidos, ninguno perdido: puedes ver dónde se quedó cada uno. Nada nuevo arranca. Solo tú puedes reanudar.» Reanudar se hace desde el equipo, por la línea de órdenes local, o con la aprobación formal de siempre. Si al parar quedó algún efecto dudoso (no se sabe si llegó a ocurrir), se acepta cada uno por su identificador en esa misma vía. No pasa: que algo se dé por fallado al parar, que se borre trabajo, que un mensaje cualquiera levante el freno, ni que otro programa o agente lo levante.
   - **E4. El volante.** El operador dice: «Hoy solo el trabajo X; lo demás espera». Pulse contesta con lo que cambia antes de hacerlo: «Pasan a espera 3 trabajos; sigue 1. Las revisiones ya empezadas terminan. Mañana vuelve todo a su orden.» «No toques el repositorio Y hoy» se anota por repositorio. No pasa: que reordene sin decir qué cambia, ni que amplíe lo que puede hacer. Redirigir solo quita o aplaza, nunca da más permiso.
3. **Fallos que no son del trabajo y fusiones sin cascada.**
   - **E5. Se cae la red (o falla una prueba ajena).** Se va la conexión con el forge. Pulse no marca nada como fallado ni cambia nada. Si pasa de media hora lo dice una vez: «Sin conexión con el forge desde las 15:10. No he tocado nada. Sigo intentándolo cada 5 minutos.» Al volver continúa sin repetir ningún trabajo. Si fallan las pruebas, dice de quién es: «falla en tu propuesta» (se corrige solo, hasta tres veces), «falla en la rama principal, no es tuyo» (lo dice una vez y no gasta intentos) o «las pruebas llevan 40 minutos en cola» (lo relanza una vez; si no avanza, lo cuenta). No pasa: que una caída de red cuente como error de un trabajo, ni un aviso por cada pasada.
   - **E6. Se fusiona una propuesta y no hay cascada.** Se fusiona una propuesta. Pulse solo actualiza la que se va a fusionar hoy o la que de verdad choca. Las otras seis no se tocan y sus revisiones siguen valiendo si lo único que cambió es la rama principal y no lo que ellas modifican. Si una cabeza nueva no arranca sus pruebas en 15 minutos, lo detecta, lo relanza una vez y, si sigue sin arrancar, lo dice: «La propuesta N lleva 15 minutos sin pruebas; ya lo he intentado una vez.» No pasa: cuatro actualizaciones de siete ramas en una tarde, revisoras relanzadas por un cambio que no toca la propuesta, ni esperar horas sin avisar.
4. **Decisiones a su hora y un día en otra instalación.**
   - **E7 (P+S). Le pide una decisión, a su hora.** En plena concentración ve una tarjeta que agrupa dos preguntas sobre lo mismo: «¿Fusionas ahora la propuesta N o esperas la segunda revisión? Si no contestas: se queda en espera, no pasa nada malo. Si aplazas: pregunto a las 12:00. Vale hasta las 18:00.» De noche no suena nada: la pregunta espera y por la mañana dice qué quedó esperando y qué hizo mientras. Si la decisión es dar permiso de fusión, no basta con contestar la tarjeta: se firma con la aprobación formal de siempre. No pasa: que tome una opción por él si calla, que repita la pregunta en bucle, ni que un permiso se dé con un «ok» de chat.
   - **E8 (P+S). Un día de trabajo en la instalación de su organización.** El operador abre el equipo de su organización, primero en otra red y luego con la VPN. Soul le da el día. Pulse de esa instalación añade: «Anoche no corrió nada porque el equipo estaba dormido. Hoy puedo trabajar entre las 13:00 y las 15:00 si hay corriente y más del 40 % de batería.» El modo inicial lo elige el operador al instalar (observar, proponer o actuar); por defecto es observar: Pulse dice qué haría, sin lanzar nada, hasta que el operador le sube el permiso cuando confía. Usa solo el motor de inferencia que el operador o su organización permitan, los repositorios de esa instalación y su forge (GitHub o Azure DevOps). Al cerrar la tapa lo que corría se interrumpe sin contar como fallo y se reanuda al abrir. No pasa: que haga falta tocar nada de TI, pedir privilegios de administrador, depender de otra instalación, ni que un dato de esa instalación salga del equipo.
5. **El muro y la caída de la voz.**
   - **E9. El muro entre instalaciones.** Desde una instalación no se ve nada de la otra: ni trabajos, ni avisos, ni cuotas, ni control. Ninguna puede parar ni dirigir a la otra. Lo único que viaja es el código público de Savia. Si Pulse de una instalación encuentra una mejora general, propone un parche escrito sin nombres ni datos de su dominio; el operador lo lee y, si quiere, lo sube él. Una lección solo cruza si el operador la lee, la aprueba y su contrato lo permite. No pasa: un canal automático entre las dos, un resumen «compartido», ni que una instalación sepa qué proyectos hay en la otra.
   - **E10 (P+S). Se cae Soul.** Soul se para. Pulse lo nota (sin señal de Soul) y pasa a un canal mínimo: una notificación del sistema operativo y una orden para ver lo pendiente, ambas con «aviso por canal de respaldo». Cuando Soul vuelve ve que ya se avisó y no lo repite. Si es Pulse el que no da señales, Soul lo dice: «Pulse no da señales desde las 14:30.» No pasa: quedarse sin enterarse, recibir lo mismo dos veces por sitios distintos, ni que uno necesite al otro para funcionar.

### Palabras de la persona

> «Servicio del sistema, con una sesión por operador, con configuración por operador y colas por operador, conectado a Savia y a la inferencia de cada operador en su propia máquina.» — 2026-11-11, al encargar el análisis de arquitectura.

### Qué SÍ será

- Un núcleo público y determinista, sin modelo en el camino crítico, que corre como servicio **de usuario** de cada operador (macOS con launchd, Linux con systemd --user) y deriva el estado en cada pasada.
- Una planta muda: Pulse publica peticiones, eventos y latido; Soul es la única voz. Sin Soul, un canal de respaldo mínimo.
- Un freno que nada pierde y que solo la persona levanta (por CLI local o aprobación formal), y un volante que solo resta.
- Errores con clase, dueño y política; telemetría desde un ledger de eventos, local a la instalación.
- Instalaciones soberanas: configuración, colas, estado y credenciales por operador y por instalación, sin canal entre ellas.

### Qué NO será

- No fusiona, no concede grants, no aprueba, no saca de borrador y no fuerza push. Nunca.
- No es un servicio del sistema ni pide administrador; no escucha en la red.
- No lee correo, calendario ni chats de la persona; no decide cómo agrupar avisos (eso es de Soul).
- No sincroniza nada entre instalaciones ni informa a una «central».
- No es un marco de orquestación general: el catálogo de estaciones y la composición de la factoría quedan fuera.

### Confirmación

- fecha: 2026-11-12
- respuesta: «E1–E10 tal cual, sin cambios». Registro de la orquestadora de la respuesta de la operadora a las diez escenas, presentadas una a una para sí, no o cambiar. La redacción en tercera persona y sin datos de instalación es posterior a la confirmación y no cambia el contenido; la revisión humana de la PR comprueba que es así.
- **E3 y E8, confirmadas.** Tras la primera confirmación, E3 y E8 se ajustaron a las decisiones D7 y D3. En la revisión del 2026-11-13 la operadora llevó D3 y D7 a la opción prudente y la redacción actual de ambas escenas (E3 sin vía de chat, E8 con «observar» por defecto) queda confirmada.

## Slice S0 — Prototipo navegable

- prototipo: `docs/specs/assets/SE-518-prototipo.html` (por construir en S0) — la tarjeta de la mañana (E1), la frase de fin de trabajo y la respuesta a «¿está funcionando?» (E2), la confirmación del freno (E3) y del volante (E4), el aviso de red (E5), la tarjeta de decisión (E7), la tarjeta de la instalación con el modo inicial elegido (E8) y el aviso de respaldo (E10), sobre datos de ejemplo, usable en el móvil. Incluye la salida de `pulse status` en texto.
- Además, S0 entrega tres medidas que deciden si el corte C sigue en pie: (a) sonda en una instalación macOS sin administrador: intérprete disponible (Python ≥ 3.9 o el runtime de Soul), LaunchAgent sin `sudo`, bloqueo de fichero sin `flock`; (b) qué modos permite la política de la organización, para informar la elección del operador (no cambia el defecto); (c) qué parte de la lógica del bucle actual es reutilizable como casos dorados del planificador.

### Confirmación del prototipo

- fecha: pendiente
- respuesta: pendiente. S1 no se pone en curso sin ella (SE-505).

## Problema

El bucle actual funciona en lo esencial: una pasada de nivel cada 10 minutos, idempotente y tolerante a pasadas perdidas, con reglas deterministas y varios fallos cerrados (memoria ilegible, tier ilegible, listado del forge fallido). Pero ocho clases de fallo se repiten y no tienen arreglo dentro de su forma actual:

| Clase de fallo | Qué pasa | Eje |
|---|---|---|
| F1. Señal de control inferida de texto libre | La cuota se deduce con una expresión regular sobre el final de un log ajeno y vale para todos los proveedores: el texto de un proveedor bloquea a otro, o una cita bloquea horas | Errores, control |
| F2. Integración en cascada | Tres actores integran la rama principal en las ramas de las propuestas (un workflow del repo, el propio bucle y la fusión en serie) sin conocerse; cada cabeza nueva invalida revisiones atadas al SHA y relanza dos revisoras por propuesta aunque el cambio no toque sus ficheros | Efectos, coste |
| F3. Reabrir no revalida | `pr-guardian.yml` no escucha `reopened`; el remedio vive en la memoria de una persona, no en código | Efectos |
| F4. Fin de trabajo mudo | Un trabajo termina o muere y nadie lo dice; la única voz es un fichero que se sobrescribe y que solo lee una sesión de chat si existe | Feedback |
| F5. Intención confundida con intento | La deduplicación usa el hash del texto de la petición: un intento muerto queda como «hecho» y dos textos de la misma intención lanzan dos veces | Idempotencia |
| F6. Alcance sin comprobar | Un worker modifica por shell un fichero fuera de su alcance (el núcleo de una guarda) y nadie lo ve hasta una auditoría posterior | Seguridad |
| F7. Vida deducida por nombre | Que un proceso vive se deduce buscando su nombre en la tabla de procesos o por un arranque reciente sin fin, sin concesión con vencimiento | Observabilidad |
| F8. Pruebas en cola sin tope | «Pendiente» se trata como «esperar», sin límite; horas sin que nada corra | Errores |

Además: no hay freno ni volante (un quinto STOP repetiría el problema que describe SE-498), el log mezcla depuración y telemetría (la gran mayoría de líneas repiten el estado), no se mide coste real ni espera de la persona, y el código no es portable (bash 4, `flock`, utilidades GNU, `/proc`) ni multioperador (rutas, organización y modelos cableados).

## Arquitectura (TO-BE C: estrangulamiento con contratos primero)

La pasada de nivel **se conserva**. Se divide en cuatro piezas, entregadas en el orden de los slices:

1. **Observadores** (adaptadores): forge (GitHub, Azure DevOps), procesos lanzados (por concesión, no por nombre), proveedores de inferencia (cuota tipada), recursos (memoria, batería, corriente). Cada observación lleva `at`, `valid_until` y `source`; una observación vencida es «no sé», nunca «está bien».
2. **Planificador puro** `plan(deseado, observado, config) → acciones`, sin entrada/salida, en Python estándar ≥ 3.9 sin dependencias (D2). El estado deseado por propuesta: revisada en su contenido, pruebas verdes en su cabeza, registrada para la fusión en serie, dentro de WIP y presupuesto. Los fallos de la tabla anterior son sus casos dorados.
3. **Ejecutor** sobre el Effect Ledger de SE-493 (`prepared → dispatched → succeeded | failed | ambiguous`), con clave de idempotencia por **intención** (de SE-513) y número de **intento**. Un lanzamiento con proceso quizá vivo es un efecto `ambiguous`, no un «hecho».
4. **Publicador**: eventos, peticiones y latido (contratos de abajo). Pulse no notifica salvo en canal de respaldo.

Dos relojes: un **tic de control** de unos 60 s que solo lee el estado de control y el latido de Soul (milisegundos), y la **pasada completa** cada 10 minutos o al terminar un trabajo. Una pasada perdida (equipo dormido) no hace daño porque la pasada es de nivel.

Efectos permitidos, cerrados: lanzar workers y revisoras dentro de presupuesto; integrar la rama principal en una propuesta según la política de integración; relanzar pruebas una vez por cabeza; registrar evidencia de revisión para la fusión en serie de SE-433/SE-500; cambiar la base de una propuesta apilada cuya base ya se fusionó. Ningún otro.

## Contratos Pulse ↔ Soul

Todos viven bajo la raíz de datos del usuario (`<datos de usuario>/savia/pulse`, junto a `<datos de usuario>/savia/soul-continuity` de SE-490), con permisos solo del usuario. Un único escritor por fichero. Pulse no tiene API de red: el móvil habla con Soul y Soul lee a Pulse por ficheros locales.

| Contrato | Escribe | Lee | Forma |
|---|---|---|---|
| Peticiones a la persona | Pulse | Soul | `peticiones.json`: instantánea de nivel, sustituida de forma atómica; cada elemento con `id` estable, las cinco cosas de SE-514 (qué, por qué ahora, si no contestas, si aplazas, caduca) y `fuente`, `nivel`, `critica`, `desde` |
| Eventos de planta | Pulse | Soul, `pulse status`, métricas | `eventos.jsonl`, solo añadir, un evento por línea con `id`, `tipo`, `at`, `clase`, `entrega` |
| Latido de Pulse | Pulse | Soul | `latido.json` con `at`, `valid_until`, pasada, fuentes vencidas |
| Presencia de Soul | Soul | Pulse | `presencia.json` con `valid_until` |
| Acuses de entrega | Soul | Pulse | `acuses.jsonl`: `id` entregado, por qué canal, cuándo |
| Control | La persona (CLI local o dispositivo emparejado vía Soul) | Pulse | Plano de control de SE-498 (época, `stop_seq`, ámbitos); Pulse es un ejecutor registrado, no un STOP nuevo. Cada orden lleva `origen.canal` ∈ {`cli_local`, `aprobacion_formal`, `soul_dispositivo`} y `origen.identidad_verificada` (booleano que pone Soul solo tras verificar la identidad de la persona); un canal fuera de la lista, o el campo ausente, es orden no autenticada |
| Intenciones nuevas | La persona vía Soul | Pulse | Admisión duradera de SE-513 |

Reglas comunes: los ficheros que lee Pulse deben pertenecer al usuario del servicio y no ser escribibles por grupo ni por otros; si no, cuentan como `FALLIDA`. Un `valid_until` de `presencia.json` más allá de un máximo configurable (por defecto 10 minutos desde `at`) se trata como vencido, para que una presencia falsa con vencimiento lejano no silencie el respaldo. `schema_version` en cada fichero; dentro de una versión mayor solo se añaden campos y el lector ignora lo desconocido. Fichero ausente = `SIN_CONECTAR`; corrupto = `FALLIDA`; **nunca vacío** (semántica de `EstadoFuente` de Soul). Pulse es el productor de tres fuentes de la cola única de SE-514: `PR_REVISION`, `AVISO_RUN` y `PENDIENTE_MANANA`.

**Una sola voz.** Cada `id` tiene un único propietario de entrega. Con Soul presente, Pulse no emite nada. Con la presencia de Soul vencida, Pulse entrega por respaldo (notificación del SO y `pulse inbox`), marca `entrega=respaldo` en el evento, y Soul, al volver, ve el `id` ya acusado y no lo repite. La fuente de verdad del acuse es Soul en modo normal y el evento de respaldo en modo degradado.

**Órdenes de Soul a Pulse: solo restan, sin excepción.** Pausar todo, un repositorio o un proveedor; aplazar; bajar WIP o presupuesto; `steer` de un trabajo. Subir el techo de autonomía o el presupuesto, dar un permiso de fusión o **reanudar tras un freno** no se aceptan desde Soul: reanudar es solo de la CLI local de la persona o de la aprobación formal (SE-488, SE-498), donde se aceptan también, uno a uno por su identificador, los efectos `INDETERMINATE` (SE-498 R6.2). Ningún agente ni proceso reanuda. Una orden de origen no autenticado, o de un canal fuera de la lista, se descarta (fail-closed).

**Lo que ninguno hace.** Soul no lanza, no mata ni reordena trabajos. Pulse no lee fuentes personales para decidir cuándo molestar. No hay base de datos compartida ni candado compartido. Los modos de foco y descanso no retrasan un freno ni silencian una petición marcada `critica` (campo estructurado, nunca deducido de texto).

## Modelo de despliegue

| Elemento | Decisión |
|---|---|
| Servicio | **Servicio de usuario**, no del sistema: `systemd --user` (con `enable-linger` si debe sobrevivir al cierre de sesión) en Linux, LaunchAgent en macOS, tarea de inicio de sesión en Windows. `pulse install` genera la unidad sin `sudo`. La intención de «siempre vivo y aislado» se cumple sin privilegios ni TI |
| Una instancia por operador | Una por **usuario del SO**. Varios operadores en una máquina = varios usuarios, cada uno con su instancia y su llavero. Nunca varios operadores dentro de un proceso |
| Configuración | Fichero del usuario validado por esquema, con valores por defecto conservadores, también el modo inicial (D3): identidad de la instalación y nivel de clasificación, forges y repos (credencial por referencia al llavero o al CLI del forge, nunca el secreto), proveedores y tiers, presupuestos y reinicios de cuota, suelo reservado a uso interactivo, ventanas sin lanzar y sin preguntar, modo inicial (techo de autonomía; por defecto `observar`; en una instalación no interactiva, sin nadie a quien preguntar, se aplica ese defecto y `pulse install` lo dice en su salida), WIP por repo, recursos (memoria, batería, corriente, red medida), política de integración, canal de avisos |
| Colas y estado | Privados por operador en su directorio de datos; nada del código público los conoce |
| Núcleo | Determinista, sin modelo en el camino crítico; los modelos solo dentro de los workers y revisoras que lanza |
| Inferencia | La de cada operador: el motor que el operador o su organización permitan (SE-517: motor opcional por persona), como adaptador con su propia credencial; «ninguno» es válido y equivale a modo `observar`, aunque el operador haya elegido `actuar`; `pulse status` muestra el modo configurado y el modo efectivo, y su motivo, cuando difieren |
| Credenciales | Pulse no guarda secretos: llavero del SO y la credencial del propio CLI del forge (Rule 1) |
| Código | Público, como proyecto propio del repo junto a Soul (D1); estado y configuración siempre privados |

## Instalaciones soberanas sin canal entre ellas

Un operador puede tener varias instalaciones soberanas (por ejemplo, una personal y otra en un equipo de su organización), sin canal entre ellas. Cada una es dueña de su dominio; ninguna controla ni observa a otra.

| Capa | Qué garantiza |
|---|---|
| Separación física y de identidad | Máquinas, usuarios del SO, credenciales y llaveros distintos. Es la barrera real |
| Sin red entre instalaciones | Pulse no tiene listener ni cliente hacia otra instalación: «controlar una desde otra» no existe como capacidad |
| Clasificación | Cada evento lleva `nivel`; dato sin nivel = N4 (fail-closed, como `nivelDeContrato` de Soul). La instalación de una organización trata su estado al nivel que fije la organización |
| Salidas permitidas | El núcleo solo habla con los hosts del forge y del proveedor configurados; otro destino es error, no aviso |
| Guarda local de términos | Lista privada de términos propios de cada instalación, comprobada antes de cualquier push al repo público; vive solo en esa instalación |
| Telemetría local | Las métricas no salen de la instalación |
| Lo único que cruza | El código público, por PR pública con el análisis de confidencialidad del repo. Lecciones: nada por defecto; `pulse export-lessons` escribe un fichero que el operador lee y mueve él si su contrato lo permite |

## Errores y clasificación

Cada fallo observado recibe una clase; la clase decide si cuenta intento, si se avisa y quién es el dueño.

| Clase | Ejemplo | Política | ¿Cuenta ronda? | Aviso |
|---|---|---|---|---|
| `transitoria` | Red caída, forge no responde | Reintento con espera creciente; **no cambia estado** | No | Una vez si dura > 30 min |
| `cuota` | Límite del proveedor | Señal tipada por proveedor, con vencimiento, escrita por el lanzador desde el código de salida o la respuesta del proveedor, nunca leída de texto libre; sonda al vencer | No | En la tarjeta de la mañana o si bloquea algo crítico |
| `ci_ajena` | Lo que falla también falla en la rama principal | Se registra y espera | No | Una vez por cabeza |
| `ci_atascada` | Cabeza sin pruebas arrancadas, o pruebas en cola (F8), durante 15 min (D12, configurable) | Relanza una vez (efecto con ledger) | No | Si el relanzamiento no arranca (los «40 minutos» de E5 son un ejemplo de ese aviso tras relanzar) |
| `logica` | HOLD de revisora, prueba propia roja | Corrección, máximo 3 rondas, luego cuarentena | Sí | Al entrar en cuarentena |
| `entorno` | Interrumpido por suspensión o señal (`143/137`) | «Interrumpido, relanzar gratis» una vez | No | Sin aviso propio la primera vez: la frase de fin de trabajo de E2 lo menciona. Aviso propio solo si se repite |
| `politica` | Guarda bloqueada, fichero fuera del alcance declarado | Cuarentena inmediata con motivo; nada se relanza | — | Siempre, `critica` |
| `desconocida` | Salida no clasificable | Cuarentena con motivo «sin clasificar»; fail-closed | — | Siempre |

La cuarentena tiene motivo, dueño y salida explícita (cabeza nueva, decisión de la persona o vencimiento de la causa), no solo «llegó otra cabeza».

**Alcance comprobado después (F6).** Al terminar un worker, Pulse compara los ficheros tocados con el alcance declarado de la tarea; un fichero fuera de alcance en rutas de guardas, hooks o control es clase `politica`.

## Política de integración (F2, F3)

- `solo_conflicto` por defecto: Pulse integra la rama principal en una propuesta solo si choca o si es la siguiente en fusionarse.
- **Validez por huella de contenido** para decidir si relanzar revisoras: si la diferencia de la propuesta respecto a su base no cambió, no se relanzan. El cálculo es fail-closed: ante cualquier error (base ilegible, diff que falla, huella anterior ausente) se relanzan. La regla de la puerta de fusión (atada al SHA) no cambia aquí; si se cambia, va por enmienda de SE-500.
- Dos cambios públicos fuera del núcleo, cada uno en su PR de tier 4: el workflow de auto-rebase deja de integrar propuestas limpias (o se retira), y `pr-guardian.yml` añade `reopened`.

## Telemetría

La telemetría de la planta (la «factoría») va dentro de Pulse; no es un proyecto aparte. Es genérica y por operador: no presupone ni forge, ni proveedor, ni organización concretos.

- **Ledger de eventos** de solo añadir como fuente; el log de depuración queda aparte. Un evento por cambio, no por pasada.
- Por trabajo: causa del código de salida, clase de error, y momento en que la persona vio cada cosa (desde los acuses de Soul).

### Datos nuevos que hoy no se registran

Cada uno es un evento del ledger con campos mínimos obligatorios. Un evento sin su campo de motivo es inválido (fail-closed): se rechaza y se registra como `telemetria_incompleta`, nunca se rellena con un valor por defecto.

| Dato | Evento | Campos mínimos | Motivo: valores cerrados |
|---|---|---|---|
| Motivo de cada rechazo de revisión (HOLD) | `review_hold` | propuesta, cabeza (SHA), revisora, ronda, `motivo`, `familia`, `nivel`, `verificado`, `origen`, `detalle` | `falta_caso_negativo`, `gate_no_fail_closed`, `contradice_spec`, `prueba_roja`, `confidencialidad`, `alcance`, `otro` (exige `detalle`) |
| Motivo de cada cierre sin fusionar | `pr_closed_unmerged` | propuesta, quién cierra (persona o Pulse), `motivo`, `detalle` | `reemplazada`, `descartada_por_persona`, `obsoleta`, `cuarentena_vencida`, `duplicada`, `otro` (exige `detalle`) |
| Error de cuota de cada trabajo | `quota_error` | trabajo, proveedor (id de adaptador), `senal_tipada`, vencimiento, ronda no consumida | Solo señal tipada del lanzador (código de salida o respuesta del proveedor); nunca texto libre |
| Momento en que la persona abre una revisión que espera de ella | `review_opened_by_operator` | propuesta, cabeza, `solicitada_en`, `abierta_en`, canal | — |

#### Estructura del HOLD y veredictos consultivos

Un HOLD no se queda en «motivo»: lleva además un diagnóstico estructurado, y los hallazgos que no deben bloquear se registran aparte, con seguimiento. Las tres piezas salen del estudio de un motor externo de revisión de código (fuente privada; no se cita aquí).

- **Familia del fallo** (`familia`, cerrada): `estado_aprobaciones`, `privacidad`, `prueba_no_falla` (test que no puede fallar), `logica`, `seguridad`, `alcance`, `otro` (exige `detalle`). Es la clase del defecto; `motivo` sigue siendo la causa concreta del conjunto de arriba.
- **Nivel** (`nivel`, cerrado): `P0`, `P1`, `P2`, los mismos que la primera línea del veredicto de SE-433.
- **Verificado** (`verificado`: `si` o `no`): `si` solo si la revisora reprodujo el defecto (ejecución, prueba roja o traza concreta que se cita en el cuerpo). `no` es una sospecha razonada. Un HOLD sin `verificado` es inválido.
- **Origen** (`origen`: `introducido` o `preexistente`): si el defecto ya está en la base de la propuesta (SHA de base) o lo introduce la propuesta. El preexistente es **consultivo**: no bloquea. La revisora cita el SHA de base donde lo reprodujo; sin esa cita el hallazgo cuenta como `introducido`.
- **Veredicto «real pero latente»**: un defecto cierto, reproducido, en código que hoy no usa nadie (sin llamador ni ruta que lo alcance en la propuesta) es consultivo: no bloquea y no consume ronda. Se registra como `review_advisory` con `clase` (`latente` o `preexistente`), propuesta, cabeza, revisora, `familia`, `nivel`, `verificado=si`, `detalle` y `seguimiento` (referencia a la tarea o spec que lo recoge). Un `review_advisory` sin `seguimiento` es inválido (fail-closed): se rechaza y se registra `telemetria_incompleta`, y el hallazgo vuelve a contar como bloqueante.
- **Límites del consultivo** (para que no sea una salida fácil): nunca aplica si la propuesta añade un llamador o ruta que active el código latente o preexistente (entonces es `introducido` y activo); nunca degrada un hallazgo de `privacidad` o de `seguridad` con nivel `P0`; y en tier 3/4 la revisión humana del PR concreto (SE-362) ve los consultivos listados antes de decidir. Ningún consultivo cuenta como `p0`, `p1` ni `p2_blocking` en el veredicto.

**Impacto en el contrato de las revisoras.** Esto cambia la primera línea `VERDICT:` y el cuerpo de la revisión que fija SE-433 (`autonomous-safety-merge-sprint.md`, sección Revisión): en un HOLD la primera línea añade `familia=`, `nivel=` y `verificado=`; cada hallazgo del cuerpo declara `origen=` y, si es consultivo, `clase=` y `seguimiento=`; y el cómputo de `p0`, `p1` y `p2_blocking` excluye los consultivos. Cualquier línea que no cumpla la forma sigue equivaliendo a HOLD. Como toca la puerta de revisión que decide qué llega al grant de fusión (SE-433, SE-362), **el slice que cambie ese contrato es de riesgo alto (tier 4)**: lo revisa explícitamente una persona y no entra por fusión en serie sin ese paso. Esta spec solo lo especifica; el cambio del contrato es el slice S5c.

`review_opened_by_operator` viene de los acuses de Soul o de la lectura del forge; si ninguna fuente lo da, el evento no se inventa y la espera queda como «sin dato», nunca como 0.

Las métricas usan además eventos que el ledger ya emite desde S1, todos con `at`: `pr_created` y `pr_merged` (propuesta), `job_started` y `job_finished` (trabajo, propuesta, id de modelo del adaptador).

### Métricas de planta

Derivadas solo del ledger, recalculables desde cero. Ninguna sale de la instalación.

| Familia | Métrica | Definición |
|---|---|---|
| Rendimiento | Propuestas fusionadas por día | Eventos `pr_merged` agrupados por día local del operador |
| Rendimiento | Tiempo de creación a fusión | `pr_merged.at` menos `pr_created.at`, con mediana y p90 |
| Retrabajo | Rondas de revisión por propuesta | Número de `review_hold` por propuesta (cada HOLD abre una ronda de corrección; no se suman aparte) |
| Retrabajo | HOLD por familia, nivel y verificado | Eventos `review_hold` agrupados por `familia`, `nivel` y `verificado`; los `verificado=no` se muestran aparte |
| Retrabajo | Consultivos abiertos | `review_advisory` sin cierre de su `seguimiento`, por `clase` y edad; los preexistentes y los latentes no se suman a las rondas |
| Retrabajo | Arreglos | Commits de corrección posteriores a un HOLD, por propuesta y por motivo |
| Coste | Horas de trabajador por modelo | Suma de (`job_finished.at` − `job_started.at`) de los trabajos, por identificador de modelo del adaptador |
| Coste | Horas de trabajador por propuesta | Idem, por propuesta; tokens solo cuando el proveedor los dé en la salida del worker |
| Espera del operador | Espera por revisión | `abierta_en` − `solicitada_en`, por tier, con mediana y p90 |
| Espera del operador | Peticiones sin abrir | Revisiones solicitadas sin `review_opened_by_operator` y su edad |

Además: avisos e interrupciones por día.

- `pulse status`: última pasada y su duración, fuentes vencidas, cola, trabajos con edad de su último latido (SE-507), bloqueos y por qué, estado del freno.
- Todo local; nada se reporta fuera de la instalación.

## Control: freno y volante

- **Freno**: Pulse es un ejecutor del plano de control de SE-498. Una orden `pause` se ve en el siguiente tic (≤ 60 s): nada nuevo arranca y los procesos que Pulse lanzó (conocidos por su concesión, no por nombre) se detienen y quedan `interrumpido` con su punto de parada. Nada se marca fallado ni se borra. Acusa la orden en el diario de SE-498.
- **Reanudar**: solo la persona, por CLI local, por la aprobación formal de SE-488/SE-498. Ningún agente ni proceso reanuda. Pulse revalida contra la época antes de lanzar nada.
- **Volante**: órdenes que restan (solo X, aplazar Y, no tocar el repositorio Z hoy, bajar WIP o presupuesto, `steer` a un trabajo en marcha). Antes de aplicarlas, Pulse publica qué cambia y cuándo caduca la orden; ninguna amplía permisos.

## Seguridad y tier

| Pieza | Tier previsto | Motivo |
|---|---|---|
| Observar, publicar, `pulse status`, respaldo | 2 | Solo lectura y avisos |
| Lanzar workers, integrar, relanzar pruebas | 3 | Efectos en ramas `agent/*` y en el forge |
| Registro de evidencia para la fusión en serie, control (freno, reanudar, techo) | 4 | Decide qué evidencia llega al grant y quién para la planta |
| Cambios en workflows del repo | 4 | Afectan a todas las propuestas |
| Cambio del contrato de las revisoras (S5c) | 4 | Toca la puerta de revisión de SE-433; revisión humana del PR concreto (SE-362) |

**Techo de autonomía** por instalación: `observar` (no lanza; dice qué haría), `proponer` (lanza solo lo que la persona aprueba) o `actuar` (autonomía plena). El modo inicial lo elige cada operador al instalar; por defecto es `observar` (D3), y cada uno lo sube a `actuar` (autonomía plena) cuando confía. Subirlo después es un acto de la persona (SE-488); bajarlo, una orden que resta.

Otros: identidad propia para los pushes de Pulse cuando el forge lo permita, distinta de la de la persona (si no, queda anotado en cada evento); los workers no heredan el entorno completo; el núcleo nunca fusiona, aprueba, concede grants, saca de borrador ni fuerza push, y hay tests negativos para cada una de esas cinco cosas.

## Criterios de aceptación

| AC | Escena | Criterio | Slice |
|---|---|---|---|
| AC-1 | E1 | Desde el ledger de una noche de ejemplo, Soul compone una tarjeta con ≤ 3 asuntos, cada uno con su porqué y su detalle. **Negativo:** con 20 eventos, ninguna lista de 20 líneas ni avisos sueltos | S1 |
| AC-2 | E2 | Un trabajo que termina genera el evento de fin y la petición en ≤ 2 min en la prueba de integración. **Negativo:** en modo concentración, un fin rutinario no interrumpe | S1 |
| AC-3 | E2 | `pulse status` responde con datos de < 60 s de edad; con el latido vencido dice «sin señales», nunca «todo bien» | S1 |
| AC-4 | E2, E5 | Un trabajo interrumpido (`143/137`) se relanza una vez y no suma ronda. **Negativo:** el segundo `143` del mismo intento no se relanza solo | S3 |
| AC-5 | E3 | `pause` detiene en ≤ 60 s todo proceso lanzado por Pulse y deja cada trabajo `interrumpido` con su punto de parada. **Negativo:** ningún trabajo pasa a `failed` ni se borra nada | S4 |
| AC-6 | E3 | **Negativo:** reanudar desde otro agente o desde un proceso que no es la persona se rechaza siempre; un «reanuda» recibido por el chat de Soul no reanuda nunca. Tras reanudar, Pulse revalida la época antes de lanzar | S4 |
| AC-6b | E3 | Una orden de reanudar con `origen.canal` fuera de {`cli_local`, `aprobacion_formal`}, o con el campo ausente o inválido, no reanuda (fail-closed). **Negativo:** el texto «reanuda» por el chat de Soul no levanta el freno. **Negativo:** con un efecto `INDETERMINATE` pendiente, reanudar exige aceptarlo por su identificador en la CLI local o la aprobación formal. Cada reanudación queda acusada con su canal en el diario de SE-498 | S4 |
| AC-7 | E4 | Una orden de volante publica qué cambia antes de aplicarse y caduca a la hora indicada. **Negativo:** una orden que amplía permisos o presupuesto se rechaza | S4 |
| AC-8 | E5 | Con el forge caído 45 min en la simulación: ningún cambio de estado, un único aviso pasados 30 min, cero trabajos repetidos al volver | S3 |
| AC-9 | E5 | Las tres clases de prueba roja (propia, de la rama principal, en cola) producen las tres políticas de la tabla. **Negativo:** `ci_ajena` no gasta ronda | S3 |
| AC-10 | E6 | Tras una fusión, solo se integra la propuesta siguiente o la que choca. **Negativo:** con la huella de contenido igual, no se relanza ninguna revisora. **Negativo:** si el cálculo de la huella falla, se relanzan (fail-closed) | S2 |
| AC-11 | E6 | Cabeza sin pruebas en 15 min → un relanzamiento registrado en el ledger y, si no arranca, una petición. **Negativo:** no hay segundo relanzamiento automático | S2 |
| AC-12 | E7 | Cada petición lleva las cinco cosas de SE-514; sin respuesta queda en espera y no se repregunta más de una vez por ventana. **Negativo:** un permiso de fusión contestado en la tarjeta no se registra como grant | S1, S4 |
| AC-13 | E8 | `pulse install` en macOS y Linux sin `sudo` deja el servicio de usuario activo y permite elegir el modo inicial; sin elección (también en instalación no interactiva), queda en `observar` y la salida lo dice. **Negativo:** en `observar`, no se produce ningún efecto del ejecutor; solo con `actuar` elegido por el operador hay efectos. **Negativo:** con inferencia «ninguno» y `actuar` elegido, no hay efectos del ejecutor y `pulse status` muestra modo configurado `actuar` y efectivo `observar` con su motivo | S7 |
| AC-14 | E8 | Con batería por debajo del umbral o sin corriente (si se configura), no se lanza nada y se publica la próxima ventana | S7 |
| AC-15 | E8 | **Negativo:** un destino de red fuera de la lista de salidas de la instalación falla como error, no como aviso | S7 |
| AC-16 | E9 | **Negativo:** el código no contiene cliente ni listener hacia otra instalación (prueba estática); `export-lessons` solo escribe un fichero local y nunca lo envía | S7 |
| AC-17 | E10 | Con la presencia de Soul vencida, la petición sale por respaldo marcada «aviso por canal de respaldo»; al volver Soul no se repite. **Negativo:** con Soul presente, Pulse no emite ninguna notificación. **Negativo:** un `presencia.json` con `valid_until` más allá del máximo, o escribible por otros, cuenta como vencido y el respaldo avisa | S1 |
| AC-18 | E10 | Con el latido de Pulse vencido, Soul publica «Pulse no da señales desde …». **Negativo:** Pulse funciona sin Soul y Soul sin Pulse en las pruebas de contrato | S1 |
| AC-19 | Todas | **Negativo:** ningún camino del núcleo fusiona, aprueba, concede grants, saca de borrador ni fuerza push (un test por acción) | S6 |
| AC-20 | Todas | El planificador en sombra coincide con las decisiones del bucle actual durante el periodo de sombra; cada discrepancia queda explicada antes del corte | S6 |
| AC-21 | Todas | Prueba con una persona no técnica: entiende cada tarjeta y la salida de `pulse status` sin ayuda | S0, S1 |
| AC-22 | Todas | Un HOLD de revisora genera `review_hold` con motivo del conjunto cerrado y ronda. **Negativo:** un HOLD sin motivo, o con `otro` sin `detalle`, se rechaza y se registra `telemetria_incompleta`; no se escribe un motivo por defecto | S5 |
| AC-23 | Todas | Cada propuesta cerrada sin fusionar genera `pr_closed_unmerged` con motivo y quién cierra. **Negativo:** una propuesta fusionada no genera ese evento; un cierre sin motivo se rechaza | S5 |
| AC-24 | E5 | Un trabajo que falla por cuota genera `quota_error` con señal tipada y vencimiento, sin consumir ronda. **Negativo:** un texto libre que menciona «quota» en la salida del worker no genera el evento | S3, S5 |
| AC-25 | E7 | Una revisión solicitada a la persona y abierta por ella genera `review_opened_by_operator` con ambos instantes y la espera calculada. **Negativo:** sin acuse ni lectura del forge no hay evento y la métrica muestra «sin dato», no 0 | S5 |
| AC-26 | Todas | Desde un ledger de ejemplo con cifras conocidas, las métricas de rendimiento, retrabajo, coste y espera coinciden con el valor esperado, y se recalculan idénticas desde cero. **Negativo:** con el ledger vacío ninguna métrica devuelve cero inventado, sino «sin datos» | S5 |
| AC-27 | Todas | **Negativo:** el ledger y las métricas no contienen identificadores de persona, organización ni rutas de la instalación en lo que exporta `pulse status`, y una prueba estática confirma que no hay destino de red para telemetría | S5, S7 |
| AC-28 | Todas | Un HOLD genera `review_hold` con `familia` del conjunto cerrado, `nivel` (P0/P1/P2) y `verificado` (si/no). **Negativo:** un HOLD sin alguno de los tres, o con `familia=otro` sin `detalle`, se rechaza y se registra `telemetria_incompleta`; no se escribe un valor por defecto. **Límite:** `verificado=si` sin traza o prueba citada en el cuerpo se rechaza | S5 |
| AC-29 | Todas | Un defecto reproducido en código sin llamador ni ruta que lo alcance genera `review_advisory` con `clase=latente` y `seguimiento`, no cuenta en `p0`, `p1` ni `p2_blocking` y no consume ronda. **Negativo:** el mismo defecto con un llamador añadido por la propuesta es `introducido` y bloquea. **Negativo:** un consultivo sin `seguimiento` se rechaza y el hallazgo vuelve a bloquear. **Negativo:** un hallazgo de `privacidad` o `seguridad` con nivel P0 nunca se degrada a consultivo | S5, S5c |
| AC-30 | Todas | Un defecto presente en el SHA de base y no introducido por la propuesta genera `review_advisory` con `clase=preexistente`, con el SHA de base citado, y no bloquea. **Negativo:** sin SHA de base citado, o con la propuesta modificando la línea afectada o ampliando su alcance, el hallazgo cuenta como `introducido` y bloquea. **Negativo:** si no se puede calcular la base, cuenta como `introducido` (fail-closed) | S5, S5c |
| AC-31 | Todas | La métrica de HOLD por familia, nivel y verificado y la de consultivos abiertos se recalculan idénticas desde el ledger. **Negativo:** con el ledger vacío dan «sin datos»; un consultivo cuyo `seguimiento` sigue abierto no desaparece de la métrica | S5 |
| AC-32 | Todas | El contrato de revisora (primera línea `VERDICT:` y cuerpo) con `familia=`, `nivel=`, `verificado=`, `origen=`, `clase=` y `seguimiento=` tiene esquema y validador, y el cómputo de `p0/p1/p2_blocking` excluye los consultivos. **Negativo:** una primera línea sin la forma exigida, o con un campo fuera del conjunto cerrado, equivale a HOLD. **Negativo:** el cambio del contrato no se fusiona sin la revisión humana del PR concreto (tier 4, SE-362) | S5c |

## Slices

| Slice | Entrega | Encaja en | Tier previsto |
|---|---|---|---|
| S0 | Prototipo confirmado; sonda macOS sin administrador; política de la organización (modos permitidos); medida de lógica reutilizable. Decide si sigue C o basta A (contratos sobre el bucle actual) | Esta spec + SE-505 | — |
| S1 | Contratos (eventos, peticiones, latido, presencia, acuses) con esquema; el lanzador emite inicio y fin con código y clase; `pulse status`; canal de respaldo | SE-507 (latido y `finish --rc`) + SE-514 (Pulse productor) | 2 |
| S2 | Política de integración `solo_conflicto`, detección de cabeza sin pruebas y relanzamiento único; huella de contenido para relanzar revisoras; las dos PR de workflows | SE-500 + PR de workflows | 3 (Pulse), 4 (workflows) |
| S3 | Señales tipadas y taxonomía de errores; cuarentena con motivo y dueño; intento ≠ intención | SE-493, SE-513 | 3 |
| S4 | Pulse como ejecutor de SE-498; tic de control; volante que resta; reanudar solo la persona (CLI local o aprobación formal) | SE-498, SE-488 | 4 |
| S5 | Ledger de eventos, los cuatro datos nuevos (HOLD con familia, nivel y verificado; cierre sin fusionar; error de cuota; apertura de revisión por la persona), eventos consultivos (latente, preexistente) con seguimiento, métricas de rendimiento, retrabajo, coste y espera; coste real cuando el proveedor lo dé | SE-507 | 2 |
| S5c | Cambio del contrato de las revisoras: `VERDICT:` y cuerpo con familia, nivel, verificado, origen y consultivos; esquema, validador y exclusión de consultivos del cómputo. Slice propio porque toca la puerta de revisión | SE-433, SE-362 | 4 |
| S6 | Planificador puro en sombra frente al bucle actual; después corte por efectos con ledger, de uno en uno | SE-493 | 3–4 |
| S7 | Configuración por operador, adaptadores (forge, proveedor, servicio del SO), lista de salidas, guarda local de términos; instalación en macOS con el modo inicial elegido por el operador (`observar` por defecto) | SE-517 | 3 |

S1 y S2 pueden empezar en el bucle actual como puente mientras la spec se revisa; la spec los fija como contrato. SE-507 está PROPOSED: si no se aprueba, S1 define aquí su parte mínima de latido.

## Decisiones

Las doce están decididas por el operador. Cada una indica lo que rige.

- **Registro de la decisión.** fecha: 2026-11-13. Registro de la orquestadora: la operadora confirmó las doce decisiones el 2026-11-13 y, en la revisión, cambió D3 y D7 a la opción recomendada (`observar` por defecto y reanudar solo por CLI o aprobación formal). No es texto literal.

- **D1. Producto público.** Decidida por el operador: sí, producto público como proyecto del repo junto a Soul, con estado siempre privado.
- **D2. Lenguaje del núcleo.** Decidida por el operador: Python estándar ≥ 3.9, sin dependencias.
- **D3. Agentes en una instalación de organización.** Decidida por el operador: el modo inicial por defecto es `observar`. Es configurable por operador: cada uno lo elige en la instalación y lo sube a `actuar` cuando confía.
- **D4. Política de integración.** Decidida por el operador: `solo_conflicto`, incluido el cambio del workflow del repo (tier 4).
- **D5. Huella de contenido.** Decidida por el operador: sí, para no relanzar revisoras; la puerta de fusión no cambia.
- **D6. Avisos.** Decidida por el operador: solo Soul cuando está presente, con respaldo mínimo si no.
- **D7. Reanudar tras el freno.** Decidida por el operador: solo se reanuda por la CLI local o por una aprobación formal. Ningún agente ni proceso reanuda, y el chat de Soul no reanuda.
- **D8. Lecciones entre instalaciones.** Decidida por el operador: no por defecto.
- **D9. Periodo de sombra.** Decidida por el operador: 7 días.
- **D10. Orden.** Decidida por el operador: S0–S2 primero.
- **D11. Reserva de cuota interactiva.** Decidida por el operador: reserva fija pequeña y configurable (por ejemplo, 15 %), medida en S5.
- **D12. Espera máxima de pruebas en cola.** Decidida por el operador: 15 minutos, configurable.

## Fuera de alcance

- Fusionar, aprobar o conceder grants: siguen en SE-433, SE-488 y SE-512.
- La política de atención (modos, presupuestos de avisos, agrupado): es de Soul (SE-490, SE-514).
- El catálogo de estaciones y la composición de la factoría.
- Cualquier sincronización entre instalaciones.
- Elegir el proveedor de inferencia de nadie.

## Riesgos

- **El consultivo como salida fácil.** Marcar «latente» o «preexistente» puede usarse para dejar pasar un defecto real. Mitigación: exige reproducción y cita del SHA de base, el seguimiento es obligatorio, nunca degrada privacidad ni seguridad P0, se desactiva si la propuesta añade un llamador, y la persona ve los consultivos en tier 3/4. La métrica de consultivos abiertos hace visible la acumulación.

- **Dos implementaciones conviviendo** durante la sombra: más superficie. Mitigación: la sombra solo planifica; un único ejecutor actúa.
- **Sombra sin comparación** se convierte en reescritura con otro nombre. AC-20 es el control.
- **Coste de revisión humana** en tier 4 (control y registro): es el cuello de botella; por eso S4 y el corte de S6 van después.
- **Modo `observar` por defecto (D3).** Una instalación nueva no lanza nada hasta que el operador sube el modo; el coste es adopción más lenta. Mitigación: `pulse status` muestra qué haría y el operador sube a `proponer` o `actuar` cuando confía; el freno, el volante y los límites de efectos cerrados aplican en todos los modos.
- **Si la organización no permite instalar un servicio de usuario, ni siquiera en `observar`** (el modo por defecto), cae el argumento de portabilidad y A (contratos sobre el bucle actual) puede bastar. S0 lo mide antes de invertir.
- **Desfase de versiones** entre Pulse y Soul: `schema_version` y pruebas de contrato en CI de ambos.
- **La causa exacta de las pruebas en cola** (F8) no está confirmada; la política de relanzar una vez no depende de conocerla, pero S2 debe registrarla.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Núcleo `pulse` (observar, planificar, ejecutar, publicar) | Proceso propio, servicio de usuario; no depende del frontend | El mismo |
| Lanzamiento de workers y revisoras | `claude -p` con herramientas acotadas | `opencode run` con el agente equivalente; el adaptador de proveedor elige |
| Peticiones y acuses | Soul (cola única de SE-514) | Soul; diálogo `ask` de Space |
| Freno | Plano de control de SE-498 | El mismo |

### Verification protocol

- [ ] El núcleo corre igual con cualquiera de los dos frontends como lanzador (adaptador)
- [ ] Tests de contrato Pulse↔Soul con un negativo por AC
- [ ] Probado en macOS y Linux sin administrador antes de pedir nada a la persona

### Portability classification

- [x] **DUAL_BINDING**: el núcleo no depende del frontend; el lanzamiento de workers tiene un adaptador por frontend desde S1.

## Aprobación

APPROVED el 2026-11-13 por la operadora (pregunta interactiva; D3 y D7 a la opción prudente). La aprobación se formaliza al fusionar la PR (SE-488).
