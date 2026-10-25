# DOMAIN — harness-architecture

## Por qué existe esta skill

Las skills hermanas ejecutan (`overnight-sprint`, `code-improvement-loop`, `automation-scheduler`,
`dag-scheduling`). Ninguna ayuda a decidir **cuánta estructura** necesita un trabajo de agentes ni a
diseñarla. Sin esa decisión se paga coste de orquestación sin fallo que lo justifique, o se lanza un
bucle sin tope. Esta skill concentra el criterio de elección y los fallos operativos observados.

## Conceptos de dominio

- **Harness**: todo lo que rodea al modelo en un agente (prompts, herramientas, hooks, memoria, bucle, verificación). Guías (antes de actuar) y sensores (después).
- **Metaharness**: harness que lanza harnesses con una ficha cada uno. Experimental (línea de investigación L39).
- **Postcondición**: comprobación sobre el artefacto, independiente de lo que el agente diga.
- **Marca de fin**: fichero que el agente escribe al terminar, aunque falle.
- **Tope de agentes simultáneos**: parámetro de política de cuenta y de máquina.
- **Etiquetas de evidencia**: [M] medida, [M-int] medida interna, [E] experiencia propia, [O] opinión, [D] documentación.

## Limites y no-objetivos

- No implementa harnesses: entrega un diseño con condiciones de parada.
- No ejecuta sprints ni bucles, no programa tareas, no gestiona el sprint de proyecto.
- No recomienda metaharness como práctica general: lo describe como experimental.
- No sustituye a `autonomous-safety.md`: lo aplica.

## Confidencialidad

- Nivel N1 (público). Solo contiene criterios y fuentes públicas; los incidentes propios van sin nombres de proyecto ni datos personales.
- Investigación de respaldo: informe aparte fuera del repo; la skill cita solo `references/fuentes.md`.

## Referencias

- Spec origen: `docs/specs/SE-457-harness-architecture-skill.spec.md`.
- Reglas: `docs/rules/domain/autonomous-safety.md`, `docs/rules/domain/maker-checker-protocol.md`, `docs/rules/domain/remedy-ladder.md`.
