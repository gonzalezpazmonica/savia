# SCL-003 — Recall operativo: recuperar lecciones de la cúpula cuando se trabaja

**Status:** APPROVED → IMPLEMENTED (2026-08-17)
**Fecha:** 2026-08-17
**Area:** Memoria / Epistemología / SaviaVaults / Hooks
**Branch:** agent/scl-001-aprendizaje-continuo
**Estimación:** ~5h (3 slices)

---

> **Supersesión parcial (SCL-008, 2026-08-17):** los AC que inyectaban snippets
> de propuestas quedan sustituidos por recall en sombra. Solo se inyectan
> principios de `CRITERIO.md` con autoría humana verificable y enlace
> `criterion_id`. Los AC históricos se conservan como registro.

## Origen

SCL-002 añadió la persistencia real (cúpula SaviaLearning) y la federación
(importar lecciones), pero **el bucle seguía sin ser útil en el momento de
trabajar**: las lecciones se guardaban, pero NADA las recuperaba cuando se
desarrollaba. Una cúpula sin recall es un cementerio de lecciones — la operadora
lo señaló con el ejemplo: "si trabajas con un desarrollo... ¿qué mecanismo hace
que los aprendizajes persistidos necesarios se recuperen de la cúpula cuando son
necesarios? Ninguno seguramente". Correcto: ninguno. Esta spec lo implementa.

## Diseño

```
captura → persistencia (SCL-002) → RECALL (SCL-003) → trabajo evita el error
                                      ↑
    UserPromptSubmit hook consulta la cúpula con el texto del prompt
    (BM25 de SaviaVaults) y devuelve las lecciones relevantes como contexto
    que el agente ve ANTES de responder.
```

## Slice 1 — `learning-recall.sh`

**AC-1.1.** Dado `--query "<contexto>"`, consulta la cúpula SaviaLearning con
BM25 (SaviaVaults search) y devuelve las lecciones relevantes formateadas
(test).

**AC-1.2.** Filtra por umbral de relevancia `--min-score` (default 5): lecciones
con score bajo (no relacionadas) no se devuelven → sin ruido (test).

**AC-1.3.** `--json` emite JSON válido con `hits[]` (path, score, snippet)
(test).

**AC-1.4.** Sin lecciones relevantes → exit 0 sin output (passthrough silencioso)
(test).

## Slice 2 — `learning-recall-hook.sh` (UserPromptSubmit)

**AC-2.1.** Registrado en `.claude/settings.json` (UserPromptSubmit). Master
switch `SAVIA_LEARNING_RECALL=on|off` (default on). Timeout 5s, exit 0 siempre
(nunca bloquea) (test + asercion settings).

**AC-2.2.** Con un prompt de trabajo relacionado (p. ej. "script que consulta
Azure DevOps con PAT"), inyecta las lecciones relevantes como contexto con el
aviso "NO reintroduzcas el error que documenta" (test E2E en producción).

**AC-2.3.** Con un prompt no relacionado (p. ej. "tiempo en Madrid"), NO inyecta
nada (umbral de score, sin ruido) (test).

## Slice 3 — Métrica de utilidad

**AC-3.1.** `learning-recall.sh` registra cada recall en
`output/learning-loop/recall.jsonl` (ts, query, hits) (test).

**AC-3.2.** Un recall con hits>0 demuestra que la lección se recuperó y llegó
al contexto del agente — la métrica de utilidad mínima del bucle (asercion).

## Validación en producción (2026-08-17)

Persistida la lección real "no hardcodear PAT, usar `cat $PAT_FILE`" (Rule #1).
Simulado el arranque de un desarrollo "crear script para consultar sprint en
Azure DevOps, autenticarme con el PAT" → el hook inyectó la lección con score
111.18 (máxima relevancia) ANTES de la respuesta del agente; log registró
hits:3. El bucle es operativo: la lección llegó al dev en el momento del trabajo.

## Verification method

1. Suite BATS `tests/test-scl-003-recall.bats` (7 tests).
2. E2E producción: prompt real → lección inyectada con score alto + log hits>0.
3. `hooks-integrity-check.sh` PASS tras registrar el hook.

## Out of scope

- Aplicación automática de la lección como gate (convertir lección activa en
  regla de gate bloqueante): requiere que la lección esté `human_authored` +
  mapeo a regla concreta. Follow-up (SCL-005 p_consistent / SE-292).
- Recall sobre memoria local (no cúpula): ya existe (memory-prime-hook,
  context-auto-prime). Este recall es específico de lecciones aprendidas.

## Referencias

- SCL-001/002: `docs/specs/SCL-001-aprendizaje-continuo.spec.md`,
  `docs/specs/SCL-002-cupula-aprendizaje.spec.md`
- Regla: `docs/rules/domain/scl-001-learning-loop.md`
- Scripts: `scripts/learning-recall.sh`, `.claude/hooks/learning-recall-hook.sh`

## Enmienda propuesta 2026-11-09 (repriorización tras Savia Viva R6)

> Propuesta en la misma PR que SE-513, SE-514 y SE-515. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **Límite conocido**: el recall se dispara con el texto del prompt de la persona, por similitud léxica, y solo entrega criterios `human_authored` (hoy uno). No hay consulta en el punto de decisión ni prueba de entrega. Lo aborda SE-515.
