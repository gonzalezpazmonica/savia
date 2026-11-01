# Modelo de amenazas del canal móvil (SE-490, AC-6)

> Alcance: la API local que sirve `soul serve` a la app de Savia Space por la VPN del operador. Código revisado: rama `agent/s490-core-20261023` (`src/api/`, `src/cli/cli.ts`, `src/startup/autostart.ts`).
> Queda fuera la parte Android (cómo guarda la app el token y cómo fija el certificado): no está en este repositorio y hay que revisarla aparte.
> Cada punto dice qué garantiza el código, con qué test se comprueba y qué no está cubierto. Los huecos van a la lista de P1 y P2 del final, con el arreglo propuesto. Este informe no cambia el núcleo: los arreglos los hace otra parte.
> Pendiente: revisión de la revisora de seguridad, como exige AC-6.

## Activos y frontera de confianza

- **Activos:** datos de trabajo N4 que responde la API (títulos, fuentes, referencias), tokens de los dispositivos, clave privada TLS de la instalación y el control (correcciones, modo de atención, nivel de detalle).
- **Frontera de confianza:** la cuenta de usuario del operador en el portátil. Quien puede escribir en su directorio de datos puede cambiar la configuración, emparejar dispositivos o leer la clave TLS. Este modelo no defiende de un atacante que ya tiene esa cuenta.
- **Atacantes considerados:**
  1. otro equipo de la VPN o de una red donde aparezca la misma dirección;
  2. alguien que observa o manipula el tráfico entre el móvil y el portátil, incluido el proveedor de la VPN;
  3. quien tiene en la mano el móvil perdido o robado;
  4. un frontend de agente en el portátil que intenta sacar el token.

## 1. Escucha solo en las direcciones configuradas

**Lo que hace el código.**

- `api.listen` está vacío por defecto. Sin direcciones, `serve` no arranca y lo dice (`src/core/config.ts:63`, `src/api/serve.ts:24-30`).
- Solo se aceptan IP literales. Se rechazan:
  - los nombres de host;
  - cualquier escritura de la dirección no especificada (`0.0.0.0`, `::`, `0::`…);
  - IPv6 con zona;
  - IPv4 incrustada o mapeada en IPv6, incluso en hexadecimal (`src/api/listen.ts:14-39`).
- Hay un servidor por dirección, con `ipv6Only` en las IPv6, para que una IPv6 no acabe aceptando IPv4 (`src/api/listen.ts:48-71`).
- Si la dirección no existe en el equipo, la escucha falla con `EADDRNOTAVAIL` y `serve` termina con código 1. Comprobado a mano en esta revisión con una dirección de documentación (192.0.2.77).

**Tests.** `test/listen.test.ts:7,17` (rechazos) y `:34` (test de puertos: la dirección configurada responde y ninguna otra interfaz del equipo, ni `127.0.0.2` ni `::1`, acepta conexión). También `test/server.test.ts:32,41` y `test/serve.test.ts:47`.

**No cubierto.** Soul no comprueba **a qué interfaz pertenece** la dirección. Si la VPN cae y la misma IP aparece en otra red (rangos como `100.64.0.0/10` o `10.0.0.0/8` se repiten en redes de hoteles o de clientes), Soul escucharía allí. TLS y el token siguen siendo obligatorios, pero el canal deja de estar limitado a la VPN → **P2-1**.

## 2. TLS con certificado propio

**Lo que hace el código.**

- Solo HTTPS: sin certificado no se crea el servidor (`src/api/server.ts:142`). Versión mínima TLS 1.3 (`src/api/server.ts:612`).
- El certificado X.509 v3 es propio de la instalación y autofirmado:
  - clave EC P-256;
  - `CA:false`, uso «firma digital», `serverAuth`;
  - SAN con las IP de escucha;
  - 397 días de validez (`src/api/cert.ts:63-86`).
- La clave privada se guarda en `tls/key.pem` con permisos 0600 (`src/core/store.ts:46-57`).
- La app fija la **huella SPKI** (`sha256/<base64>`) que se muestra al emparejar y al arrancar `serve` (`src/api/cert.ts:88-92`, `src/api/serve.ts:64`, `src/cli/cli.ts:400`).

**Tests.** `test/cert.test.ts:11` (certificado válido para las IP), `:23` (TLS real: el cliente que fija el certificado conecta y uno sin él es rechazado) y `:38` (se reutiliza y se regenera si cambian las direcciones).

**No cubierto.**

