# NOTAS — regresión de BEFORE_GUARDS (Codex)

## Cuarta ronda del 2026-11-27 — tercera revisión HOLD de #1671

Base comprobada: `de0b8bdf90eee9a46ef5b9b4354cb8b7729c297d`, rama
`agent/codex-escudo4-tests-20261127`, sobre la base explícita autorizada
`origin/agent/fix-20261126-escudo`. Tercera revisión leída entera.
Solo se amplían esta suite y estas notas. No se modifica `scripts/`,
ninguna spec ni planning-state; sin commits, push ni PR.
Los apartados inferiores conservan las mediciones históricas.

Antes: **32/32 pasan**. Después: **59 casos, 43 pasan y 16 fallan; exit BATS 1**.
Los 32 casos y helpers previos son un prefijo idéntico byte a byte del fichero
ampliado. Ninguna aserción previa cambia. Reproducción:

```bash
bats --tap tests/bats/test-shield-check-before-guards-codex.bats
```

| Caso | Escenario añadido | Resultado sobre la base actual |
| --- | --- | --- |
| 33–34 | U+2028 / U+2029 en `//` antes de `], __fake = [` | **Fallan: active / 0** |
| 35 | CR suelto en el mismo comentario | Pasa: inactive / 2 |
| 36 | U+0085 en el mismo comentario | **Falla: active / 0** |
| 37 | Todos los finales de línea del fichero de guards son CR sueltos | **Falla: active / 0** |
| 38–42 | Regex tras `await`, `yield`, `instanceof`, `new`, `extends` | **Fallan los cinco: active / 0** |
| 43–45 | Regex tras `typeof`, `delete`, `void` | Pasan: inactive / 2 |
| 46–48 | Regex tras `debugger`, `break etiqueta`, `continue etiqueta` y salto de línea | **Fallan los tres: active / 0** |
| 49 | BOM U+FEFF entre `return` y el regex | **Falla: active / 0** |
| 50 | `await /* comentario */` antes del regex | **Falla: active / 0** |
| 51–52 | Regex tras `yield*` y `return` | Pasan: inactive / 2 |
| 53–55 | Divisiones `a / b`, `Number(x) / 2`, `arr[0] / n` con cableado real | Pasan: active / 0 |
| 56 | CRLF en guards y fundación | Pasa: active / 0 |
| 57 | U+0085 sustituye todos los finales de línea de los guards | Pasa: inactive / 2 |
| 58 | Regex tras el paréntesis de `for await (const item of [])` | **Falla: active / 0** |
| 59 | BOM U+FEFF entre `if` y su paréntesis antes del regex | **Falla: active / 0** |

Los **16 rojos** son 33, 34, 36–42, 46–50, 58 y 59. Todos devuelven los ocho
componentes y `missing: []`; se exige exit 2 y la ausencia exacta de ambos
cableados. Cada caso conserva intactos los demás componentes. El caso 1
(árbol real) sigue verde; el script sobre el propio worktree también devuelve
active / 0, `missing: []`.

Distinción semántica: Node y Bun confirman que U+2028, U+2029 y CR terminan
`//` y dejan la lista real vacía en la construcción del informe. **U+0085 no
es un terminador de comentario de ECMAScript**: en 36 la lista conserva ambos
guards. El caso 36 exige el rechazo conservador pedido; no demuestra un bypass.
El caso 37 también comprueba la política conservadora pedida: CR es válido en
JS y Python lo normaliza, pero el encargo exige que no dé activo. El caso 35
sí contiene la desviación de guards y hoy ya se rechaza.

Las 17 construcciones de regex incluyen el señuelo del informe: backtick en
regex, lista local vacía, import canónico dentro de template y uso de la lista
local. Node y Bun ejecutan los 17 módulos (retirada únicamente la anotación
TS `: any[]`, con comprobación del argumento en lugar del runner) y confirman
`BEFORE_GUARDS.length = 0`. `instanceof`, `new` y `extends` están en funciones
no invocadas para evitar errores de ejecución ajenos al análisis léxico.

