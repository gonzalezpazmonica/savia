#!/usr/bin/env bats
# SE-334 S1/S2 — fingerprint determinista + issues + alertas
# Spec: docs/specs/SE-334-telemetry-intelligence.spec.md (AC-1.x, AC-2.x, AC-5.x)
# Nota: IPs de ejemplo uso IPs de documentación RFC 5737 (192.0.2.x) — nunca
# direcciones privadas reales (crédito: shield-confidencialidad).

FP="scripts/telemetry-fingerprint.py"
ISSUES="scripts/telemetry-issues.sh"
ALERT="scripts/telemetry-alert.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$FIXDIR"
}

event() {
  cat > "$FIXDIR/ev.json" << EOF
{"exception_type":"$1","message":"$2","error":{"exc_chain":[{"loc":["x"],"exc_type":"$1","message":"$2 $3"}]}}
EOF
}

@test "AC-1.1: mismo error con IDs/URLs/timestamps distintos → MISMO fingerprint" {
  event "DispatchError" "failed to dispatch request 550e8400-e29b-41d4-a716-446655440000" "at https://192.0.2.1:8443 2026-08-22T10:00:00Z"
  local a; a=$(python3 scripts/telemetry-fingerprint.py "$FIXDIR/ev.json")
  event "DispatchError" "failed to dispatch request 123e4567-e89b-12d3-a456-426614174000" "at https://192.0.2.2:8443 2026-08-22T11:30:00Z"
  local b; b=$(python3 scripts/telemetry-fingerprint.py "$FIXDIR/ev.json")
  [[ "$(echo "$a" | python3 -c "import sys,json;print(json.load(sys.stdin)['hash'])")" == \
     "$(echo "$b" | python3 -c "import sys,json;print(json.load(sys.stdin)['hash'])")" ]]
}

@test "AC-1.2: errores distintos → fingerprints distintos" {
  event "DispatchError" "failed to dispatch request 550e8400-e29b-41d4-a716-446655440000" "at https://192.0.2.1:8443"
  local a; a=$(python3 scripts/telemetry-fingerprint.py "$FIXDIR/ev.json")
  event "TimeoutError" "timed out after 30000ms waiting for generation" "at https://api.local"
  local b; b=$(python3 scripts/telemetry-fingerprint.py "$FIXDIR/ev.json")
  [[ "$(echo "$a" | python3 -c "import sys,json;print(json.load(sys.stdin)['hash'])")" != \
     "$(echo "$b" | python3 -c "import sys,json;print(json.load(sys.stdin)['hash'])")" ]]
}

@test "AC-1.3: otel-emit.sh --fingerprint adjunta hash + bucket" {
  SAVIA_TELEMETRY_FILE="$FIXDIR/evt.jsonl" SAVIA_FINGERPRINT=1 \
    bash scripts/otel-emit.sh dispatch.failed agent_name=explore \
      error="failed to dispatch request 550e8400-e29b-41d4-a716-446655440000"
  run bash -c "cat '$FIXDIR/evt.jsonl' | python3 -c \"import sys,json;d=json.load(sys.stdin);print('x' if d.get('fingerprint',{}).get('hash') else '')\""
  [[ "$output" == "x" ]]
}

@test "AC-1.4: el fingerprint redacta — sin URLs/IPs/UUIDs crudos en hash ni bucket" {
  event "DispatchError" "connect to https://192.0.2.1:8443 refused for request 550e8400-e29b-41d4-a716-446655440000 at 2026-08-22T10:00:00Z" ""
  local out; out=$(python3 scripts/telemetry-fingerprint.py "$FIXDIR/ev.json")
  echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
blob = d['bucket'] + d['hash']
for bad in ['192.0.2.1','550e8400','api.','2026-08']:
    assert bad not in blob, f'leak: {bad}'
"
}

