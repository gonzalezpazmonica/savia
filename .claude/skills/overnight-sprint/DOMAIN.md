# Overnight Sprint — Dominio

## Por qué existe esta skill

El equipo acumula tareas de bajo riesgo (lint, tests, docs, refactoring menor) que consumen tiempo productivo. Esta skill permite aprovechar horas no laborables para generar PRs listos para revisión humana al inicio del día siguiente, sin comprometer la seguridad del código.

## Conceptos de dominio

- **Tarea overnight-safe**: Work item etiquetado como apto para ejecución autónoma (bajo riesgo, sin decisiones de diseño)
- **Baseline de tests**: Estado actual de tests pasando que sirve como referencia mínima — si un cambio rompe el baseline, se descarta
- **PR en Draft**: Pull request que espera CI y la ruta de revisión humana aplicable
- **results.tsv**: Registro de cada intento con estado (pr-created, discarded, crash, timeout)
- **Ruta de revisión**: Reviewer distinto si es elegible; en repositorio de una sola colaboradora, la operadora puede revisar y mergear sus PRs bajo grant expreso

## Reglas de negocio que implementa

- RN-AUT-01: Ningún agente autónomo tiene autoridad para decisiones irreversibles
- RN-AUT-02: Todo output autónomo es propuesta pendiente de revisión humana
- RN-AUT-03: Abort tras N fallos consecutivos (configurable)

## Relación con otras skills

- **Upstream**: Backlog con tareas etiquetadas como overnight-safe
- **Downstream**: PRs en Draft listos para `code-improvement-loop` o revisión humana
- **Paralela**: `autonomous-safety.md` (regla de seguridad transversal)

## Decisiones clave

- Se eligió PR Draft; un merge posterior exige grant expreso, CI y gates de riesgo
- Se usa worktree aislado por tarea para evitar interferencia entre experimentos
- El patrón de bucle viene de autoresearch (Karpathy) adaptado con guardarraíles PM
