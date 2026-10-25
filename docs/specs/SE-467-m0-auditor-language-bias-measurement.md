# SE-467 M0 — Sesgo de idioma del auditor de tests: medición

> Evidencia de `docs/specs/SE-467-auditor-language-bias.spec.md` (PROPOSED). Decisión D2 de SE-456.
> Medido el 2026-10-24 sobre `main` en `045a82319`. El motor (`scripts/test-auditor-engine.py`) **no se tocó**:
> la variante se ejecuta en local importando el motor y sustituyendo solo el cálculo de c3, c4 y c5.

## Qué se midió

Los 896 ficheros `.bats` de `tests/` se puntuaron con tres variantes. Las tres comparten c1, c2 y c6 a c9, y el bloqueo
por vacuidad, del motor actual; solo cambian c3 (positivos), c4 (negativos) y c5 (límite).

| Variante | c3/c4/c5 |
|---|---|
| **Motor** | El actual: negativo = el nombre casa con `error\|fail\|missing\|invalid\|bad\|block\|reject\|skip\|disabled\|no.arg\|graceful\|empty`, o hay `[ "$status" -ne 0 ]` (cuenta apariciones); positivo = el resto; límite = nombre con `empty\|nonexistent\|large\|boundary\|zero\|null\|timeout…`. |
| **+ES** | Igual, más un léxico en español sobre el **nombre**: negativo (`falla`, `falta`, `inválid`, `rechaz`, `bloque`, `deneg`, `inexistente`, `nunca`, `vacío`, `exit 1`, `no crea/escribe/modifica…`) y límite (`vacío`, `límite`, `frontera`, `umbral`, `máximo`, `mínimo`, `cero`, `tope`, `longitud`…). |
| **+ES+cuerpo** | +ES y, además, patrones de comportamiento sobre el **cuerpo** del test: negativo si alguna aserción solo pasa cuando el script falla (`[ "$status" -ne 0 ]`, `-eq N` con N≥1, `-gt 0`, `!= 0`, `assert_failure`, `run !`, `run -N`); límite si la entrada es vacía de verdad (`< /dev/null`, argumento `""`, `: > fichero`); positivo si no es negativo **o** comprueba éxito (`-eq 0`, `assert_success`). Un test puede ser positivo y negativo a la vez. |

Se excluyó `sin` del léxico tras una primera pasada: casaba con nombres como «búsqueda sin servidor de embeddings», que no
son casos negativos. El medidor tiene un test propio que comprueba los tres clasificadores con muestras sintéticas
(incluido un caso negativo: un nombre inglés neutro con `-eq 0` no se vuelve negativo) y que la variante «Motor»
reproduce c3 y c5 del motor y el resultado completo en los 896 ficheros.

## Resultado global

| | Ficheros | Media | Mediana | Certifican (≥80, sin vacuidad) | <60 | 60-79 | ≥80 |
|---|---|---|---|---|---|---|---|
| Motor | 896 | 79,7 | 85 | **654** | 116 | 126 | 654 |
| +ES | 896 | 80,9 | 86 | **683** | 98 | 115 | 683 |
| +ES+cuerpo | 896 | 81,5 | 87 | **682** | 95 | 119 | 682 |

| Cambio frente al motor | +ES | +ES+cuerpo |
|---|---|---|
| Ficheros que pasan a certificar | 32 | 33 |
| Ficheros que dejan de certificar | 3 | 5 |
| Ficheros que suben / bajan de nota | 134 / 13 | 212 / 9 |

Medida aparte, la combinación que propone la spec (léxico en español + clases no excluyentes, sin patrones de cuerpo
para negativos ni límites) da 685 certificados: +33 y −2 (`test-scl-011-orchestrator` 81 → 76,
`test-workspace-integrity` 83 → 78). Con ella solo un fichero en inglés baja c3 (`scripts/test-validate-spec.bats`,
de 15 a 10), y no por el español: el patrón `exit [1-9]` del léxico casa con «nonexistent file returns exit 2». Ese
patrón es neutro respecto al idioma y la spec lo saca del léxico.

## Por idioma de los nombres

