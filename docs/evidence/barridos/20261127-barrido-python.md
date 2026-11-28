# Barrido de seguridad por clase: Python (2026-11-27)

Rama `agent/fix-20261127-barrido-python`. Alcance: `scripts/`, `.claude/hooks/`, `.opencode/`, `projects/*/scripts`, `zeroclaw/`. Quedan fuera `tests/fixtures` y el código de terceros.

## Clase

- `subprocess` con `shell=True` o con `bash -c`/`sh -c` sobre una cadena;
- `os.system`, `os.popen`, `eval`, `exec`;
- `pickle` y `yaml.load` sin SafeLoader;
- uniones de rutas con entrada externa sin `realpath` ni comprobación de contención.

Durante el barrido apareció una subclase con más casos reales: **datos interpolados dentro del código de `python3 -c "..."` desde bash**. Es un `exec` de Python con texto ajeno dentro.

## Método

1. `grep` de los patrones sobre los 355 `.py` versionados y los 1342 ficheros de shell del alcance. Después, lectura de cada candidato.
2. Para cada candidato, de dónde viene la entrada: argumento, fichero, JSON de un hook, salida de modelo o red.
3. Reproducción con un centinela inocuo (crear un fichero en `$BATS_TEST_TMPDIR`) en un test bats que falla antes del arreglo.
4. Arreglo y test en verde, agrupados por script.

## Resultado

