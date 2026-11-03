---
status: PROPOSED
priority: P0
developer_type: agent-single
created: 2026-11-01
author: Savia
phase: A
risk: L2
extends: SE-364
depends_on: [SE-364]
related_specs: [SE-355, SE-387, SE-313, SE-397-F4, SPEC-151, SPEC-188, SE-456]
origin: "Iniciativa SAVIA-RESEARCH-02, validación V2 («trazas → evals») del análisis de repositorios de IA difundidos públicamente (2026-11-01). Patrón de referencia: Tracely-ai (MIT), estudiado solo leyendo, sin ejecutarlo."
timeline:
  - from: "2026-11-01"
    learned: "2026-11-01"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-494 — Trazas a regresiones herméticas: extensión de SE-364

## Problema

SE-364 aprobó el bucle de evidencia: una intervención humana (rechazo, corrección, fallo) se
convierte en un caso de eval que impide repetir lo rechazado. La implementación en `main` cubre
una parte. Además tiene un defecto de semántica y dos huecos que la dejan sin efecto sobre datos
reales. Esta spec no sustituye a SE-364: la completa y la endurece. Añade la traza normalizada y
la congelación de fallos verificados como casos offline que bloquean regresiones en CI.

### Estado verificado en `main` (commit `6b0658b28`)

| # | Hallazgo | Evidencia | Efecto |
|---|---|---|---|
| H1 | **`to_evals()` selecciona `open`, pero su docstring y SE-364 §3 dicen «casos cerrados».** No es una errata: `capture()` siempre escribe `status: "open"` y ningún código del repo escribe `closed`. Cambiar solo el filtro daría 0 evals. | `scripts/evidence-capture.py:73` (docstring), `:76` (filtro `!= "open"`), `:63` (siempre `open`); SE-364 §3; el test `tests/scripts/test_evidence_capture.py::test_genera_evals` exige `len(evals) == len(cases)` con casos abiertos y fija la semántica contraria a la spec | Todo fallo capturado se vuelve eval sin que nadie lo haya verificado. Un falso positivo del ledger acaba como discriminante. |
| H2 | **El filtro de nivel no se aplica nunca a los datos reales.** El ledger SE-355 no escribe `level`, `target` ni `detail`. | `scripts/audit-receipts.sh:68` (campos `seq, ts, session_id, actor, action, outcome, enforced, gate_id`); `scripts/evidence-capture.py:53` (`level` ausente → `"N1"`), `:54` (lista de denegados `N3`, `N3b`, `N4b`, sin `N4`), `:59` y `:61` | El filtro N3+ falla en abierto: un registro sin nivel pasa como N1, y un registro `N4` entra al corpus porque el filtro es una lista de denegados incompleta. Además, los casos reales salen con `input: ""` y `human_correction: ""`. |
| H3 | **`output_rejected` guarda la etiqueta del resultado (`"failure"`), no la salida rechazada.** | `scripts/evidence-capture.py:60` | El discriminante de SE-364 AC-2 («si vuelve a producir lo rechazado, falla») compara una etiqueta, no un comportamiento. |
| H4 | **Los IDs dependen de la posición en el ledger leído.** | `scripts/evidence-capture.py:57` (`ev-{i:03d}`) | Dos capturas sobre ledgers distintos sobrescriben `ev-000.json`, … sin aviso. |
| H5 | **Partes de SE-364 que no existen.** No hay `scripts/evidence-to-evals.py`: la conversión vive en `evidence-capture.py`. `scripts/evals-runner.sh` no acepta `--corpus`. No se leen `focal-decisions` ni las trazas de decisión. | `ls scripts/`; `grep -n corpus scripts/evals-runner.sh` → sin resultados; `scripts/evidence-capture.py:41-69` (solo audit) | El corpus no llega al runner. SE-364 AC-1 y AC-5 están validados solo con fixtures sintéticas. |
| H6 | **El wrapper ignora en silencio los argumentos desconocidos.** | `scripts/evidence-capture.sh:25` (`*) shift`) | Una errata como `--corpuss` usa la ruta por defecto sin avisar. |
| H7 | **`evals-paired-delta.py` en modo directo da PASS con cero pares.** Si `--baseline` y `--current` no comparten IDs, `threshold_pass` vale `True` y sale con 0. El modo `--run-datasets` sí lo protege (`pairs_evaluated != len(baseline)` → `unknown`). | `scripts/evals-paired-delta.py:59-70`, `:301`; protección del otro modo en `:183-185` | Un gate que use el modo directo con IDs renombrados da verde sin comparar nada. |

H1–H4 y H6 son fallos de implementación de SE-364. H5 es alcance de SE-364 no entregado. H7 es de
SPEC-151, pero afecta a cualquier gate que reutilice el script. Esta spec corrige H1–H4, H6 y H7,
y cierra H5 solo en lo que necesita la regresión hermética.

### Lo que ya existe y se reutiliza

