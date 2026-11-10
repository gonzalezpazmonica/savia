---
status: PROPOSED
priority: P1
developer_type: agent-team
created: 2026-11-10
author: Savia
phase: A
risk: L4
human_surface: true
depends_on: [SE-428, SE-434]
related_specs: [SE-428, SE-432, SE-434, SE-435, SE-504, SE-505]
origin: "Pregunta interactiva de la operadora del 2026-11-10 («Spec y prueba ya»): usar su suscripción de ChatGPT/Codex como motor de Savia Space en lugar de DeepSeek, que es pago por uso. Encargo de la orquestadora, plan intensivo. Solo spec y prototipo S0."
timeline:
  - from: "2026-11-10"
    learned: "2026-11-10"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---

# SE-517 — Motor de Space con suscripción ChatGPT (OAuth)

## Lo que he entendido

### Escenas

1. Abres Space por primera vez después del cambio. En Ajustes > Motor ves «ChatGPT · sin sesión» y un botón «Entrar con ChatGPT». Lo tocas y Space te enseña una dirección corta y un código de ocho letras. Abres esa dirección en el móvil, escribes el código y aceptas con tu cuenta de ChatGPT. La pantalla de Space cambia sola a «sesión activa».
2. Le pides a Savia en Space «Resume el informe de ayer». La respuesta llega igual que antes, pero ya no gasta saldo de DeepSeek: tira de tu suscripción. No has copiado ninguna clave en ningún sitio.
3. Una semana después el acceso ha caducado por dentro. No te enteras: Space lo renueva solo. Si OpenAI rechaza la renovación, Space te dice «la sesión ha caducado, vuelve a entrar» y deja la tarea en espera. No se pasa a DeepSeek ni a un modelo local sin que lo sepas.
4. En la terminal escribes `savia-space doctor` y lees «ChatGPT: sesión activa, el acceso caduca a las 17:40, se renueva solo». En ninguna línea aparece el token. Si no hay sesión, `doctor` lo dice y te da la orden para entrar.
5. Decides dejar de usarlo. Tocas «Cerrar sesión», confirmas, y la sesión desaparece del ordenador. La próxima vez que Space tenga que pensar te dirá que no hay sesión.

### Palabras de la persona

> «Tenemos que estudiar qué posibilidades tenemos de usar Space con la subscripción de Codex (OpenAI). Investiga si sería posible. Vamos a dejar de usar DeepSeek porque es pago por uso.» — 2026-11-10

### Qué SÍ será

- Entrar con la cuenta de ChatGPT mediante un código de dispositivo, desde la app de Space o desde la terminal.
- Una sesión que vive en el espacio aislado del motor, que el agente y el modelo no pueden leer, y que se renueva sola.
- Un `doctor` que dice si hay sesión y cuándo caduca el acceso, sin enseñar nunca el token.
- Un error claro cuando no hay sesión o caduca, sin cambiar de proveedor a escondidas.
- Cerrar sesión borra la credencial del ordenador.
- Salida a red del motor limitada a los servidores de OpenAI que necesita este proveedor.

### Qué NO será

- Una clave de API de OpenAI ni pago por uso.
- Usar la sesión de ChatGPT o de Codex que la persona tenga fuera de Space (su `~/.codex` o el `auth.json` de su OpenCode).
- Un cambio de modelo: el modelo lo sigue eligiendo `tiers.space` en la configuración local.
- Un respaldo automático a DeepSeek, a Ollama o a otro proveedor.
- Una decisión sobre los términos de uso de OpenAI: eso lo confirma la operadora.

### Confirmación

- fecha: 2026-11-10
- respuesta: «pendiente»

Las escenas aún no se han enseñado a la operadora. La spec no puede pasar a APPROVED hasta que las confirme con sus palabras (SE-505).

## Slice S0 — Prototipo del login y de doctor

- prototipo: `docs/specs/assets/SE-517-prototipo.html`, un solo fichero HTML sin dependencias, con tema claro u oscuro según el sistema. Muestra seis estados: sin sesión (con el error que da Savia al pedirle algo), código de dispositivo, sesión activa, sesión caducada, cerrar sesión y la salida de terminal de `savia-space login`, `doctor` y `logout`. Con `?s=none|code|ok|expired|logout|doctor` se abre en cada estado. El código, las horas y el tipo de cuenta son ilustrativos.

S0 incluye además una sonda real, sin tocar el Space de la operadora: el binario fijado arranca con HOME y XDG temporales, `opencode auth login --standalone --method <id> openai` con el método de código de dispositivo, la persona escribe el código, y se comprueba dónde queda la credencial, qué campos tiene, que una petición mínima al modelo de `tiers.space` responde y que `auth logout` la borra. El resultado se anota en esta spec antes de S1.

### Confirmación del prototipo

