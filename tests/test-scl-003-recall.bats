#!/usr/bin/env bats
# SCL-003 — Recall operativo: recuperar lecciones de la cúpula cuando se trabaja
# Ref: docs/specs/SCL-003-recall-operativo.spec.md

set -uo pipefail

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

setup() {
  RECALL="$REPO_ROOT/scripts/learning-recall.sh"
  HOOK="$REPO_ROOT/.claude/hooks/learning-recall-hook.sh"
  PROP="$REPO_ROOT/scripts/learning-proposal.sh"
  PERSIST="$REPO_ROOT/scripts/learning-persist.sh"
  TMPD="$(mktemp -d -t scl-s3-XXXXXX)"
  mkdir -p "$TMPD/vault/learning" "$TMPD/proposals"
  export SCL_VAULT_DIR="$TMPD/vault"
  export SCL_PROPOSALS_DIR="$TMPD/proposals"
  export SCL_RECALL_LOG="$TMPD/recall.jsonl"
  export SCL_CRITERIO_PATH="$TMPD/CRITERIO.md"
  export SCL_NODE_PATH="bash"
  export SCL_VAULT_CLI="$TMPD/fake-vault-cli.sh"
  cat > "$SCL_VAULT_CLI" <<'EOF'
#!/usr/bin/env bash
vault=""
while [[ $# -gt 0 ]]; do
  case "$1" in --path) vault="$2"; shift 2 ;; *) shift ;; esac
done
python3 - "$vault" <<'PY'
import glob, json, os, sys
print(json.dumps([{'path': p, 'score': 42.0, 'snippet': 'fixture'} for p in glob.glob(os.path.join(sys.argv[1], 'learning', '*.md'))]))
PY
EOF
  printf '%s\n' \
    '# Criterio fixture' \
    'CRIT-034 — Diagnostico obligatorio' \
    '  principio: Exigir diagnostico no vacio antes de cambiar el hook.' \
    '  provenance: human_authored' > "$SCL_CRITERIO_PATH"
  # Crear una lección persistida en la cúpula de prueba
  echo "ev-s3" > "$TMPD/ev.txt"
  bash "$PROP" --origin "leccion: el hook de captura pierde diagnostico" \
    --evidence "$TMPD/ev.txt" --diagnosis "la captura generaba ruido sin causa raiz" \
    --change "exigir diagnostico no vacio" --target criterio --trigger ledger \
    --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  f=$(ls "$TMPD/proposals/"*.md)
  bash "$PERSIST" --file "$f" >/dev/null 2>&1
}

teardown() {
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
}

@test "SCL-008 TS-01: propuesta INFERRED relevante permanece en sombra" {
  run bash "$RECALL" --query "hook de captura diagnostico" --top 3 --mode effective --criterio "$SCL_CRITERIO_PATH" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['effective_hits'] == []; assert d['shadow_hits'] >= 1"
}

@test "AC-2: recall sin contexto relacionado no produce ruido (exit 0, 0 hits)" {
  run bash "$RECALL" --query "receta de paella valenciana" --top 3
  [ "$status" -eq 0 ]
  [[ "$output" != *"LP-"* ]]
}

@test "SCL-008 TS-05: shadow mide sin emitir contexto" {
  run bash "$RECALL" --query "hook captura diagnostico" --top 3 --mode shadow --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['effective_hits'] == []; assert d['shadow_hits'] >= 1"
}

@test "AC-4: recall registra en el log de utilidad (recall.jsonl)" {
  bash "$RECALL" --query "hook captura diagnostico" --top 3 >/dev/null 2>&1
  [ -f "$TMPD/recall.jsonl" ]
  python3 - "$TMPD/recall.jsonl" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding='utf-8').read().splitlines()[-1])
assert 'query_hash' in d and 'query' not in d
assert d['shadow_hits'] >= 1
PY
}

