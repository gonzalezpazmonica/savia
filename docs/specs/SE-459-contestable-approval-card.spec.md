---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L2
related_specs: [SE-433, SE-343, SE-446, SE-436, SE-445]
origin: investigación de arquitectura agéntica 2026-09-25 a 2026-10-23 (entrada 33)
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-459 — Aprobaciones contestables: tarjeta de aprobación en lenguaje llano

## Problema

La aprobación humana es la garantía final de Savia (Rule 8, SE-343, SE-433), pero lo que la persona
ve al aprobar no siempre le permite saber **qué** aprueba. Medido el 2026-10-23:

- El grant de un merge-sprint se aprueba contestando al diálogo del arnés para la orden
  `merge-sprint.sh grant <manifest-digest>` (cabecera de `scripts/merge-sprint.sh`, línea 6). Lo
  visible es un hash de 64 caracteres. Qué PRs entran, cuántos merges como máximo y cuándo caduca
  solo se sabe ejecutando `plan` y leyendo el manifiesto.
- De los hooks de Savia, solo `dome-guard.sh` responde «ask» con motivo
  (`permissionDecisionReason`); el resto de diálogos son los genéricos del arnés, que muestran la
  orden de shell en crudo.
- Ese mismo día, un sprint autónomo quedó detenido unas 6 horas esperando un diálogo de permiso cuya
  única información era una orden de shell larga, ilegible en el móvil desde el que se supervisaba.
- Búsqueda de una plantilla o esquema común para peticiones de aprobación (propuesta, argumentos,
  evidencia, efecto) en `docs/rules/domain/` y `scripts/`: sin resultados. La práctica de «decisiones
  con contexto llano» existe como costumbre de la orquestadora, no como contrato comprobable.

Una aprobación que la persona no entiende es una garantía débil: deja rastro de «sí» sin decisión.

## Valor y evidencia

- Akhtar et al., «Contestable Agents for Data Governance», arXiv 2610.31553 (22-oct-2026): cada
  decisión llega con argumentos puntuados y citados; la persona acepta, rechaza, modifica o añade
  argumentos antes del commit, y un registro guarda evidencia, intervención y resultado. Verificado;
  la validación es de dos casos ilustrativos, sin métricas. Se adopta el patrón, no una cifra.
- VeriWeave Govern, arXiv 2609.37457 (26-sep-2026): las acciones dudosas se enrutan a revisión
  humana con evidencia tipada y precedencia deny > review > allow. Verificado. Refuerza que «review»
  es un estado con contenido, no un sí/no.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Esquema de tarjeta (`docs/rules/domain/approval-card.md`, ≤ 60 líneas) y `scripts/approval-card.sh render <json>`: campos obligatorios `propuesta` (una frase), `por_que` (≤ 3 argumentos), `evidencia` (rutas o URLs), `efecto` (qué cambia y dónde), `reversible` (sí/no + cómo deshacer), `caduca`, `si_dices_no` (qué pasa). Salida ≤ 12 líneas de ≤ 70 caracteres: legible en un móvil. Falta un campo obligatorio → sale 2 y no imprime tarjeta. |
| S2 | Grant de merge-sprint: `merge-sprint.sh grant` exige que exista la tarjeta del manifiesto (`plan` la genera con lista de PRs por número y título, máximo de merges, TTL, cómo revocar) y la imprime en el motivo del «ask». Sin tarjeta, no hay grant. |
| S3 | Motivos de los hooks propios que responden «ask» (hoy `dome-guard.sh` y su par TypeScript) en formato tarjeta corta: efecto, dónde y reversible. Test de paridad bash/TS con la misma entrada. |
| S4 | Lint: `tests/test-approval-card-lint.bats` recorre los hooks y scripts que emiten `"ask"` y falla si alguno no pasa por `approval-card.sh` o no da motivo. |

## Fuera de alcance

- Cambiar el diálogo nativo del arnés para órdenes que Savia no intercepta. Se documenta como límite.
- Clasificar automáticamente cualquier orden de shell en lenguaje llano (riesgo de explicar mal una
  orden peligrosa): solo tarjetas de flujos que Savia conoce.
- Firmar la aprobación (Yema F4 y SE-446 tratan quién contesta; esta spec trata qué se entiende).

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `approval-card.sh render` con un JSON completo imprime ≤ 12 líneas, ninguna > 70 caracteres, y contiene los siete rótulos. |
| AC2 | Negativo: sin `efecto` o sin `reversible`, sale 2 y stdout vacío. |
| AC3 | Negativo: `merge-sprint.sh grant <digest>` sin tarjeta del manifiesto sale ≠ 0 y no escribe `grant.json` (test con `HOME_MS` temporal). |
| AC4 | Con tarjeta, el motivo del «ask» del grant lista los números de PR del manifiesto y el TTL; el test compara con el fixture. |
| AC5 | `dome-guard.sh` y `dome-guard.ts`, con la misma entrada de escritura en una cúpula, dan un motivo con efecto y reversibilidad idénticos (paridad). |
| AC6 | Negativo del lint: un hook de fixture que emite `"permissionDecision":"ask"` sin motivo hace fallar `test-approval-card-lint.bats`. |

## Riesgos

- Tarjeta que miente por omisión (efecto mal descrito). Mitigación: en S2 la tarjeta se genera del
  manifiesto, no se redacta a mano; el digest sigue siendo la atadura técnica.
- Más texto en el diálogo. El tope de 12 líneas es parte del contrato.

## Decisiones de la operadora

- **D1**: campos obligatorios (propuesta: los siete de S1).
- **D2**: ¿extender la tarjeta a las preguntas de decisión de la orquestadora (AskUserQuestion)? (propuesta: sí, como guía, sin lint).
- **D3**: anchura objetivo (propuesta: 70 caracteres, pensada para móvil).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `approval-card.sh`, grant de merge-sprint | scripts bash | los mismos |
| Motivo del «ask» de `dome-guard` | `permissionDecisionReason` del hook | `reason` de `savia-gates/lib/dome-guard.ts` |

### Verification protocol

- [ ] AC5 ejecuta el hook bash y la regla TS con la misma entrada.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **DUAL_BINDING**: el motivo del guard de cúpulas existe en los dos frontends; el resto es PURE_BASH.
