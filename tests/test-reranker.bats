#!/usr/bin/env bats
# test-reranker.bats — calibración de la skill reranker (SE-376).
# Ref: docs/propuestas/SE-032-reranker-layer.md
# Ref: .claude/skills/reranker/SKILL.md
#
# Comportamiento real: candidatos sintéticos con orden correcto conocido,
# cross-encoder simulado con un módulo stub (sin descargar modelos) y una
# sonda con PATH controlado. Nunca toca ~/.savia-memory: HOME apunta a un
# directorio temporal.

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="scripts/rerank.py"
PROBE="scripts/reranker-probe.sh"

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  cd "$ROOT"
  # Sin stub en PYTHONPATH, el backend real es el fallback (no hay
  # sentence-transformers en la CI); se fuerza para no depender del host.
  NOST="$TMPDIR/nost"
  mkdir -p "$NOST/sentence_transformers"
  printf 'raise ImportError("stub: sentence-transformers ausente")\n' \
    > "$NOST/sentence_transformers/__init__.py"
}

teardown() {
  [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR" || true
}

# Crea un CrossEncoder stub: relevancia = fracción de palabras de la query
# presentes en el texto (determinista, orden conocido).
make_stub() {
  local mode="${1:-ok}"
  mkdir -p "$TMPDIR/st/sentence_transformers"
  cat > "$TMPDIR/st/sentence_transformers/__init__.py" <<PY
MODE = "$mode"
class CrossEncoder:
    def __init__(self, model_id):
        if MODE == "boom":
            raise ImportError("stub: torch ausente")
        print("Downloading stub weights...")
        self.model_id = model_id
    def predict(self, pairs):
        out = []
        for q, t in pairs:
            words = q.lower().split()
            hits = sum(1 for w in words if w in t.lower())
            out.append(hits / len(words))
        return out
PY
}

field() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

# --- Objetivo ---

@test "target: rerank.py and probe exist; probe uses set -uo pipefail" {
  [ -f "$SCRIPT" ]
  [ -x "$PROBE" ]
  grep -q '^set -uo pipefail' "$PROBE"
}

# --- Positivos: orden ---

@test "positive: fallback-cosine orders by cosine descending (known order)" {
  local in='{"query":"q","candidates":[{"id":"low","text":"a","cosine":0.1},{"id":"high","text":"b","cosine":0.9},{"id":"mid","text":"c","cosine":0.5}]}'
  run bash -c "echo '$in' | PYTHONPATH='$NOST' python3 '$SCRIPT' --top-k 3"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "','.join(c['id'] for c in d['reranked'])")" = "high,mid,low" ]
  [ "$(echo "$output" | field "d['backend']")" = "fallback-cosine" ]
  [ "$(echo "$output" | field "d['model']")" = "None" ]
}

@test "positive: stub cross-encoder reorders by relevance and reports model" {
  make_stub ok
  local in='{"query":"gato negro","candidates":[{"id":"none","text":"perro","cosine":0.9},{"id":"both","text":"un gato negro","cosine":0.1},{"id":"one","text":"gato","cosine":0.5}]}'
  run bash -c "echo '$in' | PYTHONPATH='$TMPDIR/st' python3 '$SCRIPT' --top-k 3 --model stub/m 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "','.join(c['id'] for c in d['reranked'])")" = "both,one,none" ]
  [ "$(echo "$output" | field "d['backend']")" = "cross-encoder" ]
  [ "$(echo "$output" | field "d['model']")" = "stub/m" ]
  [ "$(echo "$output" | field "d['reranked'][0]['relevance']")" = "1.0" ]
}

@test "positive: model load chatter on stdout does not corrupt JSON output" {
  make_stub ok
  local in='{"query":"x","candidates":[{"id":"a","text":"x"}]}'
  run bash -c "echo '$in' | PYTHONPATH='$TMPDIR/st' python3 '$SCRIPT' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "d['backend']")" = "cross-encoder" ]
}

@test "positive: ties keep input order (stable sort)" {
  local in='{"query":"q","candidates":[{"id":"first","text":"a","cosine":0.5},{"id":"second","text":"b","cosine":0.5},{"id":"third","text":"c","cosine":0.5}]}'
  run bash -c "echo '$in' | PYTHONPATH='$NOST' python3 '$SCRIPT' --top-k 3"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "','.join(c['id'] for c in d['reranked'])")" = "first,second,third" ]
}

# --- Honestidad del fallback ---

@test "fallback: reports relevance null instead of omitting it" {
  local in='{"query":"q","candidates":[{"id":"a","text":"a","cosine":0.3}]}'
  run bash -c "echo '$in' | PYTHONPATH='$NOST' python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "'relevance' in d['reranked'][0] and d['reranked'][0]['relevance'] is None")" = "True" ]
}

