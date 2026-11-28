# SE-497 S0 — tests cruzados de Codex

Entrega: `se497-s0-codex.bats`, ejecutable. No se ha modificado el guion,
ninguna spec ni el estado de planificación. Sin commits, push ni PR, conforme
al encargo específico. Todos los fixtures, registros y centinelas se crean en
`mktemp -d` y se eliminan en `teardown`; no se usan datos reales.

## Resultado contra el guion actual

Ejecución del 2026-11-25 sobre HEAD `121240586`:

```bash
bats --tap tests/bats/se497-s0-codex.bats
```

**76 tests: 15 pasan, 61 fallan; salida de BATS: 1.** Rojo esperado:
la implementación S0 queda para la operadora. No se ha comprobado todavía el
paso a verde con S0 implementado.

SHA-256 del guion probado:
`ee1034ccd61a0534b0c041700d878a47e2687bdd2f929fbf482023626d316907`.

Resumen TAP literal (sin los diagnósticos de cada aserción):

```text
1..76
ok 1 S0-6: sha de 40 hex minúsculos activa con mejora
ok 2 S0-6: se488 de un carácter activa (boundary mínimo)
ok 3 S0-6: se488 de 64 caracteres activa (boundary máximo)
ok 4 S0-6: se488 permite mayúsculas números punto guion y subrayado
ok 5 S0-6: se488 permite identificador que empieza por guion
ok 6 S0-6: igualdad de métricas permite activar (boundary sin regresión)
ok 7 S0-6: dos métricas zero son presentes y permiten activar
ok 8 S0-1: rechaza trailer ausente y conserva hash de la lección
ok 9 S0-1: rechaza trailer empty y conserva hash de la lección
not ok 10 S0-1: rechaza texto libre aunque no tenga metacaracteres
not ok 11 S0-1: rechaza sha de 39 hex (boundary inferior)
not ok 12 S0-1: rechaza sha de 41 hex (boundary superior)
not ok 13 S0-1: rechaza sha con hex mayúsculo
not ok 14 S0-1: rechaza sha con carácter que no es hexadecimal
not ok 15 S0-1: rechaza prefijo SHA en mayúsculas
not ok 16 S0-1: rechaza se488 empty sin identificador
not ok 17 S0-1: rechaza se488 de 65 caracteres (boundary superior)
not ok 18 S0-1: rechaza espacio antes de un trailer válido
not ok 19 S0-1: rechaza espacio después de un trailer válido
not ok 20 S0-1: rechaza prefijo ajeno antes de un trailer válido
not ok 21 S0-1: rechaza sufijo ajeno después de un trailer válido
not ok 22 S0-1: rechaza trailer que empieza por guion de opción
not ok 23 S0-2: rechaza barra / sin tocar cabecera ni cuerpo
not ok 24 S0-2: rechaza ampersand & sin tocar cabecera ni cuerpo
not ok 25 S0-2: rechaza punto y coma ; sin tocar cabecera ni cuerpo
not ok 26 S0-2: rechaza comilla simple sin tocar cabecera ni cuerpo
not ok 27 S0-2: rechaza comilla doble sin tocar cabecera ni cuerpo
not ok 28 S0-2: rechaza barra invertida sin tocar cabecera ni cuerpo
not ok 29 S0-2: rechaza tabulador sin tocar cabecera ni cuerpo
not ok 30 S0-2: rechaza LF interior sin tocar cabecera ni cuerpo
not ok 31 S0-2: rechaza CR interior sin tocar cabecera ni cuerpo
not ok 32 S0-2: rechaza control ASCII U+0001
not ok 33 S0-2: rechaza control DEL U+007F
not ok 34 S0-2: rechaza control Unicode U+0085
not ok 35 S0-2: rechaza control Unicode bidi U+202E
not ok 36 S0-2: rechaza Unicode de ancho cero U+200B
not ok 37 S0-2: rechaza letra Unicode visualmente similar a ASCII
not ok 38 S0-2: rechaza trailer válido seguido de LF y más texto
not ok 39 S0-2: rechaza trailer válido seguido solamente de LF final
not ok 40 S0-2: rechaza trailer válido seguido de CRLF
not ok 41 S0-2: rechaza inyección GNU sed e touch y no crea centinela
not ok 42 S0-3: reason con comillas simples y dobles conserva JSON y valor
not ok 43 S0-3: reason con barra invertida conserva JSON y valor
not ok 44 S0-3: reason con salto de línea conserva una única fila JSON
not ok 45 S0-3: actor con comillas simples y dobles conserva JSON y valor
not ok 46 S0-3: actor con barra invertida conserva JSON y valor
not ok 47 S0-3: actor con salto de línea conserva una única fila JSON
not ok 48 S0-3: id con comillas simples y dobles conserva JSON y valor
not ok 49 S0-3: id con barra invertida conserva JSON y valor
not ok 50 S0-3: id con LF interior en basename conserva una única fila JSON
not ok 51 S0-3: id explícito en cabecera con comillas y barra conserva valor
not ok 52 S0-3: reason con escape JSON literal no se decodifica dos veces
not ok 53 S0-3: actor con escape JSON literal no se decodifica dos veces
not ok 54 S0-3: id con escape JSON literal no se decodifica dos veces
not ok 55 S0-3: id con LF final en basename conserva el salto al decodificar
ok 56 S0-3: actor que empieza por guion se conserva como dato
ok 57 S0-3: reason que empieza por guion se conserva como dato
ok 58 S0-3: id que empieza por guion se conserva como dato
not ok 59 S0-3: reason con Unicode combinado tabulador y CR conserva valor
not ok 60 S0-3: rechazo por trailer ausente registra JSON con valores especiales
not ok 61 S0-4: rechaza activación con cero métricas y conserva canary
not ok 62 S0-4: rechaza activación con solo metric-before y conserva canary
not ok 63 S0-4: rechaza activación con solo metric-after y conserva canary
not ok 64 S0-4: rechaza métrica before empty aunque after esté presente
not ok 65 S0-4: rechaza métrica after empty aunque before esté presente
not ok 66 S0-4: rechaza regresión con salida 5 y revierte a proposed
not ok 67 S0-4: rechaza regresión pequeña de decimales sin redondearla a igualdad
not ok 68 S0-5: segunda activación idéntica no añade fila ni cambia el fichero
not ok 69 S0-5: superseded repetido no duplica tombstone ni fila
not ok 70 S0-5: proposed repetido no crea registro de una transición inexistente
ok 71 S0-1: rechazos repetidos por trailer ausente sí añaden evidencia
ok 72 S0-6: active con trailer heredado de texto libre admite superseded
ok 73 S0-6: rutas con espacios y ledger en directorio nonexistent se crean
not ok 74 S0-1: strict rechaza trailer ausente sin alterar la lección y registra evidencia
not ok 75 S0-1: rechaza trailer inválido incluso si la lección ya está active
not ok 76 S0-7: ningún sed interpola argumentos recibidos por CLI
```