- Ledger de acciones SE-355: `scripts/audit-receipts.sh` → `data/audit/actions.jsonl`. Aporta decisiones de política y recibos.
- Reserva de efectos SE-387: `scripts/effect-reservation.sh`. Aporta efectos con clave idempotente y estado.
- Trazas de decisión SPEC-188: `scripts/decision-trace-writer.py`. Aporta planes y decisiones con justificación.
- Exportación OTLP opcional SE-313: `scripts/trace-export-otlp.sh`. Sin `SAVIA_OTLP_ENDPOINT` no hace nada.
- Gate de evals SPEC-151: `.github/workflows/evals-ci.yaml` + `scripts/evals-paired-delta.py --check-report`.

### Qué aporta Tracely-ai (leído, no ejecutado)

Repositorio `jwuthri-cloud/Tracely-ai`, MIT, creado el 2026-10-11. Con ese nombre resuelve hoy por
la API de GitHub; las variantes `jwuthri/Tracely-ai` y `jwuthri/tracely` devuelven 404. No se ha
podido reconstruir la URL original del anuncio. Patrones útiles, con su fichero:

- **Contrato fail-to-pass**: el caso debe FALLAR en la versión que rompió y PASAR en la corrección (`design/part2-tracely/05-regression-testing.md` §0–§1).
- **Aserciones sobre la trayectoria, no sobre el texto**: herramientas requeridas o prohibidas, predicados de argumentos, `no_error`, `max_tool_calls` y modos de comparación `superset/subset/strict/unordered` (`backend/tracely/domain/regression/contract.py`).
- **Veredicto derivado de comprobaciones requeridas**: `PASS / FAIL / INCOMPLETE / SKIP`. `INCOMPLETE` (no se pudo comprobar) y `NO_COVERAGE` (no se ejecutó nada) bloquean igual que `FAIL` (`backend/tracely/domain/regression/outcome.py`, `GATE_SEVERITY`).
- **Fixtures ordenadas por tipo**: las llamadas repetidas y los errores se reproducen fielmente. Una grabación vacía o ilegible es un error de ejecución, nunca «no hubo llamadas» (`backend/tracely/domain/regression/fixtures.py`, `decode`).
- **Primera divergencia nombrada** al comparar la referencia con el candidato (`backend/tracely/domain/regression/compare.py`).

Se descarta todo lo que no sea el patrón: el backend Postgres/ClickHouse/S3, el SDK, la ingesta
alojada, los jueces LLM dentro del gate y la agrupación automática de fallos. Savia adopta el
protocolo y los invariantes, no el subsistema.

## Qué decide esta spec

1. **Esquema de eventos de traza `savia.trace/v1`**: siete tipos, con IDs y huellas, sin texto libre ni secretos.
2. **Ciclo de vida del caso** en el corpus de SE-364: `open → verified → closed`. Solo `closed` produce evals y regresiones, como dice SE-364.
3. **Congelación de 10 fallos verificados** como casos herméticos offline que comprueban invariantes y efectos observables, nunca coincidencia de texto.
4. **Gate en CI**, en un workflow propio sin filtro de rutas, que bloquea con `FAIL`, `INCOMPLETE` o `NO_COVERAGE`.
5. **OTLP opcional** de salida, reutilizando SE-313, apagado por defecto.

### 1. Esquema `savia.trace/v1` (JSONL, un evento por línea)

Campos comunes, todos obligatorios:

| Campo | Tipo | Regla |
|---|---|---|
| `schema` | `"savia.trace/v1"` | Literal exacto |
| `trace_id` | 32 hex | W3C trace-context; compatible con OTLP |
| `span_id` / `parent_span_id` | 16 hex / 16 hex o `null` | Árbol de la operación |
| `seq` | entero ≥ 0 | Orden total dentro de `trace_id`, sin huecos |
| `ts` | ISO-8601 UTC | |
| `kind` | enum | `plan`, `call`, `policy_decision`, `authority_decision`, `effect`, `observation`, `receipt` |
| `actor` | `{harness, frontend, role}` | Rol funcional (`orchestrator`, `worker`, `hook:<id>`), nunca un nombre de persona |
| `level` | `N1`, `N2`, `N3`, `N3b`, `N4`, `N4b` | **Obligatorio.** Un evento sin nivel es inválido, no se asume `N1`. El enum incluye `N3b` porque `evidence-capture.py:54` ya lo trata como nivel excluido |

Campos por tipo. Ningún campo admite texto libre; los textos se sustituyen por huellas.

