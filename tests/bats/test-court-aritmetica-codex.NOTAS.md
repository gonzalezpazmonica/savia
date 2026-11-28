# Court: pruebas cruzadas de aritmética

Fecha: 2026-11-27. Solo tests y estas notas; sin cambios de producto ni commits.
Base comprobada: `HEAD == origin/main`, commit
`ef702d97bd029f88ba86d194e2fa7f90e03b1bfa`.

## Reproducción

```bash
bats --formatter tap tests/bats/test-court-aritmetica-codex.bats
```

Resultado contra esa base: **45 tests, 27 pasan y 18 fallan; exit 1 esperado**.
Diez tests crean la marca de ejecución antes del rechazo: confirman inyección,
incluso si el proceso acaba después con un error aritmético. No se han corregido
estos fallos: la implementación corresponde a la otra autora.

La sonda es `COURT_TEST_ARRAY[$(printf 0 > "$COURT_TEST_MARKER")]`.
Solo escribe un fichero dentro del directorio temporal de cada test, cuya ruta
incluye espacios. Un control positivo ejecuta la misma sonda en Bash sin
validación y comprueba la marca. También se prueba literalmente `HOME[...]`,
sin modificar `HOME`, y una referencia indirecta a una variable de entorno.
El test de `check` sustituye únicamente `git diff --stat` por una fixture fija
de dos LOC; no depende del diff de la rama ni modifica ningún repositorio.

## Tests que fallan hoy

Números correspondientes al TAP del comando anterior:

| Tests | Entrada | Fallo observado |
|---|---|---|
| 7–10 | Contadores C, H, M, L | Ejecutan la sustitución de comandos. |
| 11 | `HOME[...]` en C | Ejecuta la sonda aunque Bash aborte después. |
| 12 | Variable indirecta en C | Resuelve la variable y ejecuta la sonda. |
| 13 | `1+1` como contador | Lo evalúa y acepta; el bucle se detiene en C al fallar la aserción. |
| 14 | C = -1 | Acepta el negativo y produce score 125. |
| 15–16 | C = 1.5 o 08 | Aborta por sintaxis de Bash; falta rechazo explícito de entrada. |
| 17 | C = 18446744073709551612 | Desborda y produce score 200 con veredicto pass. |
| 19 | `COURT_SCORE_PASS` | Ejecuta la sonda en la comparación. |
| 20 | `COURT_SCORE_CONDITIONAL`, score 0 | Ejecuta la sonda al alcanzar la segunda comparación. |
| 21 | `COURT_SCORE_CONDITIONAL`, score 100 | Acepta la configuración inválida por no alcanzar esa rama. |
| 22 | Umbrales = 101 | No rechaza la configuración; el bucle se detiene en `COURT_SCORE_PASS`. |
| 25 | `COURT_MAX_LOC` | Ejecuta la sonda en `check`. |
| 28 | `COURT_MAX_FIX_ROUNDS` | Ejecuta la sonda en `validate`. |
| 29 | Máximos = `1+1` | Evalúa la expresión y acepta; se detiene primero en `check`. |

Los tests exigen validación antes de cualquier evaluación, salida no exitosa y
diagnóstico `ERROR:` para entradas enteras inválidas. Un simple error de Bash
no demuestra que la entrada se validó. Los controles conservan la fórmula,
los argumentos omitidos equivalentes a cero, los límites 90/89 y 70/69,
la saturación a cero y los máximos configurables. La política de rechazo de
`08` sigue el precedente de `coherence-court.sh`, que impide octales implícitos.
No se prescribe una implementación concreta de la corrección.

## Otros scripts revisados

| Script | Cobertura y resultado |
|---|---|
| `court-review.sh` | Aritmética externa en cuatro contadores y cuatro variables de configuración. Diez reproducciones con ejecución de sonda; resto de fallos descritos arriba. |
| `coherence-court.sh` | Rechaza la sonda en los cuatro contadores, ambos umbrales de entorno tanto en `score` como en `gate`, score del gate y ambas opciones del gate. También referencias indirectas y números inválidos. Controles válidos verdes. |
| `court-turn-router.sh` | Rechaza la sonda y expresiones en `--round` y `--max-round`; selección temprana y frontera de última revisión verdes. |
| `court-score-aggregator.sh` | Los datos numéricos externos se convierten con Python, sin aritmética Bash. Como regresión adicional: sonda en `score`, `weight`, `blocking_threshold` por stdin y en ambos umbrales de entorno; todos rechazados sin ejecución. JSONL numérico válido aceptado. |
| `coherence-gates.sh` | Comparaciones Bash sobre estados internos inicializados y códigos de salida del shell, sin valor numérico externo directo. No se ejecuta toda su batería desde estos tests. |

No se afirma ausencia universal de vulnerabilidades: se cubren estas entradas
y sondas concretas. La política de flotantes especiales del agregador, el
desbordamiento de rondas del router y otros contratos quedan fuera de esta
prueba de inyección. No se modifican specs ni planificación.

## Verificación y límites

- Segunda ejecución del fichero final: mismo resultado, 27/45 pasan,
  18 fallan y 10 detectan ejecución de sonda.
- Sensibilidad de aserciones: copia temporal exclusivamente del test, con
  aserciones de estado y de ausencia de marca invertidas. Resultado: 45/45
  fallan, incluidos los 27 antes verdes. Los 18 rojos ya fallan contra main.
  Esta comprobación no es mutation testing del código de producto ni una
  demostración del arreglo. No se ha cambiado producto ni siquiera para
  obtener una ejecución verde.
- `python3 scripts/test-auditor-engine.py tests/bats/test-court-aritmetica-codex.bats .`:
  88/100, `certified: true`, `vacuity: []`. Avisa V3 por no reconocer las
  aserciones encapsuladas en helpers; estas sí se ejecutan y se comprobaron
  invirtiéndolas. No hay `! cmd` ni `|| true` que oculten fallos en el fichero.
- Regresión existente: **43/43 pasan**, con el siguiente comando:

```bash
bats --formatter tap --filter '(score|round|validate|threshold|JSONL)' \
  tests/test-code-review-court.bats tests/test-se404-court-one-fix.bats \
  tests/test-court-turn-router.bats tests/test-se-350-coherence-court.bats \
  tests/test-se236-court-scoring.bats
```

- Clock-in: `validate-ci-local.sh --quick`: 15 PASS, 0 FAIL, 2 WARN previos
  (coherencia advisory y snapshot de documentación atrasado). Roadmap leído.
- No se ejecutó el cierre compartido `--clean-state` ni se accedió al handoff
  o registro de sesiones: la orden específica limita el acceso al worktree y
  al directorio de log asignado; ese cierre consulta otros worktrees.
- Sin commit, changelog, regeneración de derivados, firma, push ni PR por la
  instrucción específica de TDD cruzado. Los logs de ejecución se conservan
  solo en el directorio privado de log asignado.

Siguiente paso: entregar estos dos ficheros a la orquestadora y repetir la
batería después de integrar el arreglo independiente. Un resultado verde de
producto queda pendiente de esa implementación.
