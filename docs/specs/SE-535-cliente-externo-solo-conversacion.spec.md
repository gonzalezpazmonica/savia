---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-15
author: Savia
phase: A
risk: L3
human_surface: true
related_specs: [SE-528, SE-429, SE-505, SE-362]
origin: "Encargo de la orquestadora: que otra instancia de Savia, con su propia cuenta y en otro equipo, pueda conversar con esta Savia por el puente, sin recibir ningún otro poder. Ninguna spec aprobada lo cubre: SE-528 deja fuera la revocación de tokens del puente y SE-429 es de Savia Space."
timeline:
  - from: "2026-11-15"
    learned: "2026-11-15"
    value: "PROPOSED"
    source: "encargo de la orquestadora; sin respuesta aún de la operadora"
---

# SE-535 — Cliente externo con alcance solo de conversación en el puente

## Problema

Quien instala Savia puede querer que **otra Savia** (otra persona, otra cuenta de Claude, otro equipo) le pregunte criterio: qué reglas hay, qué se decidió, qué specs existen. El canal natural es el puente: ya sirve `POST /chat` con Claude, autentica por cabecera `Authorization` y cifra con TLS.

Hoy el puente no distingue tipos de cliente. Sus tokens son de la operadora o de personas de su equipo, y se diseñaron para su propia app: con ellos se hace mucho más que conversar. Además, la conversación se sirve con la configuración local completa de Claude, en un directorio de trabajo donde hay ficheros locales no versionados. El detalle comprobado vive en el registro privado de la operadora, como en SE-528; esta spec, pública, fija solo requisitos objetivo.

Ninguna spec aprobada lo cubre:
- **SE-528** endurece la autenticación del puente (canal de credenciales, sesión, fallo cerrado, TLS fuera de bucle local), pero no define alcances por token, ni ejecución de Claude en solo lectura, ni topes de uso, y deja fuera de forma explícita la revocación de tokens.
- **SE-429** define clientes con alcance para **Savia Space**, no para el puente.

Lo que ya existe y S1 reutiliza: tokens por persona con alta y revocación inmediata por la API del puente (solo con el token maestro), autenticación solo por cabecera, rechazo de credenciales en la URL y negativa a arrancar sin TLS fuera de bucle local.

## Lo que he entendido

### Escenas

1. **Dar de alta a la otra Savia.** En este equipo escribes una orden: `savia-bridge-clients add savia-externa`. Te enseña el token **una sola vez**, junto con la dirección, el puerto y la huella del certificado. Lo copias al otro equipo. No hay más pasos.
2. **La otra Savia pregunta.** En el otro equipo, su Savia ejecuta `savia-consulta "¿qué regla hay sobre piezas sin consumidor?"`. A los pocos segundos recibe la respuesta con el fichero del que sale. Aquí no queda guardada la pregunta ni la respuesta; solo una línea: quién, cuándo, cuánto ocupó y si fue bien.
3. **Pide algo que no le toca.** La otra Savia pregunta por el perfil de la persona, por un fichero local o intenta cambiar una configuración. Con ese token, cualquier ruta que no sea conversar responde «prohibido». En la conversación, Claude no tiene herramientas de escritura, ni terminal, ni red, ni acceso a ficheros fuera de la copia compartible: contesta que no lo puede leer.
4. **Se pasa del límite.** La otra Savia hace la pregunta número 21 en una hora. Recibe «límite de uso alcanzado; prueba en N minutos». Cada pregunta gasta inferencia de la cuenta de este equipo, por eso el tope es por cliente, por hora y por día, y lo fijas tú.
5. **Lo retiras.** Escribes `savia-bridge-clients revoke savia-externa`. La siguiente pregunta recibe «no autorizado». No hace falta reiniciar nada.

### Palabras de la persona

Pendiente: la spec la redacta Savia a partir de un encargo de la orquestadora; las palabras literales de la operadora se copian aquí cuando responda a la pregunta interactiva de las escenas.

