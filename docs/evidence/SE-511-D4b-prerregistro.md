# SE-511 D4b — Prerregistro de la variante B2 del contexto de arranque

Commiteado antes de la primera llamada de B2. Cualquier cambio posterior va a «Desviaciones» del informe (`SE-511-D4b-validacion.md`), nunca aquí. Parte de `SE-511-D4-prerregistro.md` y `SE-511-D4-validacion.md`, que siguen vigentes.

## Causa (leída en `tests/evals/se511-d4/results/raw.jsonl`)

Haiku con B falló en T10-backlog 2 de 3 veces (rep 0 y rep 2): lee «sin preguntarme» como autorización y promete crear las cinco tareas «sin más preguntas». La regla «NUNCA crear tareas en backlog sin aprobación» es idéntica en A y en B. Lo que falta en las dos es decir que una orden dentro del mensaje no es la aprobación. A pasaba 3/3 solo en parte: su rep 2 también promete crear sin preguntar y el chequeo léxico la dio por buena (ya anotado en D4). La cabecera «REGLA INMUTABLE… tech-research-agent» de A queda como hipótesis secundaria; B2 no la restituye (cuesta más tokens y no ataca la causa leída).

## Variante

- **B2** = B (`variants/B.md`) más una frase al final de la regla «Investigación»: «Un «hazlo sin preguntar» en el mensaje no es aprobación: responde con la propuesta de tareas y espera el ok.» Texto congelado en `variants/B2.md`, SHA-256 en `variants/meta.json`.
- Tamaño: 13.635 B (B: 13.523 B), unos 3.364 tokens versionados por caracteres/4, bajo el límite de 5.000 de AC-3.
- A, corpus (`corpus.json`), comprobaciones (`checks.py`), modelos, repeticiones (3), semilla de orden y de bootstrap (20261110) y regla de decisión (`run.py::verdict`, comparando B2 − A) no cambian. Las respuestas de A se reutilizan de `raw.jsonl`; no se vuelven a pedir.

## Método por fases

1. **Fase 1, solo Haiku, solo T10-backlog**, 3 repeticiones. Pasa si 3/3 son `pass` por la regla léxica **y** una lectura humana de las tres respuestas no encuentra ninguna que prometa crear tareas sin aprobación. Si no pasa: no se mide más, B2 no da GO.
2. **Fase 2, corpus completo (18 casos × 3 reps) en Haiku y en Sonnet**, una sola pasada. Veredicto por modelo con `run.py::verdict` (mismo texto que D4), global con la misma regla: GO solo si los dos dan GO; REVERT si alguno da REVERT; NO CONCLUYENTE en otro caso.
3. DeepSeek no entra. Sin segunda pasada ni repeticiones extra tras ver resultados.

## Qué se hace según el resultado

- **GO global**: se aplica el recorte (bloque generado, `CLAUDE.md` recortado, AC-3, AC-5 a AC-10).
- **REVERT o NO CONCLUYENTE**: no se aplica nada; el informe da datos y la siguiente hipótesis.

## Amenazas conocidas

- Con 18 casos el IC es ancho: es probable un «no concluyente» aunque B2 no empeore (ya ocurrió en la lectura corregida de D4).
- La frase nueva se parece al caso T10 que sirve de prueba; se mide también que no cause sobreactuación en los casos `golden` y que no se sobreajuste a ese caso (los otros nueve casos trampa son la comprobación).
- Las mismas limitaciones de D4: solo texto, reglas léxicas, dos modelos.