@test "AC-1.5: determinista — misma entrada → misma huella (100 iteraciones)" {
  event "DispatchError" "failed to dispatch request 550e8400-e29b-41d4-a716-446655440000" "at https://192.0.2.1:8443"
  local ref; ref=$(python3 scripts/telemetry-fingerprint.py "$FIXDIR/ev.json")
  local i h
  for i in $(seq 1 100); do
    h=$(python3 scripts/telemetry-fingerprint.py "$FIXDIR/ev.json")
    [[ "$ref" == "$h" ]] || return 1
  done
}

@test "AC-2.1: issues agrupa N eventos idénticos en 1 issue con count=N" {
  event "DispatchError" "failed to dispatch request 550e8400-e29b-41d4-a716-446655440000" "at https://192.0.2.1:8443"
  local evf="$FIXDIR/events.jsonl"
  for i in 1 2 3 4 5 6; do
    python3 -c "
import json
ev=json.load(open('$FIXDIR/ev.json'))
from importlib.machinery import SourceFileLoader
fp=SourceFileLoader('f','scripts/telemetry-fingerprint.py').load_module()
ev['fingerprint']=fp.fingerprint(ev)
ev['ts']='2026-08-22T10:0${i}:00Z'
print(json.dumps(ev))" >> "$evf"
  done
  TEL_FP_EVENTS="$evf" TEL_FP_ISSUES="$FIXDIR/issues.jsonl" bash "$ISSUES" >/dev/null
  run bash -c "head -1 '$FIXDIR/issues.jsonl' | python3 -c \"import sys,json;print(json.load(sys.stdin)['count'])\""
  [[ "$output" == "6" ]]
}

@test "AC-2.2/2.3: alert cruza umbral y emite JSON compatible" {
  event "DispatchError" "failed to dispatch request 550e8400-e29b-41d4-a716-446655440000" "at https://192.0.2.1:8443"
  local evf="$FIXDIR/events.jsonl" issuesf="$FIXDIR/issues.jsonl"
  for i in 1 2 3 4 5; do
    python3 -c "
import json
ev=json.load(open('$FIXDIR/ev.json'))
from importlib.machinery import SourceFileLoader
fp=SourceFileLoader('f','scripts/telemetry-fingerprint.py').load_module()
ev['fingerprint']=fp.fingerprint(ev)
ev['ts']='2026-08-22T10:0${i}:00Z'
print(json.dumps(ev))" >> "$evf"
  done
  TEL_FP_EVENTS="$evf" TEL_FP_ISSUES="$issuesf" bash "$ISSUES" >/dev/null
  echo "alert_on: count >= 5" > "$FIXDIR/pol.yaml"
  TEL_FP_ISSUES="$issuesf" TEL_FP_ALERT_LOG="$FIXDIR/alerts.jsonl" TEL_FP_POLICY="$FIXDIR/pol.yaml" \
    bash "$ALERT" >/dev/null
  [[ -f "$FIXDIR/alerts.jsonl" ]]
  python3 -c "import json; json.load(open('$FIXDIR/alerts.jsonl'))"
  grep -q "telemetry-alert" "$FIXDIR/alerts.jsonl"
}

@test "AC-5.1: scripts pasan bash -n y sin vendor names" {
  bash -n "$ISSUES" "$ALERT"
  run grep -niE "openai|anthropic|gpt-|gemini" "$ISSUES" "$ALERT" "scripts/telemetry-fingerprint.py"
  [[ "$status" -ne 0 ]]
}
# ── Comportamiento: normalización, campos y CLI del fingerprint ───────────────

_norm() { python3 - "$1" <<'PY'
import sys, importlib.util
sp = importlib.util.spec_from_file_location('f', 'scripts/telemetry-fingerprint.py')
m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
print(m.normalize(sys.argv[1]))
PY
}

_fp_json() { # <json-event> <campo>
  printf '%s' "$1" | python3 scripts/telemetry-fingerprint.py - | python3 -c "import sys,json;print(json.load(sys.stdin)['$2'])"
}