- Al regenerar el certificado, por cambio de direcciones o porque quedan menos de 30 días, se genera **una clave nueva** (`src/api/cert.ts:108`, que llama a `generateKeyPairSync` en `:65`). La huella cambia y la app deja de conectar hasta que el operador la vuelva a introducir. Es un fallo cerrado, pero sin aviso claro: la app solo ve «sin contacto» → **P2-2**.
- El certificado solo se comprueba al arrancar `serve`. Un `serve` que lleva más de 397 días sin reiniciar sirve un certificado caducado → **P2-3**.
- La comprobación de la huella la hace la app. Si la app no la fija bien, TLS no protege de un intermediario dentro de la VPN. Hay que verificarlo en la revisión de la parte Android → **P1-3**.
- El certificado anuncia `CN=Savia Soul Continuidad`: cualquier equipo de la VPN que abra TLS sabe qué programa escucha. Es un dato menor → **P2-4**.

## 3. Emparejamiento

**Lo que hace el código.**

- Se empareja **en el terminal del portátil** (`soul pair <nombre>`), no por la red: la API no tiene ningún endpoint de emparejamiento (`src/api/server.ts:561-610`).
- El token tiene 256 bits aleatorios y se muestra una sola vez. En disco solo queda su SHA-256 (`src/api/devices.ts:33-38`).
- Cada token va ligado a un operador: un dispositivo no ve los datos de otro perfil (`test/api/contrato.test.mjs:234`).
- `pair`, `unpair` y `devices` no se pueden ejecutar desde un frontend de agente (`src/cli/cli.ts:52,188-190`). Así, el token no pasa por el modelo de un agente.

**Tests.** `test/devices.test.ts:12` (el token se da una vez; en disco, solo el hash) y `:39`; `test/cli.test.ts:148` (órdenes vetadas al frontend de agente).

**No cubierto.**

- El token se imprime en la salida estándar, y en JSON con `--json`. Puede quedar en el historial del terminal o en un fichero si se redirige → **P2-5**.
- No hay código de emparejamiento de un solo uso: lo que se teclea en la app es el token permanente del dispositivo. El README del proyecto dice «token de un solo uso», y eso no es exacto → **P2-6**.
- La detección del frontend de agente es de mejor esfuerzo, por variables de entorno. Un agente que las borre podría ejecutar `pair` y leer el token (límite conocido del README) → **P2-7**.

## 4. Revocación del token por dispositivo

**Lo que hace el código.**

- `soul unpair <id>` marca `revoked_at` en `devices.json` (`src/api/devices.ts:41-48`, `src/cli/cli.ts:406-411`).
- `serve` relee `devices.json` en **cada petición** (`src/api/serve.ts:53-56`, `src/api/devices.ts:50-57`). La revocación vale en el acto, sin reiniciar.
- Un dispositivo revocado recibe `401` con `DEVICE_REVOKED` en todas las operaciones. Los demás siguen funcionando (`src/api/server.ts:534,623`).
- Si `devices.json` está corrupto, la lectura lanza un error y la API responde 503: falla cerrada (`src/core/store.ts:64-67`, `src/api/server.ts:621`).

**Tests.** `test/devices.test.ts:21,30`; `test/serve.test.ts:55` (el dispositivo revocado recibe 401 con el servicio en marcha); `test/api/contrato.test.mjs:188`.

**No cubierto.**

- Los tokens no caducan ni rotan en producción. La caducidad que prueba `test/api/contrato.test.mjs:213` es una opción del servidor solo para tests (`caducidadToken`, `src/api/server.ts:540`). `serve` no la usa → **P2-8**.
- Solo se puede revocar desde el portátil. Ver el punto 5.

## 5. Móvil perdido o robado

**Situación.** El móvil lleva el token y, casi siempre, también la VPN configurada. La API **no verifica la prueba DPoP**: exige la cabecera, pero no comprueba la firma (`src/api/server.ts:526-542`; límite conocido del README). El token funciona, por tanto, como un token portador.

**Qué puede hacer quien tiene el móvil, mientras no se revoque:**

- leer Q1–Q4 con el nivel de detalle vigente;
- **subir el nivel de detalle hasta el máximo de la instalación** (`PUT /detalle`, `src/api/server.ts:406-410`);
- marcar elementos como resueltos, que desaparecen de la vista del operador;
- cambiar el modo de atención y la configuración de avisos.

No puede emparejar otros dispositivos, cambiar `api.listen`, leer credenciales de fuentes ni actuar sobre las fuentes: v1 es de solo lectura.

**Procedimiento (para el documento de transparencia y la app):**

1. En el portátil: `soul devices` y `soul unpair <id>`. Vale en el acto.
2. En la consola de la VPN: retirar el nodo del móvil.
3. Si no hay acceso al portátil: retirar el nodo de la VPN corta el canal; `soul stop` en cuanto haya acceso.
4. Revisar las correcciones hechas desde el móvil (`soul export`, `ledger.jsonl`) y deshacer las ilegítimas con `soul correct <id> mio`.

