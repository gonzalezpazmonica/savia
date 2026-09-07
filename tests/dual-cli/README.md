# Runtime dual CLI — evidencia S1 y núcleo experimental

Contrato: `docs/specs/SPEC-dual-cli-runtime.spec.md`.

Ejecutar tests herméticos (biblioteca estándar, sin hooks reales ni red):

```bash
python3 -m unittest discover -s tests/dual-cli -v
python3 scripts/dual-cli/audit.py
```

El auditor termina en 1 cuando el inventario es válido pero no certificado;
2 si las fuentes faltan o su estructura es inválida. No ejecuta comandos
del inventario. Omite cuerpos de hooks, URLs y prompts en la salida.
La revisión SHA-256 cubre exclusivamente las dos fuentes indicadas en
`revision_scope`; no representa todavía una revisión completa del runtime.

## Cobertura pendiente

| AC | Evidencia requerida todavía pendiente |
|---|---|
| AC1 | Mapping de recursos, guards TS, handlers y capacidades por CLI |
| AC2 | Replay y bloqueo real de comando y edición en ambos CLI |
| AC3 | 100 publicaciones, ACK y p95 de notificación |
| AC4 | 100 carreras, Git, shell persistente, patches y symlinks |
| AC5 | SIGKILL, recuperación y reserva hasta fin del escritor |
| AC6 | Fallos HTTP/prompt/MCP, timeout y aislamiento de operaciones |
| AC7 | Contratos MCP y escritura/lectura cruzada de memoria |
| AC8 | Revocación de confianza, preflight y sandbox operativo |
| AC9 | Roles, skills y comandos en sesiones reales y subagentes |
| AC10 | Instalación idempotente, rollback y cambios de versión |

Las pruebas unitarias verdes no acreditan estos AC. El inventario conserva
todos los handlers como `untested` y nunca declara equivalencia.
El arranque aislado observado en esta sesión falla con
`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`.
Ejecutar las pruebas fuera de ese aislamiento no satisface AC8.


## Núcleo experimental S2

`protocol.py` valida el evento v1, tamaño, tipos, claves duplicadas y números
no finitos. `policy.py` interpreta resultados de gates críticos: bloquea
crash, timeout, JSON inválido y solicitudes de permiso humano.
`state.py` conserva revisión, ACK, journal y una reserva global en SQLite
con transacciones `BEGIN IMMEDIATE` y `synchronous=FULL`.
Una llamada terminada no obtiene otra reserva con la misma identidad.

`runtime.py` expone un socket Unix privado, valida el UID del cliente y
entrega tokens de sesión. Implementa hello, ack, status, close y dispatch.
Dispatch devuelve siempre deny/UNSUPPORTED_CAPABILITY: todavía no hay
adaptadores de ejecución. Acquire/release no se exponen por socket hasta
implementar supervisión de escritores y todos sus descendientes.
Los tokens separan sesiones cooperativas; no aíslan procesos hostiles del
mismo usuario, que comparten acceso a archivos privados.

Evidencia ejecutada: 58 tests, incluyendo 100 carreras de reservas entre
conexiones, SIGKILL de un escritor después de reservar, persistencia al
reabrir SQLite, socket real, bloqueo de suplantación por token y rechazo de
un segundo runtime sobre el socket activo. No se instalaron hooks nativos.

Límites pendientes: reservas no se recuperan automáticamente; un socket
remanente tras un crash impide arrancar. Falta supervisor de procesos,
recuperación del daemon, cursores de journal por consumidor, publicación de
manifiestos completos, ejecución de handlers, matchers y adaptadores reales.
La revisión del proceso se recibe como argumento experimental; todavía no
se calcula desde todo el contenido de política ni se acredita confianza.
El journal deduplica registros, no acredita idempotencia de efectos externos.
El parser de hooks se prueba aislado; no está conectado a dispatch.
S1 y S2 siguen incompletos; estos tests no cierran AC1–AC10.

## Autonomía Codex

La policy común clasifica ejecución, criterio, efecto externo, ampliación de
scope y escalada de riesgo. La proyección exige `workspace-write`, red cerrada,
probe de sandbox y enforcement antes de generar un perfil. `approval_policy =
"never"` sólo se genera cuando los gates L3/L4 están demostrados; sin esa
evidencia, la configuración aborta sin tocar el fichero personal.

El doctor y el evidence package actuales informan `DEGRADED_SAFE`. Los tests
con probes sintéticos validan lógica e idempotencia; no cuentan como canaries
reales de Codex. El runner real termina en 2 mientras falle el sandbox.
