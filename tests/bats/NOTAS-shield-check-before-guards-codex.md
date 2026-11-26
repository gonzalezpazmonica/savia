# NOTAS — regresión de BEFORE_GUARDS (Codex)

Medición del 2026-11-26 sobre `291b2bdc2`, base explícita de la tarea:
`origin/agent/fix-20261125-suite-nocturna` (PR #1669).
No se ha modificado el script, ni creado commits ni PR.

```bash
bats --tap tests/bats/test-shield-check-before-guards-codex.bats
```

Resultado actual: **17 casos, 10 pasan y 7 fallan; exit de BATS 1**.
Los fallos son regresiones esperadas de este encargo TDD cruzado: el arreglo
debe poner los 17 casos en verde sin rebajar ninguna aserción.

| Caso | Escenario | Esperado | Actual | Resultado |
| --- | --- | --- | --- | --- |
| 1 | Copia del árbol real | active / 0 | active / 0 | Pasa |
| 2 | Lista multilínea y comas finales | active / 0 | active / 0 | Pasa |
| 3 | Comentario al final de ambas líneas de guard | active / 0 | active / 0 | Pasa |
| 4 | `dataSovereigntyGate` solo en otra lista | inactive / 2 | active / 0 | **Falla** |
| 5 | `blockCredentialLeak` solo en otra lista | inactive / 2 | active / 0 | **Falla** |
| 6 | Fundación con solo comentario sobre `BEFORE_GUARDS` | inactive / 2 | active / 0 | **Falla** |
| 7 | Import de la lista sin uso | inactive / 2 | active / 0 | **Falla** |
| 8 | Uso de la lista sin import | inactive / 2 | active / 0 | **Falla** |
| 9 | Lista vacía, con imports de guards conservados | inactive / 2 | inactive / 2 | Pasa |
| 10 | `dataSovereigntyGateX` | inactive / 2 | inactive / 2 | Pasa |
| 11 | `blockCredentialLeakX` | inactive / 2 | inactive / 2 | Pasa |
| 12 | `dataSovereigntyGate` comentado con `//` | inactive / 2 | inactive / 2 | Pasa |
| 13 | `blockCredentialLeak` comentado con `//` | inactive / 2 | inactive / 2 | Pasa |
| 14 | `dataSovereigntyGate` dentro de comentario `/* … */` multilínea | inactive / 2 | active / 0 | **Falla** |
| 15 | `blockCredentialLeak` dentro de comentario `/* … */` multilínea | inactive / 2 | active / 0 | **Falla** |
| 16 | `before-guards.ts` ausente | inactive / 2 | inactive / 2 | Pasa |
| 17 | `savia-foundation.ts` ausente | inactive / 2 | inactive / 2 | Pasa |

Los siete falsos activos devuelven `missing: []` y los ocho componentes.
Cuando falta un único guard, la aserción exige que solo falte su cableado;
el guard sano y todos los demás componentes deben seguir presentes.
Cuando se rompe el vínculo con la lista, deben faltar ambos cableados.

## Causa observada

`guard_registered` busca el identificador en todo `before-guards.ts`, sin
delimitar `BEFORE_GUARDS` ni excluir comentarios de bloque. La comprobación
de la fundación usa `grep -q BEFORE_GUARDS`: no distingue comentario, import
y uso. Los casos 4–8 y 14–15 reproducen esas dos causas por separado.

## Aislamiento y comprobaciones

- Cada caso copia `.opencode` a `$BATS_TEST_TMPDIR/workspace` con `cp -RL`.
  Materializar los enlaces evita que `.opencode/hooks` quede roto o que una
  mutación escriba en el origen. Se copia también la documentación necesaria
  para evitar que un estado `partial` oculte el resultado del cableado.
- El script real se ejecuta con `SAVIA_WORKSPACE_DIR` y `--json`.
  Se comprueban el exit exacto, el estado y el contenido exacto de ambos
  arrays, incluidas sus longitudes. BATS retira sus temporales.
- Las sustituciones del fixture exigen una coincidencia exacta; si cambia el
  origen, el test falla antes de ejecutar una mutación que no haga nada.
- Suite existente: `bats --tap tests/bats/test-spec-oc-01-shield.bats`:
  **20/20 pasan, exit 0**.
- Autorrevisión de aserciones: dos copias temporales del test, eliminadas al
  terminar. Una exigía exit 1 en todos los casos; otra exigía un estado JSON
  imposible. En cada ejecución fallaron **17/17**, incluidos los diez casos
  antes verdes. No se modificó ninguna copia del script para verificarlas.
- `python3 scripts/test-auditor-engine.py tests/bats/test-shield-check-before-guards-codex.bats .`:
  73/100, `certified: false`, `vacuity: []`, `weak: []`. Su heurística no
  resuelve `SCRIPT` calculado en setup, busca límites con palabras inglesas
  y no reconoce la limpieza automática de BATS. Se conserva ese resultado;
  no se añaden pruebas de relleno para obtener una certificación.
- No se ejecutaron los gates globales `validate-ci-local.sh --quick` ni
  `--clean-state`: incluyen consultas fuera del worktree y comprobaciones
  ajenas al alcance autorizado. No se leyó ni actualizó el traspaso privado.

Siguiente acción: la autora del arreglo debe corregir checks 6 y 7 y volver
a ejecutar ambas suites. No se afirma que el escudo esté corregido.
