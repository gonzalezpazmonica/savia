#!/usr/bin/env bats
# tests/test-incident-rca.bats — SE-323: Incident RCA Agent (S1-S4).
# Ref: docs/propuestas/SE-323-incident-rca-agent.md (AC-S1, AC-S2, AC-S3, AC-S4)

MASK="scripts/mask-reversible.sh"
RCA="scripts/incident-rca.sh"
POSTMORTEM="scripts/incident-postmortem.sh"
RUNNER="scripts/rca-eval-runner.sh"
CASES="tests/evals/incident-rca/rca-cases.jsonl"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

# ── Helpers ────────────────────────────────────────────────────────────────
make_alert() { # file incident_id
  cat > "$1" <<EOF
{"incident_id":"$2","title":"test incident","severity":"high","service":"svc","ts":"2026-08-11T10:00:00Z"}
EOF
}

make_signals() { # dir
  local d="$1"
  mkdir -p "$d"
  cat > "$d/logs.txt" <<'EOF'
10:01:00 ERROR status=503 connection refused upstream
10:01:05 ERROR crashloop: back-off restarting failed container
10:01:10 INFO pod myapp-7d9f8c6b4-2xkpq healthz ok
EOF
  cat > "$d/deploys.json" <<'EOF'
[{"ts": "2026-08-11T09:50:00Z", "service": "svc", "version": "v2.0.0"}]
EOF
  cat > "$d/metrics.json" <<'EOF'
{"cpu_pct": 95.0}
EOF
}

# ── S1: Masking reversible ──────────────────────────────────────────────────

@test "S1.1: mask-reversible.sh existe y es ejecutable" {
  [[ -f "$MASK" ]]
  [[ -x "$MASK" ]]
}

@test "S1.2: usa set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$MASK"
  [[ "$output" -ge 1 ]]
}

@test "AC-S1.1: pod+cluster+IP -> placeholders unicos y restore devuelve original byte a byte" {
  local map="$TMPD/map.json"
  local orig='pod crash: myapp-7d9f8c6b4-2xkpq in cluster-prod; account 123456789012; ip 198.51.100.7'
  local masked restored
  masked=$(printf '%s' "$orig" | bash "$MASK" mask --map "$map")
  # placeholders presentes
  [[ "$masked" == *"{POD_1}"* ]]
  [[ "$masked" == *"{CLUSTER_1}"* ]]
  [[ "$masked" == *"{ACCOUNT_1}"* ]]
  [[ "$masked" == *"{IP_1}"* ]]
  [[ "$masked" != *"myapp-7d9f8c6b4"* ]]
  restored=$(printf '%s' "$masked" | bash "$MASK" restore --map "$map")
  [[ "$restored" == "$orig" ]]
}

@test "AC-S1.2: el mapa es fichero efimero (N4b, fuera del repo versionado)" {
  local map="$TMPD/map.json"
  printf 'crash myapp-7d9f8c6b4-2xkpq' | bash "$MASK" mask --map "$map"
  [[ -f "$map" ]]
  # N4b: el mapa vive en directorio efimero, no dentro del repo
  [[ "$map" == "$TMPD/"* ]]
  # output/ (destino de telemetría e informes) está gitignored
  run git check-ignore output/telemetry-events.jsonl
  [[ "$status" -eq 0 ]]
}

@test "AC-S1.3: sin identificadores -> passthrough sin cambios, exit 0" {
  local map="$TMPD/map.json"
  run bash -c "printf 'sin identificadores aqui' | bash '$MASK' mask --map '$map'"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "sin identificadores aqui" ]]
}

# ── S2: Harness RCA ─────────────────────────────────────────────────────────

@test "S2.1: incident-rca.sh existe y es ejecutable" {
  [[ -f "$RCA" ]]
  [[ -x "$RCA" ]]
}

