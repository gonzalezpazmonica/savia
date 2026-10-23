#!/usr/bin/env bats
# SCL-008 — human authority boundary for learning recall

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
  TMPD="$(mktemp -d -t scl-s8-XXXXXX)"
  mkdir -p "$TMPD/vault/learning" "$TMPD/proposals"
  export SCL_VAULT_DIR="$TMPD/vault"
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
print(json.dumps([{'path': p, 'score': 42.0, 'snippet': 'hostile proposal text'} for p in glob.glob(os.path.join(sys.argv[1], 'learning', '*.md'))]))
PY
EOF
  printf '%s\n' \
    '# Criterio fixture' \
    'CRIT-034 — Credenciales locales' \
    '  principio: Las credenciales se resuelven desde un vault local.' \
    '  provenance: human_authored' > "$SCL_CRITERIO_PATH"
  echo 'credential evidence' > "$TMPD/evidence.txt"
  bash "$PROP" --origin credential-rule --evidence "$TMPD/evidence.txt" \
    --diagnosis 'hardcoded credential' --change 'resolve credential from local vault' \
    --target criterio --criterion-id CRIT-034 --output-dir "$TMPD/proposals" \
    --graph-index "$TMPD/graph.jsonl" >/dev/null
  PROPOSAL=$(ls "$TMPD/proposals/"*.md)
  sed -i 's/^provenance: .*/provenance: human_authored/;s/^lifecycle: .*/lifecycle: active/' "$PROPOSAL"
  bash "$PERSIST" --file "$PROPOSAL" >/dev/null
}

teardown() {
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
}

@test "TS-02: active human proposal resolves principle from CRITERIO.md" {
  run bash "$RECALL" --query 'credential local vault' --mode effective \
    --criterio "$SCL_CRITERIO_PATH" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); h=d['effective_hits'][0]; assert h['criterion_id']=='CRIT-034'; assert h['principle']=='Las credenciales se resuelven desde un vault local.'"
}

@test "TS-03: linked INFERRED criterion is rejected" {
  sed -i 's/provenance: human_authored/provenance: INFERRED/' "$SCL_CRITERIO_PATH"
  run bash "$RECALL" --query 'credential local vault' --mode effective \
    --criterio "$SCL_CRITERIO_PATH" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['effective_hits']==[]; assert d['rejected_hits'] >= 1"
}

@test "TS-11: Claude and OpenCode payloads produce identical canonical context" {
  run bash -c "printf '%s' '{\"content\":\"credential local vault configuration\"}' | SAVIA_LEARNING_RECALL=on SCL_VAULT_DIR='$TMPD/vault' SCL_CRITERIO_PATH='$SCL_CRITERIO_PATH' SCL_RECALL_LOG='$TMPD/recall.jsonl' SCL_NODE_PATH=bash SCL_VAULT_CLI='$SCL_VAULT_CLI' bash '$HOOK'"
  [ "$status" -eq 0 ]
  claude_output="$output"
  run bash -c "printf '%s' '{\"prompt_text\":\"credential local vault configuration\"}' | SAVIA_LEARNING_RECALL=on SCL_VAULT_DIR='$TMPD/vault' SCL_CRITERIO_PATH='$SCL_CRITERIO_PATH' SCL_RECALL_LOG='$TMPD/recall.jsonl' SCL_NODE_PATH=bash SCL_VAULT_CLI='$SCL_VAULT_CLI' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$output" = "$claude_output" ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'CRIT-034' in d['hookSpecificOutput']['additionalContext']"
}

@test "TS-10: learning operations do not modify foundational files" {
  criterio_before=$(sha256sum "$REPO_ROOT/CRITERIO.md" | cut -d' ' -f1)
  constitution_before=$(sha256sum "$REPO_ROOT/.claude/CONSTITUCION.md" | cut -d' ' -f1)
  bash "$RECALL" --query 'credential local vault' --mode effective --criterio "$SCL_CRITERIO_PATH" --json >/dev/null
  [ "$criterio_before" = "$(sha256sum "$REPO_ROOT/CRITERIO.md" | cut -d' ' -f1)" ]
  [ "$constitution_before" = "$(sha256sum "$REPO_ROOT/.claude/CONSTITUCION.md" | cut -d' ' -f1)" ]
}

@test "security: search results outside the vault are rejected" {
  outside="$TMPD/outside.md"
  cp "$TMPD/vault/learning/"*.md "$outside"
  cat > "$SCL_VAULT_CLI" <<EOF
#!/usr/bin/env bash
printf '%s\n' '[{"path":"$outside","score":99.0}]'
EOF
  run bash "$RECALL" --query 'credential local vault' --mode effective --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['effective_hits']==[]; assert d['rejected_hits']==1"
}

# --- S03c: frontera de autoridad, caso por caso (SCL-008) ---
# Notas escritas directamente en el vault temporal; el buscador falso devuelve
# todas con score 42, así que el filtrado que se mide es el de learning-recall.sh.

note() {
  # $1=nombre $2=provenance $3=lifecycle $4=target $5=criterion_id
  cat > "$TMPD/vault/learning/$1.md" <<NOTE
---
id: $1
provenance: $2
lifecycle: $3
target: $4
criterion_id: $5
---
cuerpo $1
NOTE
}