### Qué SÍ será

- Un tipo de cliente «externo» con un único alcance: conversar.
- Una orden para crear, listar y revocar esos clientes por nombre; el token se ve una vez.
- Conversación servida por Claude **en solo lectura** sobre una copia de los ficheros versionados del repo y, si la persona lo decide, de una carpeta de criterio compartible que ella llena a mano.
- Registro de cada consulta sin su contenido.
- Tope de consultas por hora y por día por cliente, configurable.
- Un cliente de un solo fichero, sin dependencias, para el otro equipo.

### Qué NO será

- No abre nada desde este equipo hacia el otro: el otro pregunta, aquí se contesta.
- No da acceso a ficheros, perfil, equipo, empresa, configuración de git, usuarios, permisos de herramientas ni proyectos.
- No guarda las preguntas ni las respuestas, ni en registros, ni en memoria, ni en cúpulas.
- No mantiene conversaciones de varios turnos en v1: cada pregunta es independiente (así no queda historial en disco).
- No expone el puente a internet ni cambia la red: escucha solo en la dirección que se le indica.
- No toca el servidor de cúpulas.

### Confirmación

- fecha: pendiente
- respuesta: pendiente. La orquestadora enseña las escenas a la operadora por pregunta interactiva y copia aquí su respuesta literal antes de pedir la aprobación.

## Slice S0 — Prototipo navegable

- prototipo: la transcripción de la orden de alta, listado y revocación con datos de ejemplo, y la del cliente en todas sus salidas (respuesta, no autorizado, prohibido, límite, error de red, error de huella y otro error), con el texto exacto de cada mensaje. El cliente de S2 ya existe como prototipo funcional fuera del repo y se le da a la persona para que lo use en su equipo.

### Confirmación del prototipo

- fecha: pendiente
- respuesta: pendiente. S1 no se pone en curso sin ella (SE-505).

## Decisiones que se piden a la operadora

- **D1 — Qué puede leer la otra Savia.** (a) Solo los ficheros versionados del repo (nivel N1). (b) N1 más una carpeta de criterio compartible que la persona llena a mano. Recomendación: (b). A favor: el criterio acumulado (decisiones, lecciones) vive sobre todo en la memoria local, que es N3 y no se comparte; sin (b), la otra Savia no puede contestar preguntas de criterio reciente. En contra: cada cosa que se copie a esa carpeta queda expuesta a otra cuenta y a otro proveedor de inferencia; la carpeta tiene que ser un acto explícito de la persona, nunca una copia automática de la memoria.
- **D2 — Topes por defecto.** Propuesta: 20 consultas por hora y 100 por día por cliente, cambiables al crearlo. A favor: acota el gasto peor caso a una fracción de la cuota diaria. En contra: una sesión intensa de la otra Savia puede quedarse corta; la persona lo sube con una orden.
- **D3 — Modelo.** Propuesta: tier `mid`. A favor: preguntas de consulta, no de diseño; ahorra cuota del tier `heavy`. En contra: respuestas de criterio fino pueden salir peores.
- **D4 — Varios turnos.** Propuesta: no en v1 (ver «Qué NO será»).

Criterio aplicado, el más restrictivo: lo que lee la otra Savia es N1, más lo que la persona copie a la carpeta compartible si elige D1 (b). Nada N2, N3, N4 ni N4b: ni perfiles, ni memoria, ni bóveda personal, ni ficheros ignorados por git, ni datos de proyectos.

## Slices

| Slice | Contenido | Tier |
|---|---|---|
| S1 | Puente: clientes externos, alcance, ejecución en solo lectura, registro, topes, escucha | 3 (autenticación; se fuerza aunque el clasificador mida menos) |
| S2 | Cliente de un solo fichero y la instrucción para la otra Savia | 2 |

### S1 — Puente

