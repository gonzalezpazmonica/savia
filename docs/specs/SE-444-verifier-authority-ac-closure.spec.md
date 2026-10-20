---
status: PROPOSED
priority: P0
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: A
risk: L2
related_specs: [SE-396, SE-376, SE-407, SE-378]
origin: output/research/20261020-learnings-goose-gentledot-rea.md (R2, D12)
resource: https://github.com/morluto/rea
---

# SE-444 — Autoridad del verificador en los criterios de aceptación y cobertura no verificada explícita

## Problema

El predicado de cierre de Savia comprueba que un criterio de aceptación (AC) tiene evidencia
(`planning_acceptance_evidence_valid` en `scripts/lib/planning-completion.sh`: tipo `criterion` + `file`
existente y dentro del repo). No comprueba **con qué autoridad se verificó**. Un AC cuyo texto exige
comportamiento real (un proveedor real, un TEE, una ejecución H04 con coste) puede cerrarse con una
prueba contra un doble y quedar indistinguible de uno cerrado en real. Es el patrón prohibido nº 9 de
`feedback_root_cause_always` («marcar IMPLEMENTED cuando los AC no se cumplen íntegramente»), con la
forma más difícil de ver: el fichero de evidencia existe y pasa.

Además, la plantilla de spec no registra de forma estructurada qué autorizó la persona, con qué
alcance y qué autorización sustituye a cuál. El resultado práctico es deriva del tipo «me dijeron que
sí a otra cosa» al revisar una spec larga.

## Valor y evidencia

- REA (MIT) cierra una obligación solo con dueño único, fixtures y un verificador cuya **autoridad es
  comparable a la observación original**; la ausencia de evidencia nunca cierra
  (`docs/reconstruction-obligation-ledgers.md`). Su guía de pruebas exige informar la cobertura no
  verificada de forma explícita, tratar «autoridad no disponible» como un skip con nombre, y no dar por
  establecido el comportamiento de un proveedor real con uno simulado (`docs/testing.md`).
- Encaja con la cola actual: S03 («no certificar por presencia de ficheros») y S04 (graduación H04/H09
  con canaries reales) son exactamente este problema.
- gentle-dot (MIT) registra en sus tareas citas literales de la persona con alcance y cadena de
  sustitución («superseded by S8»), incluida una nota de que una autorización de organización local no
  es autorización para publicar un PR (`odd/tasks/computer-working-rings.md`).

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Regla `docs/rules/domain/ac-verifier-authority.md`: valores `real`, `simulada`, `estatica`; un AC cuyo texto exige comportamiento real no se cierra con `simulada` ni `estatica`; la falta de autoridad se registra como skip con nombre y motivo (por ejemplo «sin HSM», «sin proveedor real»). |
| S2 | Plantilla de spec (`.claude/skills/spec-driven-development/references/spec-template.md`): la tabla de AC gana las columnas `autoridad_requerida` y `autoridad_obtenida`, y una sección opcional «Autorizaciones literales» (cita textual, alcance, fecha, «sustituida por»). |
| S3 | `scripts/lib/planning-completion.sh`: cada elemento de `acceptance_evidence` admite `authority` y `authority_required`. El validador **no cambia su resultado** (compatibilidad con lo ya integrado); añade una función que lista los AC con `authority` ausente o inferior a la requerida. |
| S4 | `scripts/validate-ci-local.sh` imprime una sección «Cobertura no verificada» con esa lista. Solo informa: el código de salida del predicado no cambia. |

## Fuera de alcance

- Convertir la cobertura no verificada en bloqueo: se decide con datos tras ver el informe (D1).
- Reclasificar retroactivamente las especificaciones ya cerradas: el informe las muestra como
  `authority` ausente, sin tocarlas.
- Cambiar el umbral de calidad ≥80 ni el ratchet de SE-376.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `docs/rules/domain/ac-verifier-authority.md` existe, define los tres valores y la regla de cierre. |
| AC2 | `grep -c 'autoridad_requerida' .claude/skills/spec-driven-development/references/spec-template.md` ≥ 1 y la plantilla contiene el encabezado «Autorizaciones literales». |
| AC3 | `bats tests/test-planning-completion-authority.bats`: con una evidencia de fixture `{criterion, file, authority:"simulada", authority_required:"real"}` la función de listado devuelve ese AC; con `authority:"real"` no lo devuelve. |
| AC4 | El mismo BATS comprueba que `planning_acceptance_evidence_valid` devuelve el **mismo resultado** que antes para evidencias sin los campos nuevos (regresión: 0 cambios sobre los casos de `tests/` existentes). |
| AC5 | `bash scripts/validate-ci-local.sh --quick` imprime «Cobertura no verificada» y su código de salida coincide con el de una ejecución sin la sección en el mismo árbol. |
| AC6 | `bash scripts/roadmap.sh validate` sigue en PASS. |
| AC7 | `capability-entropy.py --check` PASS (sin scripts nuevos: solo se amplían ficheros existentes). |

## Riesgos

- Fricción de cierre: es deliberada; el informe la hace visible antes de que sea bloqueante.
- Un campo `authority` autodeclarado por el mismo agente que cierra es débil. Por eso S3–S4 son
  informe y la revisión humana del cierre (SE-396) sigue siendo quien decide; esta spec no sustituye
  esa revisión.
- Clasificar mal qué AC «exige comportamiento real». La regla pide que lo declare el autor de la spec
  y lo revise la persona que la aprueba.

## Licencia de lo reutilizado

Solo el patrón y la terminología; sin copia de texto ni de código. REA y gentle-dot son MIT. La
sección de autorizaciones literales es de diseño propio inspirada en el formato de tareas de gentle-dot.

## Esfuerzo

S: reglas y plantilla (S1–S2), ~1 sesión; S3–S4 ~1 sesión más con sus pruebas.

## Decisiones pendientes de la operadora

- **D1**: cuándo pasa de informe a bloqueo para specs nuevas (propuesta: tras ver el informe sobre dos
  cierres reales, con ratchet y no con un umbral fijo).
- **D2**: si la sección «Autorizaciones literales» es obligatoria o solo recomendada en specs de riesgo L3+.

## Referencias cruzadas

SE-396 (graduación operacional), SE-376 (deuda de calidad con pruebas de comportamiento), SE-407
(baseline), SE-378 (estado de planificación), SE-443 (sus AC de Space dependen de esta distinción).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/lib/planning-completion.sh`, `validate-ci-local.sh` | bash, invocados igual | bash idéntico |
| Plantilla de spec y regla | skill SDD y `docs/rules/domain/` | leídos como ficheros |

### Verification protocol

- [ ] Funciona con ambos motores: no hay binding de frontend.
- [ ] Tests BATS cubren el camino de la librería y del informe.
- [ ] No añade hooks.

### Portability classification

- [x] **PURE_BASH**
