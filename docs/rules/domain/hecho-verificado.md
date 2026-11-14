# Hecho verificado — declarado, verificado, refutado

> SE-530 S1. Carga bajo demanda (no `@import`). Lo deriva `scripts/hecho-verificado.py` en lectura; nada se guarda.

Un trabajo que su ejecutor declara terminado sigue «declarado» hasta que una comprobación que no hizo el ejecutor lo confirma.

## Estados (D1)

| Estado | Condición |
|---|---|
| `refutado` | Una comprobación independiente, sobre el SHA vigente, dio resultado negativo. |
| `verificado` | Sin refutación y con al menos una comprobación independiente, aprobada, superada y sobre el SHA vigente. |
| `declarado` | Todo lo demás: sin recibo, recibo ilegible, ejecutor desconocido, solo comprobación propia, SHA anterior. |

Precedencia: `refutado` > `verificado` > `declarado`. Una comprobación que falla pesa más que cien que pasan.

## Independiente (D2)

1. El verificador no es el ejecutor.
2. El verificador no es la orquestadora que despachó el trabajo, salvo clase mecánica (`ci_base`, `postcondicion`). Misma lista que `merge-sprint.sh`.
3. Lo comprobado no lo escribió el ejecutor. `ci_propio` (CI cuyas pruebas relevantes añadió el ejecutor) y `autodeclaracion` no cuentan.

Una comprobación que propone el ejecutor (D3) no cuenta hasta que la aprueba la persona, ligada al hash de esa comprobación. Una verificación de un SHA anterior no cuenta (D4). Un campo de estado escrito por el ejecutor se ignora.

## Qué dice la orquestadora (D5)

La orquestadora no usa «terminado», «listo» ni «hecho» para un trabajo `declarado`.

- `declarado`: «declarado, sin verificar» y la razón (qué falta).
- `verificado`: quién lo verificó y sobre qué SHA.
- `refutado`: qué comprobación falló.
- Resumen: tres cifras separadas, verificados / declarados sin verificar / refutados. Un declarado no se suma a los terminados.

Un trabajo `declarado` se puede usar; lo que no se puede es llamarlo terminado.

## Uso

```
python3 scripts/hecho-verificado.py classify <marca-de-fin> [--evidence F] [--reviews F] --repo <repo|owner/repo>
python3 scripts/hecho-verificado.py measure --done-dir <dir> [--window 14] [--until AAAA-MM-DD] --repo <repo|owner/repo>
python3 scripts/hecho-verificado.py check-prereg <prerregistro> <medicion>
```

`classify`: estado en la primera línea de stdout; salida 0 verificado o declarado legible, 1 refutado, 2 marca ilegible (declarado por fallo cerrado). Prerregistro y medición: `docs/evidence/SE-530-S1-*.md`.

`--repo` (`repo` u `owner/repo`, sin distinguir mayúsculas) es necesario cuando la marca cita una URL de GitHub: sin él la marca es `declarado`. Una marca que cita varias PR distintas es `declarado` (la escribe el ejecutor; no se elige la que convenga), y si la evidencia asocia el job a una PR, la marca debe citar esa. Un error interno sale con 2, nunca con 1. `declarado` y `verificado` salen ambos con 0: quien consuma el resultado debe leer la primera línea, no `$?`. Una falla de la orquestadora o con verificador igual al ejecutor no refuta, pero impide `verificado`. D3 es fail-closed: un registro de clase no mecánica sin `propuesta_por` se toma como propuesto por el ejecutor y exige aprobación de la persona. Supuesto de S1: `--done-dir` es plano (`measure` rechaza nombres de job repetidos); en S2 el recolector fija `propuesta_por` y el job se identifica por ruta relativa.
