#!/usr/bin/env bats
# test-se355-audit-receipts.bats — BATS tests for SE-355 Audit Ledger metadata-only
# Ref: SE-355 — decision receipts con `enforced`, metadata-only, retention 30d

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LEDGER="$REPO_ROOT/scripts/audit-receipts.sh"
  export LEDGER
  # Ledger aislado por test
  export SAVIA_AUDIT_DIR="$(mktemp -d)"
}

teardown() {
  if [[ -d "${SAVIA_AUDIT_DIR:-}" ]]; then
    rm -rf "$SAVIA_AUDIT_DIR"
  fi
}

# ── T1: write / schema ────────────────────────────────────────────────────────

@test "write crea receipt con seq incrementado" {
  run "$LEDGER" write --action gate_deny --actor agente-x --outcome enforced_deny --gate G13 --session s1
  [[ "$status" -eq 0 ]]
  run "$LEDGER" write --action commit --actor agente-x --outcome success --session s2
  [[ "$status" -eq 0 ]]
  run grep -q '"seq":1' "$SAVIA_AUDIT_DIR/actions.jsonl"
  [[ "$status" -eq 0 ]]
  run grep -q '"seq":2' "$SAVIA_AUDIT_DIR/actions.jsonl"
  [[ "$status" -eq 0 ]]
}

@test "write con gate → enforced=true" {
  "$LEDGER" write --action gate_deny --actor a --outcome enforced_deny --gate G13 --session s >/dev/null
  run grep -q '"enforced":true' "$SAVIA_AUDIT_DIR/actions.jsonl"
  [[ "$status" -eq 0 ]]
}

@test "write sin gate → enforced=false" {
  "$LEDGER" write --action commit --actor a --outcome success --session s >/dev/null
  run grep -q '"enforced":false' "$SAVIA_AUDIT_DIR/actions.jsonl"
  [[ "$status" -eq 0 ]]
}

@test "write sin action/actor → error" {
  run "$LEDGER" write --action solo
  [[ "$status" -ne 0 ]]
}

@test "write outcome inválido → error" {
  run "$LEDGER" write --action x --actor a --outcome inventado
  [[ "$status" -ne 0 ]]
}

# ── T2: metadata-only (AC-0) ──────────────────────────────────────────────────

@test "ledger nunca contiene prompts/bodies/args" {
  "$LEDGER" write --action commit --actor a --outcome success --session s >/dev/null
  run grep -qE 'prompt|body|argument|filename|content|tool_input' "$SAVIA_AUDIT_DIR/actions.jsonl"
  [[ "$status" -ne 0 ]]
}

# ── T3: governed (AC-1) ───────────────────────────────────────────────────────

@test "governed solo devuelve enforced=true" {
  "$LEDGER" write --action gate_deny --actor a --outcome enforced_deny --gate G13 --session s >/dev/null
  "$LEDGER" write --action commit --actor a --outcome success --session s >/dev/null
  run "$LEDGER" governed
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"G13"* ]]
  [[ "$output" != *'"outcome":"success"'* ]]
}

# ── T4: query filtros ─────────────────────────────────────────────────────────

@test "query --gate filtra por gate" {
  "$LEDGER" write --action gate_deny --actor a --outcome enforced_deny --gate G13 --session s >/dev/null
  "$LEDGER" write --action gate_deny --actor a --outcome enforced_deny --gate G5 --session s >/dev/null
  run "$LEDGER" query --gate G13 --all
  [[ "$output" == *"G13"* ]]
  [[ "$output" != *'"gate_id":"G5"'* ]]
}

@test "query --actor filtra por actor" {
  "$LEDGER" write --action commit --actor alice --outcome success --session s >/dev/null
  "$LEDGER" write --action commit --actor bob --outcome success --session s >/dev/null
  run "$LEDGER" query --actor alice --all
  [[ "$output" == *"alice"* ]]
  [[ "$output" != *"bob"* ]]
}

