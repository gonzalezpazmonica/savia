---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: B
risk: L3
related_specs: [SE-428, SE-434, SE-439, SE-362, SE-443]
origin: output/research/20261020-learnings-goose-gentledot-rea.md (D1, D8)
resource: https://github.com/Gentleman-Programming/gentle-dot
---

# SE-446 — Canal de aprobación inalcanzable para el agente: prueba de autoaprobación y mitigación

## Problema

En Savia Space el agente tiene shell. Todo lo que el agente puede alcanzar desde esa shell (un
token, un socket, un puerto local, un fichero) lo puede usar para contestar sus propias preguntas de
permiso. Si el canal por el que se aprueba un `permission.asked` es alcanzable desde el espacio del
agente, la aprobación humana es una formalidad.

SE-434 diseña con cuidado el sandbox, las fichas de llamadas aprobadas y el intermediario, y reconoce
sus límites. **No he podido verificar** cómo se autentica hoy la respuesta a un `ask` en el código de
`space-server`: no lo he leído, y las specs SE-428, SE-434 y SE-439 no mencionan descriptores de
fichero heredados ni `socketpair` (búsqueda de esos términos: sin resultados). Esta spec no afirma que
exista un fallo; exige **demostrar** que no lo hay, y si lo hay, corregirlo.

## Valor y evidencia

gentle-dot (MIT) resolvió el mismo riesgo con un canal privilegiado que el agente no puede abrir:

- La aplicación crea un `socketpair` y deja un extremo en el descriptor 3 del daemon que lanza el
  motor. El daemon comprueba con un proceso hijo sonda que sus propios hijos no heredarían ese
  descriptor y, si lo heredarían, lo cierra. La conexión **es** la autenticación: nada en ficheros ni
  variables de entorno.
- Los mensajes privilegiados (conectar un servicio, cambiar el modo, aprobar un borrador) se
  rechazan por el WebSocket aunque se posea la clave de acceso.
- Lo documentan en `docs/design.md` §4; el código está en `packages/daemon/src/app-channel.ts` y
  `apps/desktop/src-tauri/src/app_channel.rs`. En Linux usa `pre_exec` y `close_range(CLOSE_RANGE_CLOEXEC)`
  (kernel ≥ 5.9).

Es una variante del problema que SE-434 ya trata con las fichas de llamadas aprobadas (una regla
`ask` que el agente puede rodear tiene poco valor), aplicada ahora al canal donde se responde. Un fallo aquí invalida la premisa de SE-362 para Space.

## Alcance

| Slice | Entrega |
|---|---|
| S0 | **Prueba**, sin cambiar producto: un agente de prueba dentro del sandbox de SE-434 intenta contestar su propio `ask` por cada vía alcanzable (puertos locales de `space-server` y del motor, sockets de dominio Unix visibles, ficheros de token, variables de entorno heredadas, descriptores abiertos en `/proc/self/fd`). Informe con el resultado por vía: contestado / rechazado / no alcanzable. |
| S1 | Solo si S0 encuentra una vía abierta: mover el canal de aprobación a un socket heredado o sin nombre, fuera del espacio de ficheros del motor, con la sonda de herencia como test permanente. Aplica a SE-428 (orquestador), SE-434 (intermediario) y SE-439 (sesión gráfica). |
| S2 | Test permanente «el agente no puede contestar su propio ask» en la suite de conformidad de Space, ejecutado en CI contra el binario real. |
| S3 | **Opcional, condicionado a la decisión D2**: «relajación temporal» (omitir solo la confirmación de acciones de riesgo bajo, solo en memoria, que caduca y nunca persiste), con recibo de inicio y de fin. |

## Fuera de alcance

- Cambiar el modelo de permisos de OpenCode.
- Tiers 3 y 4 de SE-362 en la relajación temporal: nunca entran.
- Sustituir la autenticación móvil (SE-430): este canal es el del escritorio.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | S0 produce `docs/evidence/SE-446-S0-probe.md` con una fila por vía probada, comando usado y resultado, ejecutado contra el `space-server` real (no un doble). |
| AC2 | Si alguna vía queda en «contestado», el informe la marca como hallazgo de seguridad con severidad y se abre S1 antes de cualquier otro trabajo de Space; si ninguna, S1 queda cerrada con esa evidencia. |
| AC3 | Test de aceptación (S2): `agent-self-approve` abre cada vía enumerada en S0 y verifica que el `ask` sigue pendiente tras el intento. Falla si alguna vía contesta. |
| AC4 | Si se hace S1: la sonda de herencia lanza un hijo del motor y comprueba que no tiene el descriptor del canal (`ls /proc/<pid>/fd` no lo contiene). |
| AC5 | Si se hace S3: tras la caducidad, la acción vuelve a pedir confirmación; reiniciar el servicio la apaga; un `ask` de tier 3/4 pide confirmación aunque la relajación esté activa. |
| AC6 | `capability-entropy.py --check` PASS y `validate-ci-local.sh --quick` verde. |

## Riesgos

- Detalles específicos de Linux (`close_range` desde el kernel 5.9): se mantiene la sonda como test.
- Que S0 no encuentre nada y se dé por buena una prueba incompleta: la lista de vías debe revisarse
  por una persona y ampliarse cuando cambie la arquitectura del servicio.
- S3 erosiona una barrera; solo es aceptable porque caduca, es visible y no toca los tiers altos.

## Licencia de lo reutilizado

Solo el patrón de diseño; sin copia de código. gentle-dot es MIT; su licencia excluye las marcas de
terceros que menciona, y esta spec no usa ninguna.

## Esfuerzo

S0 S (una sesión de prueba), S1 M (solo si hace falta), S2 S, S3 S.

## Decisiones pendientes de la operadora

- **D1**: prioridad de S0 respecto al resto de Space (propuesta: antes de cualquier función nueva que dependa de aprobaciones, por ejemplo SE-443 S5 y SE-439).
- **D2**: si S3 (relajación temporal) entra, dado que la persona controla Savia desde el móvil y las
  preguntas interactivas pesan. La alternativa es no ofrecerla.

## Referencias cruzadas

SE-428 (orquestador), SE-434 (sandbox y fichas de aprobación), SE-439 (sesión gráfica), SE-362 (tiers de
riesgo), SE-443 (política por herramienta: presupone este canal seguro).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Canal de aprobación de Space | no aplica | `space-server` y su lanzamiento del motor |
| Prueba S0/S2 | no aplica | corre contra Space con OpenCode como motor |

### Verification protocol

- [ ] Funciona en runtime OpenCode (único motor de Space).
- [ ] La prueba corre contra el binario real, no contra un doble.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **SINGLE_BINDING_DEFERRED**: el canal de aprobación solo existe en Space (motor OpenCode). Claude Code no tiene este canal; no hay port pendiente, sino ausencia del problema.