- fecha: pendiente
- respuesta: «pendiente»

## Problema (observado el 2026-11-10)

La operadora paga DeepSeek por uso para el motor de Space y ya tiene una suscripción de ChatGPT que incluye Codex. Quiere que Space piense con esa suscripción.

Lo que trae el motor fijado (observado en el binario de OpenCode 2.0.32 que Space descarga y fija; lectura de cadenas y `--help`, sin red):

- La integración de OpenAI tiene métodos OAuth «Sign in with ChatGPT»: uno con navegador y retorno a `localhost:1455` (`chatgpt-browser`) y otro sin navegador por código de dispositivo (`chatgpt-headless`), que pide un código a `https://auth.openai.com/api/accounts/deviceauth/usercode`, enseña `Enter code: …` con la dirección `https://auth.openai.com/codex/device` y sondea `…/deviceauth/token`. El identificador exacto que acepta `--method` se fija en S0.
- La renovación del acceso la hace el propio motor contra `https://auth.openai.com/oauth/token`. Las peticiones de modelo van a `https://chatgpt.com/backend-api/codex`.
- Modelos de la familia Codex en el binario: `gpt-5-codex`, `gpt-5.2-codex`, `gpt-5.3-codex`, `gpt-5.3-codex-spark`.
- CLI: `opencode auth login [--method ID] [--standalone | --server URL] [<target>]`, `auth list | logout | export | import`. El login habla con un servidor de OpenCode (el servicio de fondo, uno privado con `--standalone` o el de `--server`), así que puede apuntarse al servidor del motor de Space.

Lo que hoy lo impide en Space (observado en el repo de Space, main del 2026-11-10):

1. El motor corre con HOME y XDG propios (`space-engine/src/launcher_v2.rs`, `engine_env_with`, rutas de `Paths::of`). No ve ninguna credencial de la persona y no hay ningún paso de Space que inicie sesión dentro de ese espacio.
2. El `auth.json` de OpenCode de la persona está catalogado como credencial y se tapa (`space-orchestrator/src/paths.rs`, lista `FILE_SEQS`). Es correcto y no se cambia.
3. El proxy de secretos solo sirve entradas `type: api` de `auth.json` (`space-proxy/src/secret.rs`, almacén `opencode-auth`). Una entrada OAuth (acceso, renovación, caducidad) no tiene camino.
4. `space-engine/src/env_policy.rs` solo deja pasar variables nombradas. No hay variable que sirva aquí, y no debe haberla: el token no viaja por el entorno.
5. `space-server/src/inference.rs` (D-MODEL-CLOUD) no tiene lista blanca de nube: `openai` pasa como cualquier proveedor no local. Correcto para este caso.
6. Red: el espacio del motor se crea sin `--unshare-net` (decisión D-MED-5 de SE-434, `space-engine/src/engine_ns.rs`, `bwrap_args`); el motor tiene salida libre a internet y la única restricción son `OPENCODE_DISABLE_AUTOUPDATE` y `OPENCODE_DISABLE_MODELS_FETCH`. El bash del agente sí va sin red. No existe hoy una lista de hosts de salida para el motor.

## Objetivo

Que Space use la suscripción de ChatGPT de la persona como proveedor del motor, con un login visible y sencillo, la credencial guardada solo en el espacio del motor, renovación automática, estado legible en `doctor`, cierre de sesión que borra, y ningún cambio silencioso de proveedor.

## Qué decide esta spec