@test "normalize: URL, email, UUID, timestamp e IP se sustituyen por su marcador" {
  [ "$(_norm 'see https://a.b/c?d=1 now')" = "see <url> now" ]
  [ "$(_norm 'mail bob@example.com x')" = "mail <email> x" ]
  [ "$(_norm 'id 550e8400-e29b-41d4-a716-446655440000')" = "id <uuid>" ]
  [ "$(_norm 'at 2026-08-22T10:00:00Z ok')" = "at <ts> ok" ]
  [ "$(_norm 'host 192.0.2.1:8443 down')" = "host <ip> down" ]
}

@test "normalize: hex, números, cadenas entre comillas e identificadores largos" {
  [ "$(_norm 'ptr 0xDEADBEEF')" = "ptr <hex>" ]
  [ "$(_norm 'retry 42 times')" = "retry <n> times" ]
  [ "$(_norm 'name "some value here" bad')" = "name <str> bad" ]
  [ "$(_norm 'abcdefghijklmnopqrstuvwxyz1234 long')" = "<id> long" ]
}

@test "normalize: colapsa espacios y pasa a minúsculas; texto corto queda intacto" {
  [ "$(_norm '  Multi   SPACE	TEXT ')" = "multi space text" ]
  [ "$(_norm 'ab')" = "ab" ]
}

@test "normalize: la URL se redacta antes que la IP que contiene" {
  [ "$(_norm 'GET https://192.0.2.9:80/x')" = "get <url>" ]
}

@test "fingerprint: sin tipo de excepción usa unknown; error_type es el segundo origen" {
  [ "$(_fp_json '{"message":"boom 5"}' exception_type)" = "unknown" ]
  [ "$(_fp_json '{"error_type":"E","message":"boom 5"}' exception_type)" = "E" ]
  [ "$(_fp_json '{"exception_type":"X","error_type":"E","message":"b"}' exception_type)" = "X" ]
}

@test "fingerprint: bucket = tipo :: mensaje normalizado y el hash tiene 16 hex" {
  [ "$(_fp_json '{"exception_type":"E","message":"boom 5"}' bucket)" = "E :: boom <n>" ]
  h="$(_fp_json '{"exception_type":"E","message":"boom 5"}' hash)"
  [[ "$h" =~ ^[0-9a-f]{16}$ ]]
}

@test "fingerprint: mensaje y stack distintos dan huellas distintas; mismo tipo y números distintos, igual" {
  a="$(_fp_json '{"exception_type":"E","message":"m","frames":"File x line 12"}' hash)"
  b="$(_fp_json '{"exception_type":"E","message":"m","frames":"File x line 99"}' hash)"
  c="$(_fp_json '{"exception_type":"E","message":"m","frames":"File y line 12"}' hash)"
  [ "$a" = "$b" ]
  [ "$a" != "$c" ]
}

@test "fingerprint: el campo message tiene prioridad sobre error y stack se incorpora" {
  [ "$(_fp_json '{"message":"uno","error":"dos"}' top_frame)" = "uno" ]
  [ "$(_fp_json '{"message":"m","stack":"S 1"}' top_frame)" = "m s <n>" ]
}

@test "fingerprint: error con exc_chain usa las frames lógicas y descarta el request_id del wrapper" {
  a="$(_fp_json '{"error":{"request_id":"r-111","exc_chain":[{"loc":["a"],"exc_type":"T","message":"m 9"}]}}' hash)"
  b="$(_fp_json '{"error":{"request_id":"r-222","exc_chain":[{"loc":["a"],"exc_type":"T","message":"m 9"}]}}' hash)"
  [ "$a" = "$b" ]
  [ "$(_fp_json '{"error":{"exc_chain":[{"loc":["a"],"exc_type":"T","message":"m 9"}]}}' top_frame)" = "['a']:t:m <n>" ]
}

