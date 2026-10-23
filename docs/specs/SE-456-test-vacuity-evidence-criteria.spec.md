---
status: APPROVED
approved_at: 2026-10-23
approved_by: "operadora, AskUserQuestion 2026-10-23"
priority: P1
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L2
related_specs: [SE-444, SE-453, SE-454, SE-376]
origin: vaults/SaviaLabs/labs/research/20261020-learnings-goose-gentledot-rea.md (criterio de pruebas de REA)
resource: https://github.com/morluto/rea/blob/main/docs/testing.md
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-456 — Tests que no pueden fallar: detector de vacuidad y criterio de evidencia de REA en la QA de Savia

## Problema

Un test que no puede fallar certifica lo que sea. En Savia hay al menos dos formas de escribirlo en BATS que pasan la
CI y el auditor de calidad:

1. **Aserción anulada.** `grep -q "hash" "$f" || true` o `[[ "$output" =~ X ]] || true` nunca fallan. Ejemplo:
   `tests/bats/test-se255-constitucion.bats`, AC-6.4 («la atestación incluye hash»), pasa aunque la atestación no lo
   incluya.
2. **`run` sin mirar el resultado.** `run` captura el código de salida; si después no se comprueba `$status` ni
   `$output`, el test pasa igual. Ejemplo: `tests/bats/test-se255-push-gate.bats`, AC-2.1 («pr-plan --gate-mode sale con
   exit 1 si hay FAIL»), ejecuta el gate y termina con `true`.

Medición sobre `main` (`139268c0`, 16 649 tests) con el detector de S1: 59 tests que no pueden fallar (54 V1 y
5 V2), más los débiles V3 (`run` con el estado ignorado pero con otras aserciones detrás), que se informan aparte. Al
reparar los dos ejemplos de arriba apareció un defecto real: la «firma» de todas las atestaciones de
`savia-attest.sh` era el sha256 del fichero vacío (`e3b0c442…`), porque se calculaba sobre la salida recién truncada.

Además, el auditor de calidad (`scripts/test-auditor-engine.py`, SPEC-055, umbral 80) cuenta los casos positivos,
negativos y límite **por el nombre del test** (`error`, `invalid`, `empty`…) y la calidad de las aserciones por la
presencia de patrones en cualquier parte del fichero. Un fichero con todas sus aserciones anuladas puede certificar.
Y el paso de CI «Gate: Test Quality (SPEC-055 — all tests >= 80)» (`scripts/ci-test-quality-gate.sh`) sale siempre
con 0 («advisory only»): el propio gate no puede fallar. El ratchet de S3 es su primera parte bloqueante.

## Valor y evidencia

REA (MIT) fija un criterio de pruebas que Savia no tiene escrito (`docs/testing.md`, `docs/tool-design.md`,
`docs/reconstruction-readiness.md`):

- «Paths, compiled imports, and suite names do not establish test depth»: los nombres no establecen profundidad.
- Una aserción previa que no puede fallar no añade cobertura.
- `fail`, `unknown`, `unsupported`, `truncated` y `skipped` **nunca suman `pass`**; un fallo tipado de la CLI que sale
  con 0 invalida la preparación.
- La autoridad no disponible se informa como **skip con nombre**, no como éxito; la cobertura no verificada se declara.
- Al podar tests se conservan los casos de entrada malformada, cancelación, limpieza, permisos, capacidad e identidad
  del objetivo; antes de borrar una regresión se identifica el escenario que la sustituye.
- La validez de un esquema y las heurísticas de palabras clave no demuestran que una herramienta se seleccione bien:
  hay que evaluar tareas representativas. Lo mismo vale para las skills de Savia: el auditor de disparo por palabra
  clave no mide si disparan (ver el informe de agentskills en SaviaLabs).

SE-444 ya trajo la autoridad del verificador. Esta spec trae el resto del criterio al nivel de cada test.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | `scripts/test-auditor-engine.py` gana `vacuity`: por fichero, la lista de tests con (V1) una línea de aserción (`[`, `[[`, `test`, `grep -q`) terminada en `|| true` o `|| :` sin `&&`, o (V2) un `run` cuyo `$status`/`$output`/`$lines` no se comprueba antes del siguiente `run` o del final del test. Cada hallazgo lleva fichero, test, línea y tipo. Determinista, sin LLM. |
| S2 | Un fichero con hallazgos de vacuidad **no certifica** (`certified: false`), aunque sume 80. La puntuación no cambia (no se toca el umbral). |
| S3 | Ratchet en `scripts/ci-test-quality-gate.sh`: `.ci-baseline/test-vacuity.count` con el número actual congelado. Más hallazgos que la línea base hace fallar el gate; menos, avisa de que hay que bajar la línea base. Los ficheros existentes no rompen la CI el primer día. |
| S4 | Regla `docs/rules/domain/test-evidence-criteria.md`: el criterio de REA adaptado (lista de «Valor y evidencia»), con ejemplos BATS de cada antipatrón y su arreglo. Enlazada desde `test-quality-gate.md`. |
| S5 | Arreglo de los casos confirmados por S1, por tandas: cada test se repara con una aserción real, o se borra si su escenario está cubierto por otro test (citado en el commit). Un test reparado que falla **destapa un defecto**: se arregla la causa o se deja un issue con el fallo, nunca se vuelve a anular. |

