# Soul Continuidad v1 (SE-490)

Gemelo operativo de solo lectura, por usuario y sin privilegios. Responde cuatro preguntas sobre las fuentes de trabajo del operador:

- Q1: qué tengo abierto;
- Q2: qué depende de mí;
- Q3: qué cambió desde un instante;
- Q4: qué compromisos con fecha hay.

Se consulta desde la CLI `soul` y desde la app de Savia Space emparejada, por la VPN del propio operador.

Además escribe primero (SE-504 §3, «Tu día con Savia»): un resumen de la mañana a la hora de `resumen_inicio` y seguimientos en cada latido (lo que espera respuesta desde hace más de N horas, lo que vence mañana y las dependencias nuevas), en lenguaje natural y con como mucho 3 asuntos por mensaje. Cada asunto trae una acción propuesta que solo se ejecuta si la persona la aprueba. Lógica en `src/core/gemelo.ts`; API en `GET /gemelo`, `PUT /gemelo/leido`, `POST /gemelo/acciones/{id}/decision` y `GET|PUT /gemelo/config`.

Es TypeScript sobre el runtime oficial de Node.js (≥ 22.6). No tiene dependencias de ejecución, ni módulos nativos, ni ejecutables propios. Spec: `docs/specs/SE-490-soul-continuity-work-laptop.spec.md`.

## Estructura

| Ruta | Qué es |
|---|---|
| `src/contract/` | Contrato compartido: afirmaciones (`claims.ts`), adaptadores (`adapter.ts`), semántica (`CONTRATO.md`), OpenAPI de la app y gramática de órdenes |
| `src/core/` | Núcleo: instantánea con TTL, libro de correcciones por operador (con el dispositivo de cada corrección), almacén atómico, STOP durable, configuración y perfil activo |
| `src/core/connectors.ts` | Registro de los adaptadores reales: solo los que el operador nombra en `connectors.enabled`; transporte HTTPS de solo lectura; revocación por adaptador |
| `src/adapters/` | Adaptadores de API (Microsoft 365, Google, Jira, Azure DevOps, GitHub) |
| `src/web/` | Adaptador `web`: navegador instalado en un perfil dedicado, recetas y cortafuegos (paquete aparte con `playwright-core`) |
| `src/attention/` | Política de atención de SE-490 (librería pura con sus evals y mutantes) |
| `src/cli/` | CLI `soul` (`bin/soul.mjs` la lanza) |
| `src/api/` | API local: HTTPS con certificado propio, dispositivos emparejados, escucha solo en las direcciones configuradas |
| `src/credentials/` | El único almacén de credenciales: el del sistema (Credential Manager, llavero, Secret Service) con un índice sin secretos de todo lo que guarda Soul |
| `src/startup/` | Arranque sin administrador (`systemd --user`, `LaunchAgent`, tarea de inicio de sesión) |
| `bench/` | Banco de continuidad con verdad escrita antes de ejecutar (80 escenarios, dobles, mutantes) |

## Uso

Instalación en un paso (Linux y macOS; sin git: Code → Download ZIP; detalle en `docs/instalar.md`):

```
bash install.sh                      # Node.js LTS oficial si hace falta (sin sudo), la orden «soul» y, si preguntas «s», su PATH
soul setup                           # perfil, VPN, comprobaciones, servicio de usuario y emparejar el móvil
soul doctor                          # comprobaciones con la orden exacta de cada arreglo
```

Órdenes sueltas:

```
node bin/soul.mjs init trabajo --email yo@example.test   # perfil sin fuentes ni adaptadores; escucha en la VPN detectada
node bin/soul.mjs listen --detect                         # escucha en la IP de la VPN, sin editar config.json
node bin/soul.mjs login github --token-stdin              # token al almacén del sistema
node bin/soul.mjs status             # sin red, en frío
node bin/soul.mjs q1 | q2 | q4       # preguntas
node bin/soul.mjs q3 --since 2026-10-30T09:00:00Z
node bin/soul.mjs why <id>           # ¿por qué lo sé?
node bin/soul.mjs correct <id> resuelto
node bin/soul.mjs stop | resume      # fail-safe que sobrevive a reinicios
node bin/soul.mjs pair               # emparejar la app: QR, IP, puerto, clave de 10 min y huella corta
node bin/soul.mjs serve              # API para la app
```

