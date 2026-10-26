---
status: APPROVED
approved_at: 2026-10-27
approved_by: "operadora, AskUserQuestion 2026-10-27"
priority: P1
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L2
related_specs: [SE-352, SE-445, SE-444, SE-366]
origin: investigación de arquitectura agéntica 2026-09-25 a 2026-10-23 (entradas 34 y 38)
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-460 — Reactivación revalidada: automatizaciones y memoria con vigencia, procedencia y autoridad

## Problema

Lo que persiste (una tarea programada, una entrada de memoria) puede seguir actuando cuando ya no es
legítimo: la instrucción la plantó un contenido externo, la autorización que la justificaba caducó o
alguien la cambió después de aprobarla. Medido sobre `main` (0dd2ea30b):

- **Automatizaciones.** `ScheduledTask` (`scripts/automations/models.py`, gestionado por
  `scripts/savia-automations.sh`) guarda `instructions`, `skill`, `agent` y fechas, pero no quién la creó ni con qué origen, ni una huella de las
  instrucciones aprobadas, ni caducidad. Hoy el riesgo está latente: `scripts/automations/runner.py`
  aún **no** invoca la skill ni el agente (solo registra, línea 8). El día que se active, cada
  disparo ejecutará lo que diga el fichero en ese momento, sin revalidar nada.
- **Memoria estructurada.** Ya hay procedencia y vigencia: `memory-store.sh save --origin` y
  `--expires` (SE-352), `valid_to` bitemporal, y `recall` excluye caducadas por defecto. Pero el
  filtro de origen es opcional (`--min-origin`), y `scripts/memory-stack-load.sh`, que carga memoria
  en contexto por capas, no filtra ni caducidad ni origen (búsqueda de `expir|origin|valid_to` en el
  script: cero coincidencias).
- **Memoria por ficheros del frontend.** Cada hecho es un fichero con `name`, `description` y `type`.
  No hay campo de vigencia: puede haber autorizaciones temporales registradas así, con la fecha de fin
  solo en la prosa, que se cargarían igual después de esa fecha.

## Valor y evidencia

- Xu et al., «After the Attacker Leaves: Benchmarking Carryover Attacks on LLM Agents», arXiv
  2610.28425 (20-oct-2026, EMNLP 2026): CarryoverBench, 12 escenarios y 101 tareas de ataque en tres
  canales, uno de ellos **tareas programadas** y otro **memoria que reaparece**; en cinco modelos
  frontera los payloads se reactivan sin decaimiento medible durante cinco rondas. Verificado.
- Liu et al., «Governance-State Corruption in Long-Term Memory for LLM Agents», arXiv 2610.30698
  (22-oct-2026): seis proveedores, 2.080 pares; cambiar el estado de validez de lo recuperado altera
  la proyección operativa en el 96,25 % de los pares offline, y aplicar la validez con un oráculo la
  restaura en el 100 %. Verificado. Lección: el contenido puede ser correcto y su uso, ilegítimo.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | `ScheduledTask` añade `origin` (`owner|agent|untrusted`, por defecto `untrusted`), `approved_by`, `valid_until` y `approved_hmac`. `savia-automations.sh approve <id>` sella con HMAC-SHA256 una cadena canónica de **todos** los campos que deciden si se ejecuta y con qué autoridad: `instructions`, `skill`, `agent`, `origin`, `valid_until` y `approved_by`. La clave vive fuera del fichero de la tarea y fuera de lo que edita el agente (`~/.savia/automations/seal.key`, 0600, creada en el primer `approve`; el directorio entra en las rutas protegidas de los guards de escritura y de Bash). Un sha256 sin secreto no vale: quien edita el fichero podría recalcularlo. Editar cualquiera de esos campos invalida el sello. Límite declarado: un proceso con el mismo usuario que lea la clave puede sellar; la defensa es la ruta protegida y la revisión, no criptografía. |
