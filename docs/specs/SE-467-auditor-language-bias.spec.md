---
status: APPROVED
approved_at: 2026-10-27
approved_by: "operadora, AskUserQuestion 2026-10-27"
priority: P2
developer_type: agent-single
created: 2026-10-24
author: Savia
phase: D
risk: L2
related_specs: [SE-456, SE-376, SPEC-055, SE-444]
origin: SE-456 decisión D2; notas de las PR S03 #1360, #1364, #1366, #1368, #1369, #1377
evidence: docs/specs/SE-467-m0-auditor-language-bias-measurement.md
---

# SE-467 — El auditor de tests puntúa el idioma del nombre, no el caso probado

## Problema

`scripts/test-auditor-engine.py` (SPEC-055) decide si un test es positivo, negativo o de límite (c3, c4 y c5: 40 de los
100 puntos) por palabras clave **en inglés** en el nombre del test. La mayoría de las pruebas nuevas de Savia se nombran
en español, así que un caso negativo real («rechaza una ruta inexistente», «no modifica el store») no cuenta. Las seis
PR de S03 con pruebas de comportamiento lo señalan; SE-456 dejó la decisión abierta (D2) hasta tener datos. Medido sobre
`main` (`045a82319`), motor sin tocar, con una variante local que añade un léxico en español
(`SE-467-m0-auditor-language-bias-measurement.md`):

- **Brecha de certificación por idioma**: certifican el 83 % de los 642 ficheros con nombres en inglés y el 43 % de los
  198 con nombres en español. Con el léxico en español, el 83 % y el 57 %: la brecha baja de 40 a 26 puntos.
- **Grupos S03 con mutación ≥90 %** (57 ficheros, 1 285 de 1 358 mutantes muertos): certifican **8** con el motor y
  **35** con el léxico en español. c4 sube de 10,5 a 15 de media y c5 de 3,0 a 9,2. Ninguno baja.
- **Renombrar funciona**: el grupo #1349, renombrado en inglés, certifica 10 de 10 con el motor actual.
- **Coste de renombrar**: 1 483 de 18 750 tests (320 ficheros) cambian de clase con el léxico; serían los renombrados.
- **El léxico no infla los ficheros en inglés**: 0 entran y 0 salen de la certificación.
- **Defecto estructural**: positivo se define como «no negativo». Reconocer más negativos resta positivos, y por eso 3
  ficheros dejarían de certificar con el léxico (un mismo test comprueba la rama buena y la mala); con clases no
  excluyentes quedan 2.
- **El idioma no explica toda la brecha**: 22 de los 57 siguen por debajo de 80; en 20 de ellos c3 a c5 ya están al
  máximo y lo que falta es c2 (`set -uo pipefail` literal en el test, a 0 en 20 de los 22), c7 y c8.

## Valor y evidencia

- La nota del auditor decide la certificación y el ratchet de SE-376. Hoy premia una convención de nombres, no la
  profundidad: pruebas con mutación del 92-97 % quedan entre 52 y 79, y reconocer el nombre en español, sin cambiar el test, sube hasta
  25 puntos (10,7 de media).
  SE-456 ya cita el principio: «Paths, compiled imports, and suite names do not establish test depth».
- Sin decisión, cada grupo S03 nuevo repite el mismo dilema (renombrar para subir nota o dejarla baja) y la orquestadora
  no puede usar la nota para priorizar.

## Opciones

### (a) Cambiar el motor

| Pieza | Cambio | Efecto medido |
|---|---|---|
| a1 | Léxico en español junto al inglés para c4 y c5 (lista cerrada, como la actual) | 654 → 683 certificados (+32, −3); +28 en S03; ningún fichero en inglés entra ni sale |
| a2 | Clases no excluyentes: positivo = comprueba éxito (`-eq 0`, `assert_success`) **o** no es negativo; un test puede contar en ambas | a1 + a2: 654 → 685 (+33, −2); recupera `test-savia-memory` y deja las otras dos pérdidas en 76 y 78 |
| a3 | Negativo por cuerpo: aserción que solo pasa si el script falla (`-ne 0`, `-eq N≥1`, `assert_failure`, `run !`); límite por entrada vacía real (`< /dev/null`, `""`) | a1 + a2 + a3: 654 → 682 (+33, −5). Independiente del idioma, pero cambia el criterio también en inglés: 78 ficheros en inglés suben, 2 dejan de certificar |

Ventajas: mide lo que el criterio pretende, sin tocar los tests. Coste: S. Riesgo: un léxico en dos idiomas es más
superficie que mantener, y a3 cambia notas de ficheros que nadie ha tocado.

### (b) Renombrar