| `kind` | Campos propios |
|---|---|
| `plan` | `plan_ref` (spec/tarea), `steps_digest` |
| `call` | `tool`, `args_digest`, `result_digest`, `status` (`ok`, `error`, `timeout`), `exit_code` |
| `policy_decision` | `gate_id`, `decision` (`allow`, `deny`, `ask`), `rule_ref`, `input_digest` |
| `authority_decision` | `authority_level` (`L0`–`L4`), `decision` (`granted`, `denied`, `absent`), `grant_ref` (ID de grant o `null`), `approver_role` |
| `effect` | `op`, `idempotency_key`, `state` (`reserved`, `executed`, `closed`, `ambiguous`), `target_digest` |
| `observation` | `observable` (enum cerrado: `exit_code`, `file_state`, `branch_state`, `pr_state`, `ledger_entry`, `stdout_class`), `value` (enum o entero acotado) o `value_digest` |
| `receipt` | `receipt_kind` (`audit`, `review`, `merge`, `effect`), `receipt_ref`, `content_digest`, `idempotency_key` (obligatorio si `receipt_kind` es `effect`; `null` en los demás) |

**Huellas.** `*_digest` es `sha256` del JSON canónico (claves ordenadas, UTF-8, sin espacios)
calculado **después** de sanear el objeto completo, de forma recursiva (objetos y listas anidados):

- se elimina toda clave cuyo nombre, **sin distinguir mayúsculas y por subcadena**, contenga
  `token`, `password`, `passwd`, `secret`, `authorization`, `cookie`, `api_key`, `apikey`,
  `api-key`, `credential` o `private_key`; `pat` se compara por segmento completo (`pat`,
  `gh_pat`, `azure_pat`), no por subcadena, para no eliminar `path`. Así caen también
  `access_token`, `GITHUB_TOKEN`, `x-api-key` o `AUTHORIZATION`;
- en cada **valor** de texto, incluido el de una cadena compuesta (por ejemplo, los `args` de
  Bash con `-H 'Authorization: …'`), se sustituye por `[REDACTED]` todo tramo que case con los
  patrones de secretos del escáner de confidencialidad o con una cabecera
  `Authorization`/`Cookie`.

El digest no protege un secreto de baja entropía frente a fuerza bruta, así que los secretos no
se resumen: se eliminan antes de resumir. Por la misma razón, un `sha256` sin sal de un valor N2
(una ruta bajo `HOME`, un nombre de proyecto) se puede recuperar por diccionario. Por eso los
ficheros destinados al repo (`trace.jsonl` de un caso congelado) **solo admiten eventos N1**. Las
trazas N2 se quedan en local y, si se resumen, usan HMAC-SHA256 con una clave local que no viaja
al repo.

**Validación con fallo cerrado.** `scripts/trace-validate.py` rechaza con código ≠ 0 en estos casos:

- tipo desconocido, campo desconocido o campo de texto libre;
- falta `level`, o el nivel no es N1 en un fichero destinado al repo (lista de permitidos, no de
  denegados: N2, N3, N3b, N4 y N4b se rechazan);
- cualquier valor que case con un patrón de secreto;
- `seq` con huecos o repetido.

Esta spec no añade instrumentación a los hooks en vivo. `scripts/trace-normalize.py` convierte
las fuentes existentes (ledger SE-355, reservas SE-387, trazas de decisión SPEC-188) en eventos
`savia.trace/v1`. Si una fuente no trae `level`, el normalizador **no asigna N1**: marca el
evento como `level: null` y el validador lo rechaza. El nivel lo asigna quien verifica el caso.

### 2. Ciclo de vida del caso (corrige H1–H4)

El caso del corpus de SE-364 conserva su formato y gana campos:

```json
{
  "id": "ev-<sha256(source + \x1f + canon(registro_fuente_completo))[:16]>",
  "source": "audit|effect|decision-trace|focal-decisions",
  "status": "open|verified|closed|discarded",
  "level": "N1|N2|null",
  "trace_ref": "tests/evals/trace-regressions/cases/<id>/trace.jsonl",
  "rejected_behaviour": {"kind": "...", "invariant_violated": "..."},
  "verification": {"verified_by_role": "operator|reviewer", "evidence_ref": "PR o commit", "ts": "..."}
}
```

