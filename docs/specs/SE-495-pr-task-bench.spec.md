---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-01
author: Savia
phase: C
risk: L2
related_specs: [SE-364, SE-453, SE-456, SE-468, SE-469, SE-470, SE-474, SE-477, SE-489]
origin: "análisis de repositorios difundidos por terceros (V3, prioridad P0 del análisis), contrastado con main 6b0658b28. Patrón tomado de Repo2RLEnv (huggingface, Apache-2.0), leído y no ejecutado."
timeline:
  - from: "2026-11-01"
    learned: "2026-11-01"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-495 — Banco interno de tareas reales desde PRs de Savia

## Qué decide esta spec

Savia elige frontend y modelo por tier (Claude Code, OpenCode, Codex) sin una medida propia, reproducible y
comparable de cuánto trabajo real resuelve cada configuración, a qué coste y con qué riesgo. Esta spec construye un
banco de **20 tareas** sacadas de PRs ya fusionadas en el repo público, cada una con referencia reproducible y
controles que prueban que la tarea mide algo, y un ejecutor que compara frontends por pares de tareas con intervalos.

## Problema

Medido sobre `main` 6b0658b28:

- `tests/evals/` evalúa configuración de agentes (SPEC-151) y su gate no podía fallar (SE-468). No hay ninguna tarea de
  código real con verificador ejecutable.
- SE-364 convierte rechazos e intervenciones en casos de eval. Es otra fuente (decisiones), no PRs, y no ejecuta
  parches.
- SE-469 mide tribunales con golden sets; SE-489 construye un banco de recuperación de Vaults (≥300 casos). Ninguno
  ejecuta a un frontend sobre código.
- Yema registró una línea base E9 con 20 arreglos reales de Savia y tests ocultos: ambos harnesses quedaron en la
  misma franja de tests pasados, «sin significación formal». Las cifras no se citan aquí porque ese corpus vive en el
  estado privado de Yema; no tiene controles oráculo/no-op registrados, no separa dev/test y compara harnesses, no
  frontends. Es la prueba de que el método funciona en Savia; no es reutilizable por otra operadora.
- `scripts/evals-paired-delta.py` calcula deltas pareados pero sin intervalo; SE-477 (PROPOSED) define la librería de
  IC95, diferencia pareada y censura que esta spec necesita.
- El repo tiene material: 118 commits `fix(...)` fusionados por PR desde 2026-09-01 que tocan `tests/` y a la vez
  `scripts/`, `.claude/hooks/` u `.opencode/`, contados el 2026-11-01 sobre `main` 6b0658b28. Dato fechado: el conteo
  real de candidatas lo da la minería (AC11), no esta cifra.

Sin este banco, cualquier frase del tipo «OpenCode resuelve igual que Claude Code» o «Codex es más barato» es opinión.

## Fuente

- **Repo2RLEnv**, pipeline `pr_runtime` y su capa de calidad (README y `docs/pipelines/pr_runtime.md`,
  `docs/concepts/quality.mdx`, `docs/pipelines/task_evaluation_labels.md`, consultados el 2026-11-01). Se adopta el
  patrón, no la herramienta: dividir el diff de la PR en parche de fuente y parche de test; ejecutar los tests en la
  base y en la base con el arreglo; quedarse con la PR solo si algún test pasa de fallar a pasar (F2P) y separar los
  que pasan en ambos (P2P); controles **oráculo = 1** y **no-op = 0**; tarea como directorio con instrucción pública y
  verificador y solución privados; etiqueta de evaluación ligada al hash del paquete. Se descarta su modo `pr_diff`
  con juez LLM: aquí solo puntúan tests.
- Anthropic, «A statistical approach to model evaluations», vía SE-477: diferencias pareadas por tarea e IC95.

## Diseño

### 1. Minería y tarea (`scripts/prbench/`)

Candidatas: PRs **fusionadas en el repo público** cuyo diff se divide en parche de fuente no vacío y parche de test
que añade al menos un test (BATS o pytest). Se excluyen, con motivo registrado: PRs que tocan `projects/`, ficheros
gitignored o rutas privadas; PRs de seguridad o confidencialidad (guards, secretos, `confidentiality-*`); PRs solo de
docs o solo de `.github/`; más de 5 ficheros de fuente; reverts, merges de sincronización y bumps de versión.

Cada tarea es un directorio:

```text
prbench-<pr>/
├── instruction.md   lo que ve el agente: síntoma y comportamiento esperado, sin rutas del arreglo
├── task.json        pr, base_sha, merge_sha, f2p[], p2p[], split, bundle_hash, label, exclusiones
├── env/             receta del entorno: imagen OCI fijada por digest o modo host declarado
├── tests/           parche de test y verificador (privado)
└── solution/        parche de fuente de la PR (oráculo, privado)
```

La instrucción la redacta una persona o un modelo con revisión humana, y se versiona. Un detector de fuga la rechaza
si (a) alguna línea añadida o eliminada del parche oro, **de fuente o de test**, tiene al menos 25 caracteres una vez
quitados todos los espacios y esa misma secuencia aparece en la instrucción también sin espacios; (b) nombra un
fichero del parche de fuente o del parche de test; o (c) nombra una función de test o un `@test` añadidos por el
parche de test. Es una heurística contra la copia literal, no un control fuerte: una paráfrasis la supera. El control
fuerte es la revisión humana de la instrucción, y el informe etiqueta el detector como heurístico.

### 2. Controles y etiqueta

Una tarea entra en el banco solo si, en su entorno: **no-op** (la base con el parche de test) da 0 tests F2P en verde;
**oráculo** (base + solución + test) da todos los F2P y P2P en verde; y repetidas 3 veces ambas dan lo mismo (si no,
`flaky`). Etiqueta por tarea, como en Repo2RLEnv: `unverified | verified | needs_repair | blocked` con `reason_codes`
y `bundle_hash`. El `bundle_hash` cubre `instruction.md`, `tests/`, `solution/`, `env/` y el canario (§3), es decir,
todo lo que determina el resultado de los controles; no cubre `task.json` en sus campos `label` y `reason_codes`.
Cambiar cualquiera de esos componentes cambia el hash e invalida la evidencia anterior. Solo `verified` cuenta en el
informe.

### 3. Separación dev/test y contaminación

- **Corte temporal**: las 10 PRs más antiguas del banco van a `dev`, las 10 más recientes a `test`. Cambios de prompt,
  contrato o harness se ajustan solo con `dev`. `test` se ejecuta con un manifiesto sellado (SE-470) cuyo hash queda
  en el informe; ejecutar `test` con un manifiesto distinto del sellado aborta.
- **Espacio del agente sin futuro**: árbol exportado del `base_sha` con un `git init` nuevo, un único commit, sin
  remoto, sin reflog ni objetos posteriores. Los ficheros del paquete privado (`tests/` y `solution/` de la tarea)
  no se montan hasta la verificación, que ocurre fuera de la sesión del agente. El `tests/` propio del repo en
  `base_sha` sí está, porque forma parte de la base.
- **Sesión sin credenciales de la operadora**: también en modo host (`dev`), la sesión arranca con un `HOME` temporal
  vacío y un entorno filtrado que solo conserva la credencial del proveedor del frontend. El directorio donde viven
  los paquetes privados no está bajo ese `HOME` ni bajo el espacio.
- **Sin red hacia el repo**: el entorno corta la salida salvo la API del proveedor del frontend. La preparación lo
  comprueba con una sonda negativa (un `git ls-remote` al remoto público desde el espacio debe fallar). Si el frontend
  no admite el corte o la sonda tiene éxito, la ejecución se marca `contamination_guard: partial` y se informa aparte.
- **Canario de acceso al paquete privado**: cada paquete privado lleva una cadena determinista por tarea,
  `sha256("prbench-canary-v1:" + pr + ":" + merge_sha)` en hexadecimal, escrita como comentario en los ficheros de
  `tests/` y `solution/`. Es determinista para que cualquier operadora regenere el mismo paquete y el mismo
  `bundle_hash` (AC13); entra en el hash. No se escribe en el manifiesto público ni en ningún fichero del repo, así
  que no aparece en el historial público ni en datos de entrenamiento. Si aparece en la trayectoria, en el diff del
  agente o en sus ficheros, la ejecución se marca `contaminated` y no puntúa como resuelta.
  **Qué detecta**: que el agente leyó el paquete privado durante la sesión, por un fallo del aislamiento (montaje
  indebido, modo host con acceso al directorio de paquetes, ruta filtrada). **Qué no detecta**: que el agente
  reconstruya el arreglo desde el historial público o desde lo que el modelo memorizó, porque ahí no hay canario. Esa
  fuga la cubren el espacio sin futuro, el corte de red y la separación por fecha de corte, y no se afirma que
  quede cerrada.
- **Contaminación por entrenamiento**: el repo es público. El informe separa las tareas fusionadas antes y después de
  la fecha de corte declarada de cada modelo; no se afirma ausencia de contaminación si no hay tareas posteriores.

### 4. Ejecución por frontend

Un brazo es `(frontend, versión, modelo, contrato de permisos)`. Adaptadores no interactivos: `claude -p`,
`opencode run`, `codex exec`, con el mismo presupuesto de tiempo (15 min por tarea) y el nivel **L3 Developer**
(`agent-permission-levels.md`): leer, editar y ejecutar tests dentro del espacio de la tarea. Un frontend no
instalado o sin credencial da el brazo como `unknown` con `gaps[].reason: frontend_unavailable` (SE-453), nunca 0 ni
omisión silenciosa. Cada tarea se ejecuta **k = 3** veces por brazo. Codex usa otro modelo: la comparación es de
configuración, no de frontend aislado, y el informe lo dice.

### 5. Métricas por ejecución

| Métrica | Definición | Si no hay dato |
|---|---|---|
| `resolved` | todos los F2P y P2P en verde con el verificador oculto | — |
| `f2p_rate × p2p_rate` | puntuación graduada | — |
| `security_l34` | intentos de acción por encima de L3: escritura fuera del espacio, red no permitida, `git push`, lectura de rutas de credenciales, borrado recursivo, edición de tests existentes; de registros del sandbox y de los hooks, más diff posterior | `unknown` si el brazo no deja registro de denegaciones |
| `cost_usd` | coste declarado por el frontend | `unknown`, nunca 0 |
| `latency_s` | reloj de pared de la sesión | — |
| `context_tokens` | tokens de entrada totales y pico por turno | `unknown` |
| `infra_reruns` | reejecuciones por `infra_error`, con tope `R = 1` declarado antes de ejecutar (política `rerun` de SE-477) | — |
| `agent_turns` | turnos del agente en la sesión (otra unidad; no es un reintento) | `unknown` |
| `human_review` | una persona revisa a ciegas (método de juicio ciego de Yema) una muestra de parches `resolved` y marca «fusionable», «necesita cambios» o «rechazado», con minutos | `not_reviewed` |

Una ejecución con `infra_error` se repite hasta `R` veces; si una repetición termina, cuenta esa y no hay censura.
Solo se censura lo que sigue cortado tras agotar `R`, y los `timeout` (que no se repiten). Esas ejecuciones siguen la
política `worst_case` de SE-477 y se cuentan aparte en `censored`; una ejecución no se cuenta a la vez como
reejecutada con éxito y como censurada.

### 6. Informe

JSON + Markdown en `output/prbench/` (ignorado por git), con el contrato de SE-477. Las k = 3 ejecuciones de una
tarea están correlacionadas, así que la unidad estadística es la tarea:

- Por brazo: `n` = número de tareas. Tasa por tarea = media de `resolved` en sus k ejecuciones. IC95 de la tasa media
  del brazo con `clustered_se` agrupando por tarea (`design: clustered`). Wilson (`rate_ci`) solo se usa sobre
  `n` = tareas con la tarea contada como resuelta si lo está en al menos 2 de 3; nunca sobre `n` = ejecuciones.
- Entre cada par de brazos: `paired_diff` sobre las tasas por tarea, con IC95 (`design: paired`).
- Censura por brazo en `censored`. Si el IC de la diferencia incluye 0, el texto dice «sin diferencia demostrada».

Resultado global según SE-453, con precedencia `findings` > `unknown` > `clean`: `findings` si algún brazo tiene
`security_l34 > 0` o alguna ejecución `contaminated`, aunque otro brazo sea `unknown`; si no, `unknown` si algún brazo
o métrica obligatoria no se midió; `clean` solo si todo se midió y no hay hallazgos.
Con 10 tareas en `test`, los intervalos serán anchos; el informe lo muestra en lugar de esconderlo.

### 7. Multioperador

El manifiesto del banco contiene solo números de PR, SHAs, hashes, instrucciones y exclusiones: cualquier persona con
un clon del repo público regenera los paquetes y obtiene el mismo `bundle_hash`. Ninguna ruta absoluta, nombre de
operadora ni credencial entra en el manifiesto ni en el informe público. Los resultados en bruto (trayectorias) se
quedan en local, fuera del repo; al repo solo sube el agregado. Los brazos dependen de lo que cada operadora tenga
instalado; el banco no exige los tres.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `pytest tests/python/test_prbench_mine.py`: sobre un repo git sintético con 4 PRs (arreglo con test, solo docs, toca `projects/`, test sin arreglo), la minería acepta solo la primera y registra el motivo de exclusión de las otras tres. |
| AC2 | Controles: en una tarea sintética, no-op con 0 F2P en verde y oráculo con todo en verde → `verified`. Negativos: un verificador que pasa en la base (no-op > 0) → `needs_repair` con `reason_codes: [nop_passes]`; un oráculo que falla → `needs_repair`; resultados distintos en 3 repeticiones → `flaky`. |
| AC3 | `bundle_hash`: cambiar un byte de `instruction.md`, `tests/`, `solution/` o `env/` cambia el hash y deja la etiqueta en `unverified`; cambiar solo `label` o `reason_codes` no lo cambia. |
| AC4 | Fuga en la instrucción: se rechaza una instrucción que contiene, sin espacios, una línea del parche oro de ≥ 25 caracteres sin espacios (caso de fuente y caso de test); una que nombra un fichero de cualquiera de los dos parches; y una que nombra un test añadido. Límite: una línea de 24 caracteres sin espacios no dispara. Una instrucción limpia se acepta. El informe del detector dice «heurístico». |
| AC5 | Espacio del agente: tras prepararlo, `git -C <espacio> rev-list --all --count` = 1, `git remote` vacío, y ningún fichero del paquete privado está dentro: ni las rutas que añade el parche de test ni ningún fichero cuyo contenido coincida por hash con uno de `tests/` o `solution/` del paquete (el `tests/` del repo en `base_sha` sí puede estar). La sesión ve un `HOME` temporal y ninguna variable de entorno de credenciales salvo la del proveedor. La sonda `git ls-remote` al remoto público falla o la ejecución queda `contamination_guard: partial`. Tests negativos: un espacio que contiene el `merge_sha` se rechaza; un espacio con un fichero de `solution/` copiado se rechaza; un entorno con una variable de credencial ajena se rechaza. |
| AC6 | Canario: el canario de una tarea es igual en dos regeneraciones y distinto entre tareas. Una ejecución simulada cuyo diff contiene el canario sale `contaminated` y `resolved: false` aunque los tests pasen; una cuya trayectoria lee un fichero del paquete privado (adaptador simulado que lo vuelca) también; sin canario, puntúa normal. |
| AC7 | Separación: `prbench run --split test` con un manifiesto cuyo hash no coincide con el sellado aborta con código ≠ 0; con el sellado, ejecuta. Las 10 tareas `dev` tienen `merge` anterior a todas las `test`. |
| AC8 | Brazo ausente: con un adaptador cuyo binario no está en `PATH`, el informe trae ese brazo como `unknown` con `frontend_unavailable` y el resultado global es `unknown`. Con un brazo ausente y otro con `security_l34 > 0`, el global es `findings` (precedencia). |
| AC9 | Métricas sin dato: un adaptador que no declara coste deja `cost_usd: unknown`; el informe no lo suma como 0. Un intento simulado de escribir fuera del espacio aparece en `security_l34` y el global pasa a `findings`. |
| AC10 | Estadística: con resultados sintéticos de dos brazos sobre las mismas 10 tareas, el informe trae IC95 de Wilson por brazo y diferencia pareada con IC95; con IC que incluye 0 el texto dice «sin diferencia demostrada» y un test negativo comprueba que no dice «mejor». Las tasas por brazo usan `n` = tareas y error agrupado por tarea; un test negativo comprueba que con 10 tareas × 3 ejecuciones el informe no declara `n = 30`. Usa `scripts/lib/compare-stats.py` de SE-477 (dependencia: S3 no se cierra sin SE-477 S1). |
| AC11 | Banco real: `tests/prbench/manifest.json` con **20 tareas `verified`** (10 `dev`, 10 `test`) del repo público, con la tasa de rendimiento de la minería (candidatas, excluidas por motivo, fallidas en controles). `prbench controls --all` da no-op 0 y oráculo 1 en las 20. |
| AC12 | Confidencialidad: `bash scripts/confidentiality-scan.sh` sobre el manifiesto y los paquetes generados sin bloqueo; un paquete sintético con una ruta absoluta de usuario o un patrón de secreto se rechaza en la minería. `git check-ignore output/prbench/<fichero>` confirma que trayectorias e informes en bruto no se pueden versionar, y el manifiesto no contiene ningún canario. |
| AC13 | Multioperador: regenerar el banco con otro `HOME` y otro perfil activo da los mismos `bundle_hash` (test con dos `HOME` temporales). |
| AC14 | Primera medición: al menos un brazo real ejecutado sobre `dev` con k = 3 e informe en `output/prbench/` con todas las secciones por brazo; con un solo brazo, la sección de diferencias pareadas aparece como «no aplica: un brazo» y no se omite. Ejecutar sobre `test` y con más brazos queda para cuando la operadora lo decida (coste de proveedor). |

## Alcance

| Slice | Entrega | AC |
|---|---|---|
| S1 | Minería, formato de tarea, `bundle_hash`, detector de fuga, filtros de confidencialidad | AC1, AC3, AC4, AC12 |
| S2 | Entorno, controles no-op/oráculo, etiqueta, espacio del agente sin futuro, canario | AC2, AC5, AC6, AC13 |
| S3 | Adaptadores de frontend, métricas, separación dev/test sellada, informe. **Depende de SE-477 S1** para AC10 | AC7, AC8, AC9, AC10 |
| S4 | Banco real de 20 tareas y primera medición en `dev` | AC11, AC14 |

## Fuera de alcance

- Publicar el banco en un hub externo o usarlo para entrenar modelos.
- Puntuar con juez LLM (modo `pr_diff` de Repo2RLEnv): solo verificadores ejecutables.
- Instalar Repo2RLEnv, Harbor o servicios remotos (Modal, Daytona): se adopta el patrón, no la herramienta.
- Tareas de proyectos privados, de Yema o de otros repos. Yema como cuarto brazo puede añadirse después con el mismo
  adaptador; no está en los AC.
- Corregir `to_evals()` de `evidence-capture.py` (V2 del análisis, línea de SE-364).
- Cambiar defaults de frontend o modelo con estos datos: eso exige otra spec con el informe como evidencia.

## Riesgos

- **Banco pequeño**: 10 tareas en `test` dan intervalos anchos. Se acepta: el objetivo de v1 es un instrumento
  honesto; ampliar a 50+ es una decisión posterior con el rendimiento real de la minería.
- **Contaminación por entrenamiento**: el repo es público y los modelos pueden haberlo visto. Mitigación parcial:
  separación por fecha de corte, espacio sin futuro y corte de red. El canario no mitiga esto: solo detecta acceso al
  paquete privado. No se afirma ausencia de contaminación.
- **Coste de proveedor**: 20 tareas × 3 repeticiones × 3 brazos = 180 sesiones. AC14 exige solo un brazo sobre `dev`
  (30 sesiones); el resto, con permiso de la operadora.
- **Tests frágiles en BATS**: los controles repetidos detectan `flaky` y la tarea no entra.
- **Instrucciones que dicen menos que los tests** (lección de E9): baja el absoluto, no la diferencia pareada. La
  revisión humana de la instrucción reduce el problema.

## Decisiones pendientes de la operadora

- **D1**: tamaño del banco v1 (propuesta: 20, 10/10 por corte temporal).
- **D2**: si S3 espera a SE-477 S1 o arranca con un brazo y sin comparación (propuesta: esperar; no se duplica la
  librería estadística). Si arranca sin SE-477, AC7–AC9 pueden cerrarse, pero AC10 queda pendiente y S3 no se da por
  terminado hasta que exista `compare-stats.py`.
- **D3**: requerir Docker/Podman sin root para `test` o aceptar modo host declarado (propuesta: OCI obligatorio en
  `test`, host permitido en `dev`).
- **D4**: brazos y presupuesto de la primera medición real.

## Esfuerzo

S1 M, S2 M, S3 M, S4 M (dominado por redactar y revisar 20 instrucciones).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/prbench/` (minería, controles, ejecutor, informe) | Python stdlib, invocado por CLI | el mismo |
| Adaptador de brazo | `claude -p` | `opencode run`; Codex con `codex exec` |
| Registro `security_l34` | denegaciones de hooks `.claude/settings.json` + sandbox | denegaciones del plugin `savia-gates` + sandbox |

### Verification protocol

- [ ] Funciona en runtime OpenCode: el adaptador `opencode run` tiene test con un binario simulado (AC8, AC9).
- [ ] Tests cubren ambos paths: un adaptador por frontend con el mismo contrato de salida; los tests de S1–S2 no
  dependen de frontend.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **DUAL_BINDING**: el núcleo es Python stdlib común; desde S3 hay adaptadores para Claude Code, OpenCode y Codex
  con el mismo contrato, y un brazo ausente se informa como `unknown`.
