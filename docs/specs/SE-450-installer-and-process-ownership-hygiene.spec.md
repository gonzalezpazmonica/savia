---
status: APPROVED
approved_at: 2026-10-27
approved_by: "operadora, AskUserQuestion 2026-10-27"
priority: P2
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: D
risk: L2
related_specs: [SE-434, SE-435, SPEC-OC2-02-CONFIG-COMPAT]
origin: output/research/20261020-learnings-goose-gentledot-rea.md (R3, R4)
resource: https://github.com/morluto/rea
---

# SE-450 — Instaladores aditivos e idempotentes y propiedad de procesos con identidad de arranque

## Problema

Dos higienes operativas con la misma raíz: actuar sobre el sistema de la persona sin pruebas de que la
acción es segura de repetir y de que el objetivo es el correcto.

1. **Instaladores.** `scripts/savia-setup.sh` y `scripts/setup-opencode-permissions.sh` modifican la
   configuración del usuario. En el primero, la única aparición de «backup» es un valor en una línea de
   resultado (línea 325), y no tiene modo `--dry-run`; el segundo sí hace copia con marca de tiempo en
   modo `--force`, pero no muestra un plan de cambios ni pide aprobación. Con OpenCode 2
   (SPEC-OC2-02-CONFIG-COMPAT) y la distribución de Space (SE-435) el número de configuraciones
   ajenas que se tocan crece.
2. **Propiedad de procesos.** `docs/rules/domain/dev-session-locks.md` declara un lock obsoleto si
   `kill -0 $PID` falla y han pasado 30 minutos. Un PID puede reutilizarse tras una salida, y un lock
   vivo puede apuntar al proceso equivocado. SE-434 ya valida el proceso del motor con su
   `start_time`, así que la práctica existe en Space pero no en los locks de sesión de desarrollo
   (que son los que usan los agentes). Una limpieza fallida tampoco se conserva como deuda.

## Valor y evidencia

REA (MIT) formula ambas como reglas de proyecto:

- Cambios de configuración **aditivos e idempotentes, con copia**; el instalador no instala ni
  actualiza software ajeno; muestra los cambios planificados y exige aprobación; respeta
  `OPENCODE_CONFIG_DIR` y `OPENCODE_CONFIG`, prefiere el JSONC cargado más tarde si coexisten JSON y
  JSONC (`AGENTS.md`, `docs/installation.md`).
- «Un PID y la ruta del ejecutable no bastan para establecer la propiedad tras una salida o una
  reutilización»; se conserva la propiedad de los recursos cuya limpieza falló
  (`src/process/ProcessOwnership.ts`, `ProcessStartIdentity`).

La evidencia es de diseño de otro proyecto. En Savia, el riesgo de R4 no está medido: no hay un
incidente documentado de lock apuntando a un PID reutilizado; es un riesgo de diseño. Por eso S1 y S3
empiezan con auditoría o prueba, no con cambio.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | **Auditoría** de `savia-setup.sh`, `setup-opencode-permissions.sh` (`setup-claude-permissions.sh` se retiró el 2026-10-26: era copia idéntica) contra la lista: plan previo y aprobación, copia con marca de tiempo antes de escribir, reejecución sin efecto, no instala software ajeno, respeta las variables de OpenCode y el orden JSON/JSONC. Informe `docs/evidence/SE-450-S1-installer-audit.md` con cada punto en cumple / no cumple / no aplica y evidencia. |
| S2 | Corregir lo que S1 marque como «no cumple» y sea de bajo riesgo: modo `--dry-run` que imprime el diff sin escribir, y prueba de idempotencia (dos ejecuciones = un solo cambio). |
| S3 | Locks de sesión con identidad: guardar `pid`, `starttime` (campo 22 de `/proc/<pid>/stat`) y ruta del ejecutable, y considerar vivo el lock solo si coinciden los tres. Si la limpieza falla, el lock se conserva marcado como pendiente. En macOS, `ps -o lstart=` sustituye a `/proc`. |

## Fuera de alcance

- Reescribir los instaladores ni cambiar su interfaz fuera de `--dry-run`.
- Locks en otros subsistemas (broker de Space, merge-sprint): fuera de esta spec; se evalúan tras S3.
- Garantías ante un atacante con shell del mismo usuario: igual que en el resto del repo, no se resuelve con un lock.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `docs/evidence/SE-450-S1-installer-audit.md` existe con los tres scripts y cada punto de la lista clasificado y sustentado (línea o ejecución). |
| AC2 | `bats tests/test-installer-idempotent.bats`: con `HOME` temporal, dos ejecuciones consecutivas de cada instalador dejan el mismo contenido y la segunda no crea copia nueva. |
| AC3 | Con `--dry-run`, ningún fichero bajo `HOME` cambia (hash del árbol antes y después idénticos) y la salida contiene el diff. |
| AC4 | Con `OPENCODE_CONFIG` apuntando a un fichero de fixture, el instalador escribe en ese fichero y no en la ruta por defecto. |
| AC5 | `bats tests/test-dev-session-locks-identity.bats`: un lock con `pid` de un proceso vivo pero `starttime` distinto se considera obsoleto; con los tres datos coincidentes se considera vivo; un lock sin `starttime` (formato antiguo) se considera vivo solo si pasa el criterio anterior de PID y 30 minutos (compatibilidad). |
| AC6 | Si la limpieza de un lock falla (directorio no escribible en el test), el lock permanece y se marca `cleanup_pending: true`. |
| AC7 | `capability-entropy.py --check` PASS y `validate-ci-local.sh --quick` verde. |

## Riesgos

- Linux-específico en S3 (`/proc`): mitigado con la alternativa para macOS.
- Que `--dry-run` y la ejecución real diverjan: AC3 compara sobre el mismo código de decisión, no sobre dos rutas.
- Cambios de formato de lock rompen a agentes en curso: la compatibilidad con el formato antiguo está en AC5.

## Licencia de lo reutilizado

Solo reglas y patrones; sin copia de código. REA es MIT.

## Esfuerzo

S1 S, S2 S, S3 M.

## Decisiones pendientes de la operadora

- **D1**: si el instalador pide aprobación interactiva por defecto o solo con `--interactive` (la persona
  trabaja a menudo en remoto desde el móvil, donde una pregunta bloquea).
- **D2**: si los locks de otros subsistemas entran en una spec posterior.

## Referencias cruzadas

SE-434 (validación de proceso con `start_time` en el motor de Space), SE-435 (distribución),
SPEC-OC2-02-CONFIG-COMPAT (configuración de OpenCode 2).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Instaladores (S1–S2) | scripts bash | scripts bash; escriben `opencode.json` / JSONC |
| Locks de sesión (S3) | `docs/rules/domain/dev-session-locks.md` + scripts | idénticos |

### Verification protocol

- [ ] Los instaladores se prueban escribiendo la configuración de OpenCode y la de Claude Code.
- [ ] Tests con `HOME` temporal, sin tocar la configuración real.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**
