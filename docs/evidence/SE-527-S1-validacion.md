# SE-527 S1 — Informe de validación de la retirada

Prerregistro: `docs/evidence/SE-527-S1-prerregistro.md`, commit `a7a6d1720`, anterior a la primera llamada. Base medida (variante A): `origin/main` `e61539b02`. Variante B: árbol de la PR en ese mismo commit. Datos crudos: `tests/evals/se527-s1/<exp>/results/raw.jsonl`; resumen: `summary.json`. Reproducir: `python3 tests/evals/se527-s1/run.py analyze --exp tabular` (y `--exp dispatch`).

## Veredicto

| Experimento | Modelo | Cumplimiento A → B (Δ, IC 95 %) | Sobreactuación A → B (Δ, IC 95 %) | Tokens de entrada A → B | Veredicto |
|---|---|---|---|---|---|
| `tabular` (`tabular-analyst` → skill `tabular-intelligence`) | Sonnet | 0,50 → 0,92 (+0,42, [0,00; 0,83]) | 0,33 → 0,00 (−0,33, [−0,75; 0,00]) | 1 074 → 1 168 (+8,8 %) | **GO** |
| | Haiku | 1,00 → 1,00 (0, [0; 0]) | 0,00 → 0,00 (0, [0; 0]) | 1 095 → 1 189 (+8,6 %) | **GO** |
| `dispatch` (`configurator` → `docs/RESOLVER.md` + `resolver-protocol.md`) | Sonnet | 0,75 → 1,00 (+0,25, [0,00; 0,75]) | 0,00 → 0,00 (0, [0; 0]) | 1 823 → 16 938 (+829 %) | **GO** |
| | Haiku | 0,75 → 1,00 (+0,25, [0,00; 0,75]) | 0,00 → 0,00 (0, [0; 0]) | 1 844 → 16 959 (+820 %) | **GO** |

**Global: GO en los dos experimentos** (Sonnet y Haiku GO en cada uno). Según el prerregistro, la retirada de `tabular-analyst` y de `configurator` se mantiene en la PR. 192 respuestas válidas de 192 (máximo 2 intentos por unidad, 0 `tool_effect`, 0 errores). Modelos resueltos: `claude-sonnet-5-5` y `claude-haiku-5-5`.

Los dos jueces de marco (`fiction-framing-judge`, `structural-framing-judge`) se deciden por la parte (a), sin modelos: `judge-routing-verify.sh` PASS con 31 filas y 31 jueces, `test-se273-s1-judge-routing.bats` en verde, y una fila sobrante sin fichero de agente hace fallar el verificador (antes solo avisaba; el test falla contra el verificador de `origin/main`).

## Qué pasó, caso a caso

- **dispatch, T1 cúpula**: A falla 3/3 en los dos modelos. La tabla de `configurator` no tiene fila para cúpulas y cae en `smart-routing`, o (Sonnet, una vez) intenta un `glob`. B responde `agent:context-dome-manager` 3/3 citando la fila OVERRIDE. Es el único caso que separa A de B en `dispatch`; los otros siete dan lo mismo en las dos variantes.
- **dispatch, T2**: ninguna variante propone `overnight-sprint` ni `code-improvement-loop`; la restricción de `configurator` no se pierde con el sustituto.
- **tabular, Sonnet A**: 10 de 24 respuestas fallan, y 9 de esas 10 son intentos de llamar a `tabular-profile.py` escritos como texto (el agente manda «invoca SIEMPRE tabular-profile.py» y «NUNCA procesar datos crudos»). En G4, una pregunta de una línea sobre quién tiene más horas, A sobreactúa 3/3 por eso. B resuelve con números exactos (28,2; atípico 95; Luis).
- **tabular, Haiku**: A y B empatan a 100 % en todos los casos.

## Límites y lectura honesta

- **Parte de la ventaja de B en `tabular` es un artefacto del arnés.** El arnés corre sin herramientas y `tabular-analyst` exige ejecutar un script; sin él, Sonnet intenta llamarlo en texto. Estaba declarado como amenaza en el prerregistro. No cambia la decisión: la regla pide que B no empeore, no que gane. Si se descuentan las 9 respuestas con llamada fingida, A y B quedan cerca del empate. Es una lectura exploratoria, no prerregistrada.
- **Una regla léxica penaliza a B una vez**: Sonnet B, T4 rep 2, escribe «Confianza baja: con n=3…» y la regla solo admitía «baja confianza». Es un falso negativo contra B. Se deja como está, porque las reglas estaban congeladas, y el veredicto se mantiene.
- **El sustituto de `configurator` cuesta más tokens**: unas 9 veces más de entrada como prompt de sistema (39 KB frente a 3 KB). No es un coste nuevo: `docs/RESOLVER.md` ya es la tabla que Savia consulta bajo demanda (`CLAUDE.md`, «Lazy Reference») y `configurator` no tenía ningún llamador. La retirada no cambia el contexto fijo por turno: `CLAUDE.md` tiene los mismos 3 489 bytes (solo cambia «90» por «86») y la PR no toca ninguno de sus tres @imports versionados. La medición `--versioned` en el árbol de la PR da 13 511 B. En una copia limpia de la base no se pudo repetir, porque falta el perfil local que importa `CLAUDE.md`. La igualdad con la base se deduce de esos bytes idénticos, no de una medición directa.
- Con 4 casos `trap` y 4 `golden` por experimento, los IC son anchos. Las cotas que deciden (inferior del cumplimiento ≥ 0 y superior de la sobreactuación ≤ 0) quedan dentro de la regla con margen, pero el corpus es pequeño.
- Límites heredados de SE-511: solo texto, sin sistema de ficheros, reglas léxicas, dos modelos de Claude, A y B medidas en orden aleatorio mezclado y no simultáneas.

## Desviaciones

- Ninguna sobre el método. Las variantes, el corpus, las reglas, la semilla y la regla de decisión son los del commit del prerregistro (`run.py` comprueba los SHA-256 antes de correr y de analizar).
- `test_checks.py` se ejecuta con `python3 tests/evals/se527-s1/test_checks.py` porque en la máquina de medición no hay pytest (no se instalan dependencias). Con pytest disponible corre igual.