@test "fingerprint: error-objeto sin exc_chain usa su campo error y clave como prefijo" {
  [ "$(_fp_json '{"error":{"error":"wrapped msg 3"}}' top_frame)" = "error:wrapped msg <n>" ]
}

@test "fingerprint: mensaje en forma de dict se serializa con claves ordenadas" {
  a="$(_fp_json '{"message":{"b":1,"a":2}}' hash)"
  b="$(_fp_json '{"message":{"a":2,"b":1}}' hash)"
  [ "$a" = "$b" ]
}

@test "CLI fingerprint: lee de stdin con '-' y devuelve JSON con las cinco claves" {
  out="$(echo '{"exception_type":"E","message":"x 1"}' | python3 "$FP" -)"
  keys="$(echo "$out" | python3 -c "import sys,json;print(','.join(sorted(json.load(sys.stdin))))")"
  [ "$keys" = "bucket,exception_type,hash,normalized_frames,top_frame" ]
}

@test "CLI fingerprint: sin argumento exit 2 con uso; JSON inválido falla; no-dict falla" {
  run python3 "$FP"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
  run bash -c "echo 'no json' | python3 $FP -"
  [ "$status" -ne 0 ]
  run bash -c "echo '[1,2]' | python3 $FP -"
  [ "$status" -ne 0 ]
  [[ "$output" == *"event debe ser un dict"* ]]
}

# ── Comportamiento: telemetry-issues.sh ───────────────────────────────────────

_ev() { # <hash> <ts> <severity> → línea JSONL
  printf '{"ts":"%s","severity":"%s","fingerprint":{"hash":"%s"}}\n' "$2" "$3" "$1"
}

@test "issues: ordena por count descendente y agrega first/last_seen y issue_id de 12" {
  {
    _ev aaaaaaaaaaaaaaaa 2026-01-02T00:00:00Z error
    _ev bbbbbbbbbbbbbbbb 2026-01-01T00:00:00Z error
    _ev aaaaaaaaaaaaaaaa 2026-01-01T00:00:00Z error
    _ev aaaaaaaaaaaaaaaa 2026-01-03T00:00:00Z error
  } > "$FIXDIR/e.jsonl"
  run bash "$ISSUES" --events "$FIXDIR/e.jsonl" --issues "$FIXDIR/i.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "issues=2 events=4" ]
  [ "$(head -1 "$FIXDIR/i.jsonl" | jq -r .hash)" = "aaaaaaaaaaaaaaaa" ]
  [ "$(head -1 "$FIXDIR/i.jsonl" | jq -r .count)" = "3" ]
  [ "$(head -1 "$FIXDIR/i.jsonl" | jq -r .first_seen)" = "2026-01-01T00:00:00Z" ]
  [ "$(head -1 "$FIXDIR/i.jsonl" | jq -r .last_seen)" = "2026-01-03T00:00:00Z" ]
  [ "$(head -1 "$FIXDIR/i.jsonl" | jq -r .issue_id)" = "aaaaaaaaaaaa" ]
  [ "$(sed -n 2p "$FIXDIR/i.jsonl" | jq -r .count)" = "1" ]
}

@test "issues: la severidad más alta del grupo gana (info < warn < error)" {
  {
    _ev cccccccccccccccc 2026-01-01T00:00:00Z info
    _ev cccccccccccccccc 2026-01-02T00:00:00Z warn
  } > "$FIXDIR/e.jsonl"
  bash "$ISSUES" --events "$FIXDIR/e.jsonl" --issues "$FIXDIR/i.jsonl" >/dev/null
  [ "$(jq -r .severity "$FIXDIR/i.jsonl")" = "warn" ]
  printf '%s\n' "$(_ev dddddddddddddddd 2026-01-01T00:00:00Z error)" "$(_ev dddddddddddddddd 2026-01-02T00:00:00Z info)" > "$FIXDIR/e2.jsonl"
  bash "$ISSUES" --events "$FIXDIR/e2.jsonl" --issues "$FIXDIR/i2.jsonl" >/dev/null
  [ "$(jq -r .severity "$FIXDIR/i2.jsonl")" = "error" ]
}

