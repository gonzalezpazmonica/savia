# Evaluation Harness — SE-204

> Ref: docs/propuestas/SE-204-eval-harness.md

Directorio raíz de eval cases para agentes críticos de pm-workspace.
Formato: EvalCase = `input.md` (tarea) + `criteria.md` (rúbrica LLM-as-judge).

## Estructura

```
tests/evals/
├── sdd-spec-writer/      # Eval cases para el agente sdd-spec-writer
├── court-orchestrator/   # Eval cases para court-orchestrator
└── business-analyst/     # Eval cases para business-analyst
```

Cada subdirectorio de agente contiene carpetas `eval-NN-<nombre>/` con:
- `input.md` — Descripción realista de la tarea (≥50 palabras)
- `criteria.md` — Rúbrica LLM-as-judge (≥5 criterios, umbral ≥7/10)

## Ejecución

```bash
# Listar todos los eval cases disponibles
bash scripts/run-agent-evals.sh --list

# Dry-run (sin ejecutar agentes)
bash scripts/run-agent-evals.sh --dry-run

# Ejecutar todos los agentes
bash scripts/run-agent-evals.sh

# Ejecutar un agente específico
bash scripts/run-agent-evals.sh --agent sdd-spec-writer
```

## Evals L4 de agentes (SE-387 D)

Los agentes L4 llevan además `golden.json`, `edge.json`, `adversarial.json` y
`bypass.json` en `tests/evals/<agente>/`, un descriptor en
`contracts/capabilities/` y un `tests/bats/<agente>-l4.bats`. Los de
`context-dome-manager`, `meeting-digest`, `recommendation-tribunal-orchestrator`
y `truth-tribunal-orchestrator` usan este formato:

- `cases[].checks[]`: aserción estática (`target` = `agent` o ruta del repo;
  `must_match` / `must_not_match` = regex `grep -E`). Comprueba que la garantía
  declarada (veto, lista de delegados, restricción, umbral) sigue escrita.
- `cases[].aggregate`: ejecución real del agregador determinista
  (`recommendation-tribunal-orchestrator`) con veredictos sintéticos y
  `expect` (`exit`, `verdict`, `consensus_score`, `veto_judges`).
- `cases[].aggregate` con `script`: ejecución real del script o hook del agente
  con el ejecutor único `tests/bats/l4_exec_eval.py`; ver «Cases ejecutables
  contra el guardarrail real» más abajo.
- `cases[].weights`: comprobación ejecutada de que cada perfil de pesos del
  Truth Tribunal suma 1.00 (`truth-tribunal-orchestrator`).

Cada `.bats` incluye mutantes: copias del agente (o del script) sin la
garantía, y exige que la eval falle. Una eval que no puede fallar no vale.

```bash
bats tests/bats/context-dome-manager-l4.bats tests/bats/meeting-digest-l4.bats \
     tests/bats/recommendation-tribunal-orchestrator-l4.bats \
     tests/bats/truth-tribunal-orchestrator-l4.bats
```

Estas evals NO ejecutan el agente con un modelo (igual que las demás L4: no
corren contra la API en CI). Para evaluar el comportamiento con modelo, usar
los campos `input` / `expected` de cada case como prompt y rúbrica con
`bash scripts/eval-agent.sh <agente>` en local; los `checks` sirven de
criterios comprobables de la respuesta.

## Threshold

Exit 0 si score estructural ≥ 80% de los eval cases son válidos.
Exit 1 si < 80%.

Reporte generado en `output/eval-report-YYYYMMDD.md`.

## Nota sobre Slices

- **Slice 1-2** (esta implementación): estructura + eval cases + runner estructural.
- **Slice 3-4** (futura SE-204): invocación real de agentes LLM + puntuación LLM-as-judge.

El runner actual valida que los ficheros existen y tienen forma correcta
(criteria.md ≥5 criterios, input.md ≥50 palabras). No invoca LLMs todavía.

### Evals de definicion y evals de comportamiento

`scripts/eval-coverage-matrix.py` separa las dos clases. Un fixture es de
**comportamiento** si algun caso lleva `aggregate` (se ejecuta el script real y
se compara el resultado). Los `checks` (grep sobre el prompt del agente) y los
`weights` son de **definicion**: se siguen ejecutando, pero se cumplen
escribiendo texto, asi que no cuentan para la cobertura L4. La matriz expone
`covered` (solo comportamiento) y `covered_definition`. El gate
`eval-coverage-L4` de `scripts/coherence-gates.sh` esta en modo informe para el
comportamiento (`EVAL_L4_BEHAVIOR_MODE=block` lo activa) y bloquea si se pierde
cobertura de definicion.

### Cases ejecutables contra el guardarrail real (`aggregate.script`)

Para agentes cuyo comportamiento garantizado lo impone un hook o script
determinista, el case lleva `aggregate.script` y lo ejecuta
`tests/bats/l4_exec_eval.py` (via `l4_exec_cases` de
`tests/bats/l4-exec-lib.bash`): ficheros sinteticos en un directorio temporal
(`{dir}`), stdin (`stdin_command` para hooks PreToolUse de Bash, `stdin_json`,
`stdin`), `env`, `cwd` (opcional; `{dir}` corre en el directorio del case, por
defecto la raiz del repo) y `expect` con `exit`, regex (o listas de regex, todas
obligatorias) sobre stdout/stderr y sobre ficheros escritos, `stdout_empty`,
`json` (`{"<ruta jq>": valor}` sobre stdout) y `files_absent`. El ejecutor quita
del entorno las variables del operador que cambian la decision de los hooks
(`CLAUDE_PROJECT_DIR`, `SAVIA_HOOK_PROFILE`, umbrales `COURT_*`/`COHERENCE_*`...)
antes de aplicar el `env` del case, y falla cerrado ante claves desconocidas, el
marcador retirado `{{TMP}}` o un `exit 0` sin otra expectativa. Un case con
`negative: true` espera rechazo; `l4_exec_shape` exige 3-5 cases ejecutables
por agente, uno por fixture como minimo y al menos uno negativo, y
`l4_hook_copy` copia un hook con su `lib/` para mutarlo. Las credenciales y la
PII de los fixtures van troceadas en listas de partes que se concatenan al ejecutar. Cada `.bats` incluye mutantes
del script que deben hacer fallar el case. Sin llamadas a modelo.

| Agente | Script ejecutado |
|---|---|
| infrastructure-agent | `.claude/hooks/block-infra-destructive.sh` |
| security-guardian | `.claude/hooks/block-credential-leak.sh`, `.claude/hooks/block-pat-file-write.sh` |
| test-runner | `scripts/test-coverage-ratchet.sh` |
| meeting-digest | `scripts/confidentiality-check.sh` (sobre el arbol que escribe el digest) |
| truth-tribunal-orchestrator | `scripts/truth-tribunal.sh aggregate` |
| frontend-test-runner | `.claude/hooks/responsibility-judge.sh` (Write/Edit de tests y config frontend) |
| coherence-court-orchestrator | `scripts/coherence-court.sh` |
| commit-guardian | `.claude/hooks/block-force-push.sh` |
| context-dome-manager | `.claude/hooks/dome-guard.sh` |
| court-orchestrator | `scripts/court-review.sh` |
| dev-orchestrator | `scripts/savia-orchestrator-helper.sh` |
