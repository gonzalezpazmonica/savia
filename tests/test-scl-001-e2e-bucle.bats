#!/usr/bin/env bats
# SCL-001 E2E — Bucle cerrado: error sintetico → propuesta (S1) → canary (S2) →
# medicion ΔL (S3) → activacion o reversion con registro.
# Verification Method #1 de la spec.
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md

set -uo pipefail

setup_file() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  export REPO_ROOT
}

setup() {
  TMPD="$(mktemp -d -t scl-e2e-XXXXXX)"
  mkdir -p "$TMPD/proposals" "$TMPD/ledger"
}

teardown() {
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
}

@test "E2E: error sintetico recorre el bucle y se revierte con causa" {
  PROP="$REPO_ROOT/scripts/learning-proposal.sh"
  LC="$REPO_ROOT/scripts/learning-lifecycle.sh"
  METRIC="$REPO_ROOT/scripts/learning-metric.sh"

  echo "bug-report-data" > "$TMPD/ev.txt"
  run bash "$PROP" --origin "ledger reconoce error recurrente R-042" \
    --evidence "$TMPD/ev.txt" \
    --diagnosis "la regla X reintroduce el error" \
    --change "reforzar regla X con post-condicion" \
    --target criterio --trigger recurrence \
    --output-dir "$TMPD/proposals" --graph-index "$TMPD/graph.jsonl"
  [ "$status" -eq 0 ]
  f=$(ls "$TMPD/proposals/"*.md)
  [ -f "$f" ]
  grep -q "^lifecycle: proposed" "$f"
  grep -q "^trigger: recurrence" "$f"

  run bash "$LC" --file "$f" --to canary --actor agente --ledger "$TMPD/lc.jsonl"
  [ "$status" -eq 0 ]
  grep -q "^lifecycle: canary" "$f"

  base=$(bash "$METRIC" --p-consistent 0.7 --divergence 0.2 --ignorance-resolved 0.6 --json | grep -o '"L":[0-9.]*' | cut -d: -f2)
  after=$(bash "$METRIC" --p-consistent 0.85 --divergence 0.2 --ignorance-resolved 0.6 --json | grep -o '"L":[0-9.]*' | cut -d: -f2)
  awk -v a="$after" -v b="$base" 'BEGIN{exit !(a>b)}'

  run bash "$LC" --file "$f" --to active --actor operadora --human-trailer "se488:op-e2e-sig" \
    --metric-before "$base" --metric-after "$after" --ledger "$TMPD/lc.jsonl"
  [ "$status" -eq 0 ]
  grep -q "^lifecycle: active" "$f"
  grep -q "^provenance: human_authored" "$f"

  run bash "$REPO_ROOT/scripts/learning-rollback.sh" --file "$f" \
    --reason "regresion detectada" \
    --p-before 0.85 --p-after 0.4 --ledger "$TMPD/rb.jsonl" --no-git
  [ "$status" -eq 0 ]
  grep -q "^lifecycle: proposed" "$f"
  [ -f "$TMPD/rb.jsonl" ]
  grep -q "regresion detectada" "$TMPD/rb.jsonl"
}

@test "E2E adversarial: activacion sin trailer humano se bloquea" {
  PROP="$REPO_ROOT/scripts/learning-proposal.sh"
  LC="$REPO_ROOT/scripts/learning-lifecycle.sh"
  echo "ev" > "$TMPD/ev.txt"
  bash "$PROP" --origin "o" --evidence "$TMPD/ev.txt" --diagnosis "d" --change "c" \
    --target skill --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  f=$(ls "$TMPD/proposals/"*.md)
  bash "$LC" --file "$f" --to canary --actor agente --ledger "$TMPD/lc.jsonl" >/dev/null
  run bash "$LC" --file "$f" --to active --actor agente --ledger "$TMPD/lc.jsonl" --strict
  [ "$status" -ne 0 ]
  ! grep -q "^lifecycle: active" "$f"
}

@test "E2E: reporte de ventana cierra el bucle con aprendizaje medido" {
  REPORT="$REPO_ROOT/scripts/learning-report.sh"
  run bash "$REPORT" --window "e2e-W" --captured 3 --activated 1 \
    --p-consistent-before 0.6 --p-consistent-after 0.8 --json
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"learned":true'
}