@test "query --days excluye registros viejos" {
  # escribe receipt con ts antiguo directamente
  mkdir -p "$SAVIA_AUDIT_DIR"
  printf '{"seq":1,"ts":"2020-01-01T00:00:00Z","session_id":"s","actor":"old","action":"commit","outcome":"success","enforced":false,"gate_id":"null"}\n' >> "$SAVIA_AUDIT_DIR/actions.jsonl"
  printf '{"seq":2,"ts":"%s","session_id":"s","actor":"new","action":"commit","outcome":"success","enforced":false,"gate_id":"null"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SAVIA_AUDIT_DIR/actions.jsonl"
  run "$LEDGER" query
  [[ "$output" == *"new"* ]]
  [[ "$output" != *"old"* ]]
}

# ── T5: prune (AC-4) ──────────────────────────────────────────────────────────

@test "prune borra en batch solo registros expirables" {
  mkdir -p "$SAVIA_AUDIT_DIR"
  printf '{"seq":1,"ts":"2020-01-01T00:00:00Z","session_id":"s","actor":"old","action":"commit","outcome":"success","enforced":false,"gate_id":"null"}\n' >> "$SAVIA_AUDIT_DIR/actions.jsonl"
  printf '{"seq":2,"ts":"%s","session_id":"s","actor":"new","action":"commit","outcome":"success","enforced":false,"gate_id":"null"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SAVIA_AUDIT_DIR/actions.jsonl"
  run "$LEDGER" prune --days 30
  [[ "$status" -eq 0 ]]
  run grep -q '"actor":"old"' "$SAVIA_AUDIT_DIR/actions.jsonl"
  [[ "$status" -ne 0 ]]
  run grep -q '"actor":"new"' "$SAVIA_AUDIT_DIR/actions.jsonl"
  [[ "$status" -eq 0 ]]
}

# ── T6: stats ─────────────────────────────────────────────────────────────────

@test "stats reporta resumen" {
  "$LEDGER" write --action gate_deny --actor a --outcome enforced_deny --gate G13 --session s >/dev/null
  "$LEDGER" write --action commit --actor a --outcome success --session s >/dev/null
  run "$LEDGER" stats
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"2 receipts"* ]]
  [[ "$output" == *"1"* ]]  # alguna métrica numérica
}

# ── Comportamiento: formato exacto, filtros combinados, ventanas y contadores ─

seed() {  # seed <ts> <actor> <action> <outcome> [gate]
  local gate="${5:-}" enforced=false
  [[ -n "$gate" ]] && enforced=true
  mkdir -p "$SAVIA_AUDIT_DIR"
  printf '{"seq":0,"ts":"%s","session_id":"s","actor":"%s","action":"%s","outcome":"%s","enforced":%s,"gate_id":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$enforced" "${gate:-null}" >> "$SAVIA_AUDIT_DIR/actions.jsonl"
}
ago() { date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%SZ; }

@test "write: línea de confirmación exacta sin y con gate" {
  run "$LEDGER" write --action commit --actor ana --outcome failure
  [ "$output" = "receipt 1: commit (ana) → failure" ]
  run "$LEDGER" write --action push --actor ana --outcome enforced_deny --gate G13
  [ "$output" = "receipt 2: push (ana) → enforced_deny via G13" ]
}

@test "write: el registro guarda todos los campos con sus valores y sesión por defecto unknown" {
  "$LEDGER" write --action commit --actor ana --outcome enforced_allow --gate G5 >/dev/null
  python3 - "$SAVIA_AUDIT_DIR/actions.jsonl" <<'EOP'
import json, re, sys
d = json.loads(open(sys.argv[1]).readline())
assert d["seq"] == 1 and d["actor"] == "ana" and d["action"] == "commit", d
assert d["outcome"] == "enforced_allow" and d["enforced"] is True and d["gate_id"] == "G5", d
assert d["session_id"] == "unknown", d
assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", d["ts"]), d["ts"]
EOP
}