Mientras P1-1 no esté arreglado, conviene fijar `detail.max` en `titulos` o `recuentos`: limita lo que vería quien tenga el móvil.

**No cubierto.**

- Sin DPoP verificado, un token copiado del móvil vale desde cualquier equipo de la VPN → **P1-1**.
- No hay revocación remota, y el libro de correcciones no registra el dispositivo que hizo cada corrección. No se puede saber qué deshacer → **P1-2**.
- Cómo guarda la app el token (Android Keystore o no) y si exige el bloqueo del móvil no se ha revisado → **P1-3**.

## 6. Reenvío de solicitudes y fuerza bruta

**Lo que hace el código.**

- **Fuerza bruta del token:** el espacio es de 2^256. La comparación se hace sobre el SHA-256, en tiempo constante (`src/api/devices.ts:50-57`).
- **Límite de peticiones:** 120 peticiones cada 10 s por dirección de origen, aplicado **antes** de autenticar, así que también cuentan las peticiones sin token (`src/api/serve.ts:59`, `src/api/server.ts:511-525,562`). Hay un tope de 1024 orígenes en memoria y, por encima, el servidor responde 429: falla cerrado (`src/api/server.ts:516-519`).
- **Cuerpos:** como máximo 16 KiB. Se validan contra el OpenAPI y se rechazan parámetros desconocidos o repetidos (`src/api/server.ts:543-559`).
- **Reenvío de solicitudes:**
  - TLS 1.3 impide capturarlas desde la red.
  - Las correcciones son idempotentes (`test/api/contrato.test.mjs:394`).
  - El cursor del sondeo lleva una etiqueta derivada de un secreto que se genera en cada arranque y del operador (SHA-256 truncado). Un cursor ajeno o manipulado recibe 400 o 410, nunca datos (`src/api/server.ts:412-431`, `test/api/contrato.test.mjs:323`).
- Las respuestas llevan `Cache-Control: no-store` (`src/api/server.ts:614`).

**Tests.** `test/server.test.ts:64` (agotar el cupo desde una dirección no deja sin servicio a otra), `test/api/contrato.test.mjs:251` (429 con `Retry-After`) y `:213` (401 genérico ante token desconocido, cabecera ausente, esquema `Bearer` o falta de DPoP).

**No cubierto.**

- Un token obtenido fuera de banda (punto 5) se puede reutilizar sin límite, porque no hay DPoP ni `nonce` → **P1-1**.
- No hay límite de conexiones ni tiempos de espera propios. `server.maxConnections`, `headersTimeout`, `requestTimeout` y `keepAliveTimeout` quedan con sus valores por defecto de Node.js. Un equipo de la VPN puede abrir muchas conexiones TLS lentas, y el límite de peticiones no cuenta los saludos TLS → **P2-9**.
- El límite es por IP de origen. Dentro de una VPN de malla, la IP del par es estable y la autentica la VPN, así que basta. Detrás de un NAT, varios dispositivos compartirían cupo. Nota, sin prioridad.

## 7. Si la VPN cae o la dirección cambia

| Situación | Qué pasa hoy | Cubierto por |
|---|---|---|
| La VPN aún no está levantada al arrancar | `listen` falla con `EADDRNOTAVAIL` y `serve` sale con código 1. En Linux, `systemd --user` reintenta cada 30 s (`Restart=on-failure`, `src/startup/autostart.ts:59-60`). En macOS, `launchd` reinicia porque `KeepAlive` lleva `SuccessfulExit=false` (`:87`). **En Windows, la tarea de inicio de sesión no reintenta** (`:105`): el servicio queda caído hasta el siguiente inicio de sesión | Prueba manual de esta revisión; sin test automático → **P2-10** |
| La VPN cae con `serve` en marcha | El socket sigue ligado a una dirección que ya no recibe tráfico. La app no conecta y debe decir «sin contacto desde…» (eso lo hace la app). Ningún dato sale por otra interfaz | Comportamiento del sistema operativo; sin test |
| La VPN vuelve con la misma IP | Según el sistema operativo, el socket vuelve a recibir o hay que reiniciar `serve`. **No verificado** | → **P2-11** |
| La VPN asigna otra IP | `serve` sigue en la antigua. El operador tiene que editar `api.listen` y reiniciar. El certificado se regenera con clave nueva, así que hay que volver a introducir la huella en la app | `test/cert.test.ts:38`; → **P2-2**, **P2-11** |
| La IP de la VPN aparece en otra red | Soul escucharía en esa red. TLS y el token siguen siendo obligatorios | → **P2-1** |