**Alta y revocación.**
- Una orden de línea de comandos `add <nombre> [--por-hora N] [--por-dia M]`, `list` y `revoke <nombre>`. El nombre identifica al cliente en registros y respuestas de error.
- El token se genera con un generador criptográfico, se muestra una sola vez y se guarda solo su hash. Nunca aparece en ningún registro, tampoco al arrancar.
- `revoke` surte efecto en la siguiente petición, sin reiniciar el puente. El alta también es en caliente, así que la barrera de escucha (ver «Escucha») se evalúa **también en `add`**: si el puente en marcha escucha en comodín o sin TLS, `add` falla sin crear el cliente.
- La orden habla con el puente en marcha por su API, con el token maestro, **por la dirección de escucha configurada** (la misma que usan los clientes: con un cliente externo es una dirección concreta con TLS, no el bucle local), validando el certificado con la huella ya configurada. Lee el token maestro de un fichero con permisos 600 (nunca de la línea de órdenes). El puente no abre un segundo listener de administración. Si el puente no responde, `add`, `list` y `revoke` fallan con un mensaje claro y no escriben nada directamente en disco.
- El nombre del cliente cumple `^[a-z0-9-]{1,32}$`; cualquier otro (saltos de línea, `/`, `..`, longitud mayor) se rechaza sin crear nada. Así no puede inyectar líneas en el registro ni formar rutas.
- La comparación del hash del token es en tiempo constante, y los fallos de autenticación de este tipo de cliente pasan por el mismo límite de fallos que el resto del puente. El almacén de clientes no contiene nunca el token, solo su hash.

**Alcance.**
- Un token de cliente externo solo alcanza, por lista blanca: `POST /chat` y `GET /health`. Toda otra ruta, método o ruta futura responde 403. La lista blanca está en un único sitio.
- En `POST /chat` con ese token: lista blanca de campos. Solo se acepta `message`; cualquier otra clave (`system_prompt`, `session_id`, `interactive` o una futura) responde 400. El prompt de sistema lo fija el servidor.
- Credenciales solo por la cabecera `Authorization` (SE-528); con este tipo de cliente no se emite cookie de sesión (ninguna respuesta lleva `Set-Cookie`).
- Ninguna ruta del puente, salvo `GET /health` y las de login de SE-528, responde sin autenticación. Esto cambia el comportamiento actual para los clientes existentes que hoy llaman a rutas anónimas: se declara como cambio incompatible en el changelog de S1, y la lista de rutas afectadas se obtiene recorriendo la tabla de rutas del puente, no a mano.

**Ejecución en solo lectura.** Cada consulta lanza el CLI de Claude:
- solo con herramientas de lectura (`Read`, `Grep`, `Glob`) y modo de permisos que deniega todo lo no permitido sin preguntar;
- sin servidores MCP, sin cargar la configuración local de Claude (ni hooks ni listas de permisos), sin memoria automática y sin persistir la sesión;
- con directorio de trabajo = una copia de solo los ficheros versionados de una referencia fija del repo (y la carpeta compartible si D1 (b)), sin directorios añadidos y sin enlaces simbólicos que apunten fuera de la copia. Al construir la copia se omite todo enlace simbólico cuyo destino resuelto caiga fuera de ella, incluidos los de la carpeta compartible. La copia se hace desde la referencia fija (una revisión configurada; por defecto la de la rama principal al arrancar el puente, y solo cambia con una orden de la persona), tiene un tope de 50 MB y se construye en menos de 2 segundos; si no cabe en esa cota, la consulta falla con error y no se amplía el alcance. Cada consulta usa su propia copia efímera (permisos 700, borrada al terminar, también si falla), de modo que consultas simultáneas no comparten estado;
- con entorno mínimo: el subproceso no hereda el entorno del puente (ni el token maestro ni variables de cuenta), solo una lista blanca fija;
- con el mensaje después de `--`;
- sin herramienta para aprobar permisos.

