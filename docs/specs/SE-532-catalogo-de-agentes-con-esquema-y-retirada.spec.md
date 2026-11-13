---
status: PROPOSED
priority: P3
developer_type: agent-single
created: 2026-11-13
author: Savia
phase: A
risk: L3
human_surface: false
related_specs: [SE-527, SE-253, SE-273, SE-518, SE-505, SE-362, SE-456, SPEC-161]
origin: "Spec pedida por la operadora el 2026-11-13 tras un estudio de orquestadores de agentes declarativos (proyectos públicos: kagent, CopilotKit, Google ADK; sin copiar código ni texto de ninguno). Orden de slices decidido por ella por pregunta interactiva. Solo spec: ningún agente, validador ni configuración se toca todavía."
timeline:
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "PROPOSED"
    source: "worker autónomo; encargo de la orquestadora (registro de la orquestadora de las decisiones de la operadora; no es texto literal)"
---

# SE-532 — Catálogo de agentes con esquema, referencias comprobadas y retirada explícita

> **Qué es y qué no es.** Es higiene del catálogo: un esquema único para la cabecera de los agentes, un validador que falla cerrado cuando una referencia cruzada apunta a un agente que no existe (o que ya no debería existir) y un procedimiento de retirada que no deja nada huérfano. **No cambia ningún permiso, ningún agente ni su comportamiento**, y no recorta contexto.

## Problema (verificado en origin/main 2681e26a7, 2026-11-13)

El catálogo tiene **90 agentes** en `.opencode/agents/` (fuente de verdad) y **75 espejos** en `.claude/agents/`.

1. **Hay 19 claves de cabecera distintas y ningún esquema que las defina.** Recuento sobre los 90 ficheros (cabecera parseada, claves de primer nivel): `description`, `model_tier`, `permission_level` y `name` en 90; `tools` en 88; `token_budget` en 84; `output_max_tokens` y `max_context_tokens` en 78; `color` en 51; `permissionMode` en 50; `maxTurns` en 47; `skills` en 26; `maxSteps` e `hooks` en 14; `context_cost` en 12; `decision_tree` e `isolation` en 11; `ref` en 3; `tags` en 1. De ellas, `context_cost`, `ref` y `tags` (16 apariciones) no figuran en ninguna definición de agente: `context_cost` es una clave del esquema de skills (`scripts/skill-audit.sh:47`). Dos agentes no declaran `tools` (`criterion-simulation-judge`, `social-networks`). Hoy nada lo detecta: un agente con una errata en la clave (`permision_level`) pasa sin aviso.
2. **Lo que sí se valida está repartido y mira cada uno un trozo**:
   - `scripts/validate-agent-permissions.sh` comprueba nivel de permiso frente a herramientas, con parseo YAML real y una baseline transitoria que solo puede encoger. Mira `.claude/agents/` (los 75 espejos), no la fuente de verdad; su paso en CI está en `.github/workflows/ci.yml:389`.
   - `scripts/judge-routing-verify.sh` comprueba la paridad entre jueces de `.opencode/agents/` y filas de `config/judge-routing.yaml` (33 filas), en los dos sentidos.
   - `scripts/agents-catalog-sync.sh --check` comprueba que la tabla de `docs/rules/domain/agents-catalog.md` cuadra con los ficheros (90 y 90 hoy; `.github/workflows/ci.yml:664`) y, junto con `docs/agents-sync-allowlist.md`, el emparejamiento de lados (SE-253 S3).
   - Nadie comprueba que `.opencode/protected-jobs.yaml` (12 agentes y 3 modos), los contratos `contracts/capabilities/agent.*.yaml` (8), el campo `decision_tree:` (11 agentes) o el árbol de decisión apuntan a un agente o fichero que existe.
3. **Hoy no hay referencias colgantes** (medido: las 33 filas de routing, los 12 protegidos y los 8 contratos de agente apuntan a agentes existentes). El validador es **preventivo**, no repara nada: su valor aparece cuando SE-527 empiece a retirar agentes.
4. **La retirada es manual y está repartida en diez sitios.** SE-527 D2 (`docs/specs/SE-527-recorte-de-agentes-sobrantes.spec.md:60-73`) lista diez cosas que actualizar por cada agente retirado. Un ejemplo concreto de lista a mano: `scripts/judge-routing-verify.sh:91` fija con nombres literales los dos jueces huérfanos (`fiction-framing-judge`, `structural-framing-judge`), exactamente los que SE-527 S1 retira; sin tocar el script, el check queda apuntando a nombres inexistentes.
5. **Existe una semántica de retirada, pero solo para jueces.** `config/judge-routing.yaml:11` define el modo `disabled` («lápida: se conserva para auditar y nunca se dispara») y dos filas lo usan (líneas 266 y 306). Para el resto de agentes no hay lápida: se borra el fichero y se espera haber encontrado todas las citas.

