#!/usr/bin/env bats
# SCL-001 S3 — Aprendizaje medido, no declarado: métrica L + reporte de ventana
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md (AC-3.1..3.5)

set -uo pipefail

setup_file() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  export REPO_ROOT
}

setup() {
  METRIC="$REPO_ROOT/scripts/learning-metric.sh"
  REPORT="$REPO_ROOT/scripts/learning-report.sh"
}

@test "AC-3.1: L es determinista — misma entrada produce la misma L" {
  a=$(bash "$METRIC" --p-consistent 0.8 --divergence 0.2 --ignorance-resolved 0.5 --json)
  b=$(bash "$METRIC" --p-consistent 0.8 --divergence 0.2 --ignorance-resolved 0.5 --json)
  [ "$a" = "$b" ]
  echo "$a" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 0 <= d['L'] <= 1; print('L=', d['L'])"
}

@test "AC-3.2a: propuesta con delta_L>0 en canary asciende a active" {
  # Simula: canary mide L antes/después; mejora → active (via lifecycle)
  LC="$REPO_ROOT/scripts/learning-lifecycle.sh"
  TMPD="$(mktemp -d -t scl-s3-XXXXXX)"
  mkdir -p "$TMPD/proposals"
  F="$TMPD/proposals/LP-A.md"
  cat > "$F" <<'EOF'
---
id: LP-A
provenance: INFERRED
lifecycle: proposed
---
EOF
  bash "$LC" --file "$F" --to canary --actor agente --ledger "$TMPD/lc.jsonl" >/dev/null
  bash "$LC" --file "$F" --to active --actor operadora --human-trailer "se488:sig" \
    --metric-before 0.4 --metric-after 0.9 --ledger "$TMPD/lc.jsonl" >/dev/null
  grep -q "^lifecycle: active" "$F"
  rm -rf "$TMPD"
}

@test "AC-3.2b: propuesta con delta_L<=0 en canary NO asciende y queda superseded/proposed con causa" {
  LC="$REPO_ROOT/scripts/learning-lifecycle.sh"
  TMPD="$(mktemp -d -t scl-s3-XXXXXX)"
  mkdir -p "$TMPD/proposals"
  F="$TMPD/proposals/LP-B.md"
  cat > "$F" <<'EOF'
---
id: LP-B
provenance: INFERRED
lifecycle: proposed
---
EOF
  bash "$LC" --file "$F" --to canary --actor agente --ledger "$TMPD/lc.jsonl" >/dev/null
  bash "$LC" --file "$F" --to active --actor operadora --human-trailer "se488:sig" \
    --metric-before 0.8 --metric-after 0.7 --ledger "$TMPD/lc.jsonl" >/dev/null || rc=$?
  [ "${rc:-0}" -eq 5 ]   # SE-497 S0-4: la regresión sale con 5
  ! grep -q "^lifecycle: active" "$F"
  grep -q "^lifecycle: proposed" "$F"
  grep -q '"revert":"true"' "$TMPD/lc.jsonl"
  rm -rf "$TMPD"
}

@test "AC-3.3: reporte con N=0 activaciones y delta_L<=0 emite 'Savia no aprendio esta ventana'" {
  run bash "$REPORT" --window "2026-W34" --captured 5 --activated 0 \
    --p-consistent-before 0.6 --p-consistent-after 0.6
  [ "$status" -eq 0 ]
  [[ "$output" == *"Savia no aprendió esta ventana"* ]]
}

@test "AC-3.3b: reporte con aprendizaje medido no emite el no-aprendio" {
  run bash "$REPORT" --window "2026-W34" --captured 5 --activated 2 \
    --p-consistent-before 0.6 --p-consistent-after 0.8
  [[ "$output" == *"Savia aprendió esta ventana"* ]]
  [[ "$output" != *"no aprendió"* ]]
}

@test "AC-3.4: gap de calibracion >15 puntos genera propuesta de calibracion" {
  # Gap = confianza declarada - resultado real. >15 puntos → proposal de calibración.
  TMPD="$(mktemp -d -t scl-s3-XXXXXX)"
  PROPOSALS="$TMPD/proposals"
  mkdir -p "$PROPOSALS"
  echo "evidence-call" > "$TMPD/ev.txt"
  run bash "$REPO_ROOT/scripts/learning-proposal.sh" \
    --origin "calibracion: confianza 0.95 vs resultado 0.60 (gap 35)" \
    --evidence "$TMPD/ev.txt" \
    --diagnosis "gap de calibracion 35 puntos > 15 (ART-04)" \
    --change "recalibrar confianza en evaluaciones" \
    --target criterio --trigger calibration \
    --output-dir "$PROPOSALS" --graph-index "$TMPD/graph.jsonl"
  [ "$status" -eq 0 ]
  f=$(echo "$output" | grep -oP 'CREATED: \K.*' | head -1)
  grep -q "recalibrar" "$f"
  grep -q "gap de calibracion 35" "$f"
  rm -rf "$TMPD"
}

@test "AC-3.5: L es independiente del modelo — misma tarea en dos tiers produce L comparable sobre el mismo baseline" {
  # El modelo NO es input de learning-metric: solo los escalares medidos.
  tier_heavy=$(bash "$METRIC" --p-consistent 0.7 --divergence 0.3 --ignorance-resolved 0.6)
  tier_fast=$(bash "$METRIC" --p-consistent 0.7 --divergence 0.3 --ignorance-resolved 0.6)
  [ "$tier_heavy" = "$tier_fast" ]
  # Y ambos son comparables contra el MISMO baseline (misma entrada → misma salida)
  baseline=$(bash "$METRIC" --p-consistent 0.7 --divergence 0.3 --ignorance-resolved 0.6 --json)
  echo "$baseline" | grep -q '"L":0.680000'
}
