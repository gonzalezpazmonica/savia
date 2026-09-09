---
id: SE-392
status: APPROVED
approval: "Operadora 2026-09-09: aprobación global de trabajo pendiente"
priority: P0
created: 2026-09-07
developer_type: agent-single
---
# SE-392 — Runtime común de Savia para Codex y OpenCode

## Objetivo y contrato de equivalencia

Operar ambos CLI simultáneamente en el mismo directorio con las mismas
capacidades Savia, decisiones de política y estado confirmado. Equivalencia
funcional verificable; las respuestas de modelos y las interfaces nativas no
son idénticas. Ninguna capacidad pendiente cuenta como cubierta.
El alcance incluye contexto, skills, comandos, roles, hooks, MCP, memoria,
aprobaciones, concurrencia, recuperación y actualización en sesiones activas.
La certificación aplica a versiones probadas y sesiones conectadas al runtime.
Procesos ajenos o CLI arrancados sin integración no adquieren garantías.

## Evidencia inicial

- Codex 0.153.4 informa hooks stable=true; admite hooks nativos de proyecto.
- OpenCode 1.18.21 carga savia-gates y savia-foundation en configuración resuelta.
- settings.json contiene 124 handlers en 17 eventos: 122 command, 1 http, 1 prompt.
- shell-bridge omite tipos distintos de command y deja pasar errores generales.
- savia-gates conserva hookMap inicial; ConfigChange no lo recarga.
- session-registry claim consulta ocupación sin adquirir una reserva atómica.
- Skills enlazadas; MCP de Codex CLI aún no configurados; aislamiento bwrap falla.
Estas observaciones no acreditan ejecución de los 124 handlers ni paridad E2E.

## Arquitectura y fuentes

1. Evolucionar `.scm` y fuentes existentes; coordinar con SE-375, sin otro catálogo
   autoritativo. Derivar manifiesto de capacidades con revisión SHA-256.
2. Núcleo local `scripts/dual-cli/`: normaliza eventos, ejecuta política común,
   gestiona journal transaccional y reservas. Adaptadores finos por frontend.
3. Codex usa `.codex/hooks.json`; OpenCode adapta savia-gates. Evitar que los
   guards de savia-foundation y del puente ejecuten el mismo efecto dos veces.
4. Estado privado por repositorio resuelto con realpath bajo `~/.savia/dual-cli/`.
   Socket Unix con acceso del usuario; transacciones SQLite y journal durable.
5. Launcher `scripts/savia-cli.sh codex|opencode`: preflight, conexión y cierre;
   debe detectar configuración no confiada, adaptador ausente o versión inválida.
6. Fuentes MCP locales se traducen con un generador idempotente. El runtime
   comparte backends con estado mediante proxy cuando no soporten multi-cliente.
   No copiar secretos a archivos públicos ni fusionar credenciales de proveedores.
7. Resolver roles y comandos desde fuentes actuales; mapear modelos y permisos
   explícitamente por frontend. Probar mismos contratos y AC, no texto idéntico.

## Interfaces propuestas

JSON UTF-8, protocolo v1; límites de tamaño y validación antes de ejecutar:
- Event: version:1, repo_id:string, frontend:codex|opencode, session_id:string,
  actor_id:string, event_id:string, call_id:string|null, kind:string,
  revision:string, payload:JSON. Identificar subagentes separadamente del padre.
- Decision: action:allow|deny|retry, reason:string, revision:string,
  sequence:integer, context:string|null, updated_input:JSON|null, lease:string|null.
- `hello`, `dispatch`, `ack`, `status`, `acquire`, `release`, `close` son operaciones
  del socket; errores tipados: STALE_REVISION, CONFLICT, UNTRUSTED, UNAVAILABLE,
  INVALID_EVENT, UNSUPPORTED_CAPABILITY. Sin traducción silenciosa a allow.
- `status` devuelve revisión, consumidores/ACK, reservas, lag, capacidades y gaps;
  no devuelve prompts, credenciales ni contenido privado por defecto.

## Política, confianza y semántica

Preservar bloqueo exit 2 y JSON decision:block, argumentos/contexto y matchers.
Adaptar apply_patch a operaciones por archivo, incluyendo renombrados y borrados.
Clasificar explícitamente los 124 handlers y cada evento; inventariar también
los guards TS. HTTP/prompt necesitan ejecución equivalente y pruebas de fallo.
No simular un evento nativo que no exista: derivarlo de señales verificadas o
mediar la operación en el runtime. Si falta cobertura, certificación roja.
Gates críticos síncronos: timeout, crash o salida inválida impiden la operación.
Telemetría puede ser asíncrona, con cola durable y métricas de pérdidas.
No convertir una decisión del puente en aprobación humana ni auto-confiar hooks.
Cambios de confianza requieren revisión nativa de Codex; no usar bypass de trust.

## Concurrencia y tiempo real