- `open`: lo produce la captura. No genera evals.
- `verified`: una persona revisora confirma que el fallo es real, asigna nivel y describe el comportamiento rechazado como invariante. Este paso nunca lo hace un agente (Rule 8).
- `closed`: caso congelado con traza, fixtures, invariantes y prueba fail-to-pass. **Solo los casos `closed` producen evals** (`to_evals`) y regresiones herméticas.
- `discarded`: falso positivo. Se conserva con motivo para medir la precisión de la captura.
- Un estado desconocido hace que `to_evals` termine con código 2. No se ignora en silencio.
- **Cierre exigible, no solo declarado.** `to_evals` y el gate rechazan (código 2) un caso `closed` sin `verification` completo (`verified_by_role`, `evidence_ref`, `ts`) o, si tiene `trace_ref`, sin `f2p` con `failing: FAIL` y `fixed: PASS`. El `f2p` solo se exige a los casos con `trace_ref` (regresión hermética); un caso del ledger sin componente reproducible puede cerrarse con la verificación humana y produce eval de SE-364, pero no regresión hermética. Así no cambia la semántica de SE-364 §3 para el corpus existente. `evidence_ref` debe ser un commit ancestro de `origin/main` o una PR fusionada; si no, el informe marca el caso como «verificación no firmada». El `f2p` de `case.json` no se cree: el job de CI recalcula `--verify-f2p` de cada caso que la PR añade o modifica y bloquea si no coincide. Mientras SE-491 (autorizaciones firmadas por la operadora) no esté implementada, el paso a `verified` solo entra por una PR con revisión humana (Rule 8); cuando lo esté, `verification` llevará esa firma y el gate la comprobará.
- IDs estables por contenido (H4): el ID es el hash del **JSON canónico del registro fuente completo** (claves ordenadas, sin espacios), con el prefijo `source` y un separador `\x1f` entre ambos. Incluye `seq` y todos los campos, así que dos registros distintos con el mismo `ts`, `action` y `session_id` (reintentos del mismo hook, o `ts`/`session_id` vacíos en ledgers SE-355 antiguos) no colisionan. Capturar dos veces el mismo ledger no duplica casos, y dos ledgers distintos no se pisan. Si aun así un ID nuevo coincide con uno existente de contenido distinto, la captura sale con 2 en vez de sobrescribir. Límite conocido: el ID depende de `seq`, que `audit-receipts.sh` numera de forma monotónica en `.seq` sin rotar el ledger; si alguien reinicia `.seq` o compacta el ledger, el mismo hecho obtiene un ID nuevo y aparece un caso `open` duplicado, que la persona que verifica descarta. Validación: el ID de un caso debe casar con `^ev-[0-9a-f]{16}$` y `trace_ref` debe resolverse dentro de `tests/evals/trace-regressions/cases/<id>/`; si no, el caso se rechaza (código 2), porque ambos son dato de la PR.
- `rejected_behaviour` sustituye a la etiqueta de `output_rejected` (H3). `output_rejected` se mantiene como alias de lectura para no romper consumidores de SPEC-151.

### 3. Casos congelados herméticos

Estructura: `tests/evals/trace-regressions/cases/<id>/` con estos ficheros:

- `case.json`: metadatos, procedencia, `failing_ref` y `fixed_ref` (commits públicos de `main`), `component` (hook, script o gate bajo prueba) y nivel N1/N2;
- `trace.jsonl`: la traza `savia.trace/v1` del fallo original, saneada;
- `fixtures.json`: entradas grabadas y ordenadas por tipo (stdin JSON del hook, resultados de herramientas, estado de ficheros). Una fixture vacía o ilegible da `INCOMPLETE`, nunca `PASS`;
- `invariants.json`: comprobaciones tipadas, cada una `required: true|false`.

**Qué se reproduce.** El componente determinista que falló (un hook, un guard TS, un script de
gate o de merge) se ejecuta con las entradas grabadas. Su salida se convierte en eventos
`savia.trace/v1` y se evalúan los invariantes. No se reproduce un modelo: la salida del modelo
forma parte de la fixture grabada, y la regresión prueba cómo reacciona la parte determinista de
Savia ante ella. La evaluación del comportamiento del modelo sigue en SE-364 y SPEC-151, fuera
del gate offline.

**Invariantes admitidos** (lista cerrada; el validador rechaza los demás):

| Invariante | Significado |
|---|---|
| `requires_event` / `forbids_event` | Existe o no existe un evento que case con un patrón de campos tipados |
| `precedes` | El evento A aparece antes que el B; por ejemplo, `authority_decision granted` antes de `effect executed` |
| `no_effect_after_deny` | Tras un `policy_decision deny` no hay `effect executed` con `seq` mayor en el **mismo `trace_id`** (cualquier span, también los hermanos) cuyo `op` sea igual a uno de los valores que lista el invariante (igualdad exacta, nunca regex); sin lista, ningún efecto |
| `effect_at_most_once` | Una `idempotency_key` no llega a `executed` dos veces |
| `ambiguous_blocks_retry` | Tras un `effect ambiguous` no hay reintento automático sin `authority_decision granted` |
| `receipt_for_effect` | Cada `effect closed` tiene un `receipt` con `receipt_kind: effect` y la misma `idempotency_key` |
| `observable_equals` | Un `observation` concreto toma un valor del enum o un entero (código de salida, estado de rama, del PR o del fichero) |
| `max_calls` | Límite de eventos `call` por herramienta |

Quedan **prohibidas** las aserciones sobre texto: igualdad de cadenas, expresiones regulares o
similitud sobre la salida de un modelo o el mensaje de un hook. El hook puede reformular su
mensaje sin romper la regresión. Lo que no puede cambiar es su efecto: bloquear (`exit_code` 2) o
dejar pasar.

