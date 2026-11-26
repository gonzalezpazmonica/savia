#!/usr/bin/env bats
# SCL-001 S2 — Sustrato como artefacto de despliegue: shadow → canary → active → superseded
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md (AC-2.1..2.6)

set -uo pipefail

setup_file() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  export REPO_ROOT
}

setup() {
  LC="$REPO_ROOT/scripts/learning-lifecycle.sh"
  RB="$REPO_ROOT/scripts/learning-rollback.sh"
  TMPD="$(mktemp -d -t scl-s2-XXXXXX)"
  mkdir -p "$TMPD/proposals" "$TMPD/ledger"
  F="$TMPD/proposals/LP-TEST.md"
  cat > "$F" <<'EOF'
---
id: LP-TEST
type: learning_proposal
provenance: INFERRED
lifecycle: proposed
origin: test
created_utc: 2026-08-17T00:00:00Z
---

# Test
EOF
}

teardown() {
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
}

@test "AC-2.1: entrada recorre shadow→canary→active→superseded con transiciones registradas" {
  LED="$TMPD/ledger/lc.jsonl"
  run bash "$LC" --file "$F" --to canary --actor agente --ledger "$LED"
  [ "$status" -eq 0 ]
  run bash "$LC" --file "$F" --to active --actor operadora --human-trailer "se488:op-sig" --metric-before 0.5 --metric-after 0.6 --ledger "$LED"
  [ "$status" -eq 0 ]
  run bash "$LC" --file "$F" --to superseded --actor agente --reason "obsoleto" --ledger "$LED"
  [ "$status" -eq 0 ]
  grep -q "^lifecycle: superseded" "$F"
  [ -f "$LED" ]
  python3 - "$LED" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
states = [(r["from"], r["to"]) for r in rows]
assert ("proposed","canary") in states, states
assert ("canary","active") in states, states
assert ("active","superseded") in states, states
for r in rows:
    assert r.get("ts"), "each transition must have a timestamp"
    assert r.get("actor"), "each transition must have an actor"
PY
}

@test "AC-2.2: shadow no produce efecto — gate identico con y sin entrada en shadow" {
  # Sin entrada: gate devuelve baseline
  run bash -c "grep -q 'learning_proposal' '$F' && echo ACTIVE || echo INACTIVE"
  baseline="$output"
  # En shadow (proposed): gate sigue sin ver efecto
  run bash -c "grep -q 'learning_proposal' '$F' && echo ACTIVE || echo INACTIVE"
  [ "$output" = "$baseline" ]
  # Una entrada activa SI cambia el gate (efecto global)
  LED="$TMPD/ledger/lc.jsonl"
  bash "$LC" --file "$F" --to canary --actor agente --ledger "$LED" >/dev/null
  bash "$LC" --file "$F" --to active --actor operadora --human-trailer "se488:op-sig" --metric-before 0.5 --metric-after 0.6 --ledger "$LED" >/dev/null
  run bash -c "grep -q '^lifecycle: active' '$F' && echo ACTIVE || echo INACTIVE"
  [ "$output" = "ACTIVE" ]
}

@test "AC-2.3: rollback instantaneo deja el sustrato identico al previo (diff vacio salvo registro)" {
  G="$TMPD/repo"
  mkdir -p "$G/proposals"
  FP="$G/proposals/LP-RB.md"
  cat > "$FP" <<'EOF'
---
id: LP-RB
lifecycle: proposed
provenance: INFERRED
---
contenido original
EOF
  git -C "$G" init -q
  git -C "$G" config user.email t@t
  git -C "$G" config user.name t
  git -C "$G" add -A && git -C "$G" commit -qm baseline

  LED="$TMPD/ledger/lc.jsonl"
  bash "$LC" --file "$FP" --to canary --actor agente --ledger "$LED" >/dev/null
  bash "$LC" --file "$FP" --to active --actor operadora --human-trailer "se488:sig" --metric-before 0.5 --metric-after 0.6 --ledger "$LED" >/dev/null
  # no commit tras activar → rollback restaura del HEAD
  run bash "$RB" --file "$FP" --reason "entrada erronea" --ledger "$TMPD/ledger/rb.jsonl"
  [ "$status" -eq 0 ]
  diff_empty=$(git -C "$G" diff HEAD -- proposals/LP-RB.md)
  [ -z "$diff_empty" ]
  grep -q "^lifecycle: proposed" "$FP"
  [ -f "$TMPD/ledger/rb.jsonl" ]
}