reset_vault() { find "$TMPD/vault/learning" -name '*.md' -delete; }

recall_json() { bash "$RECALL" --query 'credential local vault' --mode "${1:-effective}" --criterio "$SCL_CRITERIO_PATH" --json; }

jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

@test "autoridad: solo human_authored+active+criterio+criterio humano pasa; el resto se rechaza" {
  reset_vault
  note ok-1 human_authored active criterio CRIT-034
  note bad-target human_authored active skill CRIT-034
  note bad-life human_authored retired criterio CRIT-034
  note bad-crit human_authored active criterio CRIT-999
  note bad-prov agent_authored active criterio CRIT-034
  run recall_json
  [ "$status" -eq 0 ]
  echo "$output" | jq_py "
assert [h['proposal_id'] for h in d['effective_hits']] == ['ok-1'], d
assert d['rejected_hits'] == 4 and d['shadow_hits'] == 0, d"
}

@test "autoridad: lifecycle proposed va a sombra aunque sea human_authored" {
  reset_vault
  note prop human_authored proposed criterio CRIT-034
  run recall_json
  echo "$output" | jq_py "
assert d['effective_hits'] == [] and d['shadow_hits'] == 1 and d['rejected_hits'] == 0, d"
}

@test "modo shadow: una lección autorizada se cuenta como sombra, no se emite" {
  reset_vault
  note ok-1 human_authored active criterio CRIT-034
  run recall_json shadow
  echo "$output" | jq_py "
assert d['mode'] == 'shadow' and d['effective_hits'] == [] and d['shadow_hits'] == 1, d"
}

@test "dos lecciones del mismo criterio emiten una sola vez (dedup por CRIT)" {
  reset_vault
  note dup-a human_authored active criterio CRIT-034
  note dup-b human_authored active criterio CRIT-034
  run recall_json
  echo "$output" | jq_py "assert len(d['effective_hits']) == 1, d"
}

@test "tope de 3 criterios efectivos aunque haya más lecciones autorizadas" {
  reset_vault
  for n in 035 036 037 038; do
    printf 'CRIT-%s — extra\n  principio: principio %s\n  provenance: human_authored\n' "$n" "$n" >> "$SCL_CRITERIO_PATH"
    note "l-$n" human_authored active criterio "CRIT-$n"
  done
  run recall_json
  echo "$output" | jq_py "assert len(d['effective_hits']) == 3, d"
}

@test "criterio sin campo provenance no existe para el filtro (rechazo)" {
  reset_vault
  printf 'CRIT-040 — sin procedencia\n  principio: algo\n' >> "$SCL_CRITERIO_PATH"
  note orphan human_authored active criterio CRIT-040
  run recall_json
  echo "$output" | jq_py "assert d['effective_hits'] == [] and d['rejected_hits'] == 1, d"
}

@test "ruta con ../ que escapa del vault se rechaza (path traversal)" {
  reset_vault
  cp "$TMPD/CRITERIO.md" "$TMPD/fuera.md"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s\n' "'[{\"path\":\"../fuera.md\",\"score\":99.0}]'" > "$SCL_VAULT_CLI"
  run recall_json
  echo "$output" | jq_py "assert d['effective_hits'] == [] and d['rejected_hits'] == 1, d"
}

@test "nota inexistente referida por el buscador cuenta como rechazada, sin error" {
  reset_vault
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s\n' "'[{\"path\":\"learning/fantasma.md\",\"score\":99.0}]'" > "$SCL_VAULT_CLI"
  run recall_json
  [ "$status" -eq 0 ]
  echo "$output" | jq_py "assert d['rejected_hits'] == 1, d"
}

@test "score por debajo del mínimo se ignora (ni sombra ni rechazo)" {
  reset_vault
  note ok-1 human_authored active criterio CRIT-034
  run bash "$RECALL" --query 'credential local vault' --mode effective --criterio "$SCL_CRITERIO_PATH" --min-score 50 --json
  echo "$output" | jq_py "
assert (d['effective_hits'], d['shadow_hits'], d['rejected_hits']) == ([], 0, 0), d"
}

@test "salida de texto en modo effective lista '- [CRIT-id] principio'" {
  reset_vault
  note ok-1 human_authored active criterio CRIT-034
  run bash "$RECALL" --query 'credential local vault' --mode effective --criterio "$SCL_CRITERIO_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "- [CRIT-034] Las credenciales se resuelven desde un vault local." ]
}

@test "salida de texto en modo shadow está vacía (no filtra nada al contexto)" {
  reset_vault
  note ok-1 human_authored active criterio CRIT-034
  run bash "$RECALL" --query 'credential local vault' --mode shadow --criterio "$SCL_CRITERIO_PATH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "buscador que devuelve basura → resultado vacío con exit 0 (degradación)" {
  reset_vault
  printf '#!/usr/bin/env bash\necho "no es json"\n' > "$SCL_VAULT_CLI"
  run recall_json
  [ "$status" -eq 0 ]
  echo "$output" | jq_py "assert d['effective_hits'] == [] and d['rejected_hits'] == 0, d"
}
