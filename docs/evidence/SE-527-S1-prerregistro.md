# SE-527 S1 — Prerregistro de la validación de la retirada

Commiteado antes de la primera llamada. Cualquier cambio posterior va a «Desviaciones» del informe (`SE-527-S1-validacion.md`), nunca aquí. Método: D3 de la spec SE-527, que hereda el de SE-511 D4/D4b.

## Qué se valida

S1 retira cuatro agentes que solo existían en `.opencode/agents/`. La spec fija para este slice una validación de nivel mínimo («no hay agente fusionado cuyas tareas medir»):

- **(a) `fiction-framing-judge` y `structural-framing-judge`**: `mode: disabled` en `config/judge-routing.yaml` desde 2026-07-26 («never fires»). No hay comportamiento que comparar con un modelo: nunca se despachan. Se valida por tests deterministas: el Recommendation Tribunal y `/coherence-court` siguen enrutando sin sus filas (`judge-routing-verify.sh` PASS, `test-se273-s1-judge-routing.bats`) y una fila sobrante sin fichero de agente hace fallar el verificador (`test-se527-s1-retire-unused.bats`). Sin llamadas a modelos.
- **(b) `tabular-analyst` → skill `tabular-intelligence`** y **`configurator` → `docs/RESOLVER.md` + `docs/rules/domain/resolver-protocol.md`**: A/B con el arnés de SE-511.

## Arnés

`tests/evals/se527-s1/run.py` carga `tests/evals/se511-d4/run.py` sin modificarlo y lo apunta al directorio de cada experimento: mismas llamadas (`claude -p`, sin herramientas, sin settings, sin MCP, sin persistencia; una respuesta de más de un turno o con ficheros creados cuenta como `tool_effect` y no como respuesta válida), mismo bootstrap pareado por caso (10 000 iteraciones, semilla 20261110), mismo orden aleatorio con la misma semilla y la misma regla `run.py::verdict`.

| Experimento | Variante A (agente retirado, `e61539b02`) | Variante B (sustituto, árbol de la PR) |
|---|---|---|
| `dispatch` | `.opencode/agents/configurator.md` (3 130 B) | `docs/RESOLVER.md` + `docs/rules/domain/resolver-protocol.md` (39 103 B) |
| `tabular` | `.opencode/agents/tabular-analyst.md` (1 105 B) | `.claude/skills/tabular-intelligence/SKILL.md` (1 313 B) |

Textos congelados en `tests/evals/se527-s1/<exp>/variants/{A,B}.md` con SHA-256 en `meta.json`; `run.py` se niega a correr si no coinciden.

## Corpus y comprobaciones

8 casos por experimento (4 `trap`, 4 `golden`), en `tests/evals/se527-s1/<exp>/corpus.json`, con una regla léxica determinista por caso en `checks.py` (sin juez LLM). `test_checks.py` prueba cada regla con al menos una respuesta que cumple y otra que no (42 comprobaciones, 0 fallos; un id desconocido falla cerrado).

- **dispatch**, trap: T1 cúpula → `context-dome-manager`/`savia-vaults`; T2 «arregla los tests» → un target de tests y nunca `overnight-sprint` ni `code-improvement-loop` (restricción de `configurator`); T3 revisión por tribunal → `court-orchestrator`/`code-reviewer` y sin orden de merge; T4 intent desconocido → `smart-routing` u otro descubridor. Golden: G1 FastAPI, G2 memoria, G3 arquitectura, G4 seguridad; sobreactuar = negarse, pedir aclaraciones o no dar un target válido.
- **tabular**, trap: T1 media exacta (28,2) y atípico (95); T2 no inventar el mes que falta; T3 correlación no es causa (variable común); T4 avisar de muestra de tres datos. Golden: G1 dispersión relativa, G2 mediana, G3 cuartil, G4 máximo de una tabla; sobreactuar = negarse o exigir `tabular-profile.py`/un perfil previo para una cuenta trivial.

## Ejecución

- Modelos: `sonnet` y `haiku` (alias de Claude Code; el modelo resuelto queda en `raw.jsonl`). 3 repeticiones. 2 experimentos × 8 casos × 2 variantes × 2 modelos × 3 = 192 respuestas.
- Hasta 3 intentos por unidad solo ante error de llamada (lo hace el arnés). Una sola pasada: sin repeticiones extra ni casos nuevos tras ver resultados.

## Decisión

Por experimento y modelo, `run.py::verdict` sin cambios (B − A): REVERT si el cumplimiento baja más de 0,05 o la sobreactuación sube más de 0,10; GO si la cota inferior del IC 95 % del cumplimiento queda por encima de −0,05, la sobreactuación no sube (diferencia ≤ 0) y la cota superior de su IC es ≤ 0,10; NO CONCLUYENTE en otro caso. Global de un experimento: GO solo si Sonnet y Haiku dan GO.

- **GO en un experimento**: la retirada de ese agente se mantiene en la PR.
- **REVERT o NO CONCLUYENTE**: ese agente sale del slice (AC-S3): se restaura su fichero y sus referencias en la PR y el recuento sube en consecuencia; el informe da los datos y la siguiente hipótesis. No se repite la medición hasta que salga GO; un corpus ampliado exige un prerregistro nuevo.
- Los dos jueces de marco se deciden por (a), no por este A/B.

## Amenazas conocidas

- Con 8 casos por experimento el IC es ancho: un NO CONCLUYENTE es probable aunque B no empeore (ya pasó en SE-511 D4).
- Las variantes difieren mucho en tamaño en `dispatch` (3 KB frente a 39 KB): es la sustitución real, no un sesgo a corregir. Los tokens de entrada se reportan con su Δ %.
- Los dos agentes retirados mandan usar una herramienta (`tabular-profile.py`) o emitir JSON; sin herramientas, A no puede seguir su propio procedimiento. Las reglas miden el resultado de la tarea, no el formato.
- Límites heredados de SE-511: solo texto, sin sistema de ficheros, reglas léxicas, dos modelos de Claude, A y B no medidas simultáneamente (orden aleatorio mezclado).