Idioma por fichero: proporción de nombres de test con marcas del español (tildes, ñ o palabras funcionales como «el»,
«que», «cuando», «devuelve»). 198 ficheros tienen al menos la mitad de los nombres en español, 642 tienen menos del 10 %
y 56 son mixtos.

| Grupo | Ficheros | Media motor → +ES | Certifican motor → +ES → +ES+cuerpo | c4 medio motor → +ES | c5 medio motor → +ES |
|---|---|---|---|---|---|
| Nombres en español (≥50 %) | 198 | 72,4 → 77,2 | 85 → 113 → 114 (43 % → 57 %) | 10,1 → 12,9 | 4,4 → 7,2 |
| Nombres en inglés (<10 %) | 642 | 82,2 → 82,3 | 532 → 532 → 531 (83 %) | 12,9 → 13,0 | 6,9 → 6,9 |

La brecha de certificación entre ficheros en inglés y en español es de 40 puntos porcentuales con el motor (83 % frente
a 43 %); el léxico en español la reduce a 26. Sobre los ficheros en inglés el léxico es casi neutro (0 entran, 0 salen),
lo que indica que no infla por sí mismo. Los patrones de cuerpo sí afectan a los ficheros en inglés (78 suben de nota,
2 dejan de certificar): no son un arreglo de idioma, son un cambio de criterio.

## Grupos S03 (pruebas de comportamiento validadas con mutación)