**Fail-to-pass.** `scripts/trace-freeze.py --verify-f2p <id>` ejecuta el caso dos veces, cada una
en un worktree temporal: contra `failing_ref` debe dar `FAIL` y contra `fixed_ref` debe dar
`PASS`. El resultado se guarda en `case.json` (`f2p: {failing: "FAIL", fixed: "PASS", verified_at}`).
Un caso sin `f2p` verificado no puede estar `closed`. Así cada regresión demuestra que puede
fallar (SE-456). Antes de llamar a git, `trace-freeze.py` exige que cada ref case con `^[0-9a-f]{40}$` (un SHA
completo, nunca un nombre ni algo que git pueda leer como opción) y pasa los refs tras
`--end-of-options`. Después, antes de crear los worktrees, comprueba con
`git merge-base --is-ancestor <ref> origin/main` que `failing_ref` y `fixed_ref` son ancestros de
`origin/main`; si no, rechaza el caso (código 2) sin ejecutar nada. Las dos ejecuciones usan el
mismo entorno hermético que el runner.

**Hermeticidad.** El aislamiento de red se hace a nivel de sistema operativo, porque los
componentes bajo prueba son sobre todo hooks y scripts bash que el runner lanza como subprocesos.
Un parche de `socket` en Python no los alcanza, y vaciar `HTTP(S)_PROXY` no impide `curl` directo
ni `/dev/tcp`. El runner `scripts/trace-replay.py`:

- ejecuta cada caso dentro de un **espacio de nombres de red vacío** (solo `lo`), heredado por
  todos los subprocesos: `unshare --user --map-root-user --net` (`unshare -rn`) si el núcleo lo
  permite, o `sudo unshare --net -- setpriv --reuid=<uid> --regid=<gid> --init-groups …` en el runner de
  CI, para que el código de la PR no corra como root dentro del espacio de nombres. Antes de ejecutar el caso
  comprueba que el aislamiento funciona: una conexión de sondeo desde un subproceso bash a una
  dirección no local debe fallar;
- si no puede establecer ese aislamiento o el sondeo conecta, **no ejecuta el caso: el veredicto
  es `INCOMPLETE`**, nunca `PASS` ni un modo «best-effort». Le pasa, por ejemplo, a macOS y a los
  Linux que restringen los espacios de nombres de usuario sin privilegios (Ubuntu 24.04 con
  AppArmor: `unshare -rn` falla con «Operation not permitted» al escribir `uid_map`, comprobado
  en la máquina de desarrollo el 2026-11-02). El informe dice por qué;
- vacía `HTTP(S)_PROXY`, `SAVIA_OTLP_ENDPOINT` y las credenciales, y ejecuta con `HOME` temporal;
- usa un `PATH` mínimo declarado en `case.json`, validado contra una lista blanca de directorios
  del sistema (`/usr/bin`, `/bin`, `/usr/local/bin`) más el worktree temporal del caso. Una
  entrada fuera de la lista rechaza el caso, porque `case.json` es dato de la PR;
- además, dentro de los componentes Python, instala un bloqueo en `socket.socket` y
  `socket.create_connection`. Si se dispara, el caso da `INCOMPLETE`. Es una segunda barrera y un
  detector, no la garantía de aislamiento.

El runner nunca escribe fuera de su directorio temporal.

**Selección de los 10 casos.** Criterios:

- fallo corregido en `main` con PR pública y test;
- componente determinista;
- entrada reproducible por stdin o fichero;
- datos N1;
- al menos 3 componentes distintos;
- al menos 2 casos de efectos o autoridad.

Grupo de candidatos verificado en `git log origin/main`; la selección final y su verificación son
el slice S2:

- #1239: `block-force-push` esquivado con prefijos, subshell o `git -C`;
- #1240: `sudo` encadenado, con prefijo o en subshell (bash y TS);
- #1241: `agent-git-discipline` esquivado encadenando órdenes;
- #1242: borrado de ramas remotas ajenas;
- #1348: paridad OpenCode de `block-force-push` y agregador sin falso PASS;
- #1398: ocho hooks PreToolUse en fallo abierto por leer variables que ningún runtime define;
- #1405: hooks de subagentes no registrados para `Agent`;
- #1407: `merge-sprint` paraba con `etiqueta_fallida`;
- #1410: `agent-trace-log` y `bash-output-compress` leen la entrada por stdin;
- #1412: `agent-dispatch-validate` bloqueaba prompts de solo lectura;
- #1444: port TS de `block-gitignored-references` con proyectos autorizados.

Un candidato que no supere el fail-to-pass se descarta con motivo. No se rebaja el criterio para
llegar a 10: si quedan menos, la PR de S2 lo dice, AC-10 queda sin cumplir y la spec no pasa a
IMPLEMENTED. No hay «mínimo aceptable» por debajo de 10.

### 4. Gate en CI