@test "SCL-008 TS-01: hook no inyecta propuestas inferidas" {
  run bash -c "printf '%s' '{\"content\":\"voy a mejorar el hook de captura de memoria que pierde diagnostico\"}' | SAVIA_LEARNING_RECALL=on SCL_VAULT_DIR='$TMPD/vault' SCL_RECALL_LOG='$TMPD/recall.jsonl' SCL_NODE_PATH=bash SCL_VAULT_CLI='$SCL_VAULT_CLI' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-6: hook NO inyecta en prompt no relacionado (umbral de score)" {
  run bash -c "printf '%s' '{\"content\":\"hazme un resumen del tiempo en Madrid\"}' | SAVIA_LEARNING_RECALL=on SCL_VAULT_DIR='$TMPD/vault' SCL_RECALL_LOG='$TMPD/recall.jsonl' SCL_NODE_PATH=bash SCL_VAULT_CLI='$SCL_VAULT_CLI' bash '$HOOK'"
  [[ "$output" != *"Lecciones aprendidas relevantes"* ]]
}

@test "AC-7: hook nunca bloquea (exit 0 siempre)" {
  run bash -c "printf '%s' '{}' | SAVIA_LEARNING_RECALL=on SCL_VAULT_DIR='$TMPD/vault' SCL_RECALL_LOG='$TMPD/recall.jsonl' SCL_NODE_PATH=bash SCL_VAULT_CLI='$SCL_VAULT_CLI' bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "SCL-008 TS-07: log no persiste el prompt" {
  secret="credencial-secreta-no-persistir"
  bash "$RECALL" --query "$secret" --mode shadow --json >/dev/null
  hash=$(printf '%s' "$secret" | sha256sum | cut -d' ' -f1)
  grep -q "$hash" "$TMPD/recall.jsonl"
  ! grep -q "$secret" "$TMPD/recall.jsonl"
}

# --- S03c: contrato de CLI, log y filtros del hook (SCL-003) ---

hook_run() {
  # $1 = JSON de entrada; env: SAVIA_LEARNING_RECALL opcional
  printf '%s' "$1" | SAVIA_LEARNING_RECALL="${RECALL_SWITCH:-on}" SCL_VAULT_DIR="$TMPD/vault" \
    SCL_RECALL_LOG="$TMPD/recall.jsonl" SCL_NODE_PATH=bash SCL_VAULT_CLI="$SCL_VAULT_CLI" \
    SCL_CRITERIO_PATH="$SCL_CRITERIO_PATH" bash "$HOOK"
}

activate_proposal() {
  # Edita la nota ya persistida en el vault temporal: humana, activa, ligada a CRIT-034.
  local n
  n=$(ls "$TMPD"/vault/learning/*.md | head -1)
  sed -i -E 's/^( *)provenance: .*/\1provenance: human_authored/;s/^( *)lifecycle: .*/\1lifecycle: active/;s/^( *)criterion_id:.*/\1criterion_id: CRIT-034/' "$n"
}

@test "CLI: sin --query → exit 2 con uso" {
  run bash "$RECALL" --top 3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "Usage: learning-recall.sh"
}

@test "CLI: --top fuera de 1..20 → exit 2 (fronteras 0 y 21), 1 y 20 válidos" {
  run bash "$RECALL" --query x --top 0;  [ "$status" -eq 2 ]
  run bash "$RECALL" --query x --top 21; [ "$status" -eq 2 ]
  run bash "$RECALL" --query x --top abc; [ "$status" -eq 2 ]
  run bash "$RECALL" --query x --top 1;  [ "$status" -eq 0 ]
  run bash "$RECALL" --query x --top 20; [ "$status" -eq 0 ]
}

@test "CLI: --mode inválido y --min-score no numérico → exit 2" {
  run bash "$RECALL" --query x --mode turbo
  [ "$status" -eq 2 ]
  run bash "$RECALL" --query x --min-score -1
  [ "$status" -eq 2 ]
  run bash "$RECALL" --query x --min-score 1.5
  [ "$status" -eq 0 ]
}

@test "CLI: opción desconocida o sin valor → exit 2" {
  run bash "$RECALL" --query x --bogus
  [ "$status" -eq 2 ]
  run bash "$RECALL" --query
  [ "$status" -eq 2 ]
}

@test "CLI: vault inexistente o criterio ausente → exit 3 (entorno), no 2" {
  run bash "$RECALL" --query x --vault "$TMPD/no-vault"
  [ "$status" -eq 3 ]
  run bash "$RECALL" --query x --criterio "$TMPD/no-criterio.md"
  [ "$status" -eq 3 ]
}

@test "CLI: buscador ausente (CLI inexistente) → exit 3" {
  SCL_VAULT_CLI="$TMPD/no-existe.sh" run bash "$RECALL" --query x
  [ "$status" -eq 3 ]
}

@test "log: cada llamada añade exactamente una línea JSON con los contadores" {
  bash "$RECALL" --query "hook captura diagnostico" --mode shadow >/dev/null
  bash "$RECALL" --query "otra consulta" --mode effective >/dev/null
  [ "$(wc -l < "$TMPD/recall.jsonl")" -eq 2 ]
  python3 - "$TMPD/recall.jsonl" <<'PY'
import json, re, sys
a, b = (json.loads(l) for l in open(sys.argv[1]))
assert (a['mode'], b['mode']) == ('shadow', 'effective'), (a, b)
assert a['query_hash'] != b['query_hash'] and len(a['query_hash']) == 64
assert re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', a['ts'])
assert set(a) == {'ts','query_hash','mode','effective_hits','shadow_hits','rejected_hits','proposal_ids'}, a
PY
}

@test "log: el hash de la misma consulta es estable y distinto del texto" {
  bash "$RECALL" --query "consulta estable" >/dev/null
  bash "$RECALL" --query "consulta estable" >/dev/null
  python3 - "$TMPD/recall.jsonl" <<'PY'
import hashlib, json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
h = hashlib.sha256(b"consulta estable").hexdigest()
assert rows[0]['query_hash'] == rows[1]['query_hash'] == h, rows
PY
}

@test "--json incluye la consulta y NO expone proposal_ids" {
  run bash "$RECALL" --query "hook captura diagnostico" --json
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['query'] == 'hook captura diagnostico' and 'proposal_ids' not in d, d"
}

@test "log directory inexistente se crea (recall-log en ruta nueva)" {
  run bash "$RECALL" --query "algo" --recall-log "$TMPD/nuevo/dir/r.jsonl"
  [ "$status" -eq 0 ]
  [ -s "$TMPD/nuevo/dir/r.jsonl" ]
}

@test "hook: SAVIA_LEARNING_RECALL=off no ejecuta nada ni registra" {
  RECALL_SWITCH=off run hook_run '{"content":"voy a mejorar el hook de captura de memoria"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$TMPD/recall.jsonl" ]
}

@test "hook: prompt corto (<8 caracteres), confirmación o ruta no consultan" {
  for txt in "ok" "gracias" "vale ya" "/status-check-ahora"; do
    run hook_run "{\"content\":\"$txt\"}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  [ ! -s "$TMPD/recall.jsonl" ]
}

@test "hook: entrada que no es JSON se ignora sin error" {
  run hook_run 'esto no es json en absoluto'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$TMPD/recall.jsonl" ]
}

@test "hook: lección humana activa y relevante SÍ se inyecta con su principio" {
  activate_proposal
  run hook_run '{"content":"voy a mejorar el hook de captura que pierde diagnostico"}'
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
c = json.load(sys.stdin)['hookSpecificOutput']
assert c['hookEventName'] == 'UserPromptSubmit', c
assert '## Criterios humanos aplicables' in c['additionalContext'], c
assert '[CRIT-034] Exigir diagnostico no vacio antes de cambiar el hook.' in c['additionalContext'], c"
  [ -s "$TMPD/recall.jsonl" ]
}
