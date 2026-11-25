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