Reescribir los nombres para que incluyan las palabras clave en inglés, como en #1349. Ventajas: el motor no cambia.
Coste: hasta 1 483 nombres en 320 ficheros, M a L por tandas. Riesgo: optimiza el nombre para el auditor (Goodhart), choca
con el idioma de trabajo del repositorio y no hace que ningún test pruebe más.

### Recomendación

**(a) con a1 y a2**; **a3 como decisión aparte** (D2), porque deja de ser un arreglo de idioma y cambia el criterio para
todo el repositorio. No se propone (b) salvo para ficheros concretos cuyo nombre sea engañoso.

## Alcance (si se elige (a))

| Slice | Entrega |
|---|---|
| S1 | a1 + a2 en `test-auditor-engine.py`, con los umbrales de c3 a c5 sin cambios (≥5, ≥4, ≥3). El léxico de a1 contiene solo palabras en español: la medición incluía `exit N`, que es neutro y bajó c3 en el único fichero en inglés afectado (`test-validate-spec.bats`); queda fuera de a1 y, si se quiere, entra con a3. Test BATS de invariancia de idioma: dos fixtures con los mismos cuerpos y nombres en inglés y en español puntúan igual en c3, c4 y c5. |
| S2 | Reauditoría completa con `scripts/test-auditor.sh --all`, publicada con antes/después por fichero; los ficheros que pierden certificación se listan con la causa y se revisan uno a uno (no se reetiquetan para recuperarla). |
| S3 | Solo si D2 lo aprueba: a3, con su propia medición antes/después en ficheros en inglés. |

## Fuera de alcance

- Cambiar el umbral 80 o los pesos de los criterios.
- c2 (`set -uo pipefail`), c7 (cobertura por nombre de función) y c8 (referencia a spec): explican el resto de la brecha
  de S03 pero son otra decisión; se abre spec aparte si la operadora lo pide.
- Sustituir el léxico por un modelo o por mutación automática: el motor es determinista por diseño (SPEC-055).
- El detector de vacuidad de SE-456: no cambia y sigue bloqueando la certificación.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bats tests/test-test-auditor-engine-language.bats` pasa: el fixture en español y su traducción al inglés obtienen el mismo c3, c4 y c5. |
| AC2 | Caso negativo de AC1: un fixture en español sin ningún caso negativo real («devuelve el total», «lista los ficheros») obtiene c4 = 0; el léxico no convierte en negativo cualquier nombre en español. |
| AC3 | Test de a2: un test cuyo nombre es negativo y cuyo cuerpo afirma `[ "$status" -eq 0 ]` cuenta como positivo y como negativo. |
| AC4 | Sobre los 642 ficheros en inglés de la medición M0, ninguna nota de c3 o c4 baja por a1 (comparación por fichero en la reauditoría de S2). |
| AC5 | La reauditoría de S2 se publica con los ficheros que pierden certificación y su causa; ninguno se recupera cambiando su nombre. |
| AC6 | `python3 -m pytest` o BATS existentes del auditor en verde (`tests/` que referencian `test-auditor-engine.py`), y `capability-entropy.py --check` PASS. |

## Riesgos

- Léxico incompleto o con falsos positivos (la medición quitó `sin`). Mitigación: AC2 y revisión de los cambios de clase
  en la reauditoría.
- Sube la nota sin que suba la profundidad de los tests ya escritos. Es el efecto buscado solo donde el caso existe; la
  vacuidad (SE-456) sigue bloqueando y la evidencia de mutación sigue siendo la prueba fuerte.
- Ratchet: si la línea base de SE-376 se calcula con la nota, subirla de golpe congela el nuevo nivel. S2 publica la línea
  base nueva antes de activarla.

## Esfuerzo

S1 S, S2 S, S3 S. La opción (b), M a L por tandas.

## Decisiones pendientes de la operadora

- **D1**: (a) cambiar el motor o (b) renombrar (propuesta: (a) con a1 y a2).
- **D2**: incluir a3, negativo y límite por el cuerpo del test (propuesta: aparte, después de S2, con su propia medición).
- **D3**: abrir spec para c2 (`set -uo pipefail`), que es el siguiente limitante de S03 (propuesta: sí, tras S2).

## Referencias cruzadas

SE-456 (D2, vacuidad y criterio de evidencia), SE-376 (deuda de calidad y ratchet), SPEC-055 (motor determinista),
SE-444 (autoridad del verificador: un nombre no es evidencia), PR #1349, #1360, #1364, #1366, #1368, #1369, #1377.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/test-auditor-engine.py` y `scripts/test-auditor.sh` | script Python/bash invocado por comandos y CI | el mismo script |
| Tests del auditor | BATS independientes del frontend | los mismos |

### Verification protocol

- [ ] Los tests corren sin frontend.
- [ ] La reauditoría de S2 se ejecuta igual desde los dos frontends (mismo script, misma salida JSON).
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: cambio en un script determinista y sus tests; ningún binding de frontend.
