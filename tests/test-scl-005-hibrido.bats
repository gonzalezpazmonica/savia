#!/usr/bin/env bats
# SCL-005 — Recall híbrido (BM25 + embeddings) desbloqueado
# Ref: docs/specs/SCL-005-embeddings-hibridos.spec.md

set -uo pipefail

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

# Solo las pruebas que miden similitud semántica exigen el venv; el resto
# (léxico, degradación, autoridad) deben ejecutarse siempre.
need_venv() {
  if [[ ! -x "$HOME/.savia/venv/bin/python" ]] || ! "$HOME/.savia/venv/bin/python" -c 'import sentence_transformers' >/dev/null 2>&1; then
    skip "venv ~/.savia/venv no presente (SCL-005 requiere dependencias)"
  fi
}

setup() {
  RECALL="$REPO_ROOT/scripts/learning-recall.sh"
  HYBRID="$REPO_ROOT/scripts/learning-hybrid.py"
  TMPD="$(mktemp -d -t scl-s5-XXXXXX)"
  mkdir -p "$TMPD/vault/learning" "$TMPD/proposals"
  export SCL_VAULT_DIR="$TMPD/vault"
  export SCL_PROPOSALS_DIR="$TMPD/proposals"
  export SCL_RECALL_LOG="$TMPD/recall.jsonl"
  export SCL_VENV_PYTHON="$HOME/.savia/venv/bin/python"
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
print(json.dumps([{'path': p, 'score': 42.0} for p in glob.glob(os.path.join(sys.argv[1], 'learning', '*.md'))]))
PY
EOF
  printf '%s\n' '# Criterio fixture' > "$SCL_CRITERIO_PATH"
  # Crear 2 lecciones en la cúpula de prueba (una sobre PAT/token)
  echo "ev1" > "$TMPD/e1.txt"
  bash "$REPO_ROOT/scripts/learning-proposal.sh" --origin "error real: PAT hardcodeado" \
    --evidence "$TMPD/e1.txt" --diagnosis "los tokens de acceso hardcodeados son riesgo de fuga" \
    --change "usar cat del fichero de credenciales" --target criterio --trigger ledger \
    --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  bash "$REPO_ROOT/scripts/learning-persist.sh" --file "$(ls "$TMPD/proposals/"*.md)" >/dev/null 2>&1
  echo "ev2" > "$TMPD/e2.txt"
  bash "$REPO_ROOT/scripts/learning-proposal.sh" --origin "leccion: cocinar paella" \
    --evidence "$TMPD/e2.txt" --diagnosis "la paella lleva arroz bomba" \
    --change "usar azafran" --target skill --trigger ledger \
    --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  bash "$REPO_ROOT/scripts/learning-persist.sh" --file "$(ls -t "$TMPD/proposals/"*.md | head -1)" >/dev/null 2>&1
}

teardown() {
  if [ -n "${TMPD:-}" ]; then
    rm -rf "$TMPD"
  fi
}

@test "AC-1: hybrid.py computa scores lex+sem y marca hybrid=true" {
  need_venv
  run bash -c "printf '%s' '{\"query\":\"token de acceso\",\"docs\":[{\"path\":\"a.md\",\"text\":\"PAT hardcodeado token acceso\"},{\"path\":\"b.md\",\"text\":\"receta de paella\"}]}' | SCL_VENV_PYTHON='$HOME/.savia/venv/bin/python' python3 '$HYBRID'"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['hits'][0]['path']=='a.md', d
assert d['hits'][0]['hybrid']==True, d
assert d['hits'][0]['sem'] > 0, d"
}

@test "AC-2 + SCL-008: recall hibrido detecta la leccion PAT sin elevarla" {
  run bash "$RECALL" --query "necesito el token de acceso para conectarme" --top 3 --hybrid --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['effective_hits'] == [], d
assert d['shadow_hits'] >= 1, d"
}

@test "AC-3: recall --hybrid degrada a lexico si venv no disponible (no falla)" {
  run bash -c "printf '%s' '{\"query\":\"x\",\"docs\":[{\"path\":\"a.md\",\"text\":\"algo\"}]}' | SCL_VENV_PYTHON=/nonexistent python3 '$HYBRID'"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert 'hits' in d, d
assert d['hits'][0]['hybrid']==False, d  # sin embeddings → lexico puro"
}

@test "AC-4: recall --hybrid emite JSON valido con contadores de autoridad" {
  run bash "$RECALL" --query "token de acceso azure" --top 3 --hybrid --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert {'effective_hits','shadow_hits','rejected_hits'} <= d.keys(), d"
}