- **D1. Login en el espacio del motor por código de dispositivo.** Space ejecuta `opencode auth login --method <código de dispositivo> openai` contra el servidor del motor (o con HOME y XDG del motor), nunca con el HOME de la persona. Se elige código de dispositivo y no el método con navegador porque Space puede estar en otro equipo (escucha por VPN) y la persona entra desde el móvil; el retorno a `localhost:1455` no llegaría. La app enseña la dirección y el código; la terminal ofrece `savia-space login chatgpt`.
- **D2. La credencial vive en el `auth.json` del espacio del motor y la usa solo el proceso de OpenCode.** Permisos 0600, dentro del directorio de datos del motor. El bash del agente y las herramientas de lectura del motor no la alcanzan (misma máscara que las demás credenciales, FS-2b de SE-434). El modelo nunca la recibe: solo recibe el prompt. Alternativa descartada: que el proxy de secretos inyecte el token. Obligaría a reescribir la renovación OAuth y las peticiones a `chatgpt.com` fuera de OpenCode; se reconsidera solo si S0 demuestra que la máscara no puede separar al proceso del motor de sus herramientas.
- **D3. Renovación delegada en el motor; Space solo observa.** OpenCode renueva contra `auth.openai.com/oauth/token`. Space lee de la credencial únicamente los metadatos de caducidad y si la última renovación falló. Si la renovación falla, el turno termina con un error que nombra la causa y la acción («vuelve a entrar con ChatGPT»), y la tarea queda en espera.
- **D4. `doctor` informa sin revelar.** Línea `ChatGPT`: `sin sesión`, `sesión activa · acceso caduca <hora> · se renueva solo` o `caducada · <motivo>`. Si `tiers.space` apunta a `openai` y no hay sesión, `doctor` sale con estado de fallo. Nunca imprime el token ni un fragmento ni un hash parcial.
- **D5. Logout borra.** `savia-space logout chatgpt` y el botón de la app ejecutan `opencode auth logout` en el espacio del motor y después comprueban que no queda entrada de `openai` en su `auth.json`; si queda, Space la elimina y lo dice.
- **D6. Sin respaldo silencioso.** El proveedor y el modelo los decide `tiers.space` (configuración local, fuera del repo). Sin sesión o con sesión caducada, Space no cae a DeepSeek, a Ollama ni a otro proveedor. Cambiar de proveedor es una decisión de la persona en su configuración.
- **D7. Salida a red mínima del motor con este proveedor.** Con el proveedor `openai` por suscripción, el motor solo puede abrir conexiones a `auth.openai.com` y `chatgpt.com`. Esto revisa D-MED-5 de SE-434 solo para este proveedor y se implementa en un slice propio; hasta que esté, `doctor` dice «salida de red sin restringir». Los hosts exactos se confirman en S0 observando el tráfico de la sonda.
- **D8. Términos de OpenAI.** Savia no ha leído directamente los términos de uso de la suscripción de ChatGPT respecto a clientes de terceros. La operadora los confirma antes de que esta spec pase a IMPLEMENTED; si no lo permiten, la spec se cierra como REJECTED y no se usa.

## Plan por slices

| Slice | Contenido | Repo | Puerta de salida |
|---|---|---|---|
| S0 | Prototipo HTML (este PR) y sonda real con HOME temporal; anota método, campos de la credencial, hosts y caducidades observadas | Savia (spec) | Escenas y prototipo confirmados por la operadora |
| S1 | `savia-space login chatgpt` y `logout chatgpt` en el espacio del motor; credencial 0600; máscara para el agente; sin variables nuevas | Space | AC-1..AC-6 |
| S2 | `doctor` con estado de sesión y fallo cuando el tier pide `openai` sin sesión; error claro en el turno; sin respaldo | Space | AC-7..AC-11 |
| S3 | Pantalla «Ajustes > Motor» en la app (estados del prototipo) | Space | AC-12, AC-13 |
| S4 | Salida a red del motor limitada a los hosts de OpenAI con este proveedor | Space | AC-14, AC-15 |
| S5 | Puesta en marcha en la máquina de la operadora: cambio de `tiers.space` (lo hace ella) y retirada de la clave de DeepSeek del motor | local | AC-16, AC-17 |

S1 y siguientes no empiezan sin la confirmación de S0.

## Criterios de aceptación

### Login y almacenamiento (S1)

- [ ] **AC-1** `savia-space login chatgpt` muestra la dirección y el código del dispositivo y, al completar la persona el paso en OpenAI, deja una entrada `openai` en el `auth.json` del directorio de datos del motor, con permisos 0600. Test con un servidor OAuth falso local que imita `usercode` y `token`.
- [ ] **AC-2** (negativo) Tras el login, el `auth.json` del HOME real de la persona y su `~/.codex` no cambian (mismo hash antes y después).
- [ ] **AC-3** (negativo) El token no aparece en ningún log de Space ni del motor, ni en la salida de `login`, `doctor` o `logout`: test que siembra un token centinela en el servidor falso y busca la cadena y sus 12 primeros caracteres en todos los ficheros de log y en stdout/stderr.
- [ ] **AC-4** (negativo) El token no está en el entorno del motor ni en el del bash del agente: `env` de ambos procesos sin el centinela ni variables `OPENAI_*`; `env_policy.rs` no gana entradas.
- [ ] **AC-5** (negativo) Una herramienta de lectura o el bash del agente que intenta leer el `auth.json` del motor obtiene un fichero vacío o un error; el control sin máscara sí lo lee (la prueba mide algo).
- [ ] **AC-6** Si la persona no completa el código antes de que caduque, `login` termina con «el código ha caducado, vuelve a intentarlo» y no deja entrada parcial.

### Estado, caducidad y sin respaldo (S2)