**Registro.** Una línea por consulta: hora, nombre del cliente, bytes de la pregunta y de la respuesta, código de respuesta y duración. Nunca el contenido; el registro detallado de chat no se escribe para este tipo de cliente.

**Topes.** Por cliente, ventana deslizante de una hora y de un día. Superado cualquiera: 429 con `retry_after_s`.
- Cuenta toda consulta que llega a lanzar el CLI, incluidas las que acaban en 5xx o en timeout (ya han gastado cuota). No cuentan las rechazadas antes de lanzarlo (4xx, 429).
- La reserva del hueco es atómica antes de lanzar el CLI: N peticiones simultáneas con tope 2 aceptan como mucho 2.
- Cada cliente admite una consulta en curso a la vez; la segunda simultánea recibe 429.
- Los contadores se guardan en disco (solo marcas de tiempo, sin contenido) y sobreviven a un reinicio del puente.
- Tope de tamaño del cuerpo (16 KiB) y del mensaje (8 KiB), 413 si se supera, y timeout por consulta (120 s), configurables.
- La concurrencia por cliente es configurable y vale 1 por defecto; la atomicidad de la reserva se prueba subiéndola.

**Escucha.** Con algún cliente externo dado de alta, el puente se niega a arrancar (código distinto de 0, sin abrir puerto) si la dirección de escucha es comodín (`0.0.0.0`, `::` o vacía) o si no hay TLS.

**Cómo se verifican los AC con Claude.** La denegación se detecta en la salida estructurada del CLI (`stream-json`: resultado de herramienta con error de permiso), no en el texto de la respuesta. Si el modelo no intenta usar la herramienta, la prueba repite con hasta 3 formulaciones y, si ninguna provoca el intento, termina como **inconcluyente = fallo**, nunca como éxito. Estas pruebas necesitan el CLI y una cuenta, así que corren a mano antes de cada versión de S1 y en CI solo si hay credencial; sin CLI o sin credencial la prueba falla, no se omite en silencio.