| PR | Ficheros | Mutantes muertos | Certifican motor → +ES → +ES+cuerpo | Media motor → +ES |
|---|---|---|---|---|
| #1349 S03 | 10 | sin medir; tests **renombrados** en inglés | 10 → 10 → 10 | 87,0 → 88,0 |
| #1360 S03c | 17 | 38/39 (97 %) | 2 → 14 → 14 | 72,6 → 85,0 |
| #1364 S03d | 10 | 257/268 (96 %) | 2 → 4 → 4 | 72,3 → 79,8 |
| #1366 S03e | 10 | 474/500 (95 %) | 0 → 5 → 5 | 64,5 → 78,5 |
| #1368 S03f | 10 | 179/195 (92 %) | 1 → 4 → 4 | 69,2 → 77,7 |
| #1369 S03g | 10 | 337/356 (95 %) | 3 → 8 → 8 | 75,5 → 85,5 |
| #1377 S03h | 9 | 222/254 (87 %) | 1 → 2 → 2 | 65,7 → 77,9 |
| **Mutación ≥90 % (#1360-#1369)** | **57** | 1285/1358 | **8 → 35 → 35** | 71,1 → 81,8 |

Las cifras de mutación son las publicadas en cada PR (mutación manual, con equivalentes analizados). En los 57 ficheros
con mutación ≥90 %, c4 pasa de 10,5 a 15 de media y c5 de 3,0 a 9,2; c3 se queda en 15. Ningún fichero S03 baja.

El grupo #1349 es el contraejemplo útil: sus nombres se reescribieron en inglés describiendo lo que ya hacía cada test, y
certifica 10 de 10 con el motor actual. Renombrar funciona; la pregunta es su coste.

### Lo que el idioma no explica

Con +ES+cuerpo siguen por debajo de 80 22 de los 57. En 20 de esos 22, c3, c4 y c5 ya están al máximo (15, 15 y 10);
lo que les falta es otra cosa:

- **c2 (`set -uo pipefail` literal en el test)**: 0 en 20 de los 22. Con c2 a 10 certificarían 17 de los 22. En todo el
  repositorio hay 194 ficheros con c2 = 0, y 42 de ellos quedan entre 70 y 79 con +ES+cuerpo.
- **c7 (cobertura por nombre de función)**: 2,9 de media; los tests ejercitan los scripts por CLI, no por nombre de función.
- **c8 (referencia a spec)**: 5,5 de media.

Ninguno de estos tres criterios se mide aquí; se señalan porque una decisión sobre c3 a c5 no cierra la brecha de S03 sola.

## Ficheros que dejarían de certificar

| Fichero | Motor | +ES | +ES+cuerpo | Causa |
|---|---|---|---|---|
| `test-workspace-integrity.bats` | 83 | 68 | 78 | Los 10 nombres describen el caso bueno y el malo («igualar el baseline pasa; uno más falla»): todos pasan a negativos y los positivos caen de 6 a 0 (de 4 con cuerpo). |
| `test-savia-memory.bats` | 88 | 78 | 88 | Igual: «rechaza» y «omite» en nombres que también prueban el camino bueno; con cuerpo se recupera. |
| `test-scl-011-orchestrator.bats` | 81 | 71 | 76 | «no escribe», «no modifica», «no ejecuta»: invariantes negativos reales; quedan 2 positivos (4 con cuerpo). |
| `test-validate-ci-fresh.bats` | 82 | 82 | 77 | Cuerpo: 12 tests pasan a negativos por afirmar un estado de salida ≠ 0; quedan 3 positivos. |
| `test-se405-config-snapshot.bats` | 84 | 84 | 79 | Cuerpo: un test más pasa a negativo y los positivos quedan en 4. |
| `structure/test-agents-md-drift-check.bats` | 81 | 81 | 76 | Cuerpo: 6 negativos, 2 positivos. |

Todas las pérdidas tienen la misma causa: el motor trata positivo y negativo como **clases excluyentes** (positivo = «no
negativo»). Reconocer más negativos resta positivos. Que un fichero con 10 tests de error tenga «0 positivos» no es
falso, pero tampoco es lo que el criterio quiere medir cuando el mismo test comprueba las dos ramas.

## Coste de la opción (b), renombrar

De los 18 750 tests, 1 483 (en 320 ficheros) cambian de clase con el léxico en español (1 214 por negativo y 540 por
límite; algunos por ambas), que habría que renombrar con palabras clave en inglés para obtener la misma nota. Es una cota: no todos esos
ficheros están por debajo de 80, y un renombrado sin cambiar el test no cambia lo que prueba.

## Límites de la medición

- El léxico es una lista cerrada escrita a mano, como la del motor. Puede faltar vocabulario y tiene falsos positivos
  (se quitó `sin`; puede haber más). No se revisaron a mano los 1 483 nombres que cambian de clase; sí los de los
  ficheros que pierden certificación.
- La detección del idioma por fichero es heurística (marcas del español en el nombre).
- «Comportamiento» aquí es léxico sobre el cuerpo (qué estado de salida se afirma), no ejecución. Un test que afirma
  `-ne 0` puede seguir siendo débil; el detector de vacuidad de SE-456 es independiente y no cambia.
- La correlación entre nota y mutación solo está disponible en los 66 ficheros S03 con mutación publicada; no hay
  medición de mutación del resto del repositorio, así que no se afirma que +ES «mida mejor» en general.

## Reproducir

El medidor y su test no se versionan (no son superficie del producto). Se ejecutan desde una copia local con:

```bash
python3 measure.test.py <repo>                      # test del medidor (debe imprimir OK 896)
python3 measure.py <repo> grupos-s03.json filas.json # 896 filas: nota y c3/c4/c5 por variante
```

`grupos-s03.json` sale de `git show --name-only` de los siete commits S03 (`d941dc3a6`, `6aee24cc6`, `5e64cddac`,
`ac4cc177c`, `bc4934311`, `42c51c42c`, `14e55c1fa`), solo los `.bats`. Las expresiones regulares exactas de la variante
están en el apéndice.

## Apéndice A — Expresiones de la variante

```python
NEG_ES = (r'(fall[ao]n?\b|fallo|\bfalta|ausente|inv[aá]lid|incorrect|malformad|corrupt|'
          r'rechaz|bloque|deneg|prohib|inexistente|no existe|desconocid|abort|\bnunca\b|'
          r'ignora|omite|err[oó]ne|vac[ií][oa]|fuera de|sale con [1-9]|c[oó]digo [1-9]|exit [1-9]|'
          r'no (?:se )?(?:crea|escribe|imprime|toca|acepta|pasa|cambia|borra|ejecuta|lanza|sale|deja|'
          r'devuelve|filtra|marca|cuenta|repite|bloquea|aplica|permite|admite|sube|duplica|modifica))')
EDGE_ES = [r'vac[ií][oa]', r'inexistente', r'no existe', r'grande', r'enorme', r'l[ií]mite', r'frontera',
           r'umbral', r'm[aá]xim', r'm[ií]nim', r'\bcero\b', r'\bnul[oa]\b', r'sin argumento', r'sin arg',
           r'\btope\b', r'desbord', r'tiempo de espera', r'caducad', r'exactamente', r'\bjusto\b',
           r'extremo', r'unicode', r'espacios', r'longitud', r'\bborde\b']
# Cuerpo: aserciones que sólo pasan si el script falla (rama negativa ejercitada de verdad).
NEG_BODY = re.compile(r'\[\[?\s*"?\$\{?status\}?"?\s*(?:-ne\s*0|-gt\s*0|-eq\s*[1-9]\d*|-ge\s*[1-9]|!=\s*"?0"?|==\s*"?[1-9])'
                      r'|assert_failure|^run\s+(?:!|-[1-9]\d*)\s|^!\s')
# Cuerpo: entrada límite real (stdin vacío, argumento vacío, fichero vacío).
EDGE_BODY = re.compile(r'<\s*/dev/null|^run\b.*\s(?:""|\'\')(?:\s|$)|^:\s*>\s*\S|printf\s+[\'"]{2}\s*\|')
# Cuerpo: aserción de éxito (rama positiva ejercitada de verdad).
POS_BODY = re.compile(r'\[\[?\s*"?\$\{?status\}?"?\s*(?:-eq\s*0\b|==?\s*"?0"?\s*\]|-le\s*0\b)|assert_success|^run\s+-0\s')
```

## Apéndice B — Ficheros S03 por variante

`c` = certifica. c2 = nota actual de `safety_verification`.

| Grupo (mutantes muertos) | Fichero | Tests | % nombres ES | Motor | +ES | +ES+cuerpo | c2 |
|---|---|---|---|---|---|---|---|
| #1349 S03 (sin medir) | `bats/test-se-305-dynamic-bats.bats` | 40 | 42 | 89 c | 89 c | 89 c | 10 |
| #1349 S03 (sin medir) | `bats/test-standards-compliance-gate.bats` | 26 | 92 | 80 c | 85 c | 85 c | 10 |
| #1349 S03 (sin medir) | `test-l13-meta-control.bats` | 26 | 73 | 81 c | 81 c | 81 c | 10 |
| #1349 S03 (sin medir) | `test-l13-meta-monitor.bats` | 28 | 86 | 81 c | 81 c | 81 c | 10 |
| #1349 S03 (sin medir) | `test-otel-emit.bats` | 28 | 50 | 93 c | 93 c | 93 c | 10 |
| #1349 S03 (sin medir) | `test-requirements-hashed.bats` | 19 | 79 | 89 c | 89 c | 89 c | 10 |
| #1349 S03 (sin medir) | `test-rule-manifest-generate.bats` | 18 | 56 | 91 c | 91 c | 91 c | 10 |
| #1349 S03 (sin medir) | `test-se269-ternary-verdict.bats` | 49 | 39 | 91 c | 96 c | 96 c | 10 |
| #1349 S03 (sin medir) | `test-session-registry.bats` | 34 | 28 | 80 c | 80 c | 80 c | 10 |
| #1349 S03 (sin medir) | `test-telemetry-tail-sample.bats` | 23 | 22 | 95 c | 95 c | 95 c | 10 |
| #1360 S03c (38/39) | `test-env-scrub.bats` | 22 | 91 | 70 | 90 c | 90 c | 10 |
| #1360 S03c (38/39) | `test-freetoken-probe.bats` | 23 | 78 | 65 | 80 c | 80 c | 10 |
| #1360 S03c (38/39) | `test-memory-store.bats` | 56 | 52 | 90 c | 90 c | 90 c | 10 |
| #1360 S03c (38/39) | `test-repeat-tool-guard.bats` | 28 | 89 | 73 | 83 c | 83 c | 0 |
| #1360 S03c (38/39) | `test-savia-env.bats` | 46 | 85 | 89 c | 94 c | 94 c | 10 |
| #1360 S03c (38/39) | `test-scl-002-cupula.bats` | 21 | 71 | 69 | 89 c | 89 c | 10 |
| #1360 S03c (38/39) | `test-scl-003-recall.bats` | 23 | 70 | 74 | 89 c | 89 c | 10 |
| #1360 S03c (38/39) | `test-scl-005-hibrido.bats` | 15 | 100 | 69 | 84 c | 84 c | 10 |
| #1360 S03c (38/39) | `test-scl-008-criterio-authority.bats` | 17 | 59 | 71 | 81 c | 81 c | 10 |
| #1360 S03c (38/39) | `test-scl-010-reconcile.bats` | 26 | 69 | 77 | 92 c | 92 c | 10 |
| #1360 S03c (38/39) | `test-scl-012-pruebas.bats` | 19 | 89 | 74 | 84 c | 84 c | 10 |
| #1360 S03c (38/39) | `test-scl-013-e2e.bats` | 21 | 90 | 74 | 89 c | 89 c | 10 |
| #1360 S03c (38/39) | `test-tabular-enforcement.bats` | 29 | 62 | 63 | 78 | 78 | 10 |
| #1360 S03c (38/39) | `test-tabular-monitor.bats` | 18 | 61 | 68 | 78 | 78 | 0 |
| #1360 S03c (38/39) | `test-tabular-predict.bats` | 14 | 56 | 68 | 78 | 73 | 0 |
| #1360 S03c (38/39) | `test-tabular-profile.bats` | 28 | 64 | 71 | 81 c | 81 c | 10 |
| #1360 S03c (38/39) | `test-turn-budget-inject.bats` | 20 | 85 | 70 | 85 c | 85 c | 10 |
| #1364 S03d (257/268) | `bats/test-se352-memory-origin-gate.bats` | 45 | 87 | 69 | 79 | 79 | 0 |
| #1364 S03d (257/268) | `test-failure-pattern-memory.bats` | 30 | 70 | 75 | 80 c | 80 c | 0 |
| #1364 S03d (257/268) | `test-fronema.bats` | 44 | 95 | 64 | 79 | 79 | 0 |
| #1364 S03d (257/268) | `test-learning-proposal-cue.bats` | 36 | 94 | 79 | 89 c | 89 c | 10 |
| #1364 S03d (257/268) | `test-scope-creep.bats` | 47 | 79 | 81 c | 91 c | 91 c | 10 |
| #1364 S03d (257/268) | `test-se-332-handback.bats` | 31 | 0 | 89 c | 89 c | 89 c | 10 |
| #1364 S03d (257/268) | `test-se252-bus-factor-scan.bats` | 63 | 79 | 71 | 71 | 71 | 0 |
| #1364 S03d (257/268) | `test-se252-distribute.bats` | 37 | 78 | 66 | 71 | 71 | 0 |
| #1364 S03d (257/268) | `test-se334-telemetry-fingerprint.bats` | 39 | 87 | 66 | 71 | 71 | 0 |
| #1364 S03d (257/268) | `test-sovereignty-s5.bats` | 30 | 73 | 63 | 78 | 78 | 0 |
| #1366 S03e (474/500) | `test-audit-chain.bats` | 41 | 95 | 65 | 80 c | 80 c | 0 |
| #1366 S03e (474/500) | `test-dco-check.bats` | 38 | 87 | 61 | 71 | 71 | 0 |
| #1366 S03e (474/500) | `test-goal-service.bats` | 41 | 83 | 78 | 83 c | 83 c | 0 |
| #1366 S03e (474/500) | `test-planning-transition.bats` | 34 | 65 | 74 | 79 | 79 | 0 |
| #1366 S03e (474/500) | `test-savia-trace.bats` | 25 | 76 | 62 | 82 c | 82 c | 0 |
| #1366 S03e (474/500) | `test-se251-pre-tribunal-gates.bats` | 41 | 54 | 72 | 77 | 77 | 10 |
| #1366 S03e (474/500) | `test-se269-implementation-readiness.bats` | 47 | 66 | 65 | 75 | 75 | 0 |
| #1366 S03e (474/500) | `test-se269-review-checkpoint.bats` | 54 | 69 | 52 | 77 | 77 | 0 |
| #1366 S03e (474/500) | `test-spill.bats` | 26 | 92 | 55 | 80 c | 80 c | 0 |
| #1366 S03e (474/500) | `test-token-meter.bats` | 29 | 83 | 61 | 81 c | 81 c | 0 |
| #1368 S03f (179/195) | `bats/release-invariants.bats` | 26 | 65 | 54 | 59 | 64 | 0 |
| #1368 S03f (179/195) | `bats/test-cognitive-debt.bats` | 26 | 81 | 68 | 68 | 68 | 0 |
| #1368 S03f (179/195) | `bats/test-opencode-config-validate.bats` | 28 | 61 | 59 | 69 | 69 | 0 |
| #1368 S03f (179/195) | `test-block-commit-to-main.bats` | 20 | 55 | 76 | 81 c | 86 c | 10 |
| #1368 S03f (179/195) | `test-learning-recall-hook.bats` | 22 | 55 | 71 | 91 c | 91 c | 10 |
| #1368 S03f (179/195) | `test-memory-consolidate.bats` | 26 | 85 | 80 c | 90 c | 90 c | 10 |
| #1368 S03f (179/195) | `test-recursion-guard.bats` | 27 | 26 | 69 | 74 | 74 | 0 |
| #1368 S03f (179/195) | `test-sealed-contracts.bats` | 32 | 31 | 69 | 79 | 79 | 0 |
| #1368 S03f (179/195) | `test-slm-registry-run.bats` | 19 | 68 | 67 | 77 | 77 | 0 |
| #1368 S03f (179/195) | `test-sycophancy-strip.bats` | 23 | 61 | 79 | 89 c | 89 c | 10 |
| #1369 S03g (337/356) | `test-action-review.bats` | 39 | 85 | 73 | 78 | 78 | 0 |
| #1369 S03g (337/356) | `test-blast-radius.bats` | 27 | 78 | 78 | 93 c | 93 c | 10 |
| #1369 S03g (337/356) | `test-block-sensitive-tracking.bats` | 19 | 84 | 67 | 82 c | 82 c | 10 |
| #1369 S03g (337/356) | `test-eval-lint.bats` | 52 | 75 | 79 | 89 c | 89 c | 10 |
| #1369 S03g (337/356) | `test-kg-pipeline.bats` | 20 | 50 | 80 c | 85 c | 85 c | 10 |
| #1369 S03g (337/356) | `test-layer-baseline-test.bats` | 32 | 72 | 82 c | 92 c | 92 c | 10 |
| #1369 S03g (337/356) | `test-resilience-report.bats` | 49 | 76 | 90 c | 90 c | 90 c | 10 |
| #1369 S03g (337/356) | `test-se269-forge-idea.bats` | 47 | 53 | 65 | 75 | 75 | 0 |
| #1369 S03g (337/356) | `test-se336-discovery-order.bats` | 30 | 87 | 68 | 83 c | 83 c | 10 |
| #1369 S03g (337/356) | `test-se336-turn-sdlc-report.bats` | 28 | 93 | 73 | 88 c | 88 c | 10 |
| #1377 S03h (222/254) | `bats/test-contract-pin.bats` | 48 | 90 | 67 | 77 | 77 | 0 |
| #1377 S03h (222/254) | `bats/test-savia-setup.bats` | 55 | 87 | 68 | 78 | 78 | 0 |
| #1377 S03h (222/254) | `bats/test-savia-workspace.bats` | 31 | 87 | 58 | 73 | 73 | 0 |
| #1377 S03h (222/254) | `bats/test-sdd-research-lane.bats` | 42 | 95 | 68 | 78 | 78 | 0 |
| #1377 S03h (222/254) | `bats/test-sldc-context-loop.bats` | 29 | 90 | 60 | 80 c | 80 c | 0 |
| #1377 S03h (222/254) | `test-incident-rca.bats` | 46 | 83 | 80 c | 90 c | 90 c | 10 |
| #1377 S03h (222/254) | `test-model-gateway.bats` | 30 | 67 | 70 | 75 | 75 | 0 |
| #1377 S03h (222/254) | `test-savia-catalog.bats` | 36 | 64 | 65 | 75 | 75 | 0 |
| #1377 S03h (222/254) | `test-se269-judge-calibration.bats` | 42 | 62 | 55 | 75 | 75 | 0 |