### Límites de lo medido

- Los recuentos son de cabecera parseada con un script ad hoc; el validador de S1 los fija con su propio parser y la cifra definitiva la da su informe. Si difiere de ésta, vale la del validador y se corrige la spec.
- «Sin referencias colgantes hoy» cubre los cuatro orígenes citados (routing, protegidos, contratos de agente, `name` frente a nombre de fichero: 0 diferencias). No he medido las citas en comandos, skills y scripts; esa búsqueda es la parte difícil de S1 y la de más falsos positivos.

## Relación con SE-253 (espejos de agentes): no se duplica

SE-253 S3 garantiza que cada agente tiene su par en `.opencode/agents/` y `.claude/agents/` salvo los declarados en `docs/agents-sync-allowlist.md`, con `scripts/agents-catalog-sync.sh --check` y `tests/bats/test-se253-agent-sync.bats`. Esta spec **no vuelve a calcular ese emparejamiento ni toca la allowlist**:

| Pregunta | La responde | Esta spec |
|---|---|---|
| ¿Cada agente tiene su espejo o su excepción en la allowlist? | SE-253 S3 | La invoca como un paso más del validador y no la reimplementa. |
| ¿La tabla del catálogo cuadra con los ficheros? | `agents-catalog-sync.sh --check` | La invoca igual. |
| ¿La cabecera de cada agente cumple un esquema? | Nadie | **S1** |
| ¿Cada nombre citado en routing, protegidos, contratos y árboles existe? | Solo routing (judge-routing-verify) | **S1**, para el resto de orígenes |
| ¿Un nombre retirado ha dejado de citarse en todas partes? | Nadie | **S2** |
| ¿Lo que el frontend ve difiere de lo que el repo declara? | Nadie en ejecución | **S3** |

La allowlist es un **origen de referencias** como los demás: si un agente retirado sigue en ella, falla (S2). Pero su contenido y su formato siguen siendo de SE-253.

## Qué decide esta spec

### D1 — Tres slices, en este orden y en serie

| Slice | Qué | Cuándo | Tier pedido | Tier calculado (`scripts/risk-tier.py`) |
|---|---|---|---|---|
| S1 | Esquema de cabecera y referencias comprobadas, con lista de excepciones congelada | **Antes de SE-527**: automatiza sus comprobaciones manuales | 2 | **2** |
| S2 | Retirada explícita y lista de protegidos derivada | Después de SE-527 | 3 | **4** |
| S3 | Aviso de deriva del catálogo en Pulse | Después de que SE-518 esté fusionada | 2 | **2** |

**Tier.** Calculado con `python3 scripts/risk-tier.py --diff <ficheros>` (la lista va como un solo argumento entre comillas, separada por espacios) sobre muestras de cada slice. Un validador en `scripts/`, un esquema JSON en `config/`, tests y reglas en `docs/` dan tier 1 o 2; **un fichero de `config/` sin categoría clara sube a tier 3 (fail-closed)** y basta un fichero de `.opencode/agents/`, `.opencode/protected-jobs.yaml` o `.github/workflows/ci.yml` para que salga **tier 4 («path de gobernanza»)**. S1 está diseñada para no tocar ninguno de esos: la lista de excepciones vive en `docs/` (como la baseline de permisos, `docs/agent-permissions-excess-baseline.txt`, tier 1), no hay que editar agentes y la ejecución en CI va por un test BATS y por `scripts/validate-ci-local.sh`, no por un paso nuevo en `ci.yml`. **S2 sí los toca** (la marca de protegido va en la cabecera de 12 agentes y la lista generada sustituye a `protected-jobs.yaml`), así que sale tier 4, no 3 como se pidió. Los tiers 3 y 4 exigen revisión humana explícita de la PR concreta (SE-362) y ninguno entra en un merge-sprint por lotes de tier 1/2; para el procedimiento de S2 la diferencia entre 3 y 4 es de etiqueta, y la PR declara el calculado (Q2). La PR de S2 declara el tier calculado sobre su diff final. S3 se recalcula con su diff final: se declara 2 mientras no toque esas rutas.