@test "write: sin gate -> gate_id null y enforced false; el outcome por defecto es success" {
  "$LEDGER" write --action commit --actor ana --session s9 >/dev/null
  grep -q '"outcome":"success","enforced":false,"gate_id":"null"' "$SAVIA_AUDIT_DIR/actions.jsonl"
  grep -q '"session_id":"s9"' "$SAVIA_AUDIT_DIR/actions.jsonl"
}

@test "write: acepta cada outcome válido y rechaza otros sin escribir nada" {
  local o
  for o in enforced_deny enforced_allow success failure; do
    run "$LEDGER" write --action a --actor b --outcome "$o"
    [ "$status" -eq 0 ]
  done
  [ "$(wc -l < "$SAVIA_AUDIT_DIR/actions.jsonl")" -eq 4 ]
  run "$LEDGER" write --action a --actor b --outcome denied
  [ "$status" -eq 1 ]
  [[ "$output" == *"inválido"* ]]
  [ "$(wc -l < "$SAVIA_AUDIT_DIR/actions.jsonl")" -eq 4 ]
}

@test "write: falta action o actor -> exit 1 con uso y sin ledger" {
  run "$LEDGER" write --actor b
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso: audit-receipts.sh write"* ]]
  run "$LEDGER" write --action a
  [ "$status" -eq 1 ]
  [ ! -e "$SAVIA_AUDIT_DIR/actions.jsonl" ]
}

@test "write: la secuencia continúa desde el fichero .seq" {
  mkdir -p "$SAVIA_AUDIT_DIR"; printf '41' > "$SAVIA_AUDIT_DIR/.seq"
  run "$LEDGER" write --action a --actor b
  [[ "$output" == "receipt 42:"* ]]
  [ "$(cat "$SAVIA_AUDIT_DIR/.seq")" = "42" ]
}

@test "write: si no se puede crear el directorio del ledger -> exit 1" {
  : > "$SAVIA_AUDIT_DIR/fichero"
  SAVIA_AUDIT_DIR="$SAVIA_AUDIT_DIR/fichero/sub" run "$LEDGER" write --action a --actor b
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se puede crear"* ]]
}

@test "ayuda: sin argumentos, help y un modo desconocido imprimen el uso con exit 0" {
  run "$LEDGER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"audit-receipts.sh {write|query|governed|prune|stats}"* ]]
  run "$LEDGER" bogus
  [ "$status" -eq 0 ]
  [[ "$output" == *"prune [--days N]"* ]]
}

@test "modos de lectura sin ledger responden Ledger vacío con exit 0" {
  local m
  for m in query governed prune stats; do
    run "$LEDGER" "$m"
    [ "$status" -eq 0 ]
    [[ "$output" == "Ledger vacío: "* ]]
  done
}

@test "query: --action filtra y combina con --actor (AND)" {
  seed "$(ago 1)" ana commit success
  seed "$(ago 1)" ana push success
  seed "$(ago 1)" bob commit success
  run "$LEDGER" query --action commit
  [[ "$output" == *'"actor":"ana"'* && "$output" == *'"actor":"bob"'* ]]
  [[ "$output" != *'"action":"push"'* ]]
  run bash -c "'$LEDGER' query --action commit --actor ana 2>&1"
  [[ "$output" == *"(1 receipts)"* ]]
  [[ "$output" != *'"actor":"bob"'* ]]
}

@test "query: el recuento va por stderr y las líneas por stdout" {
  seed "$(ago 1)" ana commit success
  seed "$(ago 2)" ana commit success
  out=$("$LEDGER" query 2>/dev/null)
  [ "$(echo "$out" | wc -l)" -eq 2 ]
  [[ "$out" != *"receipts)"* ]]
  err=$("$LEDGER" query 2>&1 >/dev/null)
  [ "$err" = "(2 receipts)" ]
}

