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
related_specs: [SE-444, SPEC-106, SE-332]
origin: output/research/20261020-learnings-goose-gentledot-rea.md (R1)
resource: https://github.com/morluto/rea
---

# SE-449 — Estado epistémico en hallazgos e informes: observado, derivado, inferido, desconocido

## Problema

Savia exige honestidad radical (Rule 24) y verifica informes con el Truth Tribunal (SPEC-106, siete
jueces: veracidad, alucinación, trazabilidad de fuentes…), pero **no hay un vocabulario común y
legible por máquina que viaje con cada afirmación** y diga de qué tipo es. Hoy los jueces reconstruyen
a posteriori si una frase es algo que se leyó, se calculó, se dedujo o no se sabe. El síntoma más
frecuente es escribir «no hay X» cuando lo cierto es «no se ha buscado X» (falta de cobertura leída
como ausencia). Los informes de investigación recientes lo declaran a mano
(«no verificado», «por verificar»).

## Valor y evidencia

- REA (MIT) lo trata como regla de proyecto: distinguir observaciones, derivaciones, inferencias y
  desconocidos; **la cobertura ausente es desconocida, no ausencia**; mantener separadas las
  relaciones observadas, derivadas e inferidas y conservar las no resueltas
  (`AGENTS.md`, `docs/tool-design.md`).
- El coste se paga una vez en el productor del informe y lo aprovechan el tribunal, la persona que
  lee y los recibos de Space, que hoy no distinguen una cita verificada de una suposición.
- Evidencia limitada: es un patrón de otro proyecto, sin medición propia. S1 incluye medir cuánto
  cambian los veredictos del tribunal antes de generalizar.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Regla `docs/rules/domain/epistemic-status.md`: cuatro valores `observed` (leído o ejecutado, con fuente), `derived` (calculado de observados, con la derivación), `inferred` (deducido, sin comprobación directa) y `unknown`; «sin cobertura» se escribe siempre `unknown`, nunca como «no hay». Define la sintaxis máquina: etiqueta final `{e:observed}` en las líneas de hallazgo de `output/research/` y de informes verificados. La lectura humana la renderiza en lenguaje llano («comprobado», «calculado», «deducido», «no sé»). |
| S2 | El Truth Tribunal (`scripts/truth-tribunal.sh`) y `/report-verify` leen la etiqueta cuando existe: una afirmación `observed` sin fuente enlazada, o `derived` sin derivación, es hallazgo de trazabilidad. Sin etiqueta no cambia nada (compatible). |
| S3 | Esquema de recibos de Space: campo opcional `epistemic` con los mismos cuatro valores. Se publica como delta, sin cambiar los recibos existentes. |

## Fuera de alcance

- Etiquetar retroactivamente informes ya entregados.
- Exigir la etiqueta en comunicaciones con personas (chat, respuestas cortas): el artefacto máquina lleva la etiqueta; la presentación se escribe en lenguaje natural.
- Sustituir `verification-lattice` ni los jueces del tribunal.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `docs/rules/domain/epistemic-status.md` existe, define los cuatro valores y la regla «sin cobertura = unknown», con un ejemplo correcto y uno incorrecto. |
| AC2 | `bats tests/test-epistemic-status.bats`: un informe de fixture con `Afirmación X {e:observed}` sin enlace de fuente genera el hallazgo `EPISTEMIC_UNSOURCED`; con enlace, no. |
| AC3 | El mismo BATS: una línea `{e:derived}` sin la sección de derivación referenciada genera `EPISTEMIC_NO_DERIVATION`. |
| AC4 | Un informe sin ninguna etiqueta produce el mismo veredicto del tribunal que antes (regresión, 0 cambios). |
| AC5 | Medición S1: sobre 5 informes reales de `output/research/` etiquetados, se publica cuántas afirmaciones caen en cada categoría y si el tribunal cambió algún veredicto; el informe incluye casos negativos. |
| AC6 | `capability-entropy.py --check` PASS y `validate-ci-local.sh --quick` verde. |

## Riesgos

- Ruido y carga en informes cortos: por eso la etiqueta es del artefacto máquina y opcional.
- Etiquetar mal (`observed` por costumbre): el tribunal solo comprueba que haya fuente; no
  garantiza que la fuente diga lo que se afirma.
- Riesgo de burocracia sin beneficio medible: AC5 es la condición para generalizar.

## Licencia de lo reutilizado

Solo la distinción conceptual; sin texto ni código copiado. REA es MIT.

## Esfuerzo

S1 S, S2 S–M, S3 S. Total M.

## Decisiones pendientes de la operadora

- **D1**: sintaxis de la etiqueta (`{e:observed}` propuesta) frente a un campo en tabla.
- **D2**: si el tribunal pasa de hallazgo informativo a bloqueo para `EPISTEMIC_UNSOURCED` tras medir (AC5).

## Referencias cruzadas

SPEC-106 (Truth Tribunal), SE-444 (autoridad del verificador: misma preocupación sobre cobertura no
verificada, aplicada a AC), SE-332 (Handback: bloqueo escala al padre, aplicable a informes con muchos `unknown`).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/truth-tribunal.sh` y `/report-verify` | comando + script bash | comando equivalente + mismo script |
| Regla `epistemic-status.md` | `docs/rules/domain/` | mismo fichero |

### Verification protocol

- [ ] Funciona en ambos motores: la lógica es bash común.
- [ ] Tests BATS cubren la rama con etiqueta y sin ella.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**