| S2 | Revalidación en cada disparo, antes de ejecutar: huella distinta, caducada, origen `untrusted` o sin aprobación → el run queda `blocked_revalidation` con motivo, no se ejecuta y cuenta como fallo para SE-445. Se aplica a `run`, `execute` y `run-due`. Las comprobaciones de S2 no leen `origin` ni `valid_until` del fichero sin verificar antes el sello: sello inválido o ausente → `blocked_revalidation` motivo `huella`. La regla del origen `untrusted` en S2 es **incondicional** (también en sesión interactiva): una automatización dispara sin nadie mirando, así que la persona que la aprobó es la única garantía. D1 afecta solo a la memoria (S3). |
| S3 | `memory-stack-load.sh` excluye entradas caducadas y, en sesiones autónomas (`SAVIA_AUTONOMOUS_RUN=1` o rama `agent/*`), las de origen `untrusted`; el origen `system` (entradas que escribe el propio workspace) se trata como `owner` y se carga; lo excluido se cuenta en una línea («2 caducadas, 1 sin origen fiable omitidas»). Las entradas **sin campo `origin`** (memoria heredada) se tratan como `untrusted`, el mismo valor por defecto de `memory-store.sh save`, y en autónomo se omiten y se cuentan como «sin origen»; la operadora decide en D3 si se migran. «Autónomo» se evalúa al cargar la memoria al arrancar la sesión, antes de que el agente actúe, con el entorno que fijó quien lanzó la sesión: es un filtro de higiene de contexto, no una barrera contra un agente que ya está ejecutando. |
| S4 | Memoria por ficheros: campo opcional `valid_until` en el frontmatter; el cargador lo respeta y `memory-hygiene.sh` lista los ficheros cuya prosa contiene una fecha de fin sin campo (detección por fecha + «hasta»), sin reescribirlos. |

## Fuera de alcance

- Activar la ejecución real del runner (otra decisión).
- Detectar si una instrucción es maliciosa: aquí se exige procedencia y aprobación, no se juzga el texto.
- Reescribir memorias existentes: S4 solo informa.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | pytest: una tarea aprobada y sin cambios pasa la revalidación. |
| AC2 | Negativo: cambiar `instructions` después de aprobar → el disparo queda `blocked_revalidation` con motivo `huella`, y el espía de ejecución no se llama. |
| AC2b | Negativo de sello: editar a mano `origin: untrusted` → `owner`, o `valid_until` a una fecha lejana, o `approved_by`, en una tarea aprobada → `blocked_revalidation` motivo `huella` (fixture con el fichero editado y el sello intacto). Un sello recalculado con sha256 simple, sin la clave, también falla. |
| AC3 | Negativo: `valid_until` en el pasado → `blocked_revalidation` motivo `caducada`. |
| AC4 | Negativo: tarea creada sin `--origin` → `untrusted` → bloqueada aunque esté aprobada, hasta que la operadora la reapruebe como `owner`. |
| AC5 | Negativo: una tarea guardada en el formato antiguo (sin campos nuevos) carga sin error y queda bloqueada, no ejecutable. |
| AC6 | BATS: `memory-stack-load.sh` con un fixture de una entrada caducada y una vigente solo emite la vigente y la línea de omitidas. |
| AC7 | Negativo: con `SAVIA_AUTONOMOUS_RUN=1`, una entrada `untrusted` no aparece; sin la variable, sí (comportamiento interactivo intacto). |
| AC8 | Negativo: en una rama `agent/*` sin la variable, una entrada `untrusted` tampoco aparece (la otra definición de autónomo de S3); en `main` sin variable, sí. |
| AC9b | Una entrada con origen `system` se carga en autónomo (no se confunde con `untrusted`) y la línea de omitidas no la cuenta. |
| AC9 | Negativo: una entrada de memoria sin campo `origin` no aparece en autónomo y suma a «sin origen» en la línea de omitidas; con origen `owner` explícito, sí. |

## Riesgos

- Tareas legítimas bloqueadas tras la migración. Es intencionado (AC5): se reaprueban una vez.
- Falsa seguridad: la huella prueba que nada cambió desde la aprobación, no que lo aprobado sea bueno.
  Se dice en la regla.

## Decisiones de la operadora

- **D1**: ¿excluir la memoria `untrusted` también en sesiones interactivas? (propuesta: no; solo autónomas). No afecta a las automatizaciones (S2 bloquea siempre).
- **D2**: caducidad por defecto de una automatización aprobada (propuesta: 90 días).
- **D3**: entradas heredadas sin `origin` (propuesta: omitirlas en autónomo y migrar a `owner` solo las que la operadora marque con una orden explícita de una vez).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Automatizaciones (S1, S2) | scripts Python, sin frontend | los mismos |
| Carga de memoria (S3, S4) | `memory-stack-load.sh` | el mismo script |

### Verification protocol

- [ ] Tests sin frontend.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **Sin binding de frontend**: la lógica es Python (`scripts/automations/`, pytest) más un script bash de carga de memoria; ninguno depende del frontend. La etiqueta `PURE_BASH` no es exacta para la parte Python.