- [ ] **AC-7** `doctor` con sesión válida imprime `sesión activa` y la hora de caducidad del acceso leída de la credencial; con la credencial ausente imprime `sin sesión` y la orden para entrar.
- [ ] **AC-8** (negativo) Con `tiers.space` en `openai` y sin sesión, `doctor` sale con código distinto de 0, y un turno de Space termina con el error «no hay sesión de ChatGPT» sin ninguna petición a otro proveedor (el servidor falso de DeepSeek del test registra cero peticiones).
- [ ] **AC-9** Con el acceso caducado y la renovación aceptada por el servidor falso, el turno se completa y `doctor` muestra la nueva caducidad.
- [ ] **AC-10** (negativo) Con el acceso caducado y la renovación rechazada, el turno termina con «la sesión ha caducado, vuelve a entrar», la tarea queda en espera y no hay petición a otro proveedor.
- [ ] **AC-11** `doctor` con una credencial malformada o ilegible dice `estado desconocido` y sale con fallo (fail-closed), sin imprimir su contenido.

### App (S3)

- [ ] **AC-12** La pantalla «Ajustes > Motor» reproduce los estados del prototipo confirmado (sin sesión, código, activa, caducada, cerrar sesión) con textos en lenguaje llano y sin siglas internas.
- [ ] **AC-13** Logout: tras confirmar, no queda entrada `openai` en el `auth.json` del motor (test) y la pantalla vuelve a «sin sesión»; cancelar no borra nada (negativo).

### Red (S4)

- [ ] **AC-14** Con el proveedor `openai` por suscripción, el motor alcanza `auth.openai.com` y `chatgpt.com` y no alcanza otro host de prueba (por ejemplo `1.1.1.1:53`), medido desde dentro del espacio del motor.
- [ ] **AC-15** (negativo) Si la restricción de red no puede aplicarse en la máquina, `doctor` lo dice («salida de red sin restringir») y no lo da por cumplido.

### Puesta en marcha (S5)

- [ ] **AC-16** La operadora confirma por escrito, con fecha, que ha leído los términos de uso de OpenAI para su suscripción y que permiten este uso. Sin esa confirmación la spec no pasa a IMPLEMENTED.
- [ ] **AC-17** Usabilidad: la operadora entra con ChatGPT desde el móvil siguiendo solo lo que ve en pantalla, sin órdenes de terminal, y Space contesta una petición real con el modelo de `tiers.space`.

## Fuera de alcance

- Leer o reutilizar sesiones de ChatGPT, Codex u OpenCode que la persona tenga fuera de Space.
- Claves de API de OpenAI y facturación por uso.
- Elegir el modelo concreto: `tiers.space` sigue siendo local y de la persona.
- Implementar en Space la renovación OAuth o el cliente de `chatgpt.com` (lo hace el motor).
- Cambiar la política de red del motor para otros proveedores.
- Retirar DeepSeek del código de Space: solo deja de configurarse en la máquina de la operadora.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Los términos de OpenAI no permiten usar la suscripción desde un cliente de terceros; Savia no los ha leído directamente | AC-16: confirma la operadora antes de IMPLEMENTED; si no, REJECTED |
| Dependencia del OAuth de OpenAI y de su endpoint de Codex, que pueden cambiar sin aviso | El motor está fijado por versión; S0 anota hosts y campos; `doctor` y AC-10 hacen visible el fallo en vez de cambiar de proveedor |
| Límites de uso de la suscripción: se agotan y Space se queda sin motor | Error claro en el turno; la persona decide si cambia `tiers.space` |
| La máscara de credenciales no separa al proceso del motor de sus propias herramientas | AC-5 lo mide; si falla, se reabre D2 (token por el proxy) |
| El código de dispositivo lo puede introducir otra persona si se comparte la pantalla | El código caduca (AC-6); la cuenta que acepta es la que queda en `doctor` |
| Restringir red rompe la renovación si OpenAI usa otros hosts | S0 observa los hosts reales; AC-14 mide la renovación con la restricción puesta |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Login, logout y credencial del motor de Space | No interviene: Space es un proceso Rust propio | Motor fijado de Space (OpenCode 2.0.32), integración `openai` con OAuth de ChatGPT |
| `doctor` y estado en la app | Proceso Rust de Space | Igual |
| Política de red del espacio del motor | No aplica | Espacio del motor de SE-434 (bwrap) |
| Selección de modelo | Sin cambio: tiers locales | `tiers.space`, sin cambio de esquema |

### Verification protocol

- [ ] Funciona con el motor OpenCode fijado de Space; ningún camino depende de Claude Code
- [ ] Tests de Space con servidor OAuth falso cubren login, renovación, caducidad, logout y ausencia del token en logs y entorno
- [ ] No añade hooks de Savia ni variables de entorno nuevas al motor

### Portability classification

- [x] **DUAL_BINDING**: el cambio vive en Space y en su motor OpenCode; los frontends de agentes de Savia no cambian.

## Aprobación

Tier 4: cambia dónde se guarda una credencial de la persona, por dónde sale tráfico del ordenador y qué proveedor procesa sus datos. Necesita la confirmación de las escenas y del prototipo, y la aprobación expresa de la operadora. Ningún agente la aprueba ni la fusiona.
