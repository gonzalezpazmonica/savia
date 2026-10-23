---
status: PROPOSED
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
  No hay campo de vigencia: hay al menos una autorización temporal registrada así cuya fecha de fin
  solo está en la prosa, y se cargará igual después de esa fecha.

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
| S1 | `ScheduledTask` añade `origin` (`owner|agent|untrusted`, por defecto `untrusted`), `approved_sha256` (huella de `instructions`+`skill`+`agent` sellada al aprobar), `approved_by`, `valid_until`. `savia-automations.sh approve <id>` sella; editar cualquiera de esos campos borra la aprobación. |
| S2 | Revalidación en cada disparo, antes de ejecutar: huella distinta, caducada, origen `untrusted` o sin aprobación → el run queda `blocked_revalidation` con motivo, no se ejecuta y cuenta como fallo para SE-445. Se aplica a `run`, `execute` y `run-due`. |
| S3 | `memory-stack-load.sh` excluye entradas caducadas y, en sesiones autónomas (`SAVIA_AUTONOMOUS_RUN=1` o rama `agent/*`), las de origen `untrusted`; lo excluido se cuenta en una línea («2 caducadas, 1 sin origen fiable omitidas»). |
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
| AC3 | Negativo: `valid_until` en el pasado → `blocked_revalidation` motivo `caducada`. |
| AC4 | Negativo: tarea creada sin `--origin` → `untrusted` → bloqueada aunque esté aprobada, hasta que la operadora la reapruebe como `owner`. |
| AC5 | Negativo: una tarea guardada en el formato antiguo (sin campos nuevos) carga sin error y queda bloqueada, no ejecutable. |
| AC6 | BATS: `memory-stack-load.sh` con un fixture de una entrada caducada y una vigente solo emite la vigente y la línea de omitidas. |
| AC7 | Negativo: con `SAVIA_AUTONOMOUS_RUN=1`, una entrada `untrusted` no aparece; sin la variable, sí (comportamiento interactivo intacto). |

## Riesgos

- Tareas legítimas bloqueadas tras la migración. Es intencionado (AC5): se reaprueban una vez.
- Falsa seguridad: la huella prueba que nada cambió desde la aprobación, no que lo aprobado sea bueno.
  Se dice en la regla.

## Decisiones de la operadora

- **D1**: ¿bloquear `untrusted` también en sesiones interactivas? (propuesta: no; solo autónomas).
- **D2**: caducidad por defecto de una automatización aprobada (propuesta: 90 días).

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

- [x] **PURE_BASH**: scripts y tests independientes del frontend.