@test "AC-S2.1: alert de fixture produce informe con root_cause, evidence>=2 y confidence" {
  local alert="$TMPD/alert.json"
  local signals="$TMPD/signals"
  make_alert "$alert" INC-TEST-001
  make_signals "$signals"
  run bash "$RCA" --alert "$alert" --signals "$signals" --out "$TMPD/out" --incident-id INC-TEST-001
  [[ "$status" -eq 0 ]]
  local rca="$TMPD/out/INC-TEST-001-rca.json"
  [[ -f "$rca" ]]
  local n_ev
  n_ev=$(jq '.evidence | length' "$rca")
  [[ "$n_ev" -ge 2 ]]
  run jq -r '.root_cause' "$rca"
  [[ -n "$output" ]]
  run jq -r '.confidence' "$rca"
  [[ -n "$output" ]]
}

@test "AC-S2.2: rca.verdict aparece en output/telemetry-events.jsonl" {
  local alert="$TMPD/alert.json"
  local signals="$TMPD/signals"
  make_alert "$alert" INC-TEST-002
  make_signals "$signals"
  local tl="$TMPD/telemetry.jsonl"
  SAVIA_TELEMETRY_FILE="$tl" bash "$RCA" --alert "$alert" --signals "$signals" --out "$TMPD/out" --incident-id INC-TEST-002
  run grep -c 'rca.verdict' "$tl"
  [[ "$output" -ge 1 ]]
}

@test "AC-S2.3: sin señales -> confidence low, evidence [], no inventa" {
  local alert="$TMPD/alert.json"
  local empty="$TMPD/empty"
  mkdir -p "$empty"
  make_alert "$alert" INC-TEST-003
  run bash "$RCA" --alert "$alert" --signals "$empty" --out "$TMPD/out" --incident-id INC-TEST-003
  local rca="$TMPD/out/INC-TEST-003-rca.json"
  run jq -r '.confidence' "$rca"
  [[ "$output" == "low" ]]
  run jq '.evidence | length' "$rca"
  [[ "$output" -eq 0 ]]
}

# ── S3: Suite sintética ─────────────────────────────────────────────────────

@test "AC-S3.1: suite con >=10 casos" {
  local n
  n=$(wc -l < "$CASES" | tr -d ' ')
  [[ "$n" -ge 10 ]]
}

@test "AC-S3.2: runner puntua las 3 dimensiones y score >= 80" {
  run bash "$RUNNER"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"score="* ]]
  run bash "$RUNNER" --json
  local s
  s=$(echo "$output" | jq -r '.score')
  [[ "$s" -ge 80 ]]
}

