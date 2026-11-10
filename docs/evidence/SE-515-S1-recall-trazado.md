# SE-515 S1 — Recall trazado: informe

Spec: `docs/specs/SE-515-aprendizaje-aplicado-obligacion-comprobada.spec.md` (slice S1). Línea base: `docs/evidence/SE-515-S0-auditoria-linea-base.md` §2 («Cambio mínimo para S1»). Base: `origin/main` `a78c3bb70`.

Marcas: **O** observado (test o ejecución), **I** inferido, **NV** no verificado.

## 1. Qué se entrega

| Pieza | Cambio | AC |
|---|---|---|
| `scripts/learning-recall.sh` | La fila de `recall.jsonl` añade `returned_criteria` (ids devueltos) y `outcome` (`ok`, `no_vault`, `no_cli`, `error`). Las salidas con código 3 ya no se van sin fila | AC-3 |
| `.opencode/plugins/guards/learning-recall-guard.ts` | Fila `start` (`emitted:false`, `reason:"started"`) antes de llamar al recall y fila `end` con los ids emitidos y el motivo: `emitted`, `no_hits`, `timeout`, `unavailable`, `error`, `bad_output` o `write_failed`. Solo ids y `query_hash`; nunca el texto. Log: `output/learning-loop/recall-emission.jsonl` (`SCL_EMISSION_LOG`) | AC-3 |
| `scripts/learning-metric.sh` | Sin `--measured`, la salida sale marcada `no medido` (`"measured":false,"status":"no medido"` en JSON y `estado=no medido` en texto) | AC-4 |
| `scripts/savia-orchestrator.sh` | Pide el recall en `effective`. Si no está disponible, lo dice: `recall=shadow (declarado; efectivo no disponible: …)` o `recall=no disponible (…)`. La medida solo es `(medido)` si llegan los tres componentes (`--p-consistent`, `SAGI_L_DIVERGENCE`, `SAGI_L_IGNORANCE_RESOLVED`); si falta alguno, `(no medido: valores por defecto en …)`. No imprime «aprendió» | AC-4 |
| `scripts/learning-recall.sh ablation` | Arnés P10: recall apagado frente a encendido sobre los mismos casos, con un decisor externo. Filas por caso legibles por S09 (`case_id`, `decision_off`, `decision_on`, `changed`, `emitted_criteria`, `cost_ms_off`, `cost_ms_on`, `context_chars_on`), sin el texto del prompt. Veredicto: `cambio`, `sin efecto`, `sin muestra` o `incompleto` | AC-5 |
| Interruptor `SAVIA_LEARNING_APPLIED=off` | Guard, script, métrica y orquestador vuelven a la salida anterior; sin filas nuevas | AC-16 |

La fila `start` cubre lo que un tope no puede: si el proceso muere sin limpiar, queda `emitted:false`. Nunca hay ausencia de fila. Una consulta tiene el mismo `event_id` en `start` y `end`; `query_hash` cruza con `recall.jsonl`.

## 2. Lo que no se entrega: el hook de Claude Code

Editar `.claude/hooks/learning-recall-hook.sh` pidió permiso de fichero sensible. La sesión era headless y sin operadora: se trató como bloqueo de política y no se buscó otra vía. Consecuencias (**O**):

- En Claude Code, el hook sigue sin registrar la emisión. **AC-3 queda cubierto solo en OpenCode y en `learning-recall.sh`.**
- La verificación «el guard TS registra la misma fila que el hook ante la misma entrada» no se puede cerrar en el repo. La versión propuesta del hook y sus 10 tests (incluida la paridad fila a fila con el guard) se probaron fuera del repo: 10/10 en verde con el hook propuesto y 8/10 en rojo con el actual. Los dos que pasan con el actual son negativos que el hook de hoy ya cumple: los filtros no abren evento y el interruptor en off no deja filas. Los entrega la orquestadora a la operadora para que los aplique.

## 3. P10 en este árbol (AC-5)

Ejecución del arnés sobre el árbol de trabajo, con el hook real como inyector y un decisor constante (**O**):

```
{"cases": 3, "emitting_cases": 0, "changed": 0, "changed_controls": 0, "errors": 0, "verdict": "sin muestra"}
```

Motivo (**O**): en este árbol no existe `vaults/SaviaLearning`, así que `learning-recall.sh` sale con 3 y no se emite ningún criterio. «Sin muestra» no es «sin efecto»: el arnés los distingue a propósito, porque cero emisiones no prueban nada sobre la decisión.

**Lo que falta para un P10 real (NV):**
1. Ejecutarlo donde esté la cúpula y contar los pares (criterio humano, LP activa): entre 1 y 7, según S0 §2.
2. Casos congelados y etiquetados por personas o por el resultado de un gate (S0 §5), con commit y hash fijados antes de medir.
3. Un decisor real (el modelo con el contexto inyectado) cuya decisión se compare. Con decisor constante, el arnés solo comprueba la tubería.

## 4. Tests

- `tests/test-se515-s1-recall-trazado.bats`: 24 casos (script, guard TS, métrica, orquestador, arnés e interruptor), con negativos para cada AC. Antes del cambio fallaban todos salvo los negativos de interruptor y filtros (**O**). Los negativos AC-4 se mutaron: con la métrica siempre en `medido` y con el orquestador siempre medido, fallan (**O**).
- `tests/test-scl-003-recall.bats`: el contrato de la fila pasa a incluir `returned_criteria` y `outcome`. Se añade un caso que comprueba el formato anterior con el interruptor en off.
- Suites previas sin regresiones: `test-learning-recall-hook`, `test-scl-011-orchestrator`, `test-scl-001-s3-metrica`, `test-scl-001-s4-agnosticismo` (el arnés no nombra ningún frontend y recibe el inyector por `--injector`), `test-scl-008`, `test-scl-005`, `test-scl-012`, `test-scl-013`, `test-scl-001-e2e-bucle`, `test-scl-004`, `test-l13-meta-control` y el `bun test` del guard (**O**).

El arnés es un subcomando de `learning-recall.sh` y no un script aparte: como script nuevo subía la entropía de capacidades en 1 (1624 frente a 1623 de base).

## 5. AC de S1

| AC | Estado |
|---|---|
| AC-3 | **Parcial.** Cubierto en `learning-recall.sh` y en el guard de OpenCode, con los negativos de tope, muerte del proceso (SIGKILL; probado con el hook propuesto), fallo, sin aciertos y salida rota. Falta aplicar el hook de Claude Code |
| AC-4 | Cubierto (métrica y orquestador, con negativos) |
| AC-5 | **Arnés cubierto. Medida real pendiente**: resultado publicado `sin muestra` en este árbol |
| AC-16 | Cubierto en guard, script, métrica y orquestador. En el hook, pendiente de aplicarlo |