@test "issues: severidad ausente cuenta como error; sample_event es el primero del grupo" {
  printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","note":"primero","fingerprint":{"hash":"eeeeeeeeeeeeeeee"}}' \
                '{"ts":"2026-01-02T00:00:00Z","note":"segundo","fingerprint":{"hash":"eeeeeeeeeeeeeeee"}}' > "$FIXDIR/e.jsonl"
  bash "$ISSUES" --events "$FIXDIR/e.jsonl" --issues "$FIXDIR/i.jsonl" >/dev/null
  [ "$(jq -r .severity "$FIXDIR/i.jsonl")" = "error" ]
  [ "$(jq -r .sample_event.note "$FIXDIR/i.jsonl")" = "primero" ]
}

@test "issues: ignora líneas vacías, JSON roto y eventos sin huella; acepta fingerprint_hash plano" {
  {
    echo ""
    echo "esto no es json"
    echo '{"ts":"2026-01-01T00:00:00Z","message":"sin huella"}'
    echo '{"ts":"2026-01-01T00:00:00Z","fingerprint_hash":"ffffffffffffffff"}'
  } > "$FIXDIR/e.jsonl"
  run bash "$ISSUES" --events "$FIXDIR/e.jsonl" --issues "$FIXDIR/i.jsonl"
  [ "$output" = "issues=1 events=1" ]
  [ "$(jq -r .hash "$FIXDIR/i.jsonl")" = "ffffffffffffffff" ]
}

@test "issues: --window N solo considera los últimos N eventos del fichero" {
  {
    _ev 1111111111111111 2026-01-01T00:00:00Z error
    _ev 1111111111111111 2026-01-02T00:00:00Z error
    _ev 2222222222222222 2026-01-03T00:00:00Z error
  } > "$FIXDIR/e.jsonl"
  run bash "$ISSUES" --events "$FIXDIR/e.jsonl" --issues "$FIXDIR/i.jsonl" --window 2
  [ "$output" = "issues=2 events=2" ]
  [ "$(jq -r 'select(.hash=="1111111111111111").count' "$FIXDIR/i.jsonl")" = "1" ]
  run bash "$ISSUES" --events "$FIXDIR/e.jsonl" --issues "$FIXDIR/i.jsonl" --window 0
  [ "$output" = "issues=2 events=3" ]
}

@test "issues: fichero de eventos inexistente termina en 0 sin crear el de issues" {
  run bash "$ISSUES" --events "$FIXDIR/nope.jsonl" --issues "$FIXDIR/i.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no events file"* ]]
  [ ! -e "$FIXDIR/i.jsonl" ]
}

@test "issues: argumento desconocido es error de uso (exit 2)" {
  run bash "$ISSUES" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "issues: reejecutar regenera el fichero en vez de acumular duplicados" {
  _ev 3333333333333333 2026-01-01T00:00:00Z error > "$FIXDIR/e.jsonl"
  bash "$ISSUES" --events "$FIXDIR/e.jsonl" --issues "$FIXDIR/i.jsonl" >/dev/null
  bash "$ISSUES" --events "$FIXDIR/e.jsonl" --issues "$FIXDIR/i.jsonl" >/dev/null
  [ "$(wc -l < "$FIXDIR/i.jsonl")" -eq 1 ]
}

# ── Comportamiento: telemetry-alert.sh ────────────────────────────────────────

_issue() { # <hash> <count>
  printf '{"issue_id":"x","hash":"%s","count":%s}\n' "$1" "$2"
}

@test "alert: umbral por defecto 5 sin política; 5 alerta y 4 no" {
  { _issue h5 5; _issue h4 4; } > "$FIXDIR/i.jsonl"
  run env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" TEL_FP_POLICY="$FIXDIR/no-existe.yaml" bash "$ALERT" --issues "$FIXDIR/i.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "alerts=1 threshold=5 capture=false" ]
  [ "$(wc -l < "$FIXDIR/a.jsonl")" -eq 1 ]
  [ "$(jq -r .hash "$FIXDIR/a.jsonl")" = "h5" ]
  [ "$(jq -r .count "$FIXDIR/a.jsonl")" = "5" ]
  [ "$(jq -r .threshold "$FIXDIR/a.jsonl")" = "5" ]
  [ "$(jq -r .status "$FIXDIR/a.jsonl")" = "open" ]
  [ "$(jq -r .kind "$FIXDIR/a.jsonl")" = "telemetry-alert" ]
}

