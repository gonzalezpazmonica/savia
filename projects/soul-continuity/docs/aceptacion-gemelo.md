# Lista de aceptación del gemelo, para la operadora

> Para quien va a usar el gemelo en su trabajo, sin necesidad de ser técnica. Reúne dos especificaciones: el gemelo en el portátil de trabajo (SE-490) y la app de Savia Space que habla con él (SE-504).
> Cada criterio dice tres cosas: **qué haces tú con tus manos**, **cómo sabes que ha ido bien** y **qué prueba automática ya lo respalda**.
> Estado de este documento: redactado el 2026-11-11 a partir de las especificaciones y de un inventario de solo lectura. **No he vuelto a ejecutar las pruebas automáticas al escribirlo**; la columna de evidencia indica dónde están, no que hoy estén en verde. Lo que no he podido comprobar figura al final, en «Lo que no está verificado».

## Cómo leerlo

| Parte | Qué contiene | Quién actúa |
|---|---|---|
| **Sesión de puesta a punto** | Dejar el portátil y el teléfono listos. Es lo primero y bloquea todo lo demás | Tú, una sola vez |
| **A. Ya cubierto por pruebas automáticas** | Lo que no tienes que comprobar a mano. Hay un vistazo opcional de un minuto para quien quiera fiarse menos | Nadie |
| **B. Solo se comprueba en tu teléfono o tu portátil** | Lo que ninguna prueba automática puede ver | Tú |
| **C. Necesita a otras personas** | Pruebas con terceras personas y el piloto de una semana | Tú y otras personas |

