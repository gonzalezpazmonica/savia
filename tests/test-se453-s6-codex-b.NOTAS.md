# SE-453 S6 — TDD cruzado Codex

Fecha: 2026-11-27. Base ejecutada: `ef702d97bd029f88ba86d194e2fa7f90e03b1bfa`
(`HEAD` coincide con `origin/main`, sin cambios previos).

Encargo: exclusivamente tests y estas notas. No se modificó producto ni se
hicieron commits, push, PR, generadores o cambios de estado de specs.

## Ejecución contra main

```bash
bats tests/test-se453-s6-codex.bats
```

Resultado: **23 tests, 15 rojos esperados, 8 verdes, 0 saltos; salida 1**.
Los rojos alcanzan el daemon simulado y fallan al exigir salida `2` del hook
real: la lista actual permite coincidencias parciales y rebaja `BLOCK` a aviso.
No son fallos de herramientas ni de preparación del entorno.

| Test | Entrada sintética / escenario | Resultado actual |
|---|---|---|
| 1 | `Microsoft test-client confidential client` | ROJO |
| 2 | `HTTP confidential test-client` | ROJO |
| 3 | `Chrome confidential test-client` | ROJO |
| 4 | `API-prod-key-test-client` | ROJO |
| 5 | `github.com/test-org/secret-roadmap` | ROJO |
| 6 | `from Persona Prueba Sintetica` | ROJO |
| 7 | `10.23.45.67:8080` | ROJO |
| 8 | `db-prod.example.invalid:8443` | ROJO |
| 9 | `TEST_pwd=12345678` | ROJO |
| 10 | `test-client timeout=5 confidential` | ROJO |
| 11 | `timeout=5 confidential test-client` | ROJO |
| 12 | `RuntimeError Persona Prueba Sintetica` | ROJO |
| 13 | `mIcRoSoFt confidential test-client` | ROJO |
| 14 | Dos entidades: Microsoft y la IP del corpus | ROJO |
| 15 | Código legítimo `timeout=5`: WARN con auditoría | VERDE |
| 16 | Siete tokens completos legítimos: WARN con auditoría | VERDE |
| 17 | Persona sintética sin token de código: BLOCK | VERDE |
| 18 | `HTTP` y persona sintética: BLOCK | VERDE |
| 19 | `HTTP` en destino `docs/fixture.md`: BLOCK | VERDE |
| 20 | `Edit/new_string`: entidad Microsoft del corpus | ROJO |
| 21 | `Edit/new_string`: token `JSON` legítimo | VERDE |
| 22 | Función TS: las mismas 13 entidades del corpus | VERDE |
| 23 | Función TS: los mismos siete tokens completos | VERDE |

Los siete tokens compartidos son `Microsoft`, `HTTP`, `Chrome`, `github`,
`JSON`, `Path` y `RuntimeError`. El caso `timeout=5` impide dar por bueno un
arreglo que simplemente añada `$` y rompa el ejemplo legítimo de S4.

## Aislamiento y alcance de la comprobación TS

Se ejecuta `.opencode/hooks/data-sovereignty-gate.sh` sin copiar ni modificar
su código. El transporte `curl` se dobla mediante PATH: no usa red, daemon ni
LLM. Cada caso exige health y POST, compara el JSON completo enviado con la
entrada por stdin y comprueba diagnóstico y auditoría de la decisión.
Una herramienta ausente hace fallar el test; no hay saltos ni PASS de reserva.
Los fixtures y la auditoría viven en el directorio temporal de cada test.

En `scripts/opencode-plugin` no existe una lista SH01 gemela. Sí existe
`isCodeToken()` en `.opencode/plugins/lib/sovereignty-patterns.ts`: tiene
anclas de inicio y fin y rechaza las 13 entidades del corpus. Los tests 22–23
importan esa función real con Bun y reutilizan las entradas del hook.
Actualmente no tiene llamadas desde el guard TS; estos tests son de función,
no una demostración de bloqueo del guard TS ni de paridad entre frontends.

Límite explícito: esa función TS devuelve `false` para `timeout=5` (sonda
ejecutada), mientras que el hook Bash conserva WARN. El control legítimo de
S4 se exige al hook Bash; no se extiende S6 para cambiar una función TS sin
uso fuera de la ubicación gemela indicada en el encargo.

## Autorrevisión y verificaciones

Los 15 tests de regresión fallan contra el producto original. Para los ocho
verdes se creó una copia temporal de la suite y se cambiaron las expectativas
de salida `0`/`2` por `99`: **8/8 pasaron a rojo en sus aserciones**. No se
modificó producto para esta comprobación ni se dejaron mutaciones en la suite.
Esto demuestra que pueden fallar; no sustituye la mutación del futuro arreglo.

```bash
python3 scripts/test-auditor-engine.py tests/test-se453-s6-codex.bats .
bats tests/test-data-sovereignty-labs-dest.bats tests/test-data-sovereignty-labs-dest-n1.bats
bash scripts/validate-ci-local.sh --quick
```

Auditor: **85/100, certified=true, vacuity=[], weak=[]**; no resuelve el target
calculado, por lo que su nota es auxiliar. Suites existentes: **17/17 verdes**.
CI rápida de entrada: **15 comprobaciones verdes, 0 fallos, 2 avisos**
(coherencia en advisory y snapshot de documentación atrasado).

No se ejecutó `--clean-state`: recorre otros worktrees y el traspaso privado,
excluidos expresamente por este encargo. Tampoco se leyó o actualizó el
traspaso privado ni se registró la sesión fuera de la carpeta de log permitida.

Siguiente acción: la otra autora implementa S6 y ejecuta esta suite sin
modificar sus expectativas; deben conservarse los controles negativos verdes.
