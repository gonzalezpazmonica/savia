#!/usr/bin/env bats
# tests/test-memory-consolidate.bats — SE-317: Memoria reflexiva (S1-S4).
# Ref: docs/propuestas/SE-317-memoria-reflexiva.md (AC-S1..S4)

CONS="scripts/memory-consolidate.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

make_store() { # file
  cat > "$1" <<'EOF'
{"hash":"h1","title":"Nota A","content":"el servicio gateway sufrio un timeout en produccion","ts":"2026-08-01T10:00:00Z","concepts":["gateway"],"topic_key":"incident/gateway","quality":"unverified","importance_tier":"C"}
{"hash":"h2","title":"Nota A copia","content":"el servicio gateway sufrio un timeout en produccion","ts":"2026-08-01T11:00:00Z","concepts":["gateway"],"topic_key":"incident/gateway","quality":"unverified","importance_tier":"C"}
{"hash":"h3","title":"Nota B","content":"reunion: gateway timeout discutido, se planifico rollback","ts":"2026-08-02T09:00:00Z","concepts":["gateway","rollback"],"topic_key":"incident/gateway","quality":"unverified","importance_tier":"C"}
{"hash":"h4","title":"Nota obsoleta","content":"detalle viejo","ts":"2026-07-01T08:00:00Z","concepts":[],"topic_key":"incident/gateway","quality":"absorbed","importance_tier":"D"}
EOF
}

# ── S1: scan ────────────────────────────────────────────────────────────────

@test "S1.0: script existe, ejecutable, pipefail" {
  [[ -f "$CONS" ]]
  [[ -x "$CONS" ]]
  run grep -c 'set -uo pipefail' "$CONS"
  [[ "$output" -ge 1 ]]
}