| # | Candidato | Ruta:línea | Origen de la entrada | Veredicto |
|---|-----------|------------|----------------------|-----------|
| 1 | `float('$risk_score')` y `float('$RISK_GATE_THRESHOLD')` dentro de `python3 -c` (G3) | `scripts/pre-tribunal-gates.sh:132` (ahora 133) | `--context` JSON; `json_field` admite `'` y `(`; también la variable de entorno del umbral | **Real, reproducido y arreglado**: `0')*0+0*len(str(__import__('pathlib').Path('<centinela>').touch()))+float('0` creaba el fichero. Ahora pasa por argv |
| 2 | `open('${surface_file}')` dentro de `python3 -c` (`list`) | `scripts/agent-surface-guard.sh:225-226` | Nombre de directorio bajo `.evo/`, que crea `declare --run-id` (argumento sin validar) | **Real, reproducido y arreglado**: un run con `x'+str(__import__('pathlib').Path('pwned-list').touch())+'` ejecutaba código al listar. Ahora pasa por argv |
| 3 | `os.path.join(state_dir, f"{args.session}.json")` en modo post | `scripts/repeat-tool-guard.py:205` (ahora 206) | `--session` (el hook le pasa `CLAUDE_SESSION_ID`) | **Real, reproducido y arreglado**: `../x` y una ruta absoluta escribían el estado fuera de `--state-dir`. El modo pre ya usaba `safe_name`; ahora lo usan los dos |
| 4 | `LOG_DIR / f"{session_id}.jsonl"` | `scripts/cross-turn-correlation/track.py:74` | `--session` (CLI) | **Real, reproducido y arreglado**: `../../../escapado` creaba `escapado.jsonl` fuera de `output/cross-turn`. Ahora se valida con `[A-Za-z0-9_-]{1,128}` en `_log_path` y en la CLI. Hoy no lo llama ningún hook |
| 5 | `subprocess.run(action, shell=True)` | `zeroclaw/host/consciousness.py:72` | `DEFAULT_SCHEDULE` o `~/.savia/zeroclaw/schedule.json`, configuración de la persona (`save_schedule` no tiene llamadas) | Constante (configuración propia, como un crontab) |
| 6 | `_shell_task(cmd, shell=True)` | `zeroclaw/host/saviaclaw_headless.py:318` | Solo `SCHEDULE` literal; los `/cron add` de Talk van a `opencode run` con lista argv | Constante |
| 7 | `os.system("systemctl restart …")` | `zeroclaw/host/saviaclaw_headless.py:274` | Literal | Constante |
| 8 | `subprocess.run("cd ~/claude && git log …", shell=True)` | `zeroclaw/host/saviaclaw_acp.py:88-89` | Literal | Constante |
| 9 | `shell=True` con lista literal (Windows) | `zeroclaw/host/network_setup.py:39,72`; `scripts/web-research/searxng.py:14-19` | Literales (`netsh`, `ipconfig`, `docker compose`) | Constante |
| 10 | `os.popen("git rev-parse HEAD")` | `scripts/guardrail-inventory-parse.py:779` | Literal | Constante |
| 11 | `["bash","-c", hook["command"]]` | `scripts/ablation_kernel.py:229`; `scripts/dual-cli/gates.py:87,93` | Comandos de hooks de `settings.json`: ejecutarlos es la función del script; el payload va por stdin | Constante (por diseño) |
| 12 | `["bash","-c", executor]` | `scripts/evals-paired-delta.py:125` | Ejecutor que da la operadora; la fila va por stdin | Constante (por diseño) |
| 13 | `exec(_SRC_PATH.read_text())` | `scripts/memory-two-speed.test.py:16` | Fichero del propio repo | Constante |
| 14 | `def eval(self, js)` (CDP) | `scripts/extract-teams-transcripts.py:64` | No es el `eval` de Python | Falso positivo |
| 15 | `yaml.load(..., Loader=_UniqueLoader / DupKeyLoader)` | `scripts/harness_ficha.py:155`; `scripts/validate-agent-catalog.py:100,237`; `scripts/dual-cli/codex_executor.py:82` | Los cargadores heredan de `yaml.SafeLoader` | Falso positivo |
| 16 | Literales `pickle.loads`, `os.system`, `shell=True` en textos de remediación | `scripts/security-remediation-generator.py:135-159`; `scripts/tabular-profile.py:527` | Cadenas y comentarios | Falso positivo |
| 17 | `json.loads('''$RESULT''')` en el respaldo sin jq | `.claude/hooks/context-sanitize-input.sh:100-101` (y su copia `.opencode/hooks/`) | `RESULT` incluye `original` = contenido del `Write` | Falso positivo hoy, porque es inalcanzable: sin jq, `TEXT` queda vacío y el hook sale en la línea 80. Patrón frágil: si alguien añade una extracción sin jq, se vuelve real |
| 18 | `json.loads('$CLASSIFICATION')` (modo enforce) | `.claude/hooks/router-mode-dispatch.sh:76` | Salida de `router-mode-classifier.py`; `command` solo aparece en `reason` si está en la lista permitida o tiene fichero de comando | Real sin reproducir: no encontré un camino que meta `'`. Conviene pasarlo por stdin |
| 19 | `float('$CONF')` | `scripts/classifier-corpus-run.sh:85` | `confidence` de la salida del clasificador (modelo) sobre un corpus fijo | Real sin reproducir: el modelo es una fuente externa, pero solo ve textos fijos del corpus |
| 20 | `float('$sim')` | `scripts/learning-reconcile.sh:107,141` | Salida numérica de la función `similarity` local | Constante (valor calculado) |
| 21 | `open('$f')`, `open('$DEPS_FILE')`, `open('$CANDIDATE')`, `sqlite3.connect('$KG_DB')`… | `scripts/ci-select-bats.sh`, `corporate-adopt.sh`, `corporate-monotonicity-gate.sh`, `context-erosion-detect.sh`, `kg-export.sh`, `kg-query.sh`, `memory-check.sh`, `lib/enterprise-helpers.sh`, `opencode-config-validate.sh`, `permissions-wildcard-audit.sh`, `pr-plan-gates.sh`, `rule-manifest-generate.sh`, `federation-discover.sh`, `ensure-daemons-auth.sh`, `projects/savia-vaults/scripts/vaults:663,674` | Rutas de constantes del repo o de argumentos de la operadora; `ensure-daemons-auth.sh` interpola `$1` = alias de un bucle literal | Constante en su mayoría. Real sin reproducir si una ruta de argumento lleva `'`; mismo arreglo (argv) si se quiere cerrar la familia |
| 22 | `os.path.join(pdir, f"{pid}.request.json")` | `scripts/merge-sprint-policy.py:759` | `id` del fichero de política | Falso positivo: `request` valida (`nuevo_artefacto → validar`, `RE_ID`) antes de escribir; `verify` solo lee y `verificar` rechaza la política |
| 23 | `os.path.join(root, session_id)` | `.claude/hooks/lib/dome_guard.py:1369` | `session_id` del hook | Falso positivo: `SESSION_ID_RE.fullmatch` antes, `O_NOFOLLOW` |
| 24 | `os.path.join(..., cap["id"])`, `contract["id"]` | `scripts/lib/authority_kernel.py:536,864,1179` | Contrato | Falso positivo: `ID_RE` antes |
| 25 | `_contain_path`, `_project_dir` | `scripts/savia-bridge.py:931-957` | Red (HTTP) | Falso positivo: `realpath` en los dos lados y prefijo con separador |
| 26 | `(base / item["source"]).resolve()` | `scripts/grc-audit.py:66` | Fichero de evaluación | Falso positivo: `is_relative_to(base)` |
| 27 | `log_dir/"%s-%s.md" % (sid, status)` | `scripts/planning-view.py:385` | `--id` | Falso positivo: `ID_RE` en `_check_id_status` |
| 28 | `os.path.join(vault, cat, r["id"])` | `scripts/savia-domains-cupulas.py:108,125` | Catálogo; `id` con `[A-Z]{2,3}` | Falso positivo |
| 29 | `scripts/merge-sprint.sh`, `scripts/risk-tier.py` (fuera de alcance de arreglo) | — | — | Sin casos de la clase: todo `python3 -c` usa argv o heredoc con comillas, y `risk-tier.py` usa lista argv |