Autorrevisión: los 16 negativos rojos fallan sobre el script sin modificar.
En una copia privada se invierten las aserciones de los 11 casos nuevos verdes
y del árbol real: **12/12 fallan en la aserción**, sin fallos de setup.
Cada test nuevo puede fallar. Sin `! cmd`, `|| true`, skips ni rebaja de gates.
Auditor heurístico: **73/100, certified: false, vacuity: [], weak: []**.
Se documenta la falta de certificación; no se añaden tests de relleno.
Los TAP de antes/después, mutaciones y verificación semántica quedan en el log
privado autorizado del run.

La primera ejecución de baseline se interrumpió por espacio en `/tmp` al
copiar fixtures. Se descartó como medición y se repitió completa con `TMPDIR`
en el log autorizado, sin limpiar datos de otras sesiones ni cambiar setup.
Validación complementaria: suite Claude **51/51** y SPEC-OC-01 **20/20**.
`git diff --check` pasa; solo cambian esta suite y estas notas.
Validación rápida: **15 PASS, 0 FAIL, 2 WARN** (coherencia advisory y snapshot
atrasado). Roadmap consultado. No se lee ni actualiza el traspaso privado,
ni se ejecuta `--clean-state`: alcanzaría estado externo que el encargo prohíbe.
Siguiente acción: la autora debe corregir los falsos activos y repetir estos
59 casos sin debilitar las aserciones; esta entrega es TDD rojo deliberado.

## Tercera ronda del 2026-11-27 — segunda revisión HOLD de #1671

Base: `272990fceefd82832314a287eb6210f426df821d`, rama
`agent/codex-escudo3-tests-20261127`, sobre la base explícitamente autorizada
`origin/agent/fix-20261126-escudo`. Segunda revisión leída entera.
Solo se amplían la suite Codex y estas notas; sin cambios en `scripts/`,
commits, push ni PR. Los apartados inferiores son mediciones históricas.

Antes: **25/25 pasan**. Después: **32 casos, 26 pasan y 6 fallan; exit BATS 1**.
Los 25 tests y helpers anteriores siguen idénticos byte a byte: el fichero
de `HEAD` es prefijo exacto del ampliado. Comando de reproducción:

```bash
bats --tap tests/bats/test-shield-check-before-guards-codex.bats
```

| Caso añadido | Escenario | Resultado actual |
| --- | --- | --- |
| 26 | Regex tras `)` y falso import en cadena, import real desde `./fake.ts` | **Falla: active / 0** |
| 27 | `].filter(() => false);` | **Falla: active / 0** |
| 28 | `].slice(0, 0);` | **Falla: active / 0** |
| 29 | `] && [];` | **Falla: active / 0** |
| 30 | `const dataSovereigntyGate = async () => {};` en lugar del import | **Falla: active / 0** |
| 31 | Único uso como tipo: `[] as typeof BEFORE_GUARDS` | **Falla: active / 0** |
| 32 | Línea canónica del import dentro de template multilínea más import real de `./fake.ts` | Pasa: inactive / 2 |

Los seis falsos activos devuelven `missing: []` y los ocho componentes.
Se exige exit 2 y JSON exacto: faltan ambos cableados en 26–29, 31 y 32;
en 30 falta solo soberanía, manteniendo el guard de credenciales importado.
Los contrastes positivos pedidos ya son los casos **1–3**, conservados y
verificados: árbol real, cierre `] as const;` y comentario `//` al final
de las líneas de guard. Los tres devuelven active / 0 y `missing: []`.

Autorrevisión: los seis negativos nuevos rojos fallan contra el script sin
modificar. En una copia temporal externa a la suite, cambiar el caso 32
a `assert_shield 0 active` lo hace fallar; invertir los tres positivos
también produce tres fallos. La copia original conserva sus aserciones.
No se añaden `! cmd`, `|| true` ni excepciones que oculten errores.
Auditor: **73/100**, `certified: false`, `vacuity: []`, `weak: []`;
no se añaden tests de relleno para mejorar su puntuación heurística.
TAP de antes/después, mutación de aserciones y auditor guardados en el log
privado del run. Siguiente acción: la autora del script debe corregir los
seis falsos activos y repetir los 32 casos sin rebajar aserciones.