@test "alert: el umbral de la política manda y la frontera es inclusiva" {
  echo "alert_on: count >= 3" > "$FIXDIR/p.yaml"
  { _issue a 3; _issue b 2; _issue c 10; } > "$FIXDIR/i.jsonl"
  run env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/i.jsonl" --policy "$FIXDIR/p.yaml"
  [ "$output" = "alerts=2 threshold=3 capture=false" ]
  [ "$(jq -r .hash "$FIXDIR/a.jsonl" | tr '\n' ' ')" = "a c " ]
}

@test "alert: política sin patrón count >= N conserva el umbral por defecto" {
  echo "otra_clave: 1" > "$FIXDIR/p.yaml"
  _issue z 4 > "$FIXDIR/i.jsonl"
  run env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/i.jsonl" --policy "$FIXDIR/p.yaml"
  [ "$output" = "alerts=0 threshold=5 capture=false" ]
  [ ! -s "$FIXDIR/a.jsonl" ]
}

@test "alert: issue sin hash se ignora aunque supere el umbral" {
  echo '{"count":99}' > "$FIXDIR/i.jsonl"
  run env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/i.jsonl" --policy "$FIXDIR/no.yaml"
  [ "$output" = "alerts=0 threshold=5 capture=false" ]
}

@test "alert: añade al log sin pisar las alertas anteriores" {
  _issue h 7 > "$FIXDIR/i.jsonl"
  env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/i.jsonl" --policy "$FIXDIR/no.yaml" >/dev/null
  env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/i.jsonl" --policy "$FIXDIR/no.yaml" >/dev/null
  [ "$(wc -l < "$FIXDIR/a.jsonl")" -eq 2 ]
}

@test "alert: --dry-run informa de las alertas pero no escribe el log" {
  _issue h 7 > "$FIXDIR/i.jsonl"
  run env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/i.jsonl" --policy "$FIXDIR/no.yaml" --dry-run
  [ "$status" -eq 0 ]
  [ "$output" = "alerts=1 threshold=5 capture=false" ]
  [ ! -e "$FIXDIR/a.jsonl" ]
}

@test "alert: sin fichero de issues termina en 0 sin crear log" {
  run env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/nope.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no issues file"* ]]
  [ ! -e "$FIXDIR/a.jsonl" ]
}

@test "alert: argumento desconocido es error de uso (exit 2)" {
  run bash "$ALERT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "alert: --capture lo refleja en la salida" {
  _issue h 1 > "$FIXDIR/i.jsonl"
  run env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/i.jsonl" --policy "$FIXDIR/no.yaml" --capture
  [ "$output" = "alerts=0 threshold=5 capture=true" ]
}

@test "alert: con varios 'count >= N' en la política se usa el primero" {
  printf 'alert_on: count >= 2\nescalate: count >= 50\n' > "$FIXDIR/p.yaml"
  _issue a 2 > "$FIXDIR/i.jsonl"
  env TEL_FP_ALERT_LOG="$FIXDIR/a.jsonl" bash "$ALERT" --issues "$FIXDIR/i.jsonl" --policy "$FIXDIR/p.yaml" >/dev/null
  [ "$(jq -r .count "$FIXDIR/a.jsonl")" = "2" ]
  [ "$(jq -r .threshold "$FIXDIR/a.jsonl")" = "2" ]
}