## 8. Qué ve el proveedor de la VPN

El proveedor de la VPN elegida por el operador (por ejemplo, el plano de control de una VPN de malla o sus servidores de retransmisión) ve los metadatos de conexión: qué nodos hay, cuándo se hablan y cuánto tráfico intercambian.

El contenido viaja dentro de TLS 1.3 de extremo a extremo entre la app y Soul, por encima del cifrado de la propia VPN. Ni un proveedor capaz de descifrar la VPN vería datos de trabajo sin romper TLS o la huella fijada (punto 2). Del código solo se puede verificar la parte TLS; el resto depende del producto VPN.

## Lista de huecos

### P1 (antes del piloto, AC-7)

| Id | Hueco | Arreglo propuesto |
|---|---|---|
| P1-1 | La prueba DPoP no se verifica. El token del dispositivo funciona como portador y se puede reutilizar desde cualquier equipo de la VPN | Verificar la prueba DPoP (RFC 9449): firma con la clave pública registrada al emparejar, `htm`/`htu`/`iat`, `jti` con ventana anti-reenvío en memoria y `ath` del token. Al emparejar, guardar la clave pública del dispositivo junto al hash del token. Tests: prueba de otra clave → 401; `jti` repetido → 401; prueba caducada → 401 |
| P1-2 | Las correcciones y cambios hechos desde un dispositivo no registran cuál fue. Tras perder el móvil no se puede saber qué deshacer | Anotar el `device` en cada corrección del libro y en el registro de atención y detalle. Añadir una orden que liste y deshaga las correcciones de un dispositivo |
| P1-3 | No se ha revisado la app: almacenamiento del token (Android Keystore), fijación real de la huella SPKI y bloqueo del dispositivo | Revisión de la parte Android con los mismos criterios: test que conecta contra un certificado distinto y falla, y token no exportable |

### P2

| Id | Hueco | Arreglo propuesto |
|---|---|---|
| P2-1 | No se comprueba a qué interfaz pertenece la dirección de escucha | `api.interface` opcional (por ejemplo `tailscale0` o `utun*`). Si la dirección no está en esa interfaz, `serve` cierra la escucha y avisa. Comprobar `networkInterfaces()` cada minuto |
| P2-2 | Cambiar las direcciones o renovar el certificado rota la clave, y la huella cambia sin aviso | Conservar la clave y emitir un certificado nuevo con la misma SPKI. Si hay que rotar, avisar en `soul status` y en la siguiente respuesta a la app antes del cambio |
| P2-3 | El certificado solo se renueva al arrancar | Comprobar la caducidad en el tic de 5 minutos y recargar el contexto TLS (`server.setSecureContext`) |
| P2-4 | El `CN` del certificado identifica el producto ante cualquier par de la VPN | `CN` neutro o vacío; la identidad ya la da la huella |
| P2-5 | El token sale por la salida estándar y en `--json` | Mostrarlo solo en un terminal interactivo, sin `--json`, o como código QR. Avisar de que no se redirija |
| P2-6 | El README dice «token de un solo uso» y no lo es | Corregir el README, o introducir un código de emparejamiento de un solo uso con caducidad corta que la app canjea por el token |
| P2-7 | Un agente que borre las variables de entorno puede ejecutar `pair` | `pair` y `unpair` solo con terminal interactivo (`process.stdin.isTTY`) y confirmación tecleada |
| P2-8 | Los tokens de dispositivo no caducan ni rotan | Caducidad configurable (por ejemplo 90 días) con renovación desde la app mientras el dispositivo siga emparejado |
| P2-9 | No hay límite de conexiones ni tiempos de espera propios | Fijar `maxConnections` (por ejemplo 32), `headersTimeout` 10 s, `requestTimeout` 15 s y `keepAliveTimeout` 5 s, con un test de conexiones lentas |
| P2-10 | En Windows, la tarea de inicio de sesión no reintenta si la VPN no está lista | `RestartOnFailure` en el XML de la tarea (intervalo de 1 minuto, varios reintentos) o reintento interno de `serve` mientras la dirección no exista, con test |
| P2-11 | No se ha verificado el comportamiento al volver la VPN, ni hay vigilancia de cambio de dirección | Reintento interno de la escucha: si la dirección desaparece, cerrar; si vuelve, abrir de nuevo. Test con una dirección que se añade y se quita (en Linux, `127.0.0.x` como sustituto) |

## Cómo se ha verificado

- Lectura del código citado en la rama del núcleo.
- Prueba de escucha en una dirección ausente: `EADDRNOTAVAIL`.
- Contraste de cada garantía con su test, citado en cada punto.
- Test de coherencia de este informe y del documento de transparencia: `test/it-pack.test.ts`.