## Fuera de alcance

- Sustituir el cálculo por nombres del auditor (c3, c4, c5): se decide con datos tras S1 (decisión D2).
- Detectar vacuidad en pytest o vitest: BATS concentra casi todos los tests de Savia.
- Cambiar el umbral 80 ni el modo adaptativo del gate.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bats tests/test-se-456-test-vacuity.bats` pasa con fixtures que cubren V1 (`grep -q x f \|\| true`, `[[ … ]] \|\| true`), V2 (`run cmd` sin comprobar, `run cmd` seguido de `true`) y los **casos que no deben marcarse**: `run` + `[ "$status" -eq 0 ]`, `run` + `[[ "$output" == *x* ]]`, `cmd \|\| true` en una línea que no es aserción, `[[ -f x ]] && y \|\| true`. |
| AC2 | Un fichero fixture que suma 80 o más con un hallazgo de vacuidad sale con `certified: false`; el mismo fichero sin el hallazgo, con `certified: true`. |
| AC3 | `ci-test-quality-gate.sh`: con la línea base en N, N+1 hallazgos falla (exit distinto de 0) y N pasa; N-1 pasa con aviso de bajar la línea base. Probado con una línea base de fixture, sin tocar la real. |
| AC4 | `.ci-baseline/test-vacuity.count` existe y coincide con lo que mide el detector sobre `main` en el commit del PR. |
| AC5 | La regla de S4 existe, tiene los seis puntos del criterio y un ejemplo antes/después por antipatrón; `test-quality-gate.md` la enlaza. |
| AC6 | S5, primera tanda: los dos ejemplos de «Problema» (AC-6.4 de `test-se255-constitucion.bats` y AC-2.1 de `test-se255-push-gate.bats`) quedan reparados o sustituidos, y la línea base baja en consecuencia. |
| AC7 | `capability-entropy.py --check` PASS; `sam.py check` FRESH; `validate-ci-local.sh --quick` verde. |

## Riesgos

- **Falsos positivos** (un `run` cuyo resultado se comprueba de forma indirecta, por ejemplo con un fichero de salida).
  Mitigación: AC1 fija los casos que no se marcan; el ratchet no rompe lo existente; la línea base se ajusta con datos.
- **Falsos negativos** (vacuidad por otras vías, como `set +e` o funciones auxiliares que tragan errores). Se declaran en
  la regla como «lo que el detector no demuestra».
- **Reparar destapa fallos reales.** Es el objetivo, pero puede llenar una tanda de trabajo. Mitigación: tandas pequeñas
  y un issue por fallo destapado.

## Licencia de lo reutilizado

REA es MIT. Se toma el criterio, no el código: el detector se escribe desde cero sobre BATS.

## Esfuerzo

S1 y S2: S. S3: S. S4: S. S5: M, en tandas.

## Decisiones pendientes de la operadora

- **D1**: si el ratchet de S3 entra bloqueando o solo avisando (propuesta: bloqueando sobre la línea base, como el resto
  de ratchets).
- **D2**: si se cambia el cálculo por nombres del auditor después de ver los datos de S1 (propuesta: spec aparte).

## Referencias cruzadas

SE-444 (autoridad del verificador y skip con nombre), SE-453 (contrato de resultado de los gates: desconocido no es
limpio), SE-454 (invariantes negativos con su caso negativo), SE-376 (ratchet), SPEC-055 (auditor de tests),
`docs/rules/domain/test-quality-gate.md`, `docs/rules/domain/checker-fail-closed.md`.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `test-auditor-engine.py`, `ci-test-quality-gate.sh` | scripts del repo, en CI y en `validate-ci-local.sh` | los mismos |
| Regla `test-evidence-criteria.md` | lectura bajo demanda | la misma |

### Verification protocol

- [ ] Los scripts corren sin frontend.
- [ ] Los tests BATS no dependen del frontend.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: Python y bash del repo, sin bindings de frontend.