@test "AC-5: recall --hybrid registra en el log de utilidad" {
  bash "$RECALL" --query "token de acceso azure" --top 3 --hybrid >/dev/null 2>&1
  [ -f "$TMPD/recall.jsonl" ]
  hits=$(tail -1 "$TMPD/recall.jsonl" | python3 -c "import json,sys; print(json.load(sys.stdin)['shadow_hits'])")
  [ "$hits" -ge 1 ]
}

@test "AC-6: recall BM25 puro (sin --hybrid) sigue funcionando" {
  run bash "$RECALL" --query "PAT hardcodeado" --top 3 --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['effective_hits'] == []; assert d['shadow_hits'] >= 1, d"
}

# --- S03c: puntuación léxica determinista de learning-hybrid.py (SCL-005) ---
# SCL_VENV_PYTHON apunta a un intérprete inexistente → semántica desactivada,
# el score es w_lex * fracción del query presente en el documento.

hyb() { printf '%s' "$1" | SCL_VENV_PYTHON=/nonexistent python3 "$HYBRID"; }

@test "léxico: score = w_lex(0.4) × fracción de términos del query presentes" {
  run hyb '{"query":"token acceso azure","docs":[{"path":"a.md","text":"el token de acceso"}]}'
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
h = json.load(sys.stdin)['hits'][0]
assert h['lex'] == 0.6667 and h['sem'] == 0.0 and h['hybrid'] is False, h
assert h['score'] == round(0.4 * 2 / 3, 4), h"
}

@test "pesos personalizados: w_lex=1 hace score igual a la fracción léxica" {
  run hyb '{"query":"token acceso","docs":[{"path":"a.md","text":"token acceso"}],"w_lex":1.0,"w_sem":0.0}'
  echo "$output" | python3 -c "
import json, sys
h = json.load(sys.stdin)['hits'][0]
assert h['score'] == 1.0, h"
}

@test "orden: los hits salen por score descendente" {
  run hyb '{"query":"token acceso azure","docs":[{"path":"nada.md","text":"receta paella"},{"path":"todo.md","text":"token acceso azure"},{"path":"algo.md","text":"token"}]}'
  echo "$output" | python3 -c "
import json, sys
paths = [h['path'] for h in json.load(sys.stdin)['hits']]
assert paths == ['todo.md', 'algo.md', 'nada.md'], paths"
}

@test "borde: query vacío o solo palabras vacías/cortas → score 0 para todos" {
  run hyb '{"query":"de la el","docs":[{"path":"a.md","text":"de la el token"}]}'
  echo "$output" | python3 -c "
import json, sys
h = json.load(sys.stdin)['hits'][0]
assert h['lex'] == 0.0 and h['score'] == 0.0, h"
}

@test "borde: lista de documentos vacía → hits vacío" {
  run hyb '{"query":"token","docs":[]}'
  [ "$status" -eq 0 ]
  [ "$output" = '{"hits": []}' ]
}

@test "limpieza: el frontmatter y los wikilinks no cuentan como contenido" {
  run hyb '{"query":"entity provenance","docs":[{"path":"n.md","text":"---\nentity:\n  provenance: INFERRED\n---\n\nSolo cuerpo [[provenance]] aquí"}]}'
  echo "$output" | python3 -c "
import json, sys
h = json.load(sys.stdin)['hits'][0]
assert h['lex'] == 0.0, h"
}

@test "snippet: se trunca a 160 caracteres y sin saltos de línea" {
  python3 - <<'PY' > "$TMPD/in.json"
import json
print(json.dumps({"query": "algo", "docs": [{"path": "l.md", "text": "algo\n" + "x" * 400}]}))
PY
  run bash -c "SCL_VENV_PYTHON=/nonexistent python3 '$HYBRID' < '$TMPD/in.json'"
  echo "$output" | python3 -c "
import json, sys
s = json.load(sys.stdin)['hits'][0]['snippet']
assert len(s) == 160 and '\n' not in s, len(s)"
}

@test "entrada que no es JSON → falla (exit ≠ 0), no inventa hits" {
  run bash -c "printf 'no json' | SCL_VENV_PYTHON=/nonexistent python3 '$HYBRID'"
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q '"hits"'
}

@test "recall --hybrid: nota con score 0 (sin términos comunes) no cuenta ni como sombra" {
  run bash "$RECALL" --query "zzzzqqqq wwwwxxxx" --top 3 --hybrid --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert (d['effective_hits'], d['shadow_hits'], d['rejected_hits']) == ([], 0, 0), d"
}