@test "query: ventana por defecto 30 días; --days la cambia; --all ignora el corte" {
  seed "$(ago 40)" viejo commit success
  seed "$(ago 20)" medio commit success
  seed "$(ago 1)" nuevo commit success
  run "$LEDGER" query
  [[ "$output" != *viejo* && "$output" == *medio* && "$output" == *nuevo* ]]
  run "$LEDGER" query --days 10
  [[ "$output" != *viejo* && "$output" != *medio* && "$output" == *nuevo* ]]
  run "$LEDGER" query --days 60
  [[ "$output" == *viejo* && "$output" == *medio* ]]
  run "$LEDGER" query --all
  [[ "$output" == *viejo* && "$output" == *medio* && "$output" == *nuevo* ]]
}

@test "query: el filtro de gate no confunde registros sin gate (null)" {
  seed "$(ago 1)" ana commit success
  seed "$(ago 1)" ana push enforced_deny G13
  run bash -c "'$LEDGER' query --gate G13 2>&1"
  [[ "$output" == *"(1 receipts)"* ]]
  run bash -c "'$LEDGER' query --gate null 2>&1"
  [[ "$output" == *"(0 receipts)"* ]]
}

@test "governed: solo enforced=true, una línea por receipt gobernado" {
  seed "$(ago 1)" ana commit success
  seed "$(ago 1)" ana push enforced_deny G13
  seed "$(ago 1)" bob push enforced_allow G5
  run "$LEDGER" governed
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *G13* && "$output" == *G5* && "$output" != *'"enforced":false'* ]]
}

@test "prune: respeta --days, informa de borrados y conservados y deja los recientes" {
  seed "$(ago 40)" a commit success
  seed "$(ago 20)" b commit success
  seed "$(ago 1)" c commit success
  run "$LEDGER" prune --days 30
  [ "$output" = "Pruned 1 receipts (older than 30d), kept 2." ]
  run "$LEDGER" prune --days 5
  [ "$output" = "Pruned 1 receipts (older than 5d), kept 1." ]
  [ "$(wc -l < "$SAVIA_AUDIT_DIR/actions.jsonl")" -eq 1 ]
  grep -q '"actor":"c"' "$SAVIA_AUDIT_DIR/actions.jsonl"
}

@test "prune: sin nada expirable no toca el fichero y lo dice" {
  seed "$(ago 1)" a commit success
  seed "$(ago 2)" b commit success
  cp "$SAVIA_AUDIT_DIR/actions.jsonl" "$SAVIA_AUDIT_DIR/antes"
  run "$LEDGER" prune
  [ "$output" = "No receipts to prune (30d window). Kept 2." ]
  cmp "$SAVIA_AUDIT_DIR/actions.jsonl" "$SAVIA_AUDIT_DIR/antes"
}

@test "stats: contadores exactos por outcome y gobernadas" {
  seed "$(ago 1)" a x enforced_deny G1
  seed "$(ago 1)" a x enforced_deny G1
  seed "$(ago 1)" a x enforced_allow G2
  seed "$(ago 1)" a x success
  seed "$(ago 1)" a x success
  seed "$(ago 1)" a x success
  seed "$(ago 1)" a x failure
  run "$LEDGER" stats
  [ "${lines[0]}" = "Audit ledger: 7 receipts" ]
  [ "${lines[1]}" = "  gobernadas (enforced=true): 3" ]
  [ "${lines[2]}" = "  enforced_deny: 2 | enforced_allow: 1" ]
  [ "${lines[3]}" = "  success: 3 | failure: 1" ]
}

@test "stats: categorías sin registros salen como 0, no vacías" {
  seed "$(ago 1)" a x success
  run "$LEDGER" stats
  [ "${lines[1]}" = "  gobernadas (enforced=true): 0" ]
  [ "${lines[2]}" = "  enforced_deny: 0 | enforced_allow: 0" ]
  [ "${lines[3]}" = "  success: 1 | failure: 0" ]
}