La configuración vive en el directorio de datos del usuario: `config.json`, con `active_profile`, `profiles`, `detail`, `agent_frontend` y `api.listen`. Ese directorio es:

- en Linux, `~/.local/share/savia/soul-continuity`;
- en macOS, `~/Library/Application Support/Savia/soul-continuity`;
- en Windows, `%LOCALAPPDATA%\Savia\soul-continuity`.

Sin perfil activo, Soul responde «no sé quién eres». Sin direcciones en `api.listen`, `serve` no arranca. Instalación paso a paso para cualquier operador: [`docs/instalar.md`](docs/instalar.md).

## Garantías y dónde se prueban

| Garantía | Prueba |
|---|---|
| Banco AC-3: precisión ≥ 90 % por pregunta y todos los escenarios de garantía | `npm run bench`, `test/bench-impl.test.ts` |
| Lo revocado no vuelve; libro por operador | `test/engine.test.ts`, `test/cli.test.ts` |
| AC-4d: por un frontend de agente solo salen recuentos | `test/cli.test.ts`, `test/config.test.ts` |
| AC-5: revocar borra caché delta, perfil web y los tokens de todas las variantes; desinstalar borra todos los tokens indexados y no deja estado | `test/ac5-integracion.test.ts`, `test/connectors.test.ts`, `test/cli.test.ts` |
| H-1: nada activo por defecto; solo los adaptadores que nombra el operador | `test/connectors.test.ts` |
| Banco AC-3 del núcleo con los adaptadores reales de API contra los dobles | `test/bench-impl.test.ts` |
| Canal: DPoP verificado y clave ligada al dispositivo, tokens con caducidad, límites de conexión | `test/dpop.test.ts`, `test/devices.test.ts`, `test/serve.test.ts` |
| Emparejamiento directo por clave (soul-pair-v2): vectores comunes con la app, rechazo de v1, intermediario, bloqueo, caducidad | `test/pairing.test.ts`, `src/contract/vectores-emparejamiento.json` |
| QR de `soul pair`: vectores de la norma y decodificador independiente; terminal y PNG | `test/qr.test.ts` |
| Punta a punta: init, login, serve, pair por clave, Q1–Q4 por cursor, corrección, revoke, unpair y uninstall | `test/e2e.test.ts`, `test/instalar.test.ts` |
| 0 tokens en disco: el secreto solo por stdin al almacén del sistema; el núcleo descarta la lectura de un adaptador que devuelve el token | `test/credentials.test.ts`, `test/engine.test.ts`, `test/cli.test.ts` |
| Solo escucha en las direcciones configuradas (test de puertos) | `test/listen.test.ts` |
| Contrato de la app: 27 tests de Labs contra el servidor del producto | `test/api/contrato.test.mjs` |
| STOP durable | `test/failsafe.test.ts`, `test/serve.test.ts` |
| Gemelo (SE-504 AC-G1–G4): resumen a su hora, calla sin nada que decir, presupuesto de avisos, descanso, ninguna acción sin aprobación, nada de texto de terceros con `recuentos` | `test/gemelo.test.ts`, `test/gemelo-api.test.ts` |

```
npm test          # todos los tests
npm run bench     # banco contra el núcleo
npm run typecheck # tsc --strict (necesita npm install)
```

## Límites conocidos (v1)

