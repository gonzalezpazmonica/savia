# Revisión de graduación, lote grad-a (S27, 2026-11-10)

Medido sobre `9c3284e98` (main). Cada fichero lista los AC uno a uno con la orden ejecutada y su resultado. No se ha cambiado el `status` de ninguna spec ni se ha corregido nada: graduar lo decide la operadora.

| Spec | Recomendación | Resumen |
|---|---|---|
| [SE-442](SE-442-20261110.md) | GRADUAR | 9 AC; AC5 solo local (los jobs de GitHub no se ejecutan aquí). Dos excepciones de `pip install` del test no figuran en la spec. |
| [SE-444](SE-444-20261110.md) | GRADUAR | 7/7 AC cumplidos, con mutación. |
| [SE-445](SE-445-20261110.md) | RESTO | 9/9 AC con tests en verde; falta el test de paridad OpenCode (necesita `bun`) y la medición con revisor real. |
| [SE-451](SE-451-20261110.md) | GRADUAR | AC1-4 y 7 cumplidos; AC5 no aplica; AC6 (REUSE) no se hizo por decisión D3. |
| [SE-453](SE-453-20261110.md) | RESTO | 10/10 AC; queda abierto el delta de `data-sovereignty-gate.sh` (hueco real hallado por S4) y el ciclo de aviso de `unknown`. |
| [SE-433](SE-433-20261110.md) | NO GRADUAR | 18 AC cumplidos, 4 parciales, 6 no cumplidos, 2 no verificables: el factor de autorización de §2.3 (`render-question`, respuesta literal) no está implementado; `skipped` cuenta como CI verde. |
| [SE-403](SE-403-20261110.md) | GRADUAR | 7/7 AC, con mutación. |
| [SE-404](SE-404-20261110.md) | GRADUAR | 9/9 AC, con mutación; L3 exige revisión humana del PR. |
| [SE-455](SE-455-20261110.md) | RESTO | 6 AC cumplidos; revisión legal (D1) pendiente, citas aún marcadas. |
| [SE-456](SE-456-20261110.md) | GRADUAR | 7/7 AC, con mutación; cuatro aserciones anuladas en `setup()` fuera del alcance del detector. |
| [SE-457](SE-457-20261110.md) | GRADUAR | 8 AC; sin test persistente de AC6/AC7. |

Método: órdenes de cada spec; mutación en copia temporal (nunca en el fichero real) cuando el test era la única evidencia; NO VERIFICABLE cuando exige red, GitHub, `bun`, credencial o la operadora.