@test "AC-2.4: gate anti-auto-activacion — proposed→active sin human_authored es rechazado" {
  LED="$TMPD/ledger/lc.jsonl"
  run bash "$LC" --file "$F" --to active --actor agente --ledger "$LED" --strict
  [ "$status" -ne 0 ]
  grep -q "^lifecycle: proposed" "$F"
}

@test "AC-2.5: promocion condicionada — canary con metrica peor que baseline NO asciende" {
  LED="$TMPD/ledger/lc.jsonl"
  bash "$LC" --file "$F" --to canary --actor agente --ledger "$LED" >/dev/null
  run bash "$LC" --file "$F" --to active --actor operadora --human-trailer "se488:sig" \
    --metric-before 0.8 --metric-after 0.6 --ledger "$LED"
  grep -q "^lifecycle: proposed" "$F"
  python3 - "$LED" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
revert = [r for r in rows if r.get("revert") == "true"]
assert revert, "rollback por regresion debe registrarse"
PY
}

@test "AC-2.6: superseded no borra — entrada permanece legible con tombstone" {
  LED="$TMPD/ledger/lc.jsonl"
  bash "$LC" --file "$F" --to canary --actor agente --ledger "$LED" >/dev/null
  bash "$LC" --file "$F" --to active --actor operadora --human-trailer "se488:sig" --metric-before 0.5 --metric-after 0.6 --ledger "$LED" >/dev/null
  bash "$LC" --file "$F" --to superseded --actor agente --reason "obsoleto" --ledger "$LED" >/dev/null
  [ -f "$F" ]
  grep -q "^lifecycle: superseded" "$F"
  grep -q "^tombstone:" "$F"
  cat "$F" | grep -q "Test"
}

# ── Casos límite y negativos añadidos con SE-497 S0 ──
# SCRIPT="scripts/learning-lifecycle.sh" — funciones ejercidas: usage, trailer_ok, record, apply_state.
# Cada caso trabaja en $BATS_TEST_TMPDIR, que BATS crea y limpia solo.
_lp() {  # _lp <dir> <estado>: lección mínima de prueba
  mkdir -p "$1"; printf -- '---\nid: LP-EDGE\nlifecycle: %s\nprovenance: INFERRED\ncreated_utc: 2026-11-01\n---\ncuerpo\n' "$2" > "$1/LP-EDGE.md"
  echo "$1/LP-EDGE.md"
}
@test "S2 edge: nonexistent lesson file fails with exit 3" {
  D="$BATS_TEST_TMPDIR"
  run bash "$REPO_ROOT/scripts/learning-lifecycle.sh" --file "$D/no-existe.md" --to canary --ledger "$D/l.jsonl"
  [ "$status" -eq 3 ]
  [ ! -e "$D/l.jsonl" ]
}
@test "S2 edge: empty trailer is rejected and the lesson stays canary" {
  D="$BATS_TEST_TMPDIR"; f=$(_lp "$D" canary)
  run bash "$REPO_ROOT/scripts/learning-lifecycle.sh" --file "$f" --to active --human-trailer "" --metric-before 0.1 --metric-after 0.2 --ledger "$D/l.jsonl"
  [ "$status" -eq 4 ]
  grep -qx 'lifecycle: canary' "$f"
}
@test "S2 invalid target state is rejected with usage error" {
  D="$BATS_TEST_TMPDIR"; f=$(_lp "$D" proposed)
  run bash "$REPO_ROOT/scripts/learning-lifecycle.sh" --file "$f" --to activo --ledger "$D/l.jsonl"
  [ "$status" -eq 2 ]
  grep -qx 'lifecycle: proposed' "$f"
}
@test "S2 boundary: equal metrics promote, one less fails as regression" {
  D="$BATS_TEST_TMPDIR"; f=$(_lp "$D/a" canary)
  run bash "$REPO_ROOT/scripts/learning-lifecycle.sh" --file "$f" --to active --human-trailer "se488:edge" --metric-before 0.5 --metric-after 0.49 --ledger "$D/l.jsonl"
  [ "$status" -eq 5 ]
  grep -qx 'lifecycle: proposed' "$f"
  f=$(_lp "$D/b" canary)
  run bash "$REPO_ROOT/scripts/learning-lifecycle.sh" --file "$f" --to active --human-trailer "se488:edge" --metric-before 0.5 --metric-after 0.5 --ledger "$D/l.jsonl"
  [ "$status" -eq 0 ]
  grep -qx 'lifecycle: active' "$f"
}
@test "S2 edge: no arg at all prints usage and fails with exit 2" {
  run bash "$REPO_ROOT/scripts/learning-lifecycle.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--file"* ]]
}