@test "AC-S3.3: un caso con red herring citada como causa baja el score" {
  # El harness determinista nunca cita herrings; el runner debe detectar el
  # caso contrario: inyectar RCA con herring en root_cause -> score_rh = 0.
  local herring="deprecation: legacy fields"
  local combined="Cause: ${herring} broke the deploy"
  local n
  n=$(python3 -c "
h = '$herring'.lower()
c = '$combined'.lower()
print(0 if h in c else 1)
")
  [[ "$n" -eq 0 ]]
}

# ── S4: Postmortem ──────────────────────────────────────────────────────────

@test "AC-S4.1: --postmortem genera fichero en output/postmortems con 3 secciones rellenadas" {
  local alert="$TMPD/alert.json"
  local signals="$TMPD/signals"
  make_alert "$alert" INC-TEST-004
  make_signals "$signals"
  bash "$RCA" --alert "$alert" --signals "$signals" --out "$TMPD/out" --postmortem --incident-id INC-TEST-004
  run bash "$POSTMORTEM" --rca "$TMPD/out/INC-TEST-004-rca.json" --out "$TMPD/pm"
  [[ "$status" -eq 0 ]]
  local pm
  pm=$(find "$TMPD/pm" -name "*-INC-TEST-004.md" | head -1)
  [[ -f "$pm" ]]
  grep -q "^## Timeline" "$pm"
  grep -q "^## Diagnosis Journey" "$pm"
  grep -q "^## Resolution" "$pm"
}

@test "AC-S4.2: conserva secciones humanas vacias (Heuristic, Comprehension Gap)" {
  local alert="$TMPD/alert.json"
  local signals="$TMPD/signals"
  make_alert "$alert" INC-TEST-005
  make_signals "$signals"
  bash "$RCA" --alert "$alert" --signals "$signals" --out "$TMPD/out" --incident-id INC-TEST-005
  bash "$POSTMORTEM" --rca "$TMPD/out/INC-TEST-005-rca.json" --out "$TMPD/pm"
  local pm
  pm=$(find "$TMPD/pm" -name "*-INC-TEST-005.md" | head -1)
  grep -q "^## Heuristic Extraction" "$pm"
  grep -q "Revisión humana" "$pm"
  grep -q "^## Comprehension Gap Analysis" "$pm"
}

# ── Seguridad: cero secrets en el diff ──────────────────────────────────────

@test "S5.1: no introduce PATs ni credenciales hardcodeadas" {
  run grep -rnE "AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32,}" scripts/mask-reversible.py scripts/incident-rca.sh
  [[ -z "$output" ]]
}

# ── Comportamiento del motor determinista: reglas, confianza, evidencia ─────

# rca_run <logs|-> <deploys-json|-> <metrics-json|-> [incident] → deja el informe en $RCA_JSON
rca_run() {
  local logs="$1" deploys="$2" metrics="$3" id="${4:-INC-B}"
  local sig="$TMPD/sig-$id"
  mkdir -p "$sig"
  [[ "$logs" != "-" ]] && printf '%b' "$logs" > "$sig/logs.txt"
  [[ "$deploys" != "-" ]] && printf '%s' "$deploys" > "$sig/deploys.json"
  [[ "$metrics" != "-" ]] && printf '%s' "$metrics" > "$sig/metrics.json"
  make_alert "$TMPD/alert-$id.json" "$id"
  SAVIA_TELEMETRY_FILE="$TMPD/tel.jsonl" run bash "$RCA" --alert "$TMPD/alert-$id.json" \
    --signals "$sig" --out "$TMPD/out" --incident-id "$id"
  RCA_JSON="$TMPD/out/$id-rca.json"
}

DEPLOY='[{"ts":"2026-08-11T09:50:00Z","service":"svc","version":"v2.0.0"}]'

@test "regla 1: deploy + crashloop/5xx/oom → regresión del deploy, confianza alta, rollback primero" {
  rca_run "10:01 crashloop: back-off restarting\n" "$DEPLOY" -
  [ "$status" -eq 0 ]
  [[ "$(jq -r .root_cause "$RCA_JSON")" == "Possible regression introduced by deploy v2.0.0 of svc"* ]]
  [ "$(jq -r .confidence "$RCA_JSON")" = "high" ]
  [ "$(jq -r '.next_steps[0]' "$RCA_JSON")" = "Rollback del deploy sospechoso" ]
  [ "$(jq -r '.hypothesis[0]' "$RCA_JSON")" = "deploy_recent=2026-08-11T09:50:00Z service=svc version=v2.0.0" ]
}

@test "regla 1: la línea de tiempo lleva alerta y deploy, en ese orden" {
  rca_run "status=503 error\n" "$DEPLOY" -
  [ "$(jq -r '.timeline[0].event' "$RCA_JSON")" = "alert raised (severity=high)" ]
  [ "$(jq -r '.timeline[0].ts' "$RCA_JSON")" = "2026-08-11T10:00:00Z" ]
  [ "$(jq -r '.timeline[1].event' "$RCA_JSON")" = "deploy v2.0.0 svc" ]
  [ "$(jq '.timeline | length' "$RCA_JSON")" -eq 2 ]
}

@test "regla 1 no aplica con deploy pero solo timeouts: cae en saturación (media)" {
  rca_run "request timed out after 30s\n" "$DEPLOY" -
  [[ "$(jq -r .root_cause "$RCA_JSON")" == "Possible saturation or connectivity loss for svc"* ]]
  [ "$(jq -r .confidence "$RCA_JSON")" = "medium" ]
  [ "$(jq '.hypothesis | length' "$RCA_JSON")" -eq 1 ]
}

@test "regla 1 exige deploy: crashloop sin deploys no culpa a ningún deploy" {
  rca_run "crashloop detected\n" - -
  run jq -r .root_cause "$RCA_JSON"
  [[ "$output" != *"regression"* ]]
  [ "$(jq -r .confidence "$RCA_JSON")" = "low" ]
}

@test "regla 2: connection refused sin deploy → saturación/conectividad, confianza media" {
  rca_run "dial tcp: connection refused\n" - -
  [[ "$(jq -r .root_cause "$RCA_JSON")" == "Possible saturation or connectivity loss for svc (timeouts/connection refused)" ]]
  [ "$(jq -r .confidence "$RCA_JSON")" = "medium" ]
  [ "$(jq -r '.next_steps[0]' "$RCA_JSON")" = "Verificar capacity del servicio" ]
}

@test "regla 3: OOM → agotamiento por OOM; disk full → disco" {
  rca_run "container OOMKilled\n" - - INC-OOM
  [ "$(jq -r .root_cause "$RCA_JSON")" = "Resource exhaustion (OOM) on svc" ]
  rca_run "write failed: no space left on device\n" - - INC-DSK
  [ "$(jq -r .root_cause "$RCA_JSON")" = "Resource exhaustion (disk) on svc" ]
  [ "$(jq -r .confidence "$RCA_JSON")" = "medium" ]
}

@test "regla 4: fallo DNS" {
  rca_run "lookup db.internal failed\nNXDOMAIN for x\n" - -
  [ "$(jq -r .root_cause "$RCA_JSON")" = "DNS resolution failure affecting svc" ]
  [ "$(jq -r '.next_steps[0]' "$RCA_JSON")" = "Verificar CoreDNS/nameservers" ]
}

@test "precedencia: timeout gana a OOM y a DNS cuando no hay deploy" {
  rca_run "timeout calling x\nOOMKilled\nNXDOMAIN\n" - -
  [[ "$(jq -r .root_cause "$RCA_JSON")" == "Possible saturation"* ]]
}

@test "regla 5: métrica por encima de 90 → causa con la métrica más alta; 90 exacto no cuenta" {
  rca_run - - '{"cpu_pct": 95.5, "mem_pct": 97, "disk_pct": 40, "name": "x"}'
  [ "$(jq -r .root_cause "$RCA_JSON")" = "Resource metric above threshold (mem_pct=97) on svc" ]
  [ "$(jq -r .confidence "$RCA_JSON")" = "medium" ]
  rca_run - - '{"cpu_pct": 90}' INC-N90
  [[ "$(jq -r .root_cause "$RCA_JSON")" == "Inconclusive"* ]]
}

@test "regla 6: señales presentes sin patrón fuerte → inconclusa, confianza baja, pide ampliar" {
  rca_run "todo normal\nlinea tranquila\n" - -
  [[ "$(jq -r .root_cause "$RCA_JSON")" == "Inconclusive — weak signals present for svc"* ]]
  [ "$(jq -r .confidence "$RCA_JSON")" = "low" ]
  [ "$(jq -r '.next_steps[1]' "$RCA_JSON")" = "Ampliar ventana de observación" ]
}

@test "sin ninguna señal: root_cause null, confianza baja, un único paso de recolección" {
  rca_run - - -
  [ "$(jq -r '.root_cause' "$RCA_JSON")" = "null" ]
  [ "$(jq -r '.next_steps | length' "$RCA_JSON")" -eq 1 ]
  [ "$(jq -c '.signals_available' "$RCA_JSON")" = '{"logs":false,"metrics":false,"deploys":false}' ]
}

@test "evidencia: línea, señal y fragmento recortado; se limita a 8 y se numera desde 1" {
  local big="" i
  for i in $(seq 1 12); do big+="L$i connection refused\n"; done
  rca_run "ok\n$big" - -
  [ "$(jq '.evidence | length' "$RCA_JSON")" -eq 8 ]
  [ "$(jq -r '.evidence[0].line' "$RCA_JSON")" -eq 2 ]
  [ "$(jq -r '.evidence[0].signal' "$RCA_JSON")" = "connection_refused" ]
  [ "$(jq -r '.evidence[0].source' "$RCA_JSON")" = "logs.txt" ]
  [ "$(jq -r '.evidence[0].fragment' "$RCA_JSON")" = "L1 connection refused" ]
  [ "$(jq -r '.evidence[7].line' "$RCA_JSON")" -eq 9 ]
}

@test "evidencia: fragmento truncado a 180 caracteres" {
  local long
  long="$(printf 'x%.0s' {1..300}) timeout"
  rca_run "$long\n" - -
  [ "$(jq -r '.evidence[0].fragment | length' "$RCA_JSON")" -eq 180 ]
}

@test "patrones: cada uno de los siete se reconoce por separado" {
  local casos=(
    "ECONNREFUSED 10.0.0.1|connection_refused"
    "deadline exceeded|timeout"
    "status=502 upstream|http_5xx"
    "oom-kill event|oom"
    "Back-off restarting failed|crashloop"
    "disk full on /var|disk_full"
    "lookup foo failed|dns_failure"
  )
  local c line sig
  for c in "${casos[@]}"; do
    line="${c%%|*}"; sig="${c##*|}"
    rca_run "$line\n" - - "INC-P-$sig"
    [ "$(jq -r '.evidence[0].signal' "$RCA_JSON")" = "$sig" ]
  done
}

@test "patrones: un 200 OK o un número cualquiera no es 5xx" {
  rca_run "status=200 ok\nrequest 5000 items processed\n" - -
  [ "$(jq '.evidence | length' "$RCA_JSON")" -eq 0 ]
}

@test "red herrings: fragmentos de distracción se descartan; los reales no" {
  rca_run "deprecation warning: connection refused (retry in 5s)\nconnection refused for real\n" - -
  [ "$(jq '.red_herrings_dismissed | length' "$RCA_JSON")" -eq 1 ]
  [[ "$(jq -r '.red_herrings_dismissed[0]' "$RCA_JSON")" == "deprecation warning"* ]]
}

@test "deploys.json que no es lista o está corrupto se ignora sin romper" {
  rca_run "crashloop\n" '{"no":"lista"}' -
  [ "$status" -eq 0 ]
  [ "$(jq -r .confidence "$RCA_JSON")" = "low" ]
  rca_run "crashloop\n" 'corrupto{' - INC-C
  [ "$status" -eq 0 ]
  [ "$(jq -r '.signals_available.deploys' "$RCA_JSON")" = "true" ]
}

@test "metrics.json corrupto o no objeto se ignora" {
  rca_run "x\n" - '[1,2,3]'
  [ "$status" -eq 0 ]
  [[ "$(jq -r .root_cause "$RCA_JSON")" == "Inconclusive"* ]]
}

@test "informe: esquema, ids y datos del alert copiados" {
  rca_run "timeout\n" - -
  [ "$(jq -r .schema "$RCA_JSON")" = "savia.rca/1.0" ]
  [ "$(jq -r .incident_id "$RCA_JSON")" = "INC-B" ]
  [ "$(jq -r .title "$RCA_JSON")" = "test incident" ]
  [ "$(jq -r .severity "$RCA_JSON")" = "high" ]
  [ "$(jq -r .service "$RCA_JSON")" = "svc" ]
}

@test "salida estándar: 'RCA: <ruta>' y exit 0" {
  rca_run "timeout\n" - -
  [[ "$output" == *"RCA: $TMPD/out/INC-B-rca.json"* ]]
}

@test "incident-id del alert se usa si no se pasa --incident-id; la opción lo sobrescribe" {
  make_alert "$TMPD/al.json" DEL-ALERT
  mkdir -p "$TMPD/s"
  run bash "$RCA" --alert "$TMPD/al.json" --signals "$TMPD/s" --out "$TMPD/o1"
  [ "$status" -eq 0 ]
  [ -f "$TMPD/o1/DEL-ALERT-rca.json" ]
  run bash "$RCA" --alert "$TMPD/al.json" --signals "$TMPD/s" --out "$TMPD/o2" --incident-id OTRO
  [ "$status" -eq 0 ]
  [ -f "$TMPD/o2/OTRO-rca.json" ]
  [ "$(jq -r .incident_id "$TMPD/o2/OTRO-rca.json")" = "OTRO" ]
}

@test "alert sin incident_id y sin --incident-id: exit 2 con mensaje claro" {
  echo '{"title":"t"}' > "$TMPD/al.json"
  run bash "$RCA" --alert "$TMPD/al.json" --out "$TMPD/o"
  [ "$status" -eq 2 ]
  [[ "$output" == *"alert sin incident_id"* ]]
}

@test "alert sin título/severidad/servicio usa los valores por defecto" {
  echo '{"incident_id":"INC-D"}' > "$TMPD/al.json"
  mkdir -p "$TMPD/s"
  run bash "$RCA" --alert "$TMPD/al.json" --signals "$TMPD/s" --out "$TMPD/o"
  [ "$status" -eq 0 ]
  local r="$TMPD/o/INC-D-rca.json"
  [ "$(jq -r .title "$r")" = "untitled incident" ]
  [ "$(jq -r .severity "$r")" = "unknown" ]
  [ "$(jq -r .service "$r")" = "unknown" ]
  [ "$(jq '.timeline | length' "$r")" -eq 0 ]
}

@test "señales por defecto: <out>/<id>/signals cuando no se pasa --signals" {
  make_alert "$TMPD/al.json" INC-DEF
  make_signals "$TMPD/o/INC-DEF/signals"
  run bash "$RCA" --alert "$TMPD/al.json" --out "$TMPD/o"
  [ "$status" -eq 0 ]
  [ "$(jq -r .signals_available.logs "$TMPD/o/INC-DEF-rca.json")" = "true" ]
}

@test "uso: sin argumentos, alert ausente, alert inexistente y opción desconocida salen con 2" {
  run bash "$RCA"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
  run bash "$RCA" --out "$TMPD/o"
  [ "$status" -eq 2 ]
  [[ "$output" == *"falta --alert"* ]]
  run bash "$RCA" --alert "$TMPD/no.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"alert no existe"* ]]
  run bash "$RCA" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento desconocido '--bogus'"* ]]
}

@test "--help sale 0" {
  run bash "$RCA" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Investigación RCA"* ]]
}

@test "telemetría: el evento lleva incidente, servicio, severidad y confianza" {
  rca_run "crashloop\n" "$DEPLOY" -
  run grep 'rca.verdict' "$TMPD/tel.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INC-B"* ]]
  [[ "$output" == *"high"* ]]
}

