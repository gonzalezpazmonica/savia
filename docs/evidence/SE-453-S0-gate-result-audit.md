# SE-453 S0 — Auditoría del resultado de los gates

> Medido sobre `origin/main` (bf186922f) el 2026-10-20, leyendo cada script. Las tres columnas responden
> a las preguntas de la spec: vocabulario de códigos, qué hace si falta una dependencia, qué hace si supera un tope o timeout.
> «Estado tras SE-453» indica qué cubren S1 a S3. «Por demanda» = hueco conocido, fuera del primer lote.

## Escáneres

| Script | Vocabulario de códigos | Dependencia ausente | Tope o timeout | Estado tras SE-453 |
|---|---|---|---|---|
| `scripts/git-history-secret-scan.sh` | 0 limpio, 1 CRITICAL/HIGH, 2 MEDIUM/LOW, 3 `output/` sin ignorar, 4 fallo | gitleaks ausente salía **1** (igual que un hallazgo crítico) | sin tope ni timeout: historial enorme sin límite | Ausente → 4 + `unknown/missing_tool`; `GIT_HISTORY_SCAN_MAX_COMMITS` y `GIT_HISTORY_SCAN_TIMEOUT` → `unknown/limit` y `unknown/timeout` |
| `scripts/pre-push-security-gate.sh` | 0 limpio u omitido, 1 hallazgos | gitleaks ausente: **exit 0** con aviso «push continúa sin escaneo» | sin tope | Ausente → `unknown/missing_tool`, línea en `output/unmeasured-gates.jsonl`; `SAVIA_GATE_UNKNOWN=block` lo bloquea (D3: un ciclo de aviso) |
| `scripts/dependency-scan.sh` | 0 limpio, 1 hallazgos, 2 error | Trivy/Docker/jq ausentes → 2 (correcto en código, sin vocabulario de resultado) | sin timeout propio; Trivy rc 124 caía en «fallido» | Línea `gate-result` en todas las salidas; 2 = `unknown` con `missing_tool`, `unreadable` o `timeout` |
| `scripts/iac-security-scan.sh` | 0 limpio o NO_IAC, 1 hallazgos, 2 error | Trivy y Docker ausentes → `die` 2 | `find -maxdepth 5` solo para etiquetar tipos; Trivy escanea el árbol entero | S3 por demanda (2026-10-24): `gate-result` en tabla, `result`/`gaps` en el report JSON; Trivy fallido ⇒ `trivy-<modo>:unreadable`, rc 124 ⇒ `timeout`, sin Trivy ⇒ `missing_tool`. #1355: hallazgos en una parte y hueco en la otra ⇒ 1/`findings` con el hueco dentro; en `--format json` un exit 2 deja en stdout `{"result":"unknown",…}` en vez de nada |
| `scripts/ast-quality-gate.sh` | 0 limpio, 1 fallo, 2 entorno, 3 UNVERIFIED con `meta.coverage` | Capa que no corre = `missing/failed/unsupported`, baja cobertura | `find -maxdepth 3` para detectar lenguajes | Es el modelo interno del contrato; sin cambios |
| `scripts/mobile-security-scan.sh` | 0 con informe, 1 argumentos | MobSF y Docker ausentes → análisis básico (apktool + grep) sin marcar cobertura reducida | `curl --max-time 3` al detectar MobSF | S3 por demanda (2026-10-24): `gate-result` + `result`/`gaps` en el JSON; sin apktool, descompilación vacía, `dynamic` o MobSF sin triaje ⇒ `unknown` |
| `scripts/prompt-security-scan.sh` | 0 limpio, 1 hallazgos, 2 error (ruta) | python3 ausente solo omite una comprobación (línea 98) sin registrarlo | sin tope | S3 por demanda (2026-10-24): `PS-11:missing_tool`, fichero ilegible y path sin `.md` ⇒ `unknown` registrado; path del fichero por argv. #1355: PS-11 sin python3 (bytes UTF-8 con `grep` en locale C; también U+2060, U+00AD y bidi), `grep -a` con NUL, error de lectura que `-r` no ve y `find` fallido ⇒ `unknown`; la línea final sale también con `--quiet` |
| `scripts/confidentiality-scan.sh` | 0 limpio, 1 violaciones, 2 error | sin herramienta externa; un diff que git no calcula (sin `origin/main`) salía «No content to scan» y 0; Check 4 nunca veía ficheros | sin tope | S3 por demanda (2026-10-24): `git-diff:unreadable` y blocklist ilegible ⇒ `unknown` registrado; Check 4 lista ficheros con `--name-only`, también sin líneas añadidas y sin exclusiones de contenido |
| `scripts/security-scan.sh` | 0 siempre salvo `--ci` con hallazgos (1) | grep/find estándar | sin tope | S3 por demanda (2026-10-24): `gate-result`; grep con rc ≥ 2 o sin hooks ⇒ `unknown`; códigos sin cambio |
| `scripts/vuln-scan.sh` | 0 siempre salvo `--ci` con vulnerabilidades (1) | grep estándar | sin tope | S3 por demanda (2026-10-24): igual que `security-scan.sh` |
| `scripts/mcp-security-audit.sh` | 0 limpio, 1 hallazgos, 2 argumentos | python3 ausente: salía 1 con un falso MCP-00 «Invalid JSON» | sin tope | S3 por demanda (2026-10-24): python3 ausente ⇒ exit 2 `unknown/missing_tool`; `--config` inexistente o ninguna config ⇒ `unknown`; path por argv |
| `scripts/security-audit-all.sh` | 0 / 1 según `--fail-on`, 2 argumentos | un sub-escáner que salía 1 añadía `{}` a su JSON: el parseo fallaba y sus hallazgos contaban 0 | sin tope | S3 por demanda (2026-10-24): lee el JSON aunque salga 1; exit ≥ 2, ilegible o `unknown` ⇒ hueco propagado. SE-453 parte 2 (#1348): cuentas obligatorias y enteras (un booleano o una clave ausente es ilegible), `findings_count` > 0 sin cuentas o exit 1 sin cuentas ⇒ hueco, y `prompt-security-scan` ausente ⇒ `missing_tool` en vez de omitido |
| `scripts/transcriptor-scan.sh` | 0 limpio u omitido, 1 error | python3 ausente → 1 | sin tope | Fuera del contrato: lista reuniones por stdout, no es un gate |

## Guards y hooks `blocking: true`

| Hook | Vocabulario de códigos | Dependencia ausente (`jq`) | Tope o timeout | Estado tras SE-453 |
|---|---|---|---|---|
| `block-credential-leak.sh` | 0 o 2 | **exit 0** con aviso solo en stderr (reproducido el 2026-10-20) | `timeout 3` al leer stdin | Degrada a `grep`; si no puede evaluar, 2 |
| `block-force-push.sh` | 0 o 2 | exit 0 sin `jq` (lectura) | `timeout 3` al leer stdin | Degrada a `grep`; si no puede evaluar, 2 |
| `block-infra-destructive.sh` | 0 o 2 | degradaba a `grep` con `[^"]*` (cortaba en una comilla escapada y salía 0) | `timeout 3` al leer stdin | Usa la misma extracción tolerante a comillas escapadas |
| `agent-git-discipline.sh` | 0 o 2 | sin `jq` el comando quedaba vacío y salía 0 | `timeout 3` al leer stdin | Degrada a `grep`; si no puede evaluar, 2 |
| `validate-bash-global.sh` | 0 o 2 | sin `jq` el comando quedaba vacío y salía 0 | `timeout 3` al leer stdin | Degrada a `grep`; si no puede evaluar, 2 |
| `android-adb-validate.sh` | 0 o 2 | no usa `jq` (lee `TOOL_INPUT`) | sin tope | Sin cambios |
| `data-sovereignty-gate.sh` (excluido de `blocking`) | 0 o 2 | `jq` ausente: `\|\| exit 0` (fallo abierto) | `curl --max-time 2` y `10` al shield; si falla, sigue por el clasificador local | Fuera de S2 (no marcado). Parche preparado (2026-10-24, extracción con `grep` + no medido + sin override N3/N4 a ciegas); pendiente de aplicar: edición de `.claude/hooks/` requiere permiso de la operadora |

## Hooks no marcados que salen 0 sin `jq`

| Hook | Vocabulario de códigos | Dependencia ausente | Tope o timeout | Estado tras SE-453 |
|---|---|---|---|---|
| `acm-turn-marker`, `acm-enforcement`, `block-sensitive-tracking`, `block-gitignored-references` | 0 o 2 | exit 0 sin `jq` | — | Sale 0 y añade línea a `output/unmeasured-gates.jsonl` |
| `config-snapshot-hook`, `context-greedy-inject`, `propuestas-index-refresh`, `twin-posttooluse` | 0 | exit 0 sin `jq` | — | Igual |
| `sycophancy-strip`, `vault-frontmatter-gate` | 0 o 2 | exit 0 sin `jq` | — | Igual |
| Resto de los 31 que citan `command -v jq` (p. ej. `tdd-gate`, `contract-test-guard`) | 0 o 2 | degradan o no son de seguridad | — | Por demanda |

## Paridad OpenCode de los guards `blocking` (DUAL_BINDING, 2026-10-23)

`savia-gates` ejecuta los mismos `.sh` por su shell-bridge: paridad por construcción, también sin `jq`.
Los puertos nativos de `.opencode/plugins/guards/` no usan `jq` (caso «sin jq» no aplicable en TS) y se
compararon con el hook bash con las mismas entradas:

| Guard | Entradas | Divergencias halladas | Estado |
|---|---|---|---|
| `block-force-push.ts` | 11 | `git -C dir push --force` y `git commit --amend` pasaban en TS (bash 2, TS 0); `git push origin main-fix` bloqueaba en TS | Corregido: mismo ancla `GIT_AT` que el hook. Revisión de #1348: el primer ancla dejaba pasar en TS la orden en la línea 2 de un bloque (sin flag `m`) y, en ambos bindings, `bash -c "…"`, `sh -c`, `eval`, `then`, `{`, `xargs` y un `--force` junto a un `--force-with-lease`; corregido en bash y TS con casos de paridad. Sigue sin cubrirse una orden git construida en tiempo de ejecución (variables, alias) |
| `block-credential-leak.ts` | 4 | ninguna | Sin cambios |
| `block-infra-destructive.ts` | 4 | ninguna | Sin cambios |
| `validate-bash-global.ts` | 2 | ninguna | Sin cambios |

Falso positivo compartido y aceptado (bash y TS, mismo patrón): `commit\s+.*--amend` bloquea cualquier `git commit`
que mencione `--amend`, también en el mensaje (`git commit -m "explica --amend"`). #1355 intentó afinarlo con un
tokenizador y se retiró (decisión 2026-10-28): en 8 rondas de revisión cada versión dejaba pasar algún amend real
que esta regex sí bloquea.

Reglas solo-TS que siguen siendo más estrictas que el hook (no se tocan): `git checkout --force`,
`git rebase origin/main` y `git push --delete origin main`.

## Conclusiones para S1 a S3

1. Los tres vocabularios de la spec se confirman; además `security-scan.sh` y `vuln-scan.sh` solo fallan con `--ci`.
2. Exposición real de herramienta ausente: `pre-push-security-gate.sh` (sale 0) y los cinco guards `blocking` sin `jq`.
3. Topes reales: ninguno de los escáneres tenía tope propio que ocultara hallazgos; los dos que sí
   cortaban (`find -maxdepth`) solo etiquetan. El riesgo es el historial sin límite de
   `git-history-secret-scan.sh`, que ahora lleva tope y timeout explícitos y los registra como hueco.