AC (cada uno con su caso negativo; los de Claude con el CLI real, no simulado):
- AC-1.1 Sin token, `POST /chat` devuelve 401.
- AC-1.2 Token de cliente revocado: 401 en la siguiente petición, sin reiniciar.
- AC-1.3 Token de cliente externo contra cada ruta y método del puente que no sea `POST /chat` ni `GET /health`: 403 (test que recorre la tabla de rutas del propio puente, para que una ruta nueva no se escape).
- AC-1.4 Token en la URL (consulta) o en el cuerpo: 401 (SE-528).
- AC-1.5 `POST /chat` con cualquier clave distinta de `message` (`system_prompt`, `session_id`, `interactive` o una inventada): 400.
- AC-1.6 Prueba real con Claude y control positivo. Se colocan canarios en un fichero ignorado por el control de versiones del checkout, en un fichero fuera del repo, en la carpeta de credenciales de Claude y en el entorno del proceso del puente, y se le pide a Claude leerlos por ruta absoluta. Control: con la invocación actual del puente la respuesta **sí** contiene el canario (si no, la prueba no discrimina y falla). Con la invocación de solo lectura la respuesta no lo contiene y el CLI devuelve una denegación de herramienta. Una negativa por prompt sin denegación de herramienta no vale.
- AC-1.7 Prueba real con Claude: se le pide crear un fichero y ejecutar una orden; no existe el fichero después, no hay efecto y el CLI devuelve una denegación de herramienta (no una negativa por prompt).
- AC-1.8 Límite: con tope 2 por hora, la tercera consulta devuelve 429 y `retry_after_s`; otro cliente sigue pudiendo preguntar; una consulta rechazada con 4xx no cuenta; una que acaba en 5xx o timeout sí cuenta.
- AC-1.9 Con un cliente externo dado de alta, arrancar en `0.0.0.0`, `::` o sin TLS sale con código distinto de 0 y no abre el puerto; en una dirección concreta con TLS arranca.
- AC-1.10 El registro contiene nombre, hora y tamaños; el texto de la pregunta y el de la respuesta no aparecen en ningún fichero del directorio de datos del puente.
- AC-1.11 Ni el token de un cliente ni el token maestro aparecen en el registro de arranque.
- AC-1.12 Las rutas que hoy responden sin autenticación, salvo `GET /health` y las de login de SE-528, devuelven 401 sin token (test que recorre la tabla de rutas del puente); las de login de SE-528 siguen permitiendo autenticarse.
- AC-1.13 Con el puente en marcha en comodín o sin TLS, `add` falla y no crea el cliente; en una dirección concreta de red (no bucle local) con TLS, `add` funciona sin reiniciar y con huella equivocada falla. Con el puente parado, `add` falla.
- AC-1.14 Concurrencia: con la concurrencia por cliente en 1, la segunda consulta simultánea recibe 429. Con la concurrencia subida a 20, tope 2 y 20 peticiones simultáneas, se aceptan como mucho 2 (prueba de la reserva atómica, no de la cola).
- AC-1.15 Un cuerpo por encima del tope devuelve 413 y no lanza el CLI; una consulta que excede el timeout se corta, devuelve error y cuenta para el tope.
- AC-1.16 Los contadores sobreviven a un reinicio del puente: tras alcanzar el tope y reiniciar, la siguiente consulta sigue dando 429.
- AC-1.17 Enlaces simbólicos: un enlace versionado (y uno en la carpeta compartible) que apunta fuera de la copia, o a la carpeta de credenciales de Claude, no aparece en la copia y Claude no puede leer su destino. Tras cada consulta, la copia efímera ya no existe.
- AC-1.18 Un token incorrecto repetido activa el límite de fallos de autenticación del puente también para este tipo de cliente.
- AC-1.19 El almacén de clientes no contiene el token, solo su hash; la comparación usa una función de tiempo constante (comprobado en el código del puente); ninguna respuesta a este cliente lleva `Set-Cookie`.
- AC-1.20 Un nombre fuera de `^[a-z0-9-]{1,32}$` (`../x`, con salto de línea, de 33 caracteres) se rechaza y no crea nada; uno válido se acepta.
- AC-1.21 Con el puente parado, `list` y `revoke` fallan con mensaje claro y no modifican el almacén.
- AC-1.22 Con un cliente externo dado de alta y un adaptador distinto de `claude`, el puente no arranca.
- AC-1.23 El subproceso de Claude no ve el token maestro ni variables del puente: un proceso de prueba que vuelca su entorno solo muestra la lista blanca.
- AC-1.24 La copia efímera respeta el tope de 50 MB y de 2 segundos: un repo mayor da error y no lanza el CLI.

Reversión: revertir la PR. Los clientes externos dejan de existir. Las rutas anónimas vuelven a ser anónimas, que es el comportamiento actual: quien dependa del cambio incompatible de AC-1.12 lo recupera al revertir.

### S2 — Cliente para la otra Savia

- Un solo fichero en Python 3 de biblioteca estándar y una variante en `sh` con `curl` y `openssl`, sin dependencias.
- Configuración: dirección, huella del certificado y ruta del fichero del token (permisos 600). El token nunca va en la línea de órdenes ni en la URL.
- Comprueba la huella **antes** de enviar nada; si no coincide, sale sin enviar.
- Códigos de salida distintos para: éxito, configuración, red, huella, no autorizado (401), prohibido (403), límite (429) y otro error (5xx, 400, 413).
- Una instrucción breve para la otra Savia: cuándo usarlo (preguntas de criterio, reglas, specs, decisiones) y qué no enviar nunca (datos de su empresa, de personas o de proyectos).

