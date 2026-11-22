#!/usr/bin/env bats
# L13 F4 — meta-recalibra-ledger (recalibración desde señal real del bucle SCL)
# Linea: labs/roadmaps/l13-savia-metacognition.md (F4) / protocolo L13

RECAL="scripts/meta-recalibra-ledger.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
  cat > "$FIXDIR/lifecycle.jsonl" <<'EOF'
{"id":"LP-A","from":"proposed","to":"canary","actor":"agent","revert":"false"}
{"id":"LP-A","from":"canary","to":"active","actor":"operadora","revert":"false"}
{"id":"LP-B","from":"canary","to":"active","actor":"operadora","revert":"false"}
{"id":"LP-C","from":"proposed","to":"canary","actor":"agent","revert":"false"}
{"id":"LP-C","from":"canary","to":"proposed","actor":"operadora","revert":"true"}
EOF
}

teardown() {
  rm -rf "$FIXDIR"
}

@test "existe, bash -n, sin vendor cloud names, PURE_BASH" {
  [[ -x "$RECAL" ]]
  bash -n "$RECAL"
  run grep -niE "api\.openai\.com|api\.anthropic\.com|api\.deepseek\.com|api\.google\.com|api\.mistral\.ai" "$RECAL"
  [[ "$status" -ne 0 ]]
}

@test "sin dependencia meta-recalibrate → exit 3" {
  mkdir -p "$FIXDIR/empty"
  cp "$RECAL" "$FIXDIR/empty/r.sh"
  chmod +x "$FIXDIR/empty/r.sh"
  run bash "$FIXDIR/empty/r.sh" --ledger "$FIXDIR/lifecycle.jsonl" --calibration-file "$FIXDIR/cal.json"
  [[ "$status" -eq 3 ]]
  [[ "$output" == *"meta-recalibrate.sh"* ]]
}

@test "ledger ausente → exit 3 (no inventar señal)" {
  run bash "$RECAL" --ledger "$FIXDIR/no-existe.jsonl" --calibration-file "$FIXDIR/cal.json"
  [[ "$status" -eq 3 ]]
}

@test "F4: activacion humana canary→active = señal success; revert = fail" {
  run bash "$RECAL" --ledger "$FIXDIR/lifecycle.jsonl" \
    --calibration-file "$FIXDIR/cal.json" --predicted 70
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"signal_success=2"* ]]
  [[ "$output" == *"signal_fail=1"* ]]
  local runs
  runs=$(python3 -c "import json;d=json.load(open('$FIXDIR/cal.json'));print(len(d['runs']))")
  [[ "$runs" -eq 3 ]]
  python3 - "$FIXDIR/cal.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = sorted((r['task'].split(':')[-1], r['outcome']) for r in d['runs'])
assert out == [('LP-A', 'success'), ('LP-B', 'success'), ('LP-C', 'fail')], out
PY
}

@test "F4: señal escrita en curva alimenta meta-monitor (juicio recalibrado)" {
  bash "$RECAL" --ledger "$FIXDIR/lifecycle.jsonl" \
    --calibration-file "$FIXDIR/cal.json" --predicted 70 >/dev/null
  # tarea tipo default con curva nutrida → calibración leída por meta-monitor
  run bash scripts/meta-monitor.sh --task "default:LP-A" --confidence 80 \
    --divergence 0.2 --evidence 0.9 --calibration-file "$FIXDIR/cal.json"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import sys,json;d=json.load(sys.stdin);print('calib',d['calibration']);assert d['calibration']>0"
}

@test "CRIT-031: el conector solo escribe la curva, nunca toca CRITERIO/ledger" {
  local crit_before crit_after
  crit_before=$(sha256sum CRITERIO.md 2>/dev/null | cut -d' ' -f1)
  run bash "$RECAL" --ledger "$FIXDIR/lifecycle.jsonl" --calibration-file "$FIXDIR/cal.json"
  crit_after=$(sha256sum CRITERIO.md 2>/dev/null | cut -d' ' -f1)
  [[ "$crit_before" == "$crit_after" ]]
  # el ledger original queda intacto
  run python3 -c "
import hashlib
a=hashlib.sha256(open('$FIXDIR/lifecycle.jsonl','rb').read()).hexdigest()
b=hashlib.sha256(b'''{\"id\":\"LP-A\",\"from\":\"proposed\",\"to\":\"canary\",\"actor\":\"agent\",\"revert\":\"false\"}\n{\"id\":\"LP-A\",\"from\":\"canary\",\"to\":\"active\",\"actor\":\"operadora\",\"revert\":\"false\"}\n{\"id\":\"LP-B\",\"from\":\"canary\",\"to\":\"active\",\"actor\":\"operadora\",\"revert\":\"false\"}\n{\"id\":\"LP-C\",\"from\":\"proposed\",\"to\":\"canary\",\"actor\":\"agent\",\"revert\":\"false\"}\n{\"id\":\"LP-C\",\"from\":\"canary\",\"to\":\"proposed\",\"actor\":\"operadora\",\"revert\":\"true\"}\n''').hexdigest()
assert a==b, (a,b)
"
}

@test "input inválido (arg desconocido) → exit 2" {
  run bash "$RECAL" --bogus-flag x
  [[ "$status" -eq 2 ]]
}

@test "reproducible: dos runs → misma curva" {
  bash "$RECAL" --ledger "$FIXDIR/lifecycle.jsonl" --calibration-file "$FIXDIR/cal1.json" --predicted 70 >/dev/null
  bash "$RECAL" --ledger "$FIXDIR/lifecycle.jsonl" --calibration-file "$FIXDIR/cal2.json" --predicted 70 >/dev/null
  python3 -c "
import json
a=json.load(open('$FIXDIR/cal1.json')); b=json.load(open('$FIXDIR/cal2.json'))
# `ts` es la hora de cada ejecución (segundos): dos runs que cruzan un segundo difieren solo en ella
strip=lambda runs:[{k:v for k,v in r.items() if k!='ts'} for r in runs]
assert strip(a['runs'])==strip(b['runs']) and len(a['runs'])>0
"
}