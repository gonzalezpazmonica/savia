---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-12
author: Savia
phase: A
risk: L3
human_surface: true
parent: SE-510
depends_on: [SE-510]
related_specs: [SE-510, SE-475, SE-453, SE-362, SE-445, SE-400, SE-436]
origin: "Propuesta aprobada como idea por la operadora el 2026-11-12: reglas de guarda escritas en markdown, al estilo del plugin hookify de Anthropic, como anexo de SE-510 y no como hooks nuevos. Origen técnico: revisión de repos de Anthropic del 2026-11-11 (informe privado en Savia Labs, extracción E5). Solo spec y prototipo."
timeline:
  - from: "2026-11-12"
    learned: "2026-11-12"
    value: "PROPOSED"
    source: "worker del plan intensivo; encargo de la orquestadora"
---

# SE-520 — Reglas de guarda en texto (anexo de SE-510)

> **Por qué una spec hija y no una sección dentro de SE-510.** SE-510 está APPROVED y su `status` vale para todo el fichero; una sección PROPOSED dentro mezclaría dos estados. Además `scripts/planning-view.py:43` solo admite ids `SE-[0-9]+`, así que `SE-510.1` no tendría entrada en la planificación. Esta spec es el anexo: no cambia nada de SE-510, depende de sus slices y se lee como su capítulo sobre el formato de las guardas simples.

## Problema (verificado en origin/main 7f6f27f53, 2026-11-12)

Cada guarda de Savia es hoy un script (`.claude/hooks/*.sh`) y, si existe en OpenCode, otro escrito a mano en TypeScript (`.opencode/plugins/guards/*.ts`). Muchas guardas solo comparan un campo de la entrada con una lista de patrones, pero para añadir una más hace falta un script nuevo, un registro en `.claude/settings.json`, un proceso más en cada llamada y, para OpenCode, un segundo port que puede divergir (ya pasó: PR #1237 y #1238, dos huecos solo en TS).

El plugin `hookify` de Anthropic propone otra forma: una regla es un fichero markdown con frontmatter (evento, patrón, acción) y un único motor las evalúa todas. La idea encaja con la escalera de remedios (`docs/rules/domain/remedy-ladder.md`): una regla declarativa es más barata que un hook y más fácil de revisar. Pero hookify, tal como está, **falla abierto en todo** (ver «Qué tomamos de hookify y qué no»), y Savia no puede adoptar eso.

### Inventario: qué guardas se podrían escribir como regla de texto

Método (Apéndice A, órdenes A1–A3): de los 134 registros de hook en 17 eventos y los 126 ficheros `.claude/hooks/*.sh`, se buscan las guardas que **pueden bloquear** (exit 2, `permissionDecision: deny` o `decision: block`) y se lee la condición que precede a cada bloqueo. Resultado: **41 ficheros** con bloqueo, más **2 registros** que no son ficheros de `hooks/` (`scripts/operator-grant.sh guard` y el hook de tipo `prompt` sobre `git commit`): **43 guardas bloqueantes**. Los otros 85 ficheros solo avisan, inyectan contexto o registran telemetría; no se clasifican aquí (ver Fase 4).

Clases:

- **T — texto completo.** La decisión es una función pura de campos del JSON de entrada (stdin) con patrones o listas literales. Sin estado, sin git, sin sistema de ficheros, sin hora, sin contadores, sin variables de entorno, sin modelo.
- **P — parcial.** El núcleo es un patrón, pero necesita algo más: tokenizar la orden en segmentos, una variable de entorno o una lista leída de otro fichero. La regla podría expresar la parte de patrón; el resto se queda en el hook.
- **N — no expresable.** Depende de estado del repo (rama, árbol sucio, `.gitignore`), del sistema de ficheros (existe el test, antigüedad del resumen), de contadores o presupuestos, de una puntuación heurística o de un modelo.

| Clase | N.º | % de 43 | Guardas |
|---|---|---|---|
| T | **7** | 16 % | `block-credential-leak`, `block-infra-destructive`, `android-adb-validate`, `block-pat-file-write`, `memory-verified-gate`, `validate-layer-contract`, `agent-tool-call-validate` |
| P | **8** | 19 % | `block-force-push` (lógica entre segmentos), `agent-git-discipline` (cuenta operandos de `rm`), `block-sensitive-tracking` (rutas N3+ de un fichero), `protected-job-guard` (lista YAML y variable), `delegation-guard` (profundidad por variable), `recursion-guard` (estructura del JSON), `permission-mode-gate` (modo por variable), `agent-dispatch-validate` (contexto exigido en el prompt) |
| N | **28** | 65 % | `validate-bash-global` (resolvedor de destinos git; F1 de SE-510 enseña que un patrón no basta), `block-branch-switch-dirty`, `block-commit-to-main`, `agent-hook-premerge`, `prompt-hook-commit`, `project-isolation-gate`, `block-gitignored-references`, `block-project-whitelist`, `vault-frontmatter-gate`, `tdd-gate`, `tool-call-healing`, `pr-summary-gate`, `repeat-tool-guard`, `acm-enforcement`, `context-preflight-check`, `spec156-token-budget-projection`, `action-review`, `responsibility-judge`, `data-sovereignty-gate`, `prompt-injection-guard`, `context-sanitize-input`, `memory-write-sanitize`, `mind-virus-load-gate`, `mind-virus-write-gate`, `sycophancy-strip`, `context-greedy-inject`, `operator-grant guard`, hook `prompt` de commit |

Lectura honesta de los números:

- **Las reglas de texto no sustituyen la mayoría de guardas.** Dos de cada tres dependen de estado. El valor no está en migrar en masa, sino en: (1) que las guardas **nuevas** de clase T nazcan como regla y no como hook; (2) paridad Claude Code / OpenCode por construcción para esas reglas; (3) revisión humana más fácil (un patrón y sus casos en un fichero, no un script).
- Ahorro de procesos si las 7 T pasan a regla: por llamada a Bash, 4 procesos menos de 24 (`block-credential-leak`, `block-infra-destructive`, `android-adb-validate`, `agent-tool-call-validate`); por Edit/Write, 4 menos de 29 (`block-pat-file-write`, `memory-verified-gate`, `validate-layer-contract`, `agent-tool-call-validate`). Con el despachador de SE-510 en marcha, el motor de reglas es **un** manejador más dentro del mismo proceso por evento.
- Clasificación hecha leyendo las condiciones de bloqueo, con una búsqueda heurística para encontrarlas (A2). Puede tener errores de frontera entre T y P. La Fase 1 la convierte en un fichero de inventario comprobado por test (AC-1), no en una tabla de prosa.
- Dos de las 7 T tienen hoy un interruptor propio por variable de entorno (`SAVIA_PAT_BLOCK=off` en `block-pat-file-write`, `SAVIA_VERIFIED_MEMORY_DISABLED=true` en `memory-verified-gate`). Una regla no admite interruptores por entorno (D5). Migrarlas **quita esos interruptores**: es un cambio de comportamiento que decide la operadora (pregunta abierta Q1).
- Seis de las 7 se activan según el perfil de hooks (`profile_gate "security"` o `"standard"`, `.claude/hooks/lib/profile-gate.sh`). La regla conserva ese comportamiento con el campo `profile` (D2), que lee el despachador al elegir manejadores, no la regla al decidir. Y `validate-layer-contract` relativiza la ruta con la raíz del workspace: el alias `path_rel` (D2) lo cubre.

### Qué tomamos de hookify y qué no

Fuente: `anthropics/claude-plugins-official`, `plugins/hookify` (commit 30202c7, 2026-10-26). Licencia **Apache-2.0** (en la raíz del repo y en `plugins/hookify/LICENSE`). El encargo lo situaba en `anthropics/claude-code/plugins/hookify`: esa ruta da 404 y ese repo no declara licencia por la API; el plugin vive en `claude-plugins-official`. **No se copia código**: se toma la idea del formato. Si una fase llegara a adaptar código, llevaría el aviso de atribución de Apache-2.0.

| Aspecto | hookify | SE-520 |
|---|---|---|
| Fichero | `.claude/hookify.*.local.md`, local, sin versionar | `.claude/guard-rules/*.md`, versionado y revisado (D6) |
| Error de import, excepción, JSON malo | `exit 0` siempre (`hooks/pretooluse.py`: «ALWAYS exit 0 - never block operations due to hook errors») | exit 2 con motivo (D5) |
| Regex inválida | aviso por stderr y «no coincide» (`core/rule_engine.py`, `_regex_match`) | la regla no carga y el motor bloquea (D5) |
| Operador desconocido | «no coincide» | no carga (D5) |
| Fichero mal formado | se salta | no carga (D5) |
| Mayúsculas | `re.IGNORECASE` siempre, implícito | explícito por condición (`flags: [i]`) |
| Acciones | `warn`, `block` | `warn`, `block`. **No existe `allow`** (D2) |
| Casos de prueba | ninguno | obligatorios dentro de la regla (D4) |
| Quién crea reglas | un agente `conversation-analyzer` las propone y se activan al escribirse | un agente solo propone; entra por PR tier 3 (D6) |

## Lo que he entendido

### Escenas

1. Una worker intenta `terraform destroy` en un proyecto. Hoy la para `block-infra-destructive.sh`. Con esta spec la para la regla `infra-terraform-destroy`, con el mismo mensaje, y el registro de bloqueos de SE-510 dice qué regla fue. En OpenCode la para **la misma** regla, no un port.
2. Ves que los agentes pegan a veces un token de Slack en una orden. Escribes un fichero de veinte líneas con el patrón, dos ejemplos que deben bloquear y dos que no, y abres una PR. La revisas tú. No hace falta escribir un hook ni tocar `settings.json`.
3. Una worker en su worktree añade un `unless` a una regla para que su orden pase. La regla de `main` sigue aplicando: su copia local solo puede añadir bloqueos, nunca quitarlos.
4. Alguien deja una regla con una regex rota. El motor no la ignora: la CI falla en la PR y, si llegara a la máquina, el motor bloquea y dice qué fichero y qué línea fallan.
5. Un lunes, el registro de bloqueos enseña que una regla bloqueó tres órdenes legítimas. Savia te propone el cambio como borrador de PR con el par legítimo y el par peligroso; no lo aplica.

### Palabras de la persona

«reglas de guarda escritas en markdown (al estilo del plugin `hookify` de Anthropic), como ANEXO de SE-510 y no como hooks nuevos» — 2026-11-12, propuesta aprobada como idea por la operadora, transmitida en el encargo de la orquestadora.

### Qué SÍ será

- Un formato de regla en markdown con frontmatter, con sus casos de prueba dentro.
- Un único motor determinista, sin modelo, que corre como manejador del despachador de SE-510 y que usan los dos frontends.
- Una frontera clara de qué guardas pueden ser regla (clase T) y cuáles no.

### Qué NO será

- No sustituye las 28 guardas de clase N ni pretende hacerlo.
- No permite reglas que dejen pasar algo (`allow`): las exenciones siguen siendo el corpus de SE-510, tier 3.
- No activa reglas propuestas por un agente sin revisión humana.
- No se adelanta al despachador de SE-510: ninguna fase activa reglas antes de su slice correspondiente.

### Confirmación

- fecha: pendiente
- respuesta: pendiente. Las escenas no se han enseñado todavía a la operadora; se le preguntarán antes de pedir la aprobación (SE-505). No hay confirmación que citar.

## Slice S0 — Prototipo navegable

- prototipo: `docs/specs/assets/prototipo-SE-520.md` — tres reglas de ejemplo (una T migrada, una nueva de aviso, una con `unless` y sus pares), lo que ve la persona al bloquear, el error de carga de una regla rota, y la salida de `guard_rules.py test`.

### Confirmación del prototipo

- fecha: pendiente
- respuesta: pendiente.

## Qué decide esta spec

### D1 — Dónde viven las reglas

- `.claude/guard-rules/<id>.md`, una regla por fichero, versionadas. Sin variante `.local` dentro del repo.
- Reglas locales de una persona: `~/.savia/guard-rules/*.md`, fuera del repo. Por D2 solo pueden **añadir** bloqueos o avisos.
- `scripts/opencode-plugin/` y `.opencode/` no tienen copia: leen el mismo directorio (D7).

### D2 — Formato

```markdown
---
id: infra-terraform-destroy          # único, [a-z0-9-]+, igual al nombre del fichero
version: 1
event: PreToolUse                    # PreToolUse | PostToolUse (Fase 1-3)
tools: [Bash]                        # lista literal de nombres de herramienta
action: block                        # block | warn
class: POLITICA                      # POLITICA | FORMA (SE-475, absorbido por SE-510)
enabled: true
profile: security                    # como profile_gate hoy (opcional)
when:                                # todas deben cumplirse (Y)
  - field: tool_input.command
    op: regex
    pattern: 'terraform\s+destroy'
    flags: [i]
unless: []                           # opcional; si cualquiera se cumple, la regla no dispara
cases:
  block:
    - {tool: Bash, input: {command: "terraform destroy -auto-approve"}}
  allow:
    - {tool: Bash, input: {command: "terraform plan -destroy -out p.tfplan"}}
replaces: ".claude/hooks/block-infra-destructive.sh:32"   # solo durante la migración
---
Terraform destroy bloqueado: destruye infraestructura.
Usa `terraform plan -destroy` y pide la ejecución a una persona.
```

- **Campos de entrada** (`field`): `tool_name`, `cwd`, `hook_event_name`, `tool_input.<clave>` y tres alias normalizados que el motor define una vez: `text` (Write `content`, Edit `new_string`, MultiEdit todos los `edits[].new_string` unidos por salto de línea), `path` (`file_path` o `notebook_path`) y `path_rel` (`path` relativa a la raíz del repo, resuelta desde `cwd`; fuera del repo, la ruta absoluta normalizada). Nada más: ni entorno, ni ficheros, ni git, ni hora. Eso es lo que define la clase T.
- **Perfil** (`profile: minimal | standard | strict | security | ci`, opcional): el mismo significado que `profile_gate` hoy. Lo aplica el despachador al decidir qué reglas corren con el perfil activo (`/hook-profile`); no es un interruptor de la regla y no se puede fijar por regla desde el entorno. Sin el campo, la regla corre en todos los perfiles.
- **Operadores** (`op`): `regex` (búsqueda en cualquier punto del campo), `fullmatch` (el campo entero debe casar; es el que deben usar los `unless` sobre órdenes, pero solo si las clases negadas excluyen **todos** los metacaracteres de encadenado y sustitución: `;`, `&`, `|`, `<`, `>`, `$`, la comilla invertida, `\n` y `\r` (la «clase de separadores», `[^;&|<>$`\n\r]`). Una clase que solo excluya `;&|\n` deja pasar `$(…)`, las comillas invertidas y `<(…)`, y la orden peligrosa se ejecuta; el lint rechaza en un `unless` sobre `tool_input.command` cualquier `.`, `\S`, `\W` o clase negada que no excluya esos nueve caracteres), `contains`, `equals`, `prefix`, `suffix`, `in` (lista literal). No hay operadores negativos: la negación se escribe como `unless`, que es visible y exige su par (D4).
- **`unless` sobre `tool_input.command`**: solo con `op: fullmatch`. Con `regex` el lint lo rechaza, porque un `unless` que casa en cualquier punto de la orden se salta con `<allow>; <peligroso>`. Cuando exista `command.segments` (F4) se podrá relajar.
- **Gramática del frontmatter** (analizador propio, sin PyYAML): comentarios `# …` al final de línea o en línea propia; mapas y listas de bloque con sangría de 2 espacios; mapas de flujo `{a: 1, b: x}` y listas de flujo `[a, b]` (y `[]`) de **un nivel de anidamiento de flujo dentro de otro flujo** como máximo; cadenas simples `'…'` (sin escapes; `''` es una comilla) o dobles `"…"` (escapes `\\ \" \n \t`); enteros; `true`/`false`. Sin anclas, etiquetas, bloques `|`/`>` ni claves duplicadas (esto último → no carga). Los ejemplos de esta spec y del prototipo son la prueba de aceptación de la gramática (AC-2).
- **Semántica de regex, fija e independiente del motor**: el motor Python evalúa siempre con `re.ASCII` (`\s \w \b` solo ASCII, como JavaScript sin `u`), `re.search` para `regex` y `re.fullmatch` para `fullmatch`; las flags permitidas son solo `i` (y `s` para que `.` cruce saltos de línea). `^` y `$` quedan **prohibidos** en patrones: el inicio y el final se expresan con `fullmatch`, porque `$` casa antes de un `\n` final en Python y no en JavaScript. Con la opción B de D7 hay un solo motor; las restricciones de dialecto siguen para que una opción A futura no cambie veredictos.
- **Dialecto de regex común**: la intersección de Python `re` y JavaScript `RegExp`, comprobada por el lint al cargar. Prohibido: lookbehind, backreferences, grupos con nombre, flags en línea (`(?i)`), `\A` `\Z` `\z`, `^` y `$`, cuantificadores posesivos, clases POSIX (`[[:space:]]`). Contra backtracking: se rechazan (a) cuantificador sobre un grupo que ya contiene un cuantificador abierto (`(a+)+`, `(a*)*`, `(a|a)+`), (b) alternancia dentro de un grupo cuantificado cuando dos ramas pueden empezar igual, (c) más de **dos** cuantificadores no acotados (`*`, `+`, `{n,}`) en el mismo patrón sin un literal obligatorio entre ellos (`.*.*x` se rechaza), y (d) patrones de más de **256** caracteres. Es una regla conservadora (puede rechazar patrones inocuos); la defensa de fondo es el corte por tiempo del despachador (D5) y la prueba adversaria de D4. Las bash de hoy usan `grep -E` y `grep -P`, con semánticas distintas; migrar una regla exige comprobar la equivalencia con su corpus (D4), no traducir a ojo.
- **`action: warn` y su canal**: PreToolUse con exit 0 y texto en stderr **no** llega ni al modelo ni a la persona en Claude Code. El aviso sale por stdout como JSON `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"AVISO guard-rules:<id>: …"}}` con exit 0 (el mismo mecanismo que `project-isolation-gate.sh`); en OpenCode, el corredor TS lo convierte en el aviso que ya emite para sus guardas. Un test (AC-3b) comprueba que el aviso aparece en ese canal y que stderr no es el único destino.
- **Mayúsculas**: sensible por defecto; `flags: [i]` lo cambia por condición.
- **Mensaje**: el cuerpo markdown. Su primera línea es el `reason` del registro de bloqueos (SE-510 D2). Sin emojis.
- **Sin acción `allow`.** Una regla solo puede bloquear o avisar. Por eso el conjunto de reglas es monótono: añadir una regla nunca abre un hueco. Las exenciones siguen en `config/guard-allow-corpus.json` (SE-510 D1, tier 3).
- **Campos desconocidos** → la regla no carga (D5). El frontmatter se lee con un analizador estricto de un subconjunto de YAML (mapas, listas, cadenas, enteros, booleanos), sin PyYAML.

### D3 — Cómo se evalúa

- Motor único: `scripts/guard_rules.py` (Python estándar, sin dependencias). Subórdenes: `eval` (stdin JSON → veredicto), `lint` (valida todas las reglas), `test` (corre los `cases` de cada regla), `inventory` (Fase 1, AC-1).
- **Determinista y sin modelo**: misma entrada y mismas reglas, mismo veredicto. Orden de evaluación por `id`. Se evalúan todas las reglas aplicables; si alguna `block` dispara, exit 2 y se listan **todos** los mensajes de bloqueo; si solo disparan `warn`, exit 0 y los avisos por el canal de D2 (stdout JSON), no por stderr.
- **`eval` no ejecuta los `cases`.** En cada llamada el motor solo carga y valida la sintaxis de las reglas (lint estructural) y evalúa; los `cases` se ejecutan en `test`, en CI y en el pre-commit. Por eso entran en el presupuesto de 15 ms y por eso la fila «casos que no dan lo esperado» de D5 es un fallo de `test`/CI (exit 1), no de `eval`.
- **Conjunto efectivo = reglas de la base ∪ reglas locales.** La base es la versión versionada en la ref de base (por defecto `origin/main`; `git show origin/main:.claude/guard-rules/…`, con caché por el hash del árbol de ese directorio); las locales son la copia de trabajo y `~/.savia/guard-rules/`. Si un mismo `id` existe en las dos con contenido distinto, **se evalúan las dos versiones** y basta que una bloquee. Si el `id` existe en la base y falta en local (borrada) o está con `enabled: false` en local, la base sigue aplicando. Así un worktree puede probar una regla nueva, pero no puede debilitar una de `main` editando su copia (escena 3).
- **Relajar, desactivar o borrar una regla desde su propia PR.** La unión rige en la máquina (en `eval`). En `lint` y `test` ejecutados sobre una PR (CI y pre-commit), la base **excluye los `id` que esa PR modifica, desactiva o borra** (la lista sale de `git diff --name-only <merge-base>` sobre `.claude/guard-rules/`); esos `id` se juzgan solo con su versión nueva, con el `cases.allow` nuevo y el `cases.block` peligroso que exige D6, y por la revisión humana tier 3. Sin esa exclusión, ningún `unless` ni `enabled: false` sería probable. Consecuencia aceptada: mientras la PR no se fusiona, en el worktree de quien la propone sigue aplicando la versión de `main` (el agente de la escena 5 no ve su cambio efectivo hasta que la operadora fusiona); y el test «quitar la regla» (D4) se ejecuta con la regla aislada (ninguna otra regla ni versión de la base cuenta en ese test).
- **Ref de base configurable.** `config/guard-rules.yaml` (`base_ref`, por defecto `origin/main`; tier 3, como las reglas) permite clones sin remoto o con otro nombre de rama; no se lee de variables de entorno ni de la copia de trabajo: el valor efectivo sale de la propia ref de base (`git show <ref>:config/guard-rules.yaml`) o de `~/.savia/`, y la base efectiva es la unión de `origin/main` y la ref configurada, de modo que editar el fichero local no apunta la base a una rama sin reglas. Una caché verificada de la última base legible vive fuera del worktree (`~/.savia/cache/guard-rules-base/`, con el hash del árbol y la fecha) y se usa, marcada como «base en caché» en el motivo, cuando la ref no se puede leer. Sin ref legible **y** sin caché, rige el fallo cerrado de D5 con la salida de recuperación.
- **Modelo de amenaza, dicho con honestidad.** La base se lee de una ref local (`refs/remotes/origin/main`) y del propio `scripts/guard_rules.py`, ambos en la máquina. Quien tiene shell puede reescribirlos (`git update-ref`, `git fetch <otro-remoto> +main:refs/remotes/origin/main`, editar el motor). Esta spec protege contra **ediciones accidentales o ingenuas** de un agente o una persona; no es un límite de seguridad frente a un agente con shell y mala fe (eso lo cubren la revisión tier 3, la rama protegida y las gates de SE-510 fuera del worktree). Una mejora opcional, no exigida en F1: fijar la base a un hash de árbol que firme la operadora.
- **Dónde corre**: como manejador del despachador PreToolUse/PostToolUse de SE-510 (D3 de SE-510), en el grupo de bloqueantes baratos. Antes de que exista el despachador, el motor no se registra como hook suelto: solo corre en CI y en sombra (Fase 1).
- **Presupuesto**: p95 ≤ 15 ms de pared por llamada con 50 reglas, medido con el bench de SE-510 D4 (`scripts/hook-dispatch-bench.sh`). Si no llega, se añade un índice compilado con verificación de hash; nunca se quita una comprobación.

### D4 — Cómo se prueba

- **Casos dentro de la regla**: toda regla `block` trae al menos un `cases.block` y un `cases.allow`. Cada condición `unless` trae (a) un `cases.allow` que **casa con `when` y con ese `unless`** y que, al quitar el `unless`, pasaría a bloquear (el lint lo comprueba evaluando la regla sin él: un `allow` que no casa con `when` no ejerce nada y no vale); (b) un `cases.block` que es su variante mínima peligrosa (misma herramienta, misma orden base), como los pares de SE-510 D1; y (c) si el campo es `tool_input.command`, un `cases.block` encadenado por cada familia: `<orden del allow>; <orden peligrosa>` y `<orden del allow> $(<orden peligrosa>)` (las comillas invertidas se rechazan por la misma clase de separadores). Sin los tres, la regla no carga. Esto cierra el test que no puede fallar: el `allow` de un `unless` que nunca se evalúa.
- **Exportación al corpus de SE-510**: `guard_rules.py test --emit-corpus` vuelca los casos al formato de `config/guard-allow-corpus.json` / `config/kernel-corpus.json` (`id`, `event`, `tool`, `input`, `expect`), y los corre el runner existente (`scripts/ablation_units.py`); no se escribe otro runner. `--emit-corpus` escribe solo a stdout o a un fichero temporal, nunca al corpus versionado (lo actualiza una persona en una PR). Los casos ALLOW que entren en `guard-allow-corpus.json` siguen siendo tier 3.
- **Un test que puede fallar** (SE-456): para cada regla, el test la aísla (conjunto = solo esa regla, sin base ni otras reglas), la quita y comprueba que sus `cases.block` dejan de bloquear. Si no cambia nada, la regla o su caso no sirven. Aislar evita el falso fallo (otra regla bloquea el mismo caso) y el falso éxito (la copia de la base sigue bloqueando).
- **Equivalencia en la migración**: para cada hook T, el hook y su regla corren sobre la misma entrada (corpus de SE-510 + casos de la regla + el inventario de entradas reales del registro de bloqueos) y deben dar el mismo veredicto. Luego una semana en sombra en el despachador (SE-510 S3) con 0 discrepancias.
- **Rendimiento adversario**: el lint rechaza cuantificadores anidados y el test corre cada regex contra una entrada de 64 KiB construida para backtracking; si supera el tiempo, la regla no carga.

### D5 — Fallar cerrado

En PreToolUse, cualquiera de estas situaciones da **exit 2 con el motivo** (fichero, línea, regla) y nunca deja pasar la llamada:

| Situación | hookify hoy | SE-520 |
|---|---|---|
| Directorio de reglas ilegible, o la base no se puede leer **y** no hay caché verificada (`git` ausente, ref de base desconocida) | — | exit 2 (con salida de recuperación) |
| Base ilegible pero con caché verificada | — | se usa la caché y el motivo lo marca; no bloquea por sí sola |
| Frontmatter mal formado, campo desconocido, operador desconocido | se salta / no coincide | exit 2 |
| Regex inválida o fuera del dialecto común | no coincide | exit 2 |
| `id` duplicado o distinto del nombre de fichero | — | exit 2 |
| Regla `block` sin casos o `unless` sin sus tres casos (D4) | — | exit 2 |
| Casos que no dan lo esperado | — | exit 1 en `test`/CI; `eval` no ejecuta casos (D3) |
| JSON de entrada malformado, o campo declarado para esa herramienta que no es texto | exit 0 | exit 2 |
| Excepción del motor, tiempo agotado (lo corta el despachador) | exit 0 | exit 2 |
| `python3` ausente y `.claude/guard-rules/` o `~/.savia/guard-rules/` tienen algún `.md` | exit 0 | exit 2, incondicional: los lados bash y TS no parsean reglas para decidir si «aplica alguna» |

- Un error de carga bloquea **todas** las llamadas que el motor atiende, no solo las de la regla rota: no se puede saber qué habría hecho una regla que no se entiende. Por eso `lint` y `test` corren en CI y en el pre-commit, para que el error no llegue a la máquina.
- **Salida de recuperación.** Aunque la carga falle, el motor deja pasar solo: (a) `Edit`/`Write`/`MultiEdit` cuya ruta, **resuelta con `realpath`** (se rechazan `..` y los enlaces simbólicos que salen de la carpeta), está dentro de `.claude/guard-rules/` o `config/guard-rules.yaml`, o cuya ruta absoluta está dentro de `~/.savia/guard-rules/`; (b) la orden Bash que casa entera (`fullmatch`, sin separadores ni sustituciones) con `python3 scripts/guard_rules.py (lint|test|diagnose)( --?[a-z-]+)*`. `diagnose` no depende de git ni de la red: lista fichero, línea y motivo de cada fallo, e indica si la base viene de caché. Es una lista cerrada y literal en el motor; no la configura ninguna regla. Editar reglas en esa ruta sigue sujeto a tier 3 en PR; la excepción solo evita que un error de carga impida arreglarlo. El modo emergencia (SPEC-122) no cambia esto.
- PostToolUse no bloquea, pero el fallo se registra en el registro de bloqueos de SE-510 (D2) con `guard: guard-rules`.
- **Sin interruptores por entorno propios del motor.** No existe `SAVIA_GUARD_RULES=off` ni equivalente por regla. Excepción reconocida: el perfil de hooks (D2, `profile`) lo resuelve el despachador con `profile_gate`, que lee `SAVIA_HOOK_PROFILE` del entorno (`.claude/hooks/lib/profile-gate.sh`); con `SAVIA_HOOK_PROFILE=minimal` las reglas `profile: standard|strict|security` no corren, igual que sus hooks hoy. No es una regresión, pero sí una vía de apagado por entorno: las reglas que no deben poder apagarse se escriben **sin** campo `profile`, y la decisión de qué guardas pasan a regla con `profile` es parte de Q1. Desactivar una regla es `enabled: false` en una PR tier 3. El modo emergencia (SPEC-122) no lo cambia.
- La entrada llega por stdin (JSON). El motor no lee variables de entorno para decidir.

### D6 — Quién puede añadir, cambiar o quitar reglas

- **Toda** modificación en `.claude/guard-rules/` es **tier 3** (revisión humana explícita del PR concreto, SE-362), también las reglas `warn` y también desactivar o borrar. Se añade el prefijo a `scripts/risk-tier.py` (junto a `TIER_3_EXACT`) y a `.github/CODEOWNERS`, igual que `config/guard-allow-corpus.json`. Lo mismo para el motor y su configuración: `scripts/guard_rules.py`, `config/guard-rules.yaml` y el inventario de F1 son tier 3, porque debilitar el motor debilita todas las reglas. Los cambios en `.opencode/` (el corredor TS de D7) ya son gobernanza tier 4 (`GOVERNANCE_PREFIXES` en `scripts/risk-tier.py`); F1 y F3 lo asumen y no intentan rebajarlo.
- **Un agente nunca activa una regla.** Puede proponerla, a partir del registro de bloqueos o de una conversación (la idea del `conversation-analyzer` de hookify), como borrador de PR en una rama `agent/*` con sus casos y pares. Hasta que la operadora fusiona la PR, la regla solo existe en su worktree; por D3, ahí solo puede añadir bloqueos, nunca quitarlos de `main`.
- Reglas locales en `~/.savia/guard-rules/`: las escribe la persona, no un agente; por D2 solo restringen.
- `lint` rechaza una regla cuyo cambio quita o relaja una condición respecto a la base si la PR no lleva el par peligroso nuevo en `cases.block` (evita «exenciones por goteo», el mismo riesgo que SE-510 D1 corta en el corpus).

### D7 — Paridad Claude Code / OpenCode

Lección de PR #1237 y #1238: dos implementaciones de la misma guarda divergen. Opciones:

- **A. Port nativo en TS del motor**, como `dome-guard` (`.claude/hooks/dome-guard.sh` con núcleo en `lib/dome_guard.py`, y `scripts/opencode-plugin/savia-gates/lib/dome-guard.ts` como port, con `tests/hooks/test-dome-guard-parity.bats`). Rápido en OpenCode, pero dos motores que mantener y dos dialectos de regex.
- **B. Un solo motor**: el corredor TS de OpenCode (`.opencode/plugins/savia-foundation.ts`, `runGuardsOnVariants`) llama al mismo `scripts/guard_rules.py eval` una vez por evento, con la misma entrada por stdin. Paridad por construcción; coste de un proceso Python por evento en OpenCode.

**Recomendación: B** en las Fases 1–3. A solo si B no cumple el presupuesto de D3 en OpenCode, y entonces con el corpus de D4 como puerta: un veredicto distinto entre motores rompe la CI (amplía `scripts/opencode-parity-audit.sh` de SE-510 D3.5). En cualquier caso el dialecto común de D2 se impone desde el principio, para que un port futuro no herede incompatibilidades.

- Las guardas TS actuales que corresponden a reglas T (`block-credential-leak.ts`, `block-infra-destructive.ts`) se sustituyen por la llamada al motor en la misma PR que la regla, no después.
- La paridad se mide sobre los mismos casos: el test de D4 corre por la ruta bash del despachador y por la ruta TS con la misma entrada.

### D8 — Migración por fases

Ninguna fase arranca antes de la slice de SE-510 de la que depende.

| Fase | Depende de | Qué hace | Qué NO hace |
|---|---|---|---|
| F0 | — | Esta spec, inventario y prototipo | Nada ejecutable |
| F1 | SE-510 S1 (corpus) | `guard_rules.py` con `eval`, `lint`, `test`, `inventory`; tier 3 en `risk-tier.py` y CODEOWNERS; fichero de inventario T/P/N comprobado por test; **una** regla piloto (`infra-terraform-destroy`) que corre solo en CI contra el corpus, al lado del hook | No registra nada en `settings.json` ni en el corredor TS |
| F2 | SE-510 S3 (despachador en sombra) | El motor entra como manejador del despachador en sombra; las 7 reglas T escritas con sus casos; equivalencia hook ↔ regla sobre el corpus; una semana de sombra con 0 discrepancias | No quita ningún hook |
| F3 | SE-510 S4 (sustitución) y respuesta a Q1 | Las 7 reglas T sustituyen sus registros bash y sus guards TS; los ficheros de hook se borran una versión después | No toca P ni N |
| F4 | F3 estable un mes | Opcional y medida: alias `command.segments` (tokenizador único con su propio corpus) para la parte de patrón de las 8 P; reglas `warn` nuevas para patrones de código inseguro en Edit/Write, cada una justificada por la escalera de remedios | Nunca las 28 N |

- **Escalera de remedios.** Propuesta para F1 (no se edita la regla ahora): en `remedy-ladder.md`, el escalón 4 distingue «4a. Regla de guarda en texto» de «4b. Hook». Una guarda nueva de clase T tiene que ser regla; un hook nuevo explica en su PR por qué no basta una regla.

## Criterios de aceptación (para F1–F3)

| AC | Criterio | Tipo |
|---|---|---|
| AC-1 | `guard_rules.py inventory` clasifica los hooks bloqueantes registrados en T/P/N contra un fichero de inventario versionado; un hook bloqueante nuevo sin clasificar hace fallar el test. | negativo |
| AC-2 | `lint` rechaza: campo desconocido, operador desconocido, regex inválida, regex fuera del dialecto (cada prohibición de D2, un caso), `id` duplicado, regla `block` sin casos, `unless` sin sus tres casos de D4 (incluido: un `allow` que no casa con `when` o que sigue pasando al quitar el `unless`; un `unless` sobre `tool_input.command` con `op: regex`; falta del `block` encadenado), `^`/`$` en un patrón. La gramática de D2 acepta todas las reglas de ejemplo de esta spec y del prototipo. Cada rechazo es un caso de test. | negativo |
| AC-3 | `eval` con cada situación de la tabla de D5 da exit 2 con el motivo; ninguna deja pasar la llamada. `python3` ausente con reglas presentes → exit 2 sin parsear. | negativo |
| AC-3b | `action: warn` deja el aviso en el JSON `additionalContext` por stdout con exit 0 (Claude Code) y en el aviso del corredor TS (OpenCode); un test falla si el único destino es stderr. | positivo / negativo |
| AC-3c | Salida de recuperación: con una regla rota, un Edit sobre `.claude/guard-rules/` y `python3 scripts/guard_rules.py diagnose` pasan; `diagnose && rm x`, un Bash cualquiera y un Edit fuera de esas rutas siguen en exit 2. Con la ref de base ilegible y caché, no bloquea; sin caché, bloquea salvo recuperación. | positivo / negativo |
| AC-4 | Una regla con una regex de backtracking (`(a+)+`, `(a*)*`, `(a\|a)+`, `.*.*x`, o de más de 256 caracteres) no carga; el test acaba en menos de 2 s. | negativo / límite |
| AC-5 | Conjunto efectivo: en la máquina, una copia local que añade `unless`, pone `enabled: false` o borra una regla de la base no evita el bloqueo del caso que la base bloquea; una regla local nueva sí bloquea; editar `base_ref` en la copia local no cambia la base efectiva; un `unless` con `$(…)` o comillas invertidas no deja pasar la orden peligrosa. En `lint`/`test` de una PR, los `id` que la PR modifica se juzgan sin la base: una PR que añade un `unless` con su par pasa CI. | negativo / positivo |
| AC-6 | Con la regla aislada, quitarla hace que sus `cases.block` dejen de bloquear, y quitar un `unless` hace que su `allow` pase a bloquear (los tests pueden fallar). | negativo |
| AC-7 | Paridad: para todos los casos de las reglas y del corpus de SE-510, veredicto por la ruta bash = veredicto por la ruta TS; una mutación en un lado hace fallar el auditor. | negativo |
| AC-8 | Equivalencia: cada hook T y su regla dan el mismo veredicto sobre el mismo corpus; una semana de sombra con 0 discrepancias antes de F3. | positivo / negativo |
| AC-9 | `.claude/guard-rules/`, `scripts/guard_rules.py` y `config/guard-rules.yaml` son tier 3 en `risk-tier.py` y en CODEOWNERS; un cambio solo en una regla `warn` también sale tier 3; un cambio en `.opencode/` sigue siendo tier 4. | negativo |
| AC-10 | Presupuesto: p95 ≤ 15 ms con 50 reglas, medido con el bench de SE-510, cifras antes y después en el body de la PR. | positivo |
| AC-11 | El motor no lee variables de entorno en la decisión: un test recorre `scripts/guard_rules.py` buscando lecturas de entorno. La única lectura de entorno es `SAVIA_HOOK_PROFILE` en el despachador (`profile_gate`): una regla `profile: strict` no corre con perfil `standard` y sí con `strict`, y una regla **sin** `profile` corre con `SAVIA_HOOK_PROFILE=minimal` (no se puede apagar por entorno). | negativo / positivo |

## Fuera de alcance

- Las guardas de clase N y la parte de estado de las P.
- Eventos distintos de PreToolUse y PostToolUse (Stop, UserPromptSubmit…), como en SE-510.
- Reglas que eximen (`allow`): eso es el corpus de SE-510.
- Activación automática de reglas propuestas por agentes.
- Copiar código de hookify.

## Preguntas abiertas para la operadora

- **Q1.** Migrar las 7 T quita interruptores por entorno que hoy existen (`SAVIA_PAT_BLOCK=off`, `SAVIA_VERIFIED_MEMORY_DISABLED=true`). ¿Se aceptan sin interruptor (recomendado: desactivar sería `enabled: false` por PR tier 3), o esas dos se quedan como hook?
- **Q2.** Reglas locales en `~/.savia/guard-rules/`: ¿se permiten (solo restringen) o solo cuentan las versionadas? Recomendación: permitirlas; es útil para un operador con requisitos propios y no abre huecos.

## Riesgos

- **Un error de carga bloquea todo.** Mitigación: `lint` y `test` en CI y pre-commit; mensaje con fichero y línea; la Fase 1 no registra nada en vivo; salida de recuperación literal y `diagnose` (D5); caché de la base para no depender de la red.
- **La base local no es un límite de seguridad frente a un agente con shell** (D3, modelo de amenaza). Mitigación: revisión tier 3, rama protegida; fijar la base por hash firmado queda como mejora opcional.
- **Regex de cara al exterior con backtracking.** Mitigación: dialecto sin cuantificadores anidados, test adversario y tiempo por manejador del despachador.
- **Exenciones por goteo vía `unless`.** Mitigación: par peligroso obligatorio, tier 3 y comparación con la base en el lint (D6).
- **Más dependencia de `python3` en OpenCode.** Mitigación: el doctor lo comprueba; sin él, fallo cerrado explícito, no silencio.
- **Vender más de lo que es.** Son 7 guardas de 43. La PR de F3 enseña la cifra real de procesos ahorrados, no una estimación.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Reglas | `.claude/guard-rules/*.md` | El mismo directorio, sin copia |
| Motor | `scripts/guard_rules.py eval` como manejador de `hooks/dispatchers/dispatch-pretooluse.sh` / `dispatch-posttooluse.sh` (SE-510 D3) | El corredor de `.opencode/plugins/savia-foundation.ts` (`runGuardsOnVariants`) llama al mismo `guard_rules.py eval` por stdin (D7, opción B) |
| Guards sustituidos (F3) | `block-credential-leak.sh`, `block-infra-destructive.sh`, `android-adb-validate.sh`, `block-pat-file-write.sh`, `memory-verified-gate.sh`, `validate-layer-contract.sh`, `agent-tool-call-validate.sh` | `.opencode/plugins/guards/block-credential-leak.ts`, `block-infra-destructive.ts` salen de `BEFORE_GUARDS`; las otras cinco no tienen port TS hoy y quedan cubiertas por primera vez |
| Registro de bloqueos | `output/guard-blocks.jsonl` (SE-510 D2), `guard: guard-rules:<id>` | El mismo |
| Tier y propietarios | `scripts/risk-tier.py`, `.github/CODEOWNERS` | Igual (no depende del frontend) |

### Verification protocol

- [ ] Funciona en runtime OpenCode: los casos de todas las reglas corren por el corredor TS
- [ ] Tests BATS y pytest cubren cada regla, su par y cada fila de D5
- [ ] Hooks nuevos o cambiados registrados en el plugin `savia-gates` (el motor entra por el despachador; ningún hook suelto nuevo)

### Portability classification

- [x] **DUAL_BINDING**: un solo motor y un solo directorio de reglas para los dos frontends; la paridad se comprueba con la misma entrada (AC-7).

## Apéndice A — Órdenes de medida

- **A1** (registros): `python3` que carga `.claude/settings.json` y cuenta `g['hooks']` por evento → 134 registros en 17 eventos (57 PreToolUse, 39 PostToolUse); `ls .claude/hooks/*.sh | wc -l` → 126.
- **A2** (bloqueantes): para cada `.claude/hooks/*.sh`, `grep -qE 'exit 2|permissionDecision.{0,6}deny|"decision": *"block"'` → 41 ficheros; más `scripts/operator-grant.sh guard` y el hook `prompt` de `git commit`, registrados en PreToolUse → 43.
- **A3** (clase): para cada uno de los 43, `grep -n -B4 -E 'exit 2|deny'` y lectura de la condición; dependencia de estado buscada con `git (status|diff|rev-parse|branch|log|ls-files|symbolic-ref)`, `stat -c|find .*-mmin|date +%s`, rutas de estado, variables de entorno en la condición y llamadas a modelo. La Fase 1 sustituye esta lectura manual por `guard_rules.py inventory` y su fichero versionado (AC-1).

## Aprobación

Pendiente. La operadora aprobó la **idea** el 2026-11-12; esta spec está en PROPOSED hasta que confirme las escenas y responda Q1 y Q2.