**Orden respecto a SE-527.** SE-527 (PROPOSED, ya en `main`, #1543) retira 14 agentes en cuatro slices y lleva una lista de comprobación manual de diez sitios (D2) y un `grep -w` de referencias vivas (AC-S0, «el patrón exacto se fija en el script de S1»). **S1 de esta spec va antes de SE-527 S1** para que esas comprobaciones sean una orden y no una lista. Esta spec **no modifica SE-527**: propone que SE-527 S1 consuma `--retired <nombre>` de S1 (D4); si la operadora lo acepta, el cambio va en la PR de SE-527. **S2 va después de SE-527** porque necesita ver qué retirada real hay que modelar, y porque la lista de protegidos que S2 deriva incluye a `court-orchestrator` y `drift-auditor`, que SE-527 S4 usa como destino de fusión.

### D2 — Esquema único de la cabecera (S1)

Un fichero `config/agent-frontmatter.schema.json` (JSON Schema) con estas reglas. **Una clave que no figura en el esquema es error** (fail-closed): es lo contrario de lo que hacen otros esquemas públicos de agentes declarativos, que aceptan claves extra y dejan pasar una errata. El esquema describe el estado actual, no uno deseado: no cambia ningún valor.

| Clave | Regla |
|---|---|
| `name` | Obligatoria. Igual al nombre del fichero sin `.md` (0 diferencias hoy). |
| `description` | Obligatoria, cadena no vacía. |
| `model_tier` | Obligatoria, una de `heavy`, `mid`, `fast` (26, 56 y 8 hoy). Nunca un identificador de modelo (tiers en fuente, modelos solo en definición local). |
| `permission_level` | Obligatoria, una de `L0` a `L4`. La coherencia con `tools` sigue siendo de `validate-agent-permissions.sh`; el esquema solo valida el dominio. |
| `tools` | Obligatoria: mapa herramienta → booleano. Dos excepciones congeladas (arriba). |
| `token_budget` | Opcional: mapa con `per_invocation`, `context_window_target` y `escalation_policy`. Ausente en 6 agentes. Hacerla obligatoria no es de esta spec (Q1). |
| `output_max_tokens`, `max_context_tokens` | Opcionales, enteros positivos. |
| `permissionMode` | Opcional, una de `acceptEdits`, `bypassPermissions`, `default`, `dontAsk`, `plan`: los valores que hay hoy. El esquema los registra tal cual y **no opina** sobre ellos. |
| `maxTurns` / `maxSteps` | Opcionales, enteros. `maxSteps` es la clave de OpenCode; `scripts/agents-opencode-convert.sh:223` ignora las dos al comparar la conversión, así que se aceptan ambas. |
| `color`, `skills`, `hooks`, `isolation`, `decision_tree` | Opcionales. `isolation` solo `worktree`. `decision_tree` debe ser una ruta que existe bajo `.opencode/agents/`. |
| Cualquier otra | Error. |

Claves hoy sin esquema, que entran en la lista congelada: `context_cost` (12 agentes), `ref` (3) y `tags` (1).

### D3 — Referencias cruzadas que comprueba el validador (S1)

Un validador `scripts/validate-agent-catalog.py` (Python con PyYAML, fail-closed si falta, como `validate-agent-permissions.sh`; sale 0 solo si todo pasa, 1 con errores, 2 con error de uso o de entorno) con una regla por línea y un mensaje que **nombra el fichero y la línea**:

| Regla | Qué falla |
|---|---|
| R1 | Cabecera ilegible, sin cerrar o con claves duplicadas. |
| R2 | Falta una clave obligatoria, o una clave tiene un valor fuera de su dominio (D2). |
| R3 | Clave desconocida. |
| R4 | `tools` no es un mapa de booleanos. |
| R5 | `name` distinto del nombre del fichero. |
| R6 | Una fila de `config/judge-routing.yaml` cita un agente que no existe. |
| R7 | Un nombre de `.opencode/protected-jobs.yaml` (`protected_agents`) no existe. |
| R8 | Un contrato `contracts/capabilities/agent.<x>.yaml` no corresponde a un agente `<x>`, o su `id` no es `agent.<x>`. |
| R9 | `decision_tree:` apunta a un fichero que no existe. |
| R10 | Con `--retired <nombre>...`: el nombre aún tiene fichero en `.opencode/agents/` o `.claude/agents/`, o sigue citado en una referencia viva (patrones de `subagent_type`, `agent: <nombre>`, listas de agentes, filas de routing, protegidos, contratos, allowlist y nombre literal en `scripts/`). La historia (`CHANGELOG*`, `docs/specs-archive/`, `docs/evidence/`, specs) no cuenta. |

Además corre como pasos, sin reimplementarlos, `scripts/agents-catalog-sync.sh --check` (SE-253, catálogo) y `scripts/judge-routing-verify.sh` (paridad de jueces, SE-273); su salida se reporta con la de las reglas. El validador **no** repite `validate-agent-permissions.sh`.

**Qué automatiza de la lista D2 de SE-527** (honestidad: no es toda). Quedan cubiertos total o parcialmente los puntos 1 (agente, espejo y árboles), 2 (catálogo y contratos), 4 (routing), 7 (allowlist, vía SE-253), 10 (nombres literales, vía R10) y, con su script actual, el 6 (permisos). **No** cubre el 3 (comandos y skills que despachan por nombre: R10 detecta la cita, no decide el sustituto), el 5 (recuentos «90»: sigue siendo AC-S1 de SE-527), el 8 (reescribir tests anclados) ni el 9 (capability map, SAM, entropía: ya tienen sus gates).

### D4 — Lista de excepciones congelada (S1)

`docs/agent-catalog-exceptions.txt`: una línea por incumplimiento conocido, con agente, regla, detalle, fecha de alta y motivo. Se genera una sola vez con `--freeze` en la PR de S1 y **solo puede encoger**:

- Una excepción cuya violación ya no existe es **error por obsoleta** (mismo patrón que la baseline de `validate-agent-permissions.sh`).
- Una excepción nueva respecto a `origin/main` es error. Si no se puede leer la versión de `origin/main` del fichero, el validador falla (fail-closed), salvo en la propia PR que lo crea.
- Una excepción de un agente retirado es error: retirar un agente la quita en el mismo cambio (S2).
- Un agente nuevo no puede entrar con excepciones.

Contenido esperado el día de S1 (a confirmar con el informe del validador): **18 líneas**, 2 por falta de `tools` y 16 por clave sin esquema. Así S1 no toca ningún agente: el catálogo actual pasa y cualquier errata nueva falla.

### D5 — Retirada explícita de agentes (S2)

Un agente retirado deja una **lápida** en `config/agent-retired.yaml`, una entrada por agente con `name`, `retired_at`, `spec`, `reason` y `replaced_by` (otro agente, una skill o un comando que existen; obligatorio). Es la generalización del `disabled` de routing: hoy una lápida de juez es una fila con el agente aún presente; la lápida nueva vale para cualquier agente ya borrado.

Procedimiento, con una orden que lo comprueba:

1. `python3 scripts/validate-agent-catalog.py --plan-retire <nombre>`: solo lectura; lista cada cita viva por categoría (routing, protegidos, contrato, allowlist, árbol de decisión, comandos, skills, scripts, tests, recuentos) con fichero y línea. Es la lista D2 de SE-527 hecha automática; no escribe nada.
2. Las ediciones las hace la PR del retiro (como en SE-527); **esta spec no añade una orden que borre**.
3. Con la lápida, el validador exige: ningún fichero del agente en ninguno de los dos lados; sin fila de routing (la lápida sustituye al `disabled` en un agente ya borrado); sin entrada en protegidos, contratos, allowlist ni en la lista de excepciones; `replaced_by` existe; sin cita viva (R10).
4. Un agente retirado **no puede reaparecer** con el mismo nombre sin quitar antes su lápida en una PR que lo diga.
5. `scripts/judge-routing-verify.sh:91` deja de llevar nombres a mano: el conjunto de huérfanos se deriva de las filas con `mode: disabled` y de las lápidas.

### D6 — Lista de protegidos derivada (S2)

Hoy `.opencode/protected-jobs.yaml` (SPEC-161) es una lista a mano de 12 agentes que el guard `.claude/hooks/protected-job-guard.sh` lee. S2:

- Añade a la cabecera una clave opcional `protected: true` (entra en el esquema D2) en los 12 agentes actuales.
- Un generador reescribe `protected_agents` de `.opencode/protected-jobs.yaml` desde esas marcas; los `autonomous_modes` y `override_env` se conservan tal cual. Un `--check` falla si el fichero no coincide con lo generado (y en CI).
- **El hook no se toca** y sigue leyendo el mismo YAML con el mismo formato.
- **AC de igualdad:** la lista generada es idéntica a la actual (los mismos 12 nombres); cualquier diferencia exige que la persona la apruebe en la PR, con el nombre y el motivo.
- **Ningún permiso cambia.** Un informe de la PR compara `permission_level`, `permissionMode` y `tools` de los 90 agentes antes y después; el diff esperado es vacío. Si no lo es, la PR no sale de borrador.
- Riesgo propio: el guard es fail-closed ante fichero ilegible; una generación errónea no puede dejar a un agente caro sin proteger sin que el `--check` falle.

### D7 — Aviso de deriva en Pulse (S3)

Cuando SE-518 esté fusionada, Pulse puede emitir un evento que **informa y no aplica nada**: la huella del catálogo del repositorio difiere de la que ve la instalación.

- **Huella:** hash estable de los pares (nombre del agente, hash del fichero) del catálogo, calculado a un lado con lo que `scripts/agents-opencode-convert.sh` generaría desde `.opencode/agents/` y al otro con los espejos presentes en la instalación. Cuáles son exactamente los dos lados se fija al empezar S3, con medición previa; no se asume aquí.
- **Evento:** un tipo nuevo del ledger de SE-518 (solo añadir), con los nombres de los agentes que difieren (son públicos), el nivel de dato declarado y un campo de motivo. El ledger no se reescribe: al restaurar el agente se emite un evento de resolución y el estado «con deriva» se **deriva** del último evento, como el resto de métricas de planta.
- **No hace nada más:** no regenera espejos, no corrige, no bloquea.
- Se escribe contra el contrato de eventos de SE-518 tal como esté al fusionarse; si cambia, esta spec se revisa antes de S3.
- **Diferencia con SE-253:** `agents-catalog-sync.sh --check` corre en CI sobre el repo y comprueba emparejamiento y tabla; S3 vigila en la instalación en marcha que lo que el frontend lee no se ha quedado atrás tras un pull o una edición.

## Slices

### S1 — Esquema y referencias comprobadas (tier 2, antes de SE-527)

- **Entrega.** `config/agent-frontmatter.schema.json`, `scripts/validate-agent-catalog.py`, `docs/agent-catalog-exceptions.txt` (D4), un test BATS en `tests/bats/` que ejecuta el validador sobre el catálogo real, su paso en `scripts/validate-ci-local.sh` y la regla de la lista de comprobación en `docs/rules/domain/` (qué comprueba cada R).
- **No toca** ningún fichero de `.opencode/agents/`, `.claude/agents/`, `.opencode/protected-jobs.yaml`, `config/judge-routing.yaml`, `.github/workflows/ci.yml` ni los hooks. Al empezar se comprueba que `ci-select-bats` elige el test del validador cuando cambia un agente; si no lo elige, se declara y el paso dedicado en `ci.yml` (tier 4) pasa a ser una decisión de la operadora, no un añadido silencioso.
- **Pruebas (BATS).** Por cada regla R1 a R10 un caso negativo que falla con mensaje que nombra el fichero, y su corrección que pasa. Casos obligatorios: un agente con una clave desconocida, otro sin `model_tier` y otro con `tools` mal formado fallan y, corregidos, pasan; una excepción nueva respecto a la base falla; una excepción obsoleta falla; sin PyYAML sale 2, no 0; sin directorio de agentes sale 2. Edge: cabecera vacía, `name` con mayúsculas, fichero sin cabecera.
- **Reversión.** `git revert` de la PR: no hay migración ni estado fuera del repo.

### S2 — Retirada y protegidos (tier 4 calculado, después de SE-527)

- **Entrega.** `config/agent-retired.yaml`, `--plan-retire`, la marca `protected: true`, el generador de `protected_agents` y su `--check`, y la derivación de huérfanos en `judge-routing-verify.sh`.
- **Pruebas.** Retirar un agente referenciado falla (nombre en routing, en protegidos, en contrato, en allowlist, en excepciones, cada uno por separado). Un agente retirado sin `replaced_by` o con uno inexistente falla. Un retirado que reaparece falla. La lista generada es igual a la actual y una marca omitida o añadida en un agente hace fallar el `--check`. El informe de permisos antes y después sale vacío y un cambio de nivel provocado lo hace aparecer.
- **Reversión.** `git revert` de la PR; el `protected-jobs.yaml` vuelve a ser fuente.

### S3 — Deriva en Pulse (tier 2, después de SE-518)

- **Entrega.** El cálculo de huella y el evento de deriva y de resolución.
- **Pruebas.** Modificar un agente sin regenerar el espejo produce el evento; restaurarlo emite la resolución y el estado derivado vuelve a «sin deriva»; un catálogo idéntico no emite nada; el evento no contiene contenido de agentes, solo nombres.
- **Reversión.** `git revert`; el ledger conserva los eventos ya escritos (solo añadir).

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| AC-1 | Un agente con una clave desconocida, otro sin `model_tier` y otro con `tools` mal formado fallan con un mensaje que nombra el fichero; corregidos pasan. | negativo |
| AC-2 | Cada regla R1 a R10 tiene al menos un test negativo que falla contra una copia mutada y pasa con la corrección. Un test que no puede fallar no cuenta (SE-456). | negativo |
| AC-3 | Sobre el catálogo actual, el validador pasa con exactamente las excepciones congeladas y con **ninguna** edición de agente; la cifra de excepciones coincide con la de su informe. | positivo |
| AC-4 | La lista de excepciones solo encoge: una nueva, una obsoleta y una de agente retirado fallan. Si no se puede leer la base, falla. | negativo |
| AC-5 | Faltar PyYAML, el directorio de agentes o el esquema da error de entorno (2), nunca PASS. | negativo |
| AC-6 | `--retired <nombre>` sobre un agente que aún existe, o citado en una referencia viva, falla; sobre uno ya retirado sin citas, pasa. La prosa que usa la palabra común no cuenta. | negativo |
| AC-7 | S1 no modifica `.opencode/agents/`, `.claude/agents/`, `.opencode/protected-jobs.yaml`, `config/judge-routing.yaml` ni `.github/workflows/ci.yml` (se comprueba con el diff de la PR). Su tier calculado es 2; si sale 3 o 4, la PR lo dice y se explica. | negativo |
| AC-8 | S2: la lista de protegidos generada es igual a la actual o la diferencia la aprueba la persona; el diff de `permission_level`, `permissionMode` y `tools` de los 90 agentes es vacío o figura en la PR. | negativo |
| AC-9 | S2: retirar un agente referenciado falla, uno por cada origen de referencia. | negativo |
| AC-10 | S3: cambiar un agente sin regenerar el espejo produce el evento; restaurarlo emite la resolución. Un catálogo igual no emite. | positivo / negativo |
| AC-11 | Esta spec: `tests/bats/se532-spec-coherence.bats` pasa y cada comprobación falla sobre una copia mutada. | negativo |

## Puerta de comprensión

**Antes y después, en lenguaje llano.**

- **Slice S1 y S2 (la persona no ve nada nuevo).** Hoy, si alguien escribe mal una clave en la ficha de un agente o borra un agente que otra lista aún nombra, nadie se entera hasta que algo falla. Después, la revisión automática de cada PR lo para y dice qué fichero y qué línea. Quien pide cosas a Savia sigue pidiéndolas igual.
- **Slice S3 (sí cambia lo que la persona puede ver).** Hoy, si los agentes que Savia usa en tu máquina se quedan atrás respecto al repositorio (por ejemplo tras actualizar sin regenerar), no hay aviso: lo notas cuando un agente se comporta distinto. Después, Pulse anota el desajuste y Savia, con su única voz (SE-518), puede incluirlo como un asunto más de su resumen, con los nombres de los agentes que difieren, y lo retira solo cuando vuelve a coincidir. **No añade pantallas ni botones**, no arregla nada por su cuenta y no interrumpe.

Como S3 cambia algo que la persona ve, **no se pone en curso sin que la operadora confirme este texto** por pregunta interactiva (SE-505); esa confirmación no existe todavía y no se inventa aquí. Por eso la spec declara `human_surface: false` (S1 y S2 no tienen superficie, S3 solo emite un evento que la tarjeta ya sabe mostrar) y deja la confirmación de S3 como condición de arranque, no de aprobación del resto.

## Fuera de alcance

- Cambiar permisos de ningún agente. `permissionMode: bypassPermissions` de los agentes que lo usan hoy se registra en el esquema y no se discute aquí.
- Hacer obligatorios `token_budget`, `output_max_tokens` o `max_context_tokens`.
- Exportar el catálogo a otros estándares de agentes o generar las definiciones desde un esquema.
- Retirar ningún agente (eso es SE-527) y tocar su lista D2 o sus AC.
- Reescribir la allowlist de SE-253 o su guard.
- Límites de delegación entre agentes: la línea no encadena agentes y primero hay que medir si existe alguna cadena sin cota.

## Decisiones pendientes de la operadora

- **Q1. ¿`token_budget` obligatorio?** Recomendada: **no ahora**. Faltan 6 agentes y la spec no puede decidir el presupuesto de cada uno. Alternativa: obligatorio con 6 excepciones congeladas más.
- **Q2. ¿S2 en tier 4?** Recomendada: **sí, aceptar el tier calculado**. Tocar la cabecera de los 12 agentes protegidos y su lista es gobernanza. Alternativa: dejar `protected-jobs.yaml` como fuente y que el validador solo compruebe que cada marca coincide (menos cambio, pero la lista sigue siendo a mano y duplicada).
- **Q3. ¿SE-527 S1 consume `--retired`?** Recomendada: **sí**, en la PR de SE-527 y con tu confirmación; esta spec no toca la suya.

## Riesgos

- **Esquema demasiado estricto frena a agentes nuevos.** Mitigación: describe el estado actual, las claves opcionales lo son y un cambio de esquema es una PR visible.
- **Falsos positivos de R10 (prosa que usa una palabra común como nombre de agente).** Mitigación: patrones por contexto (`subagent_type`, `agent:`, listas), no por palabra; test con la palabra en prosa que no debe contar.
- **La lista de excepciones se convierte en cajón de sastre.** Mitigación: solo encoge, cada línea lleva motivo y fecha, y un agente nuevo no puede entrar con excepciones.
- **Generar la lista de protegidos con un error la deja corta.** Mitigación: AC-8 (igualdad) y `--check` en CI; el hook sigue fail-closed.
- **Dependencia de SE-518 para S3.** Si el contrato de eventos cambia, S3 se rehace; S1 y S2 no dependen de ella.
- **Parecer que cambia permisos.** No lo hace; AC-8 lo demuestra con el diff vacío.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Fuente de verdad del catálogo | `.claude/agents/<x>.md`, espejo generado por `scripts/agents-opencode-convert.sh` | `.opencode/agents/<x>.md`; el validador lee este lado |
| Esquema y validador | `config/agent-frontmatter.schema.json`, `scripts/validate-agent-catalog.py` (comunes) | Los mismos ficheros |
| Lista de protegidos | `.opencode/protected-jobs.yaml`, leída por `.claude/hooks/protected-job-guard.sh` | El mismo fichero |
| Routing de jueces | `config/judge-routing.yaml` (común) | El mismo fichero |
| Allowlist de lados | `docs/agents-sync-allowlist.md` (SE-253) | Igual |

### Verification protocol

- [ ] Funciona en runtime OpenCode: el validador se ejecuta desde ambos frontends sobre `.opencode/agents/` y da el mismo resultado
- [ ] Tests BATS cubren cada regla y cada slice, con su caso negativo y su reversión (AC-1 a AC-11)
- [ ] No se registra ningún hook nuevo; el guard de protegidos no cambia

### Portability classification

- [x] **DUAL_BINDING**: el esquema y el validador son comunes; la cabecera de los agentes vive en los dos lados y el espejo se genera desde la fuente de `.opencode/agents/`.

## Aprobación

**Pendiente de la operadora.** El orden de slices viene de sus respuestas por pregunta interactiva del 2026-11-13 (registro de la orquestadora, sin enlace verificable desde la PR). El estado pasa a APPROVED solo cuando ella lo confirme en esta PR con un comentario; hasta entonces la spec es PROPOSED y no desbloquea ningún slice. Cada slice se fusiona con revisión humana de su PR concreta (SE-362).