Los fallos 10–40 y 75 muestran aceptación de trailers fuera del formato o
modificación del fichero antes del rechazo. El 41 falla específicamente porque
GNU sed ejecuta `e touch` y crea el centinela temporal. Los 42–55, 59 y 60
exponen JSON inválido o valores alterados al decodificar (incluido `\n` literal,
que produce JSON válido pero cambia el valor). Los 61–67 exponen el gate de
métricas y el código incorrecto de regresión. Los 68–70 detectan duplicados;
el 74 detecta ausencia de auditoría con `--strict`. El 76 localiza las tres
interpolaciones actuales de `$HUMAN_TRAILER` en órdenes `sed`.

## Cobertura y comprobación de que los tests pueden fallar

- S0-1/S0-2: SHA-256 antes/después del fichero completo, código 4, límites de
  longitudes, alfabeto, prefijos/sufijos, LF final, CRLF, controles ASCII y
  Unicode, homógrafos y el centinela de ejecución. Se comprueban tanto trailers
  inválidos en canary como un inválido cuando la entrada ya está active.
- S0-3: decodificación de **cada línea** con `json.loads`, sin omitir vacías,
  seguida de comparación exacta del valor original; ramas de éxito y rechazo.
  Las comillas y barras se prueban también en `id:` explícito. Para LF en id se
  utiliza la interfaz existente de fallback a basename cuando falta `id:`;
  se cubren LF interior y final sin inventar un formato YAML multilínea.
- S0-4: cero métricas, solo before, solo after, vacío explícito, regresión,
  mejora, igualdad y cero numérico. Los rechazos por métricas ausentes no
  cambian canary; las regresiones exigen proposed y código 5.
- S0-5: activación repetida, superseded repetido (un solo tombstone) y proposed
  repetido; se compara el ledger completo con `cmp` para detectar cualquier fila
  añadida. Dos intentos sin trailer deben seguir dejando dos filas de auditoría.
- S0-6: ambos tipos de trailer, se488 mínimo/máximo, procedencia y valor exactos,
  rutas con espacios, directorios de ledger inexistentes y retirada de una
  lección activa con trailer heredado sintético sin cambiarlo ni degradarla.
- S0-7: inspección léxica de órdenes sed, con continuaciones, tuberías y las
  siete variables prohibidas, tanto `$VAR` como `${VAR}`. Es un control estático
  de las órdenes presentes, no una demostración general de ausencia de shell
  indirecto, alias o generación dinámica de órdenes.