AC:
- AC-2.1 Huella equivocada: sale con su código y el servidor no recibe ninguna petición `POST`.
- AC-2.2 Fichero del token legible por otros: sale sin conectar.
- AC-2.3 401, 403, 429, 5xx, error de red y huella dan cada uno su código; 200 imprime la respuesta.
- AC-2.4 El token no aparece en ninguna URL pedida.
- AC-2.5 Funciona contra el cierre TLS del puente real (sin longitud y sin aviso de cierre).

## Fuera de alcance

- Conversaciones de varios turnos (D4).
- Clientes externos con otros alcances (leer ficheros, proponer cambios).
- Cambios de red, cortafuegos o túneles: la dirección de escucha la decide quien instala.
- Rotación periódica automática de tokens.
- Savia Space (SE-429) y el servidor de cúpulas.

## Riesgos

- **Fuga por la carpeta compartible (D1 (b)).** Mitigación: solo la llena la persona, a mano; nada la alimenta de forma automática.
- **Inyección de instrucciones desde la otra Savia.** Puede pedir a Claude que lea lo vedado o que actúe. Mitigación: la barrera no es el prompt sino la ejecución (herramientas de solo lectura, permisos que deniegan sin preguntar, directorio sin ficheros locales). AC-1.6 y AC-1.7 lo prueban con el CLI real.
- **Gasto.** Cada consulta consume cuota de esta cuenta. Mitigación: topes (D2) y modelo (D3).
- **Datos de terceros que llegan en la pregunta.** No se guardan (AC-1.10); la instrucción de S2 pide no enviarlos.

## Evidencia de factibilidad

Comprobado antes de proponer, con el CLI real de Claude Code y una copia de solo ficheros versionados del repo como directorio de trabajo:
- La combinación de herramientas de lectura, modo de permisos que deniega sin preguntar, sin fuentes de configuración locales, con los hooks desactivados, sin MCP, sin memoria automática y sin persistir la sesión deniega `Read`, `Grep` y `Glob` sobre rutas fuera de la copia (ficheros locales ignorados, carpetas de estado del usuario, temporales). La respuesta no contiene los canarios.
- En la misma ejecución no hay herramienta para escribir, ejecutar órdenes ni descargar: el fichero pedido no aparece y la orden no tiene efecto.
- El modo mínimo del CLI no sirve como barrera: no lee la autenticación por suscripción.
- La invocación actual del puente, con un token de persona, puede leer ficheros locales no versionados que estén en su directorio de trabajo. Es la razón de S1, y AC-1.6 lo exige como control positivo.

## Criterio de abandono

Se abandona S1 y se vuelve a esta spec si, con la invocación de solo lectura, AC-1.6 o AC-1.7 no pasan con el CLI real (Claude lee lo vedado o produce un efecto), o si el CLI deja de poder ejecutarse sin la configuración local. En ese caso no se entrega una versión con la barrera solo en el prompt.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Puente (S1) | script del puente, adaptador `claude` | El adaptador `opencode` del puente queda fuera de v1: con un cliente externo dado de alta, el puente exige el adaptador `claude` y se niega a arrancar con otro |
| Cliente (S2) | script independiente | Mismo script; no depende del frontend |

### Verification protocol

- [ ] Tests pytest del puente con el CLI real para AC-1.6 y AC-1.7
- [ ] Tests del cliente contra un puente simulado con TLS
- [ ] Ningún hook nuevo; ningún cambio en la configuración de Claude Code

### Portability classification

- [x] **PURE_BASH / servicio**: independiente del frontend de agentes, salvo la restricción de adaptador de S1.

## Ficheros de esta spec

- Prueba de coherencia: `tests/bats/se535-spec-coherence.bats`.
- Registro: `docs/propuestas/planning.d/SE-535.json` y `docs/propuestas/LOG.d/SE-535-PROPOSED.md`.
- Fragmento de changelog: `CHANGELOG.d/se535-cliente-externo-conversacion.md`.