- **DPoP**: la API verifica la prueba (ES256, `htm`, `htu`, `iat` ±60 s, `jti` de un solo uso, `ath`). La clave queda ligada al emparejar (soul-pair-v2); no hay ligadura en el primer uso. Un dispositivo emparejado antes, sin clave ligada, no entra: hay que volver a emparejarlo con `soul pair`. La ventana de `jti` vive en memoria: tras reiniciar `serve`, una prueba capturada podría repetirse durante 60 s como mucho.
- **Emparejamiento**: la clave `soulpk_` se guarda en `pairing.json` (0600) mientras la ventana está abierta, no solo su hash, porque es la clave del HMAC. Se borra al usarse, caducar o bloquearse. Una respuesta del reto permite probar claves sin conexión, pero con 178,6 bits no es viable (≈ 2^-116 con un millón de GPU en la ventana; cálculo en `docs/canal-amenazas.md`). El QR de `soul pair` contiene la clave: no compartas capturas durante la ventana.
- **AC-4d es de mejor esfuerzo frente a un agente adversario**: la detección del frontend usa variables de entorno y `--frontend`, y un agente podría borrarlas. Protege contra el uso normal desde Claude Code u OpenCode, no contra un agente que quiera saltárselo.
- **Política de atención de la API**: decide `Politica` de `src/attention/` (H-11) y su estado se persiste con `estadoATexto` dentro de `attention-state.json`, junto con modo, avisos, alertas, pendientes, registro y mensajes del sondeo; `soul mode` se aplica en el siguiente tic. La API la configura con ventanas de presupuesto de `ventana_min` desde las 00:00 UTC, sin franjas de descanso declaradas (el contrato de la app no las tiene todavía). Los avisos de las fuentes entran por la ruta API; solo las reglas de remitente por la web entran por la ruta WEB (la política las baja a aviso). Si el estado de la política es ilegible, se avisa y se empieza de cero: la API no usa PARA (el STOP es aparte).
- **Gemelo**: selecciona y redacta sin modelo, con plantillas; sin proveedor de inferencia de la organización, el borrador es una plantilla que lo dice en su primera línea. Soul v1 no escribe en las fuentes: una acción aprobada queda con `ejecucion: sin_ejecutor` salvo que quien arranca la API inyecte `ejecutorAcciones`. Días y horas en UTC, como los resúmenes de la API. El resumen de la mañana no gasta presupuesto (es programado) pero no notifica fuera de `DISPONIBLE`; los seguimientos pasan por `Politica` como avisos. El grant de una aprobación es un control de coherencia (sha256 sin clave del tipo, el elemento y el contenido), no una firma: quien pueda escribir `attention-state.json` podría fabricarlo; por eso al restaurar no se ejecuta nada, y el texto y las acciones se recalculan desde las plantillas. Si un ejecutor falla, la acción vuelve a `propuesta`. Con la autenticación de pruebas por tokens de las semillas el grant queda con `dispositivo: null`; en producción lo fija `autenticar` con el dispositivo emparejado. Con `recuentos`, cada asunto lleva id opaco, motivo y fechas, como el sondeo, pero ningún título ni nombre.
- **Q3 en la app**: sale del núcleo, como `soul q3 --since` (claves nuevas y con otra huella). Lo retirado (`removed`) no se sirve todavía, porque el contrato de la app no tiene cómo marcar un elemento como desaparecido; la CLI sí lo da. Sin ninguna lectura anterior a `desde`, la base es la primera lectura guardada: responde «qué cambió desde que Soul empezó a leer» (D6).
- **Configuración en caliente**: `serve` relee `config.json` en cada lectura, pero los operadores de la API (perfiles) y su nivel de detalle se fijan al arrancar. Un perfil añadido con el servicio en marcha recibe 401 hasta reiniciar `serve`.
- **Credenciales**: en Windows y macOS solo se han probado con un doble, no contra el almacén real. En Windows, `Add-Type` falla bajo Constrained Language Mode: entonces el almacén da error y el token no se guarda en ningún otro sitio.