Workflow propio, `.github/workflows/trace-regressions.yaml`, y no un job dentro de
`evals-ci.yaml`. Ese workflow solo se dispara con cambios en `.claude|.opencode/{skills,agents,hooks}`
(`evals-ci.yaml:9-17`), así que no correría en las PRs que más importan: `scripts/**` (por
ejemplo, `merge-sprint`, #1407), los guards TS del plugin `savia-gates` o la propia suite. Además,
su job actual tiene `pull-requests: write` (`evals-ci.yaml:43-45`). El nuevo workflow:

- se dispara con `pull_request` hacia `main` **sin filtro de `paths`**, y nunca con
  `pull_request_target`, porque ejecuta código de la PR y de `failing_ref`;
- declara `permissions: contents: read` y nada más, y usa `actions/checkout` con
  `persist-credentials: false` y `fetch-depth: 0` (el código de la PR no debe poder leer el token
  de `.git/config`, y `git merge-base` y `git show origin/main:…` necesitan la historia);
- ejecuta `python3 scripts/trace-replay.py --suite tests/evals/trace-regressions --report <json>` y después `--check-report`.

Hacerlo check requerido en la protección de `main` es un cambio de configuración del repositorio.
Lo hace la operadora; la PR de S3 lo pide en el body.

- Veredicto por caso, derivado de las comprobaciones requeridas (patrón de Tracely): `FAIL` si una falla; `INCOMPLETE` si una no se pudo evaluar, la ejecución no terminó o no hubo aislamiento de red; `PASS` si todas se ejecutaron y pasaron.
- Estado del gate, de peor a mejor: `FAIL` > `INCOMPLETE` > `NO_COVERAGE` > `PASS`. **Solo `PASS` deja pasar**; los otros tres salen con código ≠ 0.
- **Manifiesto.** `tests/evals/trace-regressions/manifest.json` lista cada caso con `{id, status, case_digest}`, donde `case_digest` es el sha256 del JSON canónico de `case.json`, `invariants.json` y `fixtures.json`. Lo genera `trace-freeze.py`; no se edita a mano, y el validador rechaza un manifiesto que no coincida con los casos.
- **`NO_COVERAGE`** se da cuando hay 0 casos ejecutados, o cuando un caso `closed` en el manifiesto de la **rama base** (`git show origin/main:tests/evals/trace-regressions/manifest.json`) falta en la PR o no se ejecutó. La referencia es la base y no la copia de trabajo, para que una PR no pueda borrar un caso y su entrada del manifiesto a la vez y dar `PASS`. Un caso `closed` en la base que en la PR tenga cualquier estado distinto de `closed` o `discarded` cuenta como falta. Un caso solo deja de contar si la PR lo pasa a `discarded` con motivo. Si el manifiesto no existe en la base (la PR que crea la suite), el conjunto de la base es vacío y solo aplica la regla de 0 casos; cualquier otro error de `git show` da `INCOMPLETE`.
- **Cambios de cobertura visibles.** El informe y el resumen del job listan, frente a la base, cada caso pasado a `discarded` y cada caso cuyo `case_digest` cambia (por ejemplo, un `invariants.json` debilitado), para que la revisión humana no dependa de leer JSON. La PR de S3 pide a la operadora un `CODEOWNERS` sobre `tests/evals/trace-regressions/`, que es configuración del repositorio.
- El informe nombra la **primera divergencia** de cada caso fallido: invariante, evento esperado y evento observado.
- El gate es offline y sin secretos.

### 5. OTLP opcional

`scripts/trace-normalize.py --emit-telemetry` escribe los eventos en el formato que ya consume
`scripts/trace-export-otlp.sh` (SE-313). Sin `SAVIA_OTLP_ENDPOINT` no sale nada (cero telemetría
por defecto). Tampoco sale ningún evento con nivel distinto de N1/N2, haya o no endpoint. La
ingesta OTLP de entrada (recibir trazas de harnesses externos) queda fuera de alcance.

## Criterios de aceptación

Cada AC se cumple con un test que falla contra el código anterior y pasa con el nuevo; los ACs
de comportamiento incluyen caso negativo.

- **AC-1 (H1)** `to_evals()` solo emite casos `closed`. Test: un corpus con `open`, `verified`, `closed` y `discarded` produce exactamente el `closed`. Negativo: un estado `foo` hace que `--to-evals` salga con 2, y un caso `closed` sin `verification` o sin `f2p` (`failing: FAIL`, `fixed: PASS`) teniendo `trace_ref` también sale con 2. El test actual `test_genera_evals`, que fija la semántica contraria a SE-364, se reescribe para exigir que un caso `open` **no** produzca eval. El cambio y su motivo (contradicción con SE-364 §3) constan en el body de la PR.
- **AC-2 (H2)** Un registro de ledger sin `level` no entra al corpus como N1: el caso queda `open` con `level: null` y `to_evals` no lo emite aunque se fuerce `closed` sin nivel (código 2). Un registro `N4` tampoco entra (hoy entra: `evidence-capture.py:54`); el filtro pasa a lista de permitidos `N1`/`N2`. Negativo: un registro N2 verificado sí produce eval.
- **AC-3 (H3, H4)** IDs estables: capturar dos veces el mismo ledger deja el mismo número de ficheros, y dos ledgers distintos con la misma posición no se pisan. Caso límite: dos registros con el mismo `ts`, `action` y `session_id` (o ambos vacíos) y distinto `seq` dan dos casos distintos. `rejected_behaviour` está presente y `output_rejected` sigue legible.
- **AC-4 (H6)** `evidence-capture.sh` con un argumento desconocido sale con 2 y lo nombra en stderr.
- **AC-5 (H7)** `evals-paired-delta.py --baseline A --current B` con 0 IDs comunes sale con 2 (`unknown`), no con 0. Antes de cambiarlo, un `grep` de los llamadores en `scripts/` y `.github/` confirma que ninguno depende del 0. Caso límite: con un par común se mantiene el comportamiento actual.
- **AC-6** `trace-validate.py` acepta una traza válida de los 7 tipos y rechaza (≠ 0), con un test por motivo: tipo desconocido, campo de texto libre, `level` ausente, nivel N3 destinado al repo, valor con forma de token (patrón del escáner) `seq` con hueco, evento N2 en un fichero destinado al repo, ID que no casa con `^ev-[0-9a-f]{16}$` y `trace_ref` fuera del directorio del caso. Saneado: `access_token`, `GITHUB_TOKEN`, `X-Api-Key` y una clave denegada anidada en un objeto interior se eliminan antes del digest; una cadena `-H 'Authorization: Bearer …'` dentro de `args` queda `[REDACTED]`; la clave `path` se conserva.
- **AC-7** `trace-normalize.py` convierte un ledger SE-355, una reserva SE-387 y una traza SPEC-188 de fixture en eventos válidos, y no asigna nivel a lo que no lo trae.
- **AC-8** Cada invariante de la lista cerrada tiene un test que pasa y otro que falla. Un `invariants.json` con una aserción de texto (`text_equals`, `regex`) se rechaza. Casos límite: `no_effect_after_deny` falla con un `effect executed` en un span hermano posterior al `deny`; `receipt_for_effect` falla si el recibo tiene otra `idempotency_key`.
- **AC-9** Hermeticidad: (a) un componente **bash** que intenta `curl` y `/dev/tcp` hacia una dirección no local y solo deja una marca si conecta no la deja bajo el runner, y el caso no da `PASS`; (b) con el aislamiento de red no disponible (simulado forzando el fallo de `unshare`) todo caso da `INCOMPLETE`, nunca `PASS`; (c) un componente Python que abre un socket da `INCOMPLETE`; (d) una fixture vacía da `INCOMPLETE`; (e) un `PATH` de `case.json` fuera de la lista blanca rechaza el caso; (f) el runner no escribe fuera de su directorio temporal (comprobado con un `HOME` de solo lectura).
- **AC-10** Hay **10 casos `closed`** en `tests/evals/trace-regressions/cases/`. Cada uno tiene `f2p` verificado (`FAIL` en `failing_ref` y `PASS` en `fixed_ref`, ambos ancestros de `origin/main`; un ref que no lo es, o que no es un SHA de 40 hex (por ejemplo, `--output=x`), se rechaza sin ejecutar git, con test), pertenece a uno de al menos 3 componentes distintos y no contiene datos N3+ ni secretos (`confidentiality-scan.sh --pr` limpio). Al menos 2 casos usan `no_effect_after_deny`, `effect_at_most_once`, `ambiguous_blocks_retry` o `precedes` sobre autoridad.
- **AC-11** El workflow `trace-regressions` bloquea en estos casos: un invariante roto adrede (`FAIL`), un caso con fixture borrada (`INCOMPLETE`), una suite vacía (`NO_COVERAGE`) y una PR que borra un caso `closed` **y** su entrada del manifiesto a la vez (`NO_COVERAGE`, comparado con el manifiesto de la base). Con la suite íntegra pasa. Un `case.json` con `f2p` escrito a mano que no coincide con el recálculo bloquea. Se demuestra con ejecuciones de `--check-report` sobre informes y manifiestos de fixture. El manifiesto ausente en la base no bloquea por sí solo; un caso `closed` de la base que pasa a `open` en la PR da `NO_COVERAGE`; el informe lista los casos descartados o modificados frente a la base. El workflow no tiene filtro de `paths`, declara solo `contents: read`, usa `persist-credentials: false` y no usa `pull_request_target` (test sobre el YAML).
- **AC-12** Multioperador: los casos y el runner no contienen rutas absolutas personales, nombres de persona ni dependencias del perfil activo. La suite pasa con `HOME` vacío y con `SAVIA_PROFILE` sin definir en Linux con aislamiento de red. En macOS, sin espacios de nombres de red, el resultado esperado es `INCOMPLETE` por caso (AC-9 b), no `PASS`; el body de la PR lo documenta.
- **AC-13** OTLP: sin `SAVIA_OTLP_ENDPOINT`, `--emit-telemetry` no abre conexiones; con endpoint, un evento N3 no se emite (test con endpoint simulado local).
- **AC-14** Sin regresión: la suite SE-364 (`tests/bats/test-se364-evidence-loop.bats`, `tests/scripts/test_evidence_capture.py`, salvo el test reescrito de AC-1) y el gate SPEC-151 de `evals-ci.yaml` siguen en verde.

## Fuera de alcance

- Instrumentar los hooks en vivo para que emitan `savia.trace/v1`. Será otra spec, con medición de latencia (SE-397-F4 está DEFERRED y es el lugar natural).
- Ingesta OTLP de entrada, jueces LLM dentro del gate, agrupación automática de fallos y backend propio de trazas.
- Reproducir el comportamiento de modelos o comparar harnesses. Corresponde a V3 (benchmark desde PRs, SAVIA-RESEARCH-02 segunda parte), que necesitará spec propia.
- Leer `focal-decisions` y completar `evals-runner.sh --corpus` (el resto de H5). Se anota como deuda de SE-364, no se cierra aquí.
- Promover un caso a `verified` o `closed` de forma automática. Siempre interviene una persona.

## Slices

| Slice | Contenido | ACs |
|---|---|---|
| S1 | Corrección de SE-364: ciclo de vida, nivel obligatorio, IDs estables, wrapper estricto y paired-delta con cero pares | AC-1–AC-5, AC-14 |
| S2 | Esquema, validador y normalizador; runner hermético, invariantes y fail-to-pass; congelación de los 10 casos | AC-6–AC-10, AC-12 |
| S3 | Workflow de CI y OTLP opcional | AC-11, AC-13 |

Cada slice es una PR Draft independiente sobre `main`.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/evidence-capture.py` / `.sh` | CLI, sin binding | Idéntico |
| `scripts/trace-validate.py`, `trace-normalize.py`, `trace-replay.py`, `trace-freeze.py` | CLI python3 stdlib | Idéntico |
| `tests/evals/trace-regressions/` | Datos del repo | Idéntico |
| Casos sobre guards TS (por ejemplo, #1348 y #1444) | No aplica | El runner invoca el port TS del plugin `savia-gates` con la misma fixture que el hook bash; los dos deben cumplir el mismo invariante |
| `.github/workflows/trace-regressions.yaml` (nuevo) | CI, independiente del frontend | Idéntico |

### Verification protocol

- [ ] La suite corre igual se lance desde Claude Code u OpenCode: no depende de variables del frontend.
- [ ] Los casos de guards con port TS ejecutan bash y TS sobre la misma fixture; si falta Node.js, dan `INCOMPLETE`, nunca `PASS`.
- [ ] No añade hooks; no hay registro en `savia-gates`.

```bash
python3 -m pytest tests/scripts/test_evidence_capture.py tests/scripts/test_trace_regressions.py -q
bats tests/bats/test-se364-evidence-loop.bats tests/bats/test-se494-trace-regressions.bats
python3 scripts/trace-replay.py --suite tests/evals/trace-regressions --report /tmp/tr.json
python3 scripts/trace-replay.py --check-report /tmp/tr.json
```

### Portability classification

- [x] **PURE_BASH**: python3 stdlib y bash, sin bindings de frontend. Los casos de paridad TS solo necesitan Node.js, que ya exige el plugin `savia-gates`.

## Riesgos

- **Fuga por la traza.** Es el riesgo principal. Lo mitigan cuatro barreras: esquema sin texto libre, nivel obligatorio sin valor por defecto, eliminación de secretos antes del digest y escáner de confidencialidad en la PR. Una traza que no valida no entra.
- **Casos frágiles.** Atar la regresión al texto del hook la rompería con cada reformulación. Por eso se prohíben las aserciones de texto: solo cuentan efectos observables e invariantes.
- **Aislamiento no disponible.** Donde no hay espacios de nombres de red, la suite da `INCOMPLETE` y el gate bloquea. Es deliberado: un verde sin aislamiento sería un falso verde. El CI de GitHub (Ubuntu) es el entorno de referencia; S2 mide allí que `unshare --net` funciona antes de activar el gate.
- **Coste de CI.** 10 casos de componentes deterministas, sin red ni modelo; previsto por debajo de 60 s. Se mide en S3 y se informa en la PR.
- **Falsa sensación de cobertura.** 10 casos no son una garantía general. El informe dice qué invariantes y componentes cubre y cuáles no.

## Referencias

- SE-364 (bucle de evidencia, canónico), SE-355 (ledger), SE-387 (reservas de efectos), SE-313 (OTLP opcional), SE-397-F4 (traza operativa, DEFERRED), SPEC-151 (paired-delta), SPEC-188 (trazas de decisión), SE-456 (tests que pueden fallar).
- Tracely-ai, `github.com/jwuthri-cloud/Tracely-ai` (MIT): `design/part2-tracely/05-regression-testing.md`, `backend/tracely/domain/regression/{contract,outcome,fixtures,compare}.py`.
- W3C Trace Context (formato de `trace_id` y `span_id`).