@test "fallback: cross-encoder crash with non-OSError falls back and says so" {
  make_stub boom
  local in='{"query":"q","candidates":[{"id":"a","text":"a","cosine":0.2},{"id":"b","text":"b","cosine":0.8}]}'
  run bash -c "echo '$in' | PYTHONPATH='$TMPDIR/st' python3 '$SCRIPT' 2>'$TMPDIR/err'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "d['backend']")" = "fallback-cosine" ]
  [ "$(echo "$output" | field "d['model']")" = "None" ]
  grep -q "cross-encoder failed" "$TMPDIR/err"
  ! grep -q "Traceback" "$TMPDIR/err"
}

@test "fallback: partial cosine is identity, never a silent partial sort" {
  local in='{"query":"q","candidates":[{"id":"a","text":"a","cosine":0.1},{"id":"b","text":"b"}]}'
  run bash -c "echo '$in' | PYTHONPATH='$NOST' python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "d['backend']")" = "fallback-identity" ]
  [ "$(echo "$output" | field "','.join(c['id'] for c in d['reranked'])")" = "a,b" ]
}

# --- Límite ---

@test "boundary: empty candidates returns empty-input backend" {
  run bash -c "echo '{\"query\":\"q\",\"candidates\":[]}' | PYTHONPATH='$NOST' python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "len(d['reranked']), d['backend']")" = "0 empty-input" ]
}

@test "boundary: single candidate gets rank 1" {
  run bash -c "echo '{\"query\":\"q\",\"candidates\":[{\"id\":\"solo\",\"text\":\"t\"}]}' | PYTHONPATH='$NOST' python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "d['reranked'][0]['id'], d['reranked'][0]['rank']")" = "solo 1" ]
}

@test "boundary: top-k larger than n returns all n, ranks contiguous" {
  local in='{"query":"q","candidates":[{"id":"a","text":"a","cosine":0.2},{"id":"b","text":"b","cosine":0.4}]}'
  run bash -c "echo '$in' | PYTHONPATH='$NOST' python3 '$SCRIPT' --top-k 1000"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "[c['rank'] for c in d['reranked']]")" = "[1, 2]" ]
}

@test "boundary: top-k zero is a usage error (exit 2)" {
  run bash -c "echo '{}' | python3 '$SCRIPT' --top-k 0"
  [ "$status" -eq 2 ]
}

@test "boundary: unicode query and ids survive unescaped, valid JSON" {
  local in='{"query":"canción ñandú","candidates":[{"id":"árbol","text":"日本語 🌳","cosine":0.4}]}'
  run bash -c "echo '$in' | PYTHONPATH='$NOST' python3 '$SCRIPT' --json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"canción ñandú"* ]]
  [ "$(echo "$output" | field "d['reranked'][0]['id']")" = "árbol" ]
}

# --- Negativos: entrada inválida sin traceback ---

@test "error: top-level JSON array is rejected with exit 1 and no traceback" {
  run bash -c "echo '[1,2]' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "error: non-string query is rejected with exit 1 and no traceback" {
  run bash -c "echo '{\"query\":5,\"candidates\":[]}' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"query"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "error: non-numeric cosine is invalid input, exit 1, no traceback" {
  local in='{"query":"q","candidates":[{"id":"a","text":"a","cosine":"alta"},{"id":"b","text":"b","cosine":0.3}]}'
  run bash -c "echo '$in' | PYTHONPATH='$NOST' python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cosine"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "error: null cosine is invalid input, exit 1" {
  local in='{"query":"q","candidates":[{"id":"a","text":"a","cosine":null}]}'
  run bash -c "echo '$in' | PYTHONPATH='$NOST' python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" != *"Traceback"* ]]
}

@test "error: invalid UTF-8 on stdin fails with exit 1 and no traceback" {
  run bash -c "printf '{\"query\":\"\xff\",\"candidates\":[]}' | PYTHONIOENCODING=utf-8:surrogateescape python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid UTF-8"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "error: non-string text is rejected" {
  run bash -c "echo '{\"query\":\"q\",\"candidates\":[{\"id\":\"a\",\"text\":null}]}' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"text"* ]]
}

# --- Sonda de viabilidad ---

@test "probe: missing python3 reports BLOCKED, not NEEDS_INSTALL" {
  local bin="$TMPDIR/bin"
  mkdir -p "$bin"
  for t in bash cut awk df head sed cat; do ln -s "$(command -v "$t")" "$bin/$t"; done
  run env PATH="$bin" bash "$PROBE" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"verdict":"BLOCKED"'* ]]
}

@test "probe: VIABLE with stub deps on PATH and PYTHONPATH (exit 0)" {
  local bin="$TMPDIR/bin2" st="$TMPDIR/deps"
  mkdir -p "$bin" "$st/sentence_transformers" "$st/torch"
  printf '#!/bin/sh\nexit 0\n' > "$bin/pip3"; chmod +x "$bin/pip3"
  : > "$st/sentence_transformers/__init__.py"; : > "$st/torch/__init__.py"
  run env PATH="$bin:$PATH" PYTHONPATH="$st" bash "$PROBE" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | field "d['verdict'], d['sentence_transformers'], d['torch']")" = "VIABLE 1 1" ]
}

@test "probe: invalid flag is rejected with exit 2" {
  run bash "$PROBE" --bogus
  [ "$status" -eq 2 ]
}