## Hallazgos fuera de la clase (para la operadora)

- `scripts/pre-tribunal-gates.sh:131-136`: G3 **falla abierto**. Un `risk_score` que no es número (por ejemplo `"alto"`) hace fallar a Python y el gate no bloquea. Este barrido no lo cambia porque cambiaría el comportamiento del gate; necesita su propia decisión y su test.
- `scripts/agent-surface-guard.sh:64`: `declare --run-id ../x` escribe `surface.json` fuera de `.evo/` (recorrido de ruta en bash). Además, `run_id` y las listas se meten en el JSON con `printf` sin escapar. Conviene validar `run_id` con una expresión cerrada.
- `scripts/savia-bridge.py:3632`: el endpoint autenticado admite como `credential.helper` una ruta absoluta (`_SAFE_CREDENTIAL` permite `/`). Git ejecutará ese binario en cada operación con credenciales. Conviene limitarlo a una lista cerrada (`store`, `cache`, `manager`…).
- `.claude/hooks/context-sanitize-input.sh:138,160,…`: `[[ "$SCORE" -gt … ]]` evalúa `SCORE` como aritmética de bash. `SCORE` sale de `normalize.py` (un número), así que hoy no se alcanza. Es la clase de `court-review.sh` y le toca al barrido de bash.

## Tests

- Antes del arreglo (114 tests en 5 ficheros): 7 fallan (`pre-tribunal-gates` ×2, `repeat-tool-guard` ×2, `surface-guard` ×1, `cross-turn-track` ×2).
- Después: 114 de 114 en verde (`tests/test-se251-pre-tribunal-gates.bats`, `tests/test-repeat-tool-guard.bats`, `tests/test-repeat-tool-guard-block.bats`, `tests/test-se-217-surface-guard.bats`, `tests/test-cross-turn-track-session.bats`).
