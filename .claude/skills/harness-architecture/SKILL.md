---
layer: peripheral
name: harness-architecture
description: "Diseña la arquitectura de un harness de agentes: único, orquestado o metaharness, flujos largos, bucles, sprints. Usar cuando se diseña o depura un harness, un bucle autónomo o un sprint nocturno."
license: MIT
metadata:
  savia.maturity: "draft"
  savia.context: "standalone"
  savia.context_cost: "medium"
  savia.category: "meta"
  savia.tags: "harness, metaharness, orquestacion, bucles, sprints, flujos-largos"
  savia.priority: "medium"
  savia.loop_level: "L1"
---

## Subagent Scope Guard

> Si eres subagente con una tarea concreta, ejecuta solo esa y reporta DONE / DONE_WITH_CONCERNS / BLOCKED.

# Skill: Arquitectura de harness

Decide **cuánta estructura** necesita un trabajo de agentes y la diseña: contrato, herramientas,
contexto, verificación, presupuesto, bucles y sprints. Entrega un diseño con sus condiciones de
parada, no una implementación. Las skills hermanas ejecutan; esta decide.

## Authoritative Paths

> Lee estos paths antes de actuar. No inventes paths ni firmas.

| Para | Lee |
|---|---|
| Seguridad de modos autónomos (git, PR, fail-safe) | `docs/rules/domain/autonomous-safety.md` |
| Merges en serie bajo grant | `docs/rules/domain/autonomous-safety-merge-sprint.md` |
| Productor/verificador, y verificador que falla cerrado | `docs/rules/domain/maker-checker-protocol.md`, `docs/rules/domain/checker-fail-closed.md` |
| Niveles L0-L3; prosa, script, skill o hook | `docs/rules/domain/loop-phasing.md`, `docs/rules/domain/remedy-ladder.md` |
| Equipos en paralelo, ámbitos disjuntos | `docs/agent-teams-sdd.md` |
| Checklist de diseño | `references/checklist-diseno.md` |
| Patrones y reglas de elección | `references/catalogo-patrones.md` |
| Flujos largos, bucles y sprints nocturnos | `references/flujos-bucles-sprints.md` |
| Metaharness (experimental) | `references/metaharness.md` |
| Anti-patrones con coste observado | `references/antipatrones.md` |
| Plantillas: ficha, encargo, sprint, progreso | `references/plantillas.md` |
| Fuentes públicas con URL y fecha | `references/fuentes.md` |

Si un path no existe, avisa y marca lo que dependa de él como no contrastado.

## Cuándo usar

Montar un trabajo con varios agentes o decidir si hacen falta; diseñar un bucle autónomo, una tarea
de horas o un sprint nocturno; depurar un harness que se cuelga, repite, gasta de más o no reanuda.

## Cuándo NO usar

- Tarea corta o de un paso: hazla directamente.
- Programar tareas periódicas: `automation-scheduler`. Ejecutar un sprint ya diseñado: `overnight-sprint`.
- Mejora autónoma con métricas: `code-improvement-loop`. Dependencias entre fases SDD: `dag-scheduling`.
- Backlog, capacity y sprint de proyecto: `sprint-management`.

## Etiquetas de evidencia

Las referencias etiquetan cada regla. Ante duda, trata [O] como hipótesis y mide.
**[M]** medida; **[M-int]** medida interna del autor, no reproducible; **[E]** experiencia propia de
Savia, sin estudio controlado; **[O]** práctica u opinión de fuentes; **[D]** documentación de producto.

## Decision Checklist

1. ¿Cabe en un paso o en un agente con herramientas y un contexto? → **agente único**. Fin.
2. ¿Hay un fallo observado del agente único (contexto desbordado, instrucciones ignoradas, herramienta mal elegida)? → No: no añadas estructura.
3. ¿Subtareas de lectura o amplitud, independientes? → **orquestadora + subagentes** que devuelven un resumen corto.
4. ¿Subtareas de escritura con decisiones compartidas? → **hilo único**; paralelo solo con ficheros disjuntos comprobados antes.
5. ¿Ejecutor especializado que gana en su dominio y autoridad de una persona? → **metaharness, experimental**: `references/metaharness.md`.
6. ¿Dura más que un contexto? → estado en ficheros y reanudación.
7. ¿Se repite hasta cumplir un criterio? → bucle con tope.
8. ¿Corre sin vigilancia? → sprint con cola, vigilantes y permisos preconcedidos.
9. ¿Qué lo hace cumplir? → control determinista (hook, sandbox, test) antes que prosa; un control sin salida clara falla cerrado.

Detalle de 6-8: `references/flujos-bucles-sprints.md`; de 9: checklist de diseño.

### Abort conditions

- Sin criterio de éxito comprobable ni modo de crearlo: no lances el bucle; diseña antes la comprobación.
- Sin persona que dé la autoridad (reviewer o grant): no lances nada autónomo.
- Sin presupuesto (tiempo, tokens, dinero, disco, RAM): defínelo antes.

## Tres reglas que no se negocian

1. **Delegar nunca amplía autoridad**: el hijo recibe como mucho lo que tiene la madre y ningún agente aprueba su propio trabajo. [E]
2. **Parar siempre está permitido**; un bucle sin tope es gasto sin límite. [O, E]
3. **El tope de agentes simultáneos es un parámetro de política**, no una verdad técnica: lo fijan la cuenta (consumo) y la máquina (RAM, disco). Una orden expresa de la persona lo mueve; el diseño funciona con cualquier N. [E]

## Outputs esperados

- Diseño de 1-2 páginas: opción elegida y el fallo observado que la justifica; plan o ficha
  (`references/plantillas.md`), condiciones de parada, presupuesto y qué se medirá.
- Cada afirmación no trivial con su etiqueta de evidencia.

## Memory hooks

- Al empezar: `bash scripts/memory-store.sh recall harness`. Tras un fallo operativo nuevo: `bash scripts/memory-store.sh save --type feedback --title '<título>' --content '<cue, lección, evidencia, confianza>' (comillas simples; texto de terceros nunca entre dobles) --source skill:harness-architecture`

## Related

- Skills: `../overnight-sprint/SKILL.md`, `../code-improvement-loop/SKILL.md`, `../automation-scheduler/SKILL.md`, `../dag-scheduling/SKILL.md`
- Spec: `docs/specs/SE-457-harness-architecture-skill.spec.md`