Las referencias de la columna «Respaldo» son rutas del repositorio público (relativas a `projects/soul-continuity/` salvo que diga otra cosa) o el número de una PR del repositorio privado de la app (**Space #N**). Una ruta marcada con ✱ existe en el repositorio, pero no he confirmado que su última ejecución esté en verde.

---

## Sesión de puesta a punto (una sola sesión, en orden)

Lo necesitas hecho antes de cualquier prueba de las partes B y C. Calcula entre 1 y 2 horas, con tu teléfono y tu portátil a mano. La guía de instalación completa es `docs/instalar.md`; aquí va solo el orden y lo que tienes que ver en cada paso.

Los agentes no pueden hacer estos pasos por ti: el emparejamiento y el arranque del servicio se rechazan a propósito cuando los pide un agente, y hay que hacerlos con tu teléfono físico.

1. **Prepara el portátil.** Copia la carpeta del gemelo y ejecuta `bash install.sh` desde ella. Debe terminar diciendo dónde ha dejado la orden `soul`.
   *Va bien si:* `soul help` muestra la lista de órdenes sin errores.
2. **Crea tu perfil.** `soul setup` te hace preguntas sencillas; Intro acepta la propuesta. No activa ninguna fuente de trabajo por sí solo.
   *Va bien si:* `soul status` responde en menos de un segundo con tu perfil.
3. **Pon la red privada (VPN) en marcha en el portátil y en el teléfono**, con la misma cuenta en los dos, y comprueba que el portátil tiene una **dirección numérica propia dentro de la VPN**. Es lo primero que falló la última vez que se intentó: la interfaz de la VPN existía pero sin dirección.
   *Va bien si:* `tailscale ip -4` (o el equivalente de tu VPN) devuelve una dirección que empieza por `100.`.
   *Si no devuelve nada:* ejecuta `soul doctor`. Si dice que el gestor de red le quita la dirección a la VPN, te da la orden exacta para arreglarlo (pide tu contraseña una vez). Está descrito en `docs/instalar.md`, apartado «Si `serve` no arranca». No he comprobado que esa sea la causa en tu equipo.
4. **Dale a tu usuario permiso de operador sobre la VPN**, para que el gemelo pueda preguntarle su dirección sin pedir contraseña cada vez: `sudo tailscale set --operator=$USER`. Pide tu contraseña una vez.
   *Va bien si:* `tailscale ip -4` funciona sin `sudo`.
5. **Haz que el gemelo escuche solo en la VPN.** `soul listen --detect` busca la dirección y la guarda. El gemelo se niega a escuchar en todas las interfaces; no hay forma de equivocarse en el sentido peligroso.
   *Va bien si:* `soul listen` muestra la misma dirección `100.…` que el paso 3.
6. **Arranca el servicio.** `soul autostart install`, que lo deja arrancando con tu sesión sin permisos de administrador. Después, `soul doctor` repite todas las comprobaciones.
   *Va bien si:* `soul doctor` no marca ningún fallo. Anota qué marca si algo falla, con la frase tal cual.
7. **Instala la aplicación en el teléfono.** Descarga la aplicación (el archivo de instalación, `.apk`) generada desde la versión fusionada y ábrela en el teléfono.
   *Va bien si:* aparece «Instalada» y el icono de Savia Space.
8. **Si sale «App no instalada»**, ese mensaje no dice la causa y no se ha diagnosticado todavía. Se averigua así:
   1. En el teléfono, activa «Opciones de desarrollador» y dentro «Depuración por USB».
   2. Conecta el teléfono al portátil con cable y acepta la ventana de confianza del teléfono.
   3. En el portátil: `adb devices`. Debe listar el teléfono (si no lo lista, el cable o el permiso no están bien; no sigas).
   4. `adb install -r <archivo>.apk`. Esta vez la orden **sí escribe la causa**, con una frase del tipo `INSTALL_FAILED_…`.
   5. Anota esa frase tal cual. Las causas habituales y su salida: firma distinta de una versión anterior (hay que desinstalar la anterior, y eso borra el emparejamiento de esa copia); versión más antigua que la instalada (`-d`); poco espacio; Android demasiado antiguo para la aplicación. Si es una causa del archivo y no del teléfono, para y avisa: hay que corregir la aplicación, no tu teléfono.
9. **Empareja el teléfono.** En el portátil, `soul pair` muestra un código QR. En la app, elige el modo directo y escanea el QR. Compara que la huella corta que enseña la app es la misma que la del portátil.
   *Va bien si:* la app muestra la pantalla de continuidad sin ningún error de conexión. El código vale 10 minutos y una sola vez; no compartas capturas mientras esté activo.
10. **Prueba de humo.** En la app, pulsa «Consultar ya».
    *Va bien si:* aparece la hora de «último contacto» de hace segundos y el cajón dice «Portátil conectado».

Si los diez pasos terminan bien, ya puedes seguir con la parte B. Si no, para en el primero que falle y anota la frase exacta que sale.

---

## A. Ya cubierto por pruebas automáticas

Esta parte no te pide trabajo. Aun así, para cada fila hay una forma de ver el respaldo con tus ojos si lo necesitas: abrir el fichero indicado, que es la prueba, o ver el resultado de la integración continua de la PR correspondiente. Lo único que se ejecutó al preparar el inventario fueron las pruebas de la firma de las peticiones y de la API del gemelo: 22 de 22 en verde. El resto lo cuento por lectura del nombre y del fichero, no por ejecución.

### A1. El gemelo en el portátil

| Qué garantiza, en palabras llanas | Respaldo | Límite |
|---|---|---|
| Funciona en Windows, macOS y Linux sin permisos de administrador, y `status` responde en menos de un segundo (SE-490 AC-1) | `.github/workflows/soul-continuity.yml` (matriz de tres sistemas) ✱; `test/soul.test.ts` ✱ | No he comprobado que la última ejecución esté en verde |
| Hay un banco de ejemplos con la respuesta correcta escrita *antes* de ejecutar, de más de 60 escenarios (AC-2) | `bench/test/runner.test.ts` ✱; `bench/truth/` | Los ejemplos son sintéticos |
| Acierta al menos el 90 % por pregunta, sin usar nada revocado, sin cruzar datos entre personas y con Q1 en menos de 2 s (AC-3) | `test/bench-impl.test.ts` ✱, `test/adapters/index.test.ts` ✱ | **Medido con fuentes de prueba, no con las tuyas.** Con tus fuentes reales no está medido (eso lo mide el piloto, parte C) |
| Un remitente falsificado no dispara una alerta; por la ruta web una regla de remitente solo da aviso (AC-4c) | `bench/test/runner.test.ts` ✱ | — |
| A Claude Code, OpenCode u otra herramienta cuyo modelo está en la nube solo llegan cifras, nunca asuntos, nombres ni remitentes (AC-4d) | `test/config.test.ts` ✱, `test/cli.test.ts` ✱ | No he comprobado línea a línea el caso «sin declaración» |
| Revocar una fuente borra su caché y sus claves; desinstalar no deja nada (AC-5) | `test/ac5-integracion.test.ts` ✱, `test/connectors.test.ts` ✱ | Lo que el gemelo no puede borrar por ti es la concesión en cada proveedor (Microsoft, Google, GitHub…); está explicado en `docs/instalar.md` §7 |
| Cada petición a la API lleva una prueba criptográfica ligada a tu teléfono; una repetida, caducada o hecha para otra dirección da error 401 (AC-6b) | `src/api/dpop.ts`; `test/dpop.test.ts` y `test/gemelo-api.test.ts` (**22/22 ejecutadas en el inventario**) | Es la parte que más protege si pierdes el teléfono |
| El documento de transparencia y el modelo de amenazas del canal móvil existen y fueron revisados (AC-6) | `docs/canal-amenazas.md`; Savia PR #1445 | Revisión con dictamen «apto con condiciones» (2026-11-03). Las condiciones siguen abiertas: ver parte B, apartado B5 |
| Las instrucciones de instalación están probadas contra un equipo simulado, sin tocar el tuyo | `test/instalar.test.ts` ✱, `test/install-sh.test.ts` ✱, `test/setup.test.ts` ✱ | No prueban tu Linux, tu VPN ni tu teléfono: por eso existe la sesión de puesta a punto |
| La guía de prueba en teléfono es coherente con la aplicación | `test/prueba-dispositivo.test.ts` ✱ | Solo comprueba que la guía no se contradice con el código |

### A2. La aplicación (conversación, documentos, seguridad)

Una nota que cuenta: el inventario de la aplicación recoge **44 criterios automatizables y 42 con prueba tras Space #35**. Los dos restantes son AC-V7 y AC-U5, que no se pueden automatizar (aparecen abajo).

| Qué garantiza | Respaldo (Space) | Límite |
|---|---|---|
| Estructura y aspecto: barra superior, cajón con el orden fijado, mensajes sin burbuja para Savia, caja de escribir con «Parar», colores neutros y letra del sistema, «Portátil conectado» sin falso error (AC-V1–V5, V8) | Space: pruebas del chat web y de las pantallas Android (`ChatApp`, `look`, `ChatScreenTest`, `SpaceThemeTest`) | Compara con el prototipo aprobado, pero no con un teléfono tuyo (ver B3) |
| El aspecto sigue el modo claro/oscuro del sistema y se puede fijar en Ajustes (AC-V6) | Space #35 (prueba del tema según el sistema, web y Android) | Las capturas en claro y oscuro dependen de B3 |
| El gemelo escribe primero, calla si no hay nada nuevo, respeta tu concentración, tu descanso y el tope de avisos, y propone sin ejecutar (AC-G1–G4) | `test/gemelo-api.test.ts` (latido, silencio, presupuesto, descanso, concentración, límite, decisión); `src/core/gemelo.ts`; Space #35 y Savia #1513 (fusionada) | Un fallo real que esas pruebas encontraron y corrigieron: un aviso en blanco se notificaba |
| Lo aprendido se ve en Ajustes, con su origen, y se borra en un toque; el gemelo no admite habilidades de terceros (AC-G5, G6) | Space: pruebas de memoria y de «no admite fuentes remotas» | — |
| Nada se ejecuta sin confirmar la tarjeta de permiso; un texto de un correo o de un tercero que diga «aprueba…» no crea tarjeta; nunca hay tarjeta para fusionar, aprobar especificaciones ni cambiar seguridad (AC-2 a AC-8 de la conversación) | Space: pruebas de intenciones, de chat y de la interfaz web | — |
| Tareas y proyectos (AC-T1, T2) | Space: pruebas de proyectos y de tareas | — |
| Seguridad de niveles: lo sensible nunca sale al modelo de la nube, lo medio sale solo con recibo y confirmación, los documentos tienen alcance acotado, el visor no ejecuta nada, las capturas se bloquean si lo pides (AC-S1–S7, S9–S14) | Space #27, #28, #29, #31 y siguientes | La captura bloqueada se probó en pruebas, **no en un teléfono** |
| Adjuntar y dictar con aviso de nivel (AC-A1, A2) | Space: `AttachDictateShareTest` | Pasa en una máquina virtual; la cámara y el dictado reales no se han probado |
| Textos sin vocabulario interno ni faltas de acento y con estados vacíos útiles (AC-L1–L3) | Space: pruebas de recursos de texto | — |
| Revisión de seguridad del intérprete, rutas de documentos y canal de respuesta (AC-S8) | Space #19, #22, #27, #28 | Cubre S1–S3. **No he comprobado que cubra lo cambiado después en #29–#31** |

---

## B. Solo se comprueba en tu teléfono o en tu portátil

Cuatro cosas ayudan a todas las pruebas de esta parte:

- Haz antes la **sesión de puesta a punto**.
- Escribe el resultado de cada prueba como una casilla y una frase corta, sin direcciones, sin nombres de personas, sin asuntos de correos reales y sin capturas de la pantalla de bloqueo.
- Un fallo no es un fracaso tuyo: es el motivo de la prueba. Anota la frase exacta que ves.
- Si algo te parece raro y no está en la lista, anótalo igual.

### B1. El gemelo te avisa en segundo plano (AC-4b)

La guía paso a paso, con la plantilla de resultados, es **`docs/prueba-dispositivo.md`**. Dura unos 10 minutos de trabajo y una espera de una hora con el teléfono quieto. No la repito aquí; este es el resumen.

| Qué haces | Cómo sabes que ha ido bien | Respaldo automático | Si falla |
|---|---|---|---|
| Dejas la app en segundo plano 12 minutos y miras la notificación fija | La hora de «último contacto» avanza al menos dos veces, con no más de 6 minutos entre una y otra, y la notificación no desaparece | `tests/attention/ac4b.test.ts` ✱ (política de avisos); `test/gemelo-api.test.ts` (consulta y latido) | El teléfono o el fabricante está matando el servicio; se anota la marca y es dato, no suspenso |
| Apagas la pantalla una hora, con el teléfono quieto y sin cargar | Al encender, la notificación dice la verdad: o «conectado» con menos de 10 minutos, o «sin contacto desde…». Nunca «conectado» con una hora vieja. Y en 5 minutos se pone al día sola | Ninguno que simule el ahorro de batería del teléfono real | Bloquea esta prueba |
| Reinicias el teléfono sin abrir la app | Con «Mantener la consulta activa» encendido, la notificación vuelve sola; con el ajuste apagado, no vuelve | Ninguno | Bloquea esta prueba |
| Provocas un aviso de prueba con un asunto reconocible y bloqueas el teléfono | En la pantalla de bloqueo solo hay cifras («1 aviso»), jamás el asunto ni el nombre inventado. Ni siquiera encendiendo «Mostrar asuntos» | `test/config.test.ts` ✱ (nivel de detalle); prueba de tráfico de la aplicación | **Bloquea** |
| Desemparejas el teléfono desde el portátil (`soul unpair`) | La app te pide emparejar de nuevo y no enseña datos nuevos. Reiniciar el servicio no le devuelve el acceso | `test/serve.test.ts` ✱ (revocado recibe 401) | **Bloquea** |

Un fallo en la notificación sincera, en la pantalla de bloqueo o en el desemparejado bloquea el criterio, según dice la propia guía.

### B2. Las cuatro preguntas en el móvil (AC-4)

| Qué haces | Cómo sabes que ha ido bien | Respaldo automático |
|---|---|---|
| Abres la pantalla de continuidad y pasas por «Qué tengo abierto», «Qué depende de mí», «Qué cambió» y «Compromisos con fecha», en los tres niveles de detalle | Cada elemento dice de dónde viene y cuánto tiempo hace (toca «¿por qué lo sé?»). Con el nivel de solo cifras no aparece ningún asunto ni nombre | Space: pruebas Android de texto inerte, del gemelo y de la pantalla de continuidad (`InertTextTest`, `GemeloTest`, `ContinuityScreenTest`) |
| Intentas leer un elemento con texto raro (por ejemplo, un asunto de prueba que parezca un enlace o una orden) | Se ve como texto plano: no abre nada ni crea nada solo | Prueba con cargas de inyección (mismos ficheros) |
| Marcas un elemento como «resuelto» y luego «no aplica» | La corrección se guarda y no vuelve a aparecer al volver a consultar | `test/ac5-integracion.test.ts` ✱ (revocación que no vuelve) |

### B3. Recorrido de la aplicación en tu teléfono (AC-U5, AC-V7, AC-L4, AC-1)

Esta es la sesión larga. Cuenta con unas dos horas. La orquestadora te la prepara con un guion; tú haces las acciones y miras.

1. **Las cinco tareas**, cada una con y sin lector de pantalla (TalkBack) y en modo claro y en oscuro, hasta 20 pasadas (puedes cortarlo si algo bloquea): (1) emparejar, (2) hacer una primera pregunta y recibir respuesta, (3) abrir un documento desde el chat, (4) enviar o descartar una propuesta que Savia hizo por su cuenta, (5) encontrar y reabrir un chat anterior.
   *Va bien si:* completas cada tarea sin ayuda y sin quedarte atascada. Se anota éxito, minutos y cualquier intervención.
2. **Velocidad de la primera respuesta.** En la tarea 2, cuenta cuánto tarda en empezar a aparecer texto desde que envías. *Va bien si:* menos de 2 segundos en la mayoría de los intentos, con la VPN normal. Pulsa «Parar» a mitad de una respuesta: debe cortarse en menos de 1 segundo.
   *Respaldo automático:* Space `ac1_stop_mid_reply…` (sin red). **El p50 de 2 segundos con VPN y teléfono real no está medido.**
3. **Letra grande.** En los ajustes del teléfono sube la letra al 200 % y mira los cuatro estados (chat nuevo, chat, cajón, visor). *Va bien si:* nada se corta ni queda pegado a otra cosa y todos los botones se pulsan sin fallar.
   *Respaldo automático:* tamaños táctiles de 48 px y contraste AA en web hechos; **letra al 200 % y TalkBack en el teléfono: pendiente.**
4. **Parecido con el prototipo (AC-V7).** La orquestadora te enseña capturas de la app a 360 dp junto a las del prototipo aprobado, con la lista de diferencias. *Tú decides* para cada diferencia: aceptarla o pedir que se corrija. *Respaldo:* las capturas de web existen en Space; **no he verificado que existan las de Android a 360 dp.**
5. **Capturas bloqueadas.** Activa «Bloquear capturas» en Ajustes e intenta hacer una captura del chat. *Va bien si:* el sistema te lo impide; apagado, te deja. *Respaldo:* Space #31 en máquina virtual; **no probado en teléfono real.**
6. **Cámara y dictado reales (AC-A1, A2).** Adjunta una foto con la cámara y dicta una frase. *Va bien si:* lo dictado queda en la caja de escribir sin enviarse solo y la tarjeta del adjunto te dice qué pasará según su nivel.

### B4. Cierre de fallos que salgan (corrección y repetición)

De B1 a B3 saldrán fallos; es lo normal en una primera vuelta con un teléfono real (Doze, notificaciones, textos, tamaños). Cada fallo se corrige en una PR aparte, y **tú repites solo la prueba que falló**. Dependiendo de lo que toque (si afecta al emparejamiento o a la firma de peticiones, requiere tu revisión expresa de esa PR), cuenta entre 30 y 60 minutos más.

### B5. Condiciones abiertas de la revisión del canal (AC-6)

Esto se comprueba en tu portátil y no necesita a nadie más, pero no se puede cerrar con una prueba automática.

| Qué haces | Cómo sabes que ha ido bien | Respaldo |
|---|---|---|
| Compruebas que la aplicación instalada sale de la versión fusionada | El número de versión que enseña la app coincide con el de la última versión publicada | Space #14 (según el traspaso, fusionada) |
| Intentas emparejar con un teléfono **sin bloqueo de pantalla** | El emparejamiento se rechaza con un mensaje claro | `isSecure()` existe en el código de emparejamiento de Space; **no he comprobado que el gemelo se niegue** |
| Revisas que el gemelo escucha *solo* en la dirección de la VPN | `soul listen` muestra una sola dirección `100.…` y, desde otro equipo que no esté en la VPN, no hay respuesta | `docs/canal-amenazas.md`; el test de puertos de AC-4b |
| Pierdes el teléfono (simulacro): `soul corrections --device <id>`, luego `soul unpair <id> --undo` | El teléfono deja de entrar y sus correcciones se deshacen | `docs/instalar.md` §5 |

### B6. Recetas web reales de Outlook, Teams y SharePoint (AC-4e)

Esto es lo más frágil, y necesita **tu portátil de trabajo y tu sesión**. La especificación es tajante: las recetas de los clientes web reales **solo se publican si pasan la batería de pruebas contra una grabación de su tráfico real**. Si no la pasan, no se publican, y esa fuente se queda sin ruta web (no se relaja la regla).

| Qué haces | Cómo sabes que ha ido bien | Respaldo |
|---|---|---|
| Inicias sesión en el perfil aparte del navegador solo en esas webs y grabas una sesión normal de trabajo | La grabación se hace, sin guardar contraseñas ni correos completos | — |
| La batería se pasa contra la grabación | 0 mutaciones, 0 operaciones fuera de la lista, 0 envíos por WebSocket; si no, la receta se desactiva con un aviso | `src/web/test/navegador/bateria.test.ts` ✱ y `.github/workflows/soul-continuity-web.yml` (Savia #1451), con sitios simulados |

**Límite honesto:** hoy la batería pasa con sitios *de prueba*. Con los clientes reales, no hay garantía de que pase.

---

## C. Necesita a otras personas

Aquí no puedo darte una lista cerrada que completes tú sola: dependen de personas que no están identificadas.

| Criterio | Qué se necesita de otras personas | Qué haces tú | Cómo se sabe que ha ido bien | Respaldo |
|---|---|---|---|---|
| **Tareas sin ayuda (AC-U1)** | 3 personas no técnicas que no hayan visto Savia | Eliges a las tres, les pides permiso, estás en la sesión. La orquestadora conduce con un guion fijo | Las 3 completan las 5 tareas de B3 en su teléfono sin ninguna intervención (una intervención cuenta como fracaso) | Ninguno: no se ha ejecutado |
| **Cuestionario SUS (AC-U2)** | Las mismas 3 personas | Les pasas el cuestionario al terminar | Media de 80 o más y ninguna por debajo de 68 | Ninguno |
| **Cuestionario UEQ-S (AC-U3)** | Las mismas 3 personas | Idem | Las escalas práctica y de agrado por encima de 0,8; si no, se documenta qué falló | Ninguno |
| **Cara a cara con Claude y ChatGPT (AC-U4)** | Las mismas 3 personas, con las apps de Claude y de ChatGPT instaladas | Estás presente. Las tareas 2 y 3 se hacen en las tres apps en orden alterno, con un mismo documento | Savia no falla más y no tarda más de un 25 % de diferencia mediana. Se publica tal cual salga | Ninguno |
| **Piloto de una semana (AC-7)** | Tu propio uso durante una semana laborable, más dos días previos de línea base (sin usar el producto) | Cada día anotas: cuántos minutos te costó reconstruir la mañana, cuántas veces consultaste y, por cada elemento que viste, si era correcto, incorrecto o no aplicaba | Precisión percibida ≥ 80 %, 0 fugas, y menos minutos de reconstrucción que en los dos días de línea base. Solo se registran cifras | Ninguno: no ha empezado |

**Condiciones de parada del piloto**, del propio criterio: cualquier fuga, precisión percibida menor del 80 %, o que tú lo pidas sin dar explicaciones.

**Esta parte condiciona el cierre:** la especificación de la aplicación dice que **no pasa a «implementada»** sin AC-U1 a U4. Con el calendario actual no cabe todo antes del sábado 14 (ver más abajo).

---

## Lo que no está verificado

Dicho sin suavizar. Todo esto se comprobó leyendo, no ejecutando:

- El resultado actual de la integración continua del gemelo (`soul-continuity.yml`).
- Que el gemelo se niegue a emparejar un teléfono sin bloqueo de pantalla.
- Que existan capturas de Android a 360 dp, y que haya un emulador en el portátil.
- Que la corrección de Space #37 arregle el fallo de la prueba de un tercero con OpenCode 1.19.5.
- Que la dirección de la VPN se haya recuperado desde el último diagnóstico.
- Los resultados de `cargo test` y `gradlew`: las cifras salen de las notas de cierre de los agentes, no de una ejecución mía.
- La revisión de seguridad tras los cambios de Space #29–#31.
- Seguimientos abiertos de revisión: el conjunto de niveles en la memoria, un código de error que falta en la definición de la API, y la ejecución síncrona de la propuesta de la variante A.

---

## Cuánto tiempo tuyo hace falta (estimación mía, no medida)

| Bloque | Tiempo tuyo | Notas |
|---|---|---|
| Sesión de puesta a punto | 1–2 h | Hasta 2 h si «App no instalada» necesita el cable y una causa que no sea del teléfono |
| B1 prueba en el teléfono | 30–45 min de acción + 60 min de espera | La espera se solapa con otra tarea |
| B2 las cuatro preguntas | 20–30 min | — |
| B3 recorrido completo | 2 h | 20 pasadas con medición |
| B3 revisión de capturas del prototipo | 20–30 min | Decidir aceptar o corregir cada diferencia |
| B4 repetir lo que falló | 30–60 min | Según los fallos |
| B5 condiciones del canal | 30 min | — |
| B6 recetas web reales | 1–2 h | Y no hay garantía de que se publiquen |
| C — preparar y asistir a tres personas | 4–5 h | Elegirlas, pedir permiso, estar presente y 1 h de comparación con las otras dos apps |
| C — piloto | 10–15 min/día durante una semana, más 2 días de línea base | Unas 1–1,5 h repartidas en al menos 9 días naturales |
| **Total aproximado** | **7–10 h** entre puesta a punto y parte B (incluida la hora de espera), **4–5 h** más para las tres personas y **1–1,5 h** repartidas en el piloto, que ocupa **9 días naturales como mínimo** | Suma de las filas de arriba; no está medido |

**Lo que dice el calendario.** Contando desde el 11 de noviembre, con la sesión de puesta a punto hecha hoy o mañana, el camino crítico es: puesta a punto → B1 → B3 → B4. Es realista llegar a ese punto el sábado 14 si dedicas unas 7–10 h entre el miércoles y el viernes, y quedan **sin hacer antes del sábado**: el piloto de una semana (aunque empezara hoy, la semana laboral acaba el 17 como pronto), las pruebas con tres personas (no hay personas identificadas) y las recetas web reales. El resultado probable del sábado es una lista con todo lo automatizable en verde y los criterios de teléfono y de personas marcados «pendiente», no «cumplido».