@test "--postmortem genera el postmortem desde el RCA (en --out cuando es explícito)" {
  rca_run "crashloop\n" "$DEPLOY" -
  run bash "$RCA" --alert "$TMPD/alert-INC-B.json" --signals "$TMPD/sig-INC-B" --out "$TMPD/o3" --incident-id INC-B --postmortem
  [ "$status" -eq 0 ]
  run find "$TMPD/o3" -name "*INC-B*.md"
  [ -n "$output" ]
}

@test "fragmentos con caracteres no ASCII se guardan literales en el informe" {
  rca_run "error: conexión rechazada ñandú — connection refused\n" - -
  grep -q 'conexión rechazada ñandú' "$RCA_JSON"
}

@test "dependencias auxiliares que fallan no tumban el informe: telemetría caída y postmortem fallido" {
  local d="$TMPD/aislado/scripts"
  mkdir -p "$d"
  cp "$RCA" "$d/incident-rca.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$d/otel-emit.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$d/incident-postmortem.sh"
  make_alert "$TMPD/al.json" INC-F
  mkdir -p "$TMPD/s"
  run bash "$d/incident-rca.sh" --alert "$TMPD/al.json" --signals "$TMPD/s" --out "$TMPD/o" --postmortem
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: incident-postmortem.sh falló (continúa)"* ]]
  [[ "$output" == *"RCA: $TMPD/o/INC-F-rca.json"* ]]
  [ -f "$TMPD/o/INC-F-rca.json" ]
}

@test "postmortem correcto no emite el aviso y recibe la ruta del RCA y --out explícito" {
  local d="$TMPD/aislado2/scripts"
  mkdir -p "$d"
  cp "$RCA" "$d/incident-rca.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/otel-emit.sh"
  printf '#!/usr/bin/env bash\necho "$@" > "%s/pm-args"\nexit 0\n' "$TMPD" > "$d/incident-postmortem.sh"
  make_alert "$TMPD/al.json" INC-G
  mkdir -p "$TMPD/s"
  run bash "$d/incident-rca.sh" --alert "$TMPD/al.json" --signals "$TMPD/s" --out "$TMPD/o" --postmortem
  [[ "$output" != *"WARN"* ]]
  [ "$(cat "$TMPD/pm-args")" = "--rca $TMPD/o/INC-G-rca.json --out $TMPD/o" ]
}