Los **61 tests rojos** fallan contra el guion sin modificar, con diagnósticos de
aserciones del contrato. Para los **15 verdes** se ejecutó individualmente cada
caso en una copia temporal de la suite, cambiando su expectativa de salida 0/4
por 99 (también en los helpers compartidos): **15/15 pasaron a rojo**. No se
modificó código de producción para esta comprobación. Esto comprueba que las
aserciones pueden fallar; no equivale a retirar defensas de una implementación
S0 que aún no existe. Esa segunda validación queda pendiente al implementar S0.

Auditor de tests del repositorio:

```bash
python3 scripts/test-auditor-engine.py tests/bats/se497-s0-codex.bats .
```

Resultado: **91/100, certified=true, vacuity=[], weak=[]**. El auditor no resuelve
el target calculado mediante `LC`; esa puntuación es auxiliar, no prueba de
corrección. Validación limitada a esta suite y al auditor; no se ejecutaron gates
globales ni generadores, por el alcance exclusivo de tests y las restricciones
sobre otros ficheros y worktrees.

## Casos explorados y excluidos por falta de decisión en S0

Se ejecutaron sondas independientes con fixtures temporales contra el guion
actual. No se añadieron expectativas nuevas para estas decisiones abiertas:

| Caso | Observado hoy | Decisión que falta |
|---|---|---|
| Fichero sin cabecera ni lifecycle | Salida 0, fichero intacto, ledger anuncia transición | Rechazar o inicializar; código y formato de error |
| `lifecycle:` también en el cuerpo | Al superseder modifica cabecera y cuerpo y añade dos tombstones | Delimitar frontmatter y decidir sobre duplicados reales dentro de la cabecera |
| Métricas `x` / `y` | Salida 0 y activación | Gramática numérica: negativos, exponentes, NaN/Inf y código de rechazo |
| Padre del ledger es un fichero | Salida 0, cambia la lección y no existe registro | Atomicidad entre lección y auditoría; código ante error de I/O |

Otros casos no convertidos en tests: opciones repetidas o sin argumento,
symlinks, concurrencia, fallos de herramientas y validez YAML completa. S0 no
fija su política ni sus códigos. Un byte NUL no puede viajar en un argumento
POSIX/Bash: probarlo con `$'\0'` produciría un valor distinto al pretendido.
No se confunde ese caso con el rechazo de otros controles, que sí se prueba.

## Interpretaciones y límites

- Se aplica la aprobación parcial S0: aún se escribe `active`; no se exige
  recibo, estado derivado ni validación de main de los slices posteriores.
- El encargo exige conservar los rechazos por falta de trailer como evidencia
  sin exceptuar `--strict`; el test 74 aplica literalmente ese requisito también
  en modo estricto. La implementación actual sale antes de escribir el registro.
- No se exige una fila concreta por trailer **malformado** o por métricas ausentes:
  S0 no fija ese esquema. Sí se exige la fila existente `refused-no-human` para
  ausencia de trailer y se conserva la evidencia de intentos repetidos.
- No se fija resultado para una repetición de activación con un trailer diferente
  ni se obliga a revalidar métricas en una activación ya efectiva. Solo se prueba
  la repetición idéntica y el rechazo explícito de un trailer inválido.
- Los datos heredados se prueban con una identidad sintética; no se leen ni se
  copian las cinco lecciones reales. Se verifica la lectura de `active` mediante
  el `from` del ledger y su transición permitida a superseded.

Siguiente paso: implementar S0 sin cambiar estos tests, ejecutar la suite hasta
verde y comprobar mutaciones que eliminen cada defensa de la implementación.

## Cierre de la orquestadora (2026-11-25)

Con S0 implementado: 76/76 de esta batería y 34/34 de la de Claude. Dos tests
de Codex obligaron a cambiar el guion: el 74 (el rechazo por falta de trailer
se registra también con `--strict`) y el 55 (el id tomado del nombre de fichero
conserva un salto de línea final). Ningún test de Codex se modificó.

Mutaciones sobre la implementación (tests que lo detectan, Claude / Codex):
regex sin anclas 4 / 19 · trailer sin validar 8 / 33 · sin puerta de métricas
3 / 5 · sin idempotencia 3 / 3 · regresión con salida 0: 1 / 2 · registro sin
codificar comillas 5 / 5. Quitar el rechazo explícito de LF y CR no lo detecta
ninguna batería: la expresión cerrada ya los rechaza por sí sola; se mantiene
como defensa redundante porque la spec lo pide antes de la expresión.

Decisiones tomadas donde S0 no fijaba nada: los trailers mal formados y la
falta de métricas también dejan fila (`refused-invalid-trailer`,
`refused-no-metrics`); las métricas admiten solo decimales simples (sin
exponente, NaN ni infinito); la cabecera se edita solo dentro del frontmatter.
Siguen abiertos los cuatro casos de la tabla anterior salvo el segundo.