Validación complementaria: suite Claude **33/33**, SPEC-OC-01 **20/20**;
`git diff --check` pasa y `scripts/` no tiene cambios. Roadmap consultado.
`validate-ci-local.sh --quick` termina con exit 1: **14 PASS, 2 FAIL, 1 WARN**.
Fallos ajenos a esta ampliación: `Generado desfasado: derivados de reglas
(SE-501)` y `BLOCK coherence/eval-coverage-L4: matriz de cobertura no evaluable
(fail-closed, SE-387 D)`; aviso de snapshot de cúpula atrasado. No se regeneran
artefactos fuera del alcance. No se ejecuta `--clean-state`, ni se lee o
actualiza el traspaso privado: consultarían otros worktrees o estado externo
prohibido por el encargo. El run entrega tests rojos deliberados, no un arreglo.

## Ampliación del 2026-11-27 — revisión HOLD de #1671

Base comprobada: `404c2157983ec4e18914ebb541eaa2262206f558`, rama de trabajo
`agent/codex-escudo2-tests-20261127`, sobre `origin/agent/fix-20261126-escudo`.
Informe independiente leído entero. Solo se amplían esta suite y sus notas;
no se modifica `scripts/`, ni se crean commits, pushes o PRs.

Antes de ampliar: **17/17 pasan**. Los 17 casos originales y sus helpers se
conservan idénticos byte a byte, comprobado contra una copia previa al cambio.
Después: **25 casos; 18 pasan, 7 fallan; exit de BATS 1**.

```bash
bats --tap tests/bats/test-shield-check-before-guards-codex.bats
```

| Caso nuevo | Escenario | Salida actual | Resultado |
| --- | --- | --- | --- |
| 18 | Import dentro de cadena y uso de BEFORE_GUARDS | active / 0 | **Falla** |
| 19 | Import dentro de template y uso de BEFORE_GUARDS | active / 0 | **Falla** |
| 20 | Import real desde fake.ts más señuelo en cadena | active / 0 | **Falla** |
| 21 | Import real desde fake.ts más señuelo en template | active / 0 | **Falla** |
| 22 | Template con interpolación anidada | active / 0 | **Falla** |
| 23 | Lista exacta de regex con comillas del informe | inactive / 2, cableado de soberanía falso | **Falla** |
| 24 | Mismas regex con blockCredentialLeak real añadido | active / 0 | **Falla** |
| 25 | PATH hermético sin python3, árbol válido | inactive / 2, faltan ambos cableados | Pasa |

Los casos 18–21 exigen que falten ambos cableados. En 20–21 existe `fake.ts`
con una lista vacía. En 22 y 24 se permite conservar el guard de credenciales
real o rechazar toda la lista ambigua; nunca aceptar el guard de soberanía
escrito dentro de una cadena. En 23 faltan ambos guards reales: la salida
ya es inactiva, pero el JSON aún declara `savia-foundation-wired`. El caso 24
aísla ese defecto conservando el guard sano y reproduce el falso activo.

El PATH del caso 25 solo contiene enlaces a Bash y dirname, sin heredar
directorios del entorno. Se exige que `command -v python3` devuelva 1 y salida
vacía. Solo el proceso probado recibe ese PATH; la aserción JSON usa el normal.
Una copia temporal con la aserción cambiada a `assert_shield 0 active` falla
sobre el exit 2 real. Los otros siete casos nuevos ya fallan contra el script
actual, demostrando que discriminan. No se altera el script para esta prueba.

Comprobaciones adicionales: suite SPEC-OC-01 **20/20**, `git diff --check`
sin incidencias. Auditor: **73/100**, `certified: false`, `vacuity: []`,
`weak: []`; se conserva el resultado, sin pruebas de relleno.
Arranque `validate-ci-local.sh --quick`: **15 PASS, 0 FAIL, 2 WARN**
(coherencia advisory y snapshot de cúpula atrasado). Roadmap consultado.
No se ejecuta `--clean-state` ni se accede al traspaso privado: consultarían
otros worktrees o estado fuera del ámbito permitido por este encargo.
TAP y prueba de aserción mutada guardados en la carpeta privada de este run.

Siguiente acción: la autora del script debe corregir los siete fallos y
repetir las suites de 25 y 20 casos, sin rebajar aserciones.

## Histórico del 2026-11-26 (anterior al arreglo de #1671)

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