@test "AC-S1.1: 2 notas idénticas -> candidato a merge con score 1.0" {
  local s="$TMPD/store.jsonl"
  make_store "$s"
  run bash "$CONS" scan --store "$s"
  [[ "$status" -eq 0 ]]
  run python3 -c "
import json
last = None
with open('$TMPD/scan.jsonl') as f:  # no, leemos de output real
    pass
"
  # buscamos en el fichero de salida real del scan
  local out
  out=$(ls output/memory-consolidation/*-scan.jsonl 2>/dev/null | tail -1)
  run python3 -c "
import json, sys
with open('$out') as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'duplicate' and d.get('score') == 1.0:
            assert d['a']['hash'] == 'h1' and d['b']['hash'] == 'h2'
            sys.exit(0)
sys.exit(1)
"
  [[ "$status" -eq 0 ]]
}

@test "AC-S1.2: notas del mismo episodio -> near-duplicate (score > 0.85)" {
  local s="$TMPD/store2.jsonl"
  cat > "$s" <<'EOF'
{"hash":"n1","title":"X","content":"el mismo contenido del episodio uno dos tres cuatro","ts":"2026-08-01T10:00:00Z","concepts":["a"],"topic_key":"ep/1"}
{"hash":"n2","title":"Y","content":"el mismo contenido del episodio uno dos tres cinco","ts":"2026-08-01T11:00:00Z","concepts":["a"],"topic_key":"ep/1"}
EOF
  bash "$CONS" scan --store "$s" >/dev/null
  local out
  out=$(ls output/memory-consolidation/*-scan.jsonl 2>/dev/null | tail -1)
  run python3 -c "
import json, sys
with open('$out') as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'near_duplicate' and d.get('score', 0) > 0.85:
            sys.exit(0)
sys.exit(1)
"
  [[ "$status" -eq 0 ]]
}

# ── S2: link ────────────────────────────────────────────────────────────────

@test "AC-S2.1: nota que cita a otra existente -> arista derived-from" {
  local s="$TMPD/store3.jsonl"
  cat > "$s" <<'EOF'
{"hash":"a1","title":"Guia","content":"ver hash b1 para detalle del incidente","ts":"2026-08-01T10:00:00Z","concepts":["g"]}
{"hash":"b1","title":"Incidente","content":"detalle completo","ts":"2026-08-01T12:00:00Z","concepts":["g"]}
EOF
  bash "$CONS" link --store "$s" >/dev/null
  local out
  out=$(ls output/memory-consolidation/*-link.jsonl 2>/dev/null | tail -1)
  run python3 -c "
import json, sys
with open('$out') as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'derived-from' and d['from'] == 'a1' and d['to'] == 'b1':
            sys.exit(0)
sys.exit(1)
"
  [[ "$status" -eq 0 ]]
}

# ── S3: distill ─────────────────────────────────────────────────────────────

@test "AC-S3.1: episodio de >=2 notas genera 1 insight con citations" {
  local s="$TMPD/store4.jsonl"
  make_store "$s"
  bash "$CONS" distill --store "$s" >/dev/null
  local out
  out=$(ls output/memory-consolidation/*-distill.jsonl 2>/dev/null | tail -1)
  run python3 -c "
import json, sys
with open('$out') as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'insight':
            assert d['sources'] >= 2, d
            assert 'citations' in d and len(d['citations']) >= 2, d
            sys.exit(0)
sys.exit(1)
"
  [[ "$status" -eq 0 ]]
}

@test "AC-S3.2: fuentes marcadas absorbed (no borradas)" {
  local s="$TMPD/store5.jsonl"
  make_store "$s"
  bash "$CONS" distill --store "$s" >/dev/null
  local out
  out=$(ls output/memory-consolidation/*-distill.jsonl 2>/dev/null | tail -1)
  run python3 -c "
import json, sys
with open('$out') as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'insight':
            assert 'absorbed' in d and len(d['absorbed']) >= 2, d
            sys.exit(0)
sys.exit(1)
"
  [[ "$status" -eq 0 ]]
}

# ── S4: prune ───────────────────────────────────────────────────────────────

@test "AC-S4.1: --dry-run no modifica nada y lista candidatos con razón" {
  local s="$TMPD/store6.jsonl"
  make_store "$s"
  local before after
  before=$(sha256sum "$s" | cut -d' ' -f1)
  bash "$CONS" prune --store "$s" >/dev/null
  after=$(sha256sum "$s" | cut -d' ' -f1)
  [[ "$before" == "$after" ]]
  local out
  out=$(ls output/memory-consolidation/*-prune.jsonl 2>/dev/null | tail -1)
  run python3 -c "
import json, sys
with open('$out') as f:
    for line in f:
        d = json.loads(line)
        assert d.get('type') == 'prune_candidate', d
        assert d.get('dry_run') is True, d
        assert 'reason' in d and d['reason'], d
        sys.exit(0)
sys.exit(1)
"
  [[ "$status" -eq 0 ]]
}

@test "AC-S4.2: automatización semanal registrada en el scheduler" {
  run grep -c 'memory-consolidation' scripts/savia-automations.sh
  [[ "$output" -ge 1 ]]
}

@test "AC-S4.3: cada ejecución deja reporte en output/memory-consolidation/" {
  local s="$TMPD/store7.jsonl"
  make_store "$s"
  bash "$CONS" scan --store "$s" >/dev/null
  run ls output/memory-consolidation/*-scan.jsonl 2>/dev/null
  [[ -n "$output" ]]
}

# ── Seguridad ───────────────────────────────────────────────────────────────

@test "S5.1: no introduce secrets ni IPs internas" {
  run grep -rnE "AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32,}|192\.168\.|10\.([0-9]{1,3}\.){2}" scripts/memory-consolidate.sh
  [[ -z "$output" ]]
}

# --- Comportamiento: copia del script en un árbol temporal (la salida va a su output/) ---

mkenv() {
  TREE="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$TREE/scripts"
  cp "$CONS" "$TREE/scripts/memory-consolidate.sh"
  STORE_T="$BATS_TEST_TMPDIR/store.jsonl"
  OUTD="$TREE/output/memory-consolidation"
}
cons() { run bash "$TREE/scripts/memory-consolidate.sh" "$@"; }
outfile() { ls "$OUTD"/*-"$1".jsonl; }

@test "uso: sin accion sale 2; accion desconocida sale 2; argumento desconocido sale 2" {
  mkenv; : > "$STORE_T"
  cons
  [ "$status" -eq 2 ]; [[ "$output" == *"usage:"* ]]
  cons bailar --store "$STORE_T"
  [ "$status" -eq 2 ]; [[ "$output" == *"acción desconocida 'bailar'"* ]]
  cons scan --store "$STORE_T" --raro
  [ "$status" -eq 2 ]; [[ "$output" == *"argumento desconocido '--raro'"* ]]
}

@test "store inexistente sale 2 con el path en el error y sin crear salida" {
  mkenv
  cons scan --store "$BATS_TEST_TMPDIR/nada.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"store no existe"* ]]
  [ ! -e "$OUTD" ]
}

@test "scan: frontera del umbral 0.85 (ratio 0.85 no es near-duplicate; 0.9 si)" {
  mkenv
  printf '%s\n' \
   '{"hash":"a","title":"A","content":"aaaaaaaaaaaaaaaaaaaa"}' \
   '{"hash":"b","title":"B","content":"aaaaaaaaaaaaaaaaabbb"}' > "$STORE_T"
  cons scan --store "$STORE_T"
  [[ "$output" == "scan: 0 candidato(s)"* ]]
  printf '%s\n' \
   '{"hash":"a","title":"A","content":"aaaaaaaaaaaaaaaaaaaa"}' \
   '{"hash":"b","title":"B","content":"aaaaaaaaaaaaaaaaaabb"}' > "$STORE_T"
  cons scan --store "$STORE_T"
  [[ "$output" == "scan: 1 candidato(s)"* ]]
  [ "$(jq -r '.type + " " + (.score|tostring)' "$(outfile scan)")" = "near_duplicate 0.9" ]
}

@test "scan: idénticas ignorando mayúsculas y espacios en los extremos; contenido vacío no cuenta" {
  mkenv
  printf '%s\n' \
   '{"hash":"a","title":"A","content":"  Hola Mundo  "}' \
   '{"hash":"b","title":"B","content":"hola mundo"}' \
   '{"hash":"c","title":"C","content":""}' \
   '{"hash":"d","title":"D"}' \
   '{"hash":"e","title":"E","content":"   "}' > "$STORE_T"
  cons scan --store "$STORE_T"
  [[ "$output" == "scan: 1 candidato(s)"* ]]
  [ "$(jq -r '.type + " " + (.score == 1 | tostring) + " " + .a.hash + .b.hash' "$(outfile scan)")" = "duplicate true ab" ]
}

@test "scan: lineas vacias o con JSON roto se ignoran sin abortar" {
  mkenv
  printf '%s\n' '{"hash":"a","content":"x uno"}' '' 'no es json' '{"hash":"b","content":"x uno"}' > "$STORE_T"
  cons scan --store "$STORE_T"
  [ "$status" -eq 0 ]
  [[ "$output" == "scan: 1 candidato(s)"* ]]
}

@test "link: cita de hash y cita de titulo (>12 caracteres) generan derived-from; no se enlaza a si misma" {
  mkenv
  printf '%s\n' \
   '{"hash":"abc123","title":"Nota raiz del gateway","content":"base"}' \
   '{"hash":"def456","title":"Otra","content":"deriva de abc123 sin mas"}' \
   '{"hash":"ghi789","title":"Tercera","content":"menciona la nota raiz del gateway aqui"}' > "$STORE_T"
  cons link --store "$STORE_T"
  [[ "$output" == "link: 2 candidato(s)"* ]]
  run jq -r '"\(.from)>\(.to):\(.reason)"' "$(outfile link)"
  [[ "$output" == *"def456>abc123:cites hash"* ]]
  [[ "$output" == *"ghi789>abc123:cites title"* ]]
}

@test "link: titulos de 12 caracteres o menos no generan enlace (frontera)" {
  mkenv
  printf '%s\n' \
   '{"hash":"h1","title":"123456789012","content":"base"}' \
   '{"hash":"h2","title":"Otra","content":"cita 123456789012 aqui"}' > "$STORE_T"
  cons link --store "$STORE_T"
  [[ "$output" == "link: 0 candidato(s)"* ]]
  printf '%s\n' \
   '{"hash":"h1","title":"1234567890123","content":"base"}' \
   '{"hash":"h2","title":"Otra","content":"cita 1234567890123 aqui"}' > "$STORE_T"
  cons link --store "$STORE_T"
  [[ "$output" == "link: 1 candidato(s)"* ]]
}

@test "link: los conceptos tambien cuentan como texto citable" {
  mkenv
  printf '%s\n' \
   '{"hash":"abc123","title":"Raiz","content":"base"}' \
   '{"hash":"def456","title":"Otra","content":"nada","concepts":["abc123"]}' > "$STORE_T"
  cons link --store "$STORE_T"
  [[ "$output" == "link: 1 candidato(s)"* ]]
}

@test "distill: grupos de 1 no generan insight; grupos de 2+ si, con conceptos ordenados y citas" {
  mkenv
  printf '%s\n' \
   '{"hash":"a","title":"A","topic_key":"t/uno","concepts":["zeta","alfa"]}' \
   '{"hash":"b","title":"B","topic_key":"t/uno","concepts":["alfa"]}' \
   '{"hash":"c","title":"C","topic_key":"t/solo"}' > "$STORE_T"
  cons distill --store "$STORE_T"
  [[ "$output" == "distill: 1 candidato(s)"* ]]
  f=$(outfile distill)
  [ "$(jq -r '.group' "$f")" = "t/uno" ]
  [ "$(jq -c '.concepts' "$f")" = '["alfa","zeta"]' ]
  [ "$(jq -c '.citations' "$f")" = '["a","b"]' ]
  [ "$(jq -r '.sources' "$f")" = "2" ]
}

@test "distill: sin topic_key agrupa por domain y luego por uncategorized" {
  mkenv
  printf '%s\n' \
   '{"hash":"a","domain":"infra"}' '{"hash":"b","domain":"infra"}' \
   '{"hash":"c"}' '{"hash":"d"}' > "$STORE_T"
  cons distill --store "$STORE_T"
  [[ "$output" == "distill: 2 candidato(s)"* ]]
  run jq -r '.group' "$(outfile distill)"
  [[ "$output" == *"infra"* && "$output" == *"uncategorized"* ]]
}

@test "prune: absorbed y tier D son candidatos con su razon; el resto no; nunca borra del store" {
  mkenv
  printf '%s\n' \
   '{"hash":"a","title":"A","quality":"absorbed"}' \
   '{"hash":"b","title":"B","importance_tier":"D"}' \
   '{"hash":"c","title":"C","importance_tier":"C"}' \
   '{"hash":"d","title":"D","quality":"verified"}' > "$STORE_T"
  before=$(cat "$STORE_T")
  cons prune --store "$STORE_T"
  [[ "$output" == "prune: 2 candidato(s)"* ]]
  run jq -r '"\(.hash):\(.reason):\(.dry_run)"' "$(outfile prune)"
  [[ "$output" == *"a:absorbed (fuente de insight):true"* ]]
  [[ "$output" == *"b:importancia tier D:true"* ]]
  [ "$(cat "$STORE_T")" = "$before" ]
}

@test "prune --apply marca dry_run=false pero tampoco modifica el store" {
  mkenv
  echo '{"hash":"a","title":"A","quality":"absorbed"}' > "$STORE_T"
  before=$(cat "$STORE_T")
  cons prune --store "$STORE_T" --apply
  [ "$(jq -r .dry_run "$(outfile prune)")" = "false" ]
  [ "$(cat "$STORE_T")" = "$before" ]
}

@test "absorbed gana a tier D cuando ambos se dan (una sola razon por nota)" {
  mkenv
  echo '{"hash":"a","quality":"absorbed","importance_tier":"D"}' > "$STORE_T"
  cons prune --store "$STORE_T"
  [[ "$output" == "prune: 1 candidato(s)"* ]]
  [ "$(jq -r .reason "$(outfile prune)")" = "absorbed (fuente de insight)" ]
}

@test "el fichero de salida lleva la fecha UTC y la accion en el nombre" {
  mkenv
  echo '{"hash":"a","quality":"absorbed"}' > "$STORE_T"
  cons prune --store "$STORE_T"
  [ -f "$OUTD/$(date -u +%Y%m%d)-prune.jsonl" ]
  [[ "$output" == *"/output/memory-consolidation/$(date -u +%Y%m%d)-prune.jsonl" ]]
}

@test "link: una nota que contiene su propio hash o su propio titulo no se enlaza a si misma" {
  mkenv
  printf '%s\n' \
   '{"hash":"abc123","title":"Titulo largo de la nota","content":"soy abc123 y el titulo largo de la nota"}' > "$STORE_T"
  cons link --store "$STORE_T"
  [[ "$output" == "link: 0 candidato(s)"* ]]
}

@test "distill: los conceptos salen ordenados alfabeticamente" {
  mkenv
  printf '%s\n' \
   '{"hash":"a","topic_key":"t","concepts":["mu","zeta","beta","omega","alfa","kappa"]}' \
   '{"hash":"b","topic_key":"t","concepts":["delta","gamma"]}' > "$STORE_T"
  cons distill --store "$STORE_T"
  [ "$(jq -c .concepts "$(outfile distill)")" = '["alfa","beta","delta","gamma","kappa","mu","omega","zeta"]' ]
}