Una revisión completa se publica atómicamente; nunca mezclar revisiones parciales.
Notificar consumidores en p95 <=1 s local (100 cambios, 2 CLI). Consumir y ACK
antes de la siguiente herramienta/turno; bloquear si usa revisión obsoleta.
Si un CLI no recarga un catálogo, reanudar controladamente su sesión en un punto
seguro; no declarar hot reload cuando hubo reinicio. No interrumpir escrituras.
Conflicto de fuente simultáneo: rechazar publicación, conservar ambas versiones
para revisión; nunca last-writer-wins silencioso en política o memoria estructurada.
Un único escritor del workspace por operación; comandos shell de efectos
indeterminados reservan el workspace completo. Índice/rama Git exclusivos.
Reservar antes del efecto y retener hasta finalizar también procesos hijos,
PTY, write_stdin y trabajos en segundo plano. Un TTL vencido no autoriza otro
escritor mientras el anterior siga vivo. Escrituras externas invalidan la revisión.
Revalidar hashes leídos antes de editar para impedir sobrescritura con contexto viejo.
Lecturas durante escrituras se posponen o usan snapshot confirmado.
Unificar memoria mediante transacciones y control de versión; no fusionar ni
sobrescribir las bases internas de conversaciones de los CLI.
Journal con event_id único y consumidores con cursor/ACK; entrega al menos una
vez con efectos idempotentes. Efectos externos sin clave idempotente y resultado
incierto requieren reconciliación; no prometer exactly-once universal.

## Criterios de aceptación y pruebas obligatorias

- AC1: inventario completo de capacidades activas, mapping y pruebas por CLI;
  ningún unsupported, skipped o untested permite declarar equivalencia completa.
- AC2: replay del mismo corpus normalizado produce las mismas decisiones,
  efectos y revisiones en ambos; bloquear en ambos un comando y una edición reales.
- AC3: 100 cambios entre dos sesiones: p95 <=1 s de notificación, ACK obligatorio,
  cero herramientas con revisión vieja; medir reinicios por separado.
- AC4: 100 carreras de edición y Git: un único escritor; cero cambios perdidos;
  incluir shell persistente, background, patch multiarchivo, symlink y rename.
- AC5: SIGKILL de CLI/runtime durante escritura: no otorgar segunda reserva
  hasta verificar fin del escritor; recuperar journal sin duplicar efectos.
- AC6: caída de HTTP/prompt/MCP, JSON inválido y timeout bloquean gates críticos;
  una operación no relacionada puede continuar si su política lo permite.
- AC7: mismos MCP tools/list y contratos; prueba de memoria escribir en uno,
  leer desde el otro; reconexión sin doble mutación ni credenciales en logs.
- AC8: modificación/revocación de confianza no se autoaprueba; sin hooks activos
  el preflight rechaza el modo certificado; sandbox operativo sin rebajar permisos.
- AC9: comandos, roles, contexto y skills cumplen su contrato en dos CLI reales,
  incluidas sesiones ya abiertas y subagentes; no basta probar adaptadores aislados.
- AC10: instalación y generación idempotentes, rollback preserva archivos ajenos;
  versión nueva queda sin certificar hasta pasar replay y E2E.

## Entregas y archivos previstos

S1 inventario y probes E2E: `scripts/dual-cli/audit.py`, `tests/dual-cli/`.
S2 núcleo/política: `scripts/dual-cli/{runtime,protocol,policy,state}.py`.
S3 adaptadores: `scripts/dual-cli/codex-hook.py`, `.codex/hooks.json`,
`scripts/opencode-plugin/savia-gates/{index.ts,lib/shell-bridge.ts}`.
S4 sincronización/MCP: `scripts/dual-cli/{config,mcp_proxy}.py`,
`scripts/savia-cli.sh`, configuración local generada y no pública.
S5 concurrencia: `scripts/session-registry.sh` como fachada del estado común;
S6 certificación: `tests/dual-cli/`, `docs/frontend-compatibility.md`, READMEs.
Cada slice empieza con tests rojos, termina con evidencia; S1 decide viabilidad
antes de activar nuevos hooks. Revisar seguridad antes del despliegue local.

## OpenCode Implementation Plan

### Bindings touched
Codex hooks nativos y savia-gates llaman al mismo núcleo. Traducir explícitamente
inicio/fin, herramientas, permisos, compactación, subagentes y cambios de contexto.
### Verification protocol
Replay compartido más E2E contra ambos CLI instalados; informe por capacidad.
### Portability classification
DUAL_BINDING. Bloqueos nativos ausentes requieren mediación probada; no excepción.

## Fuentes

- https://learn.chatgpt.com/docs/hooks
- https://learn.chatgpt.com/docs/config-file/config-reference
- https://opencode.ai/docs/plugins/
- `scripts/opencode-plugin/savia-gates/index.ts` y `lib/shell-bridge.ts`
- `scripts/session-registry.sh`, `.claude/settings.json`, SE-375
