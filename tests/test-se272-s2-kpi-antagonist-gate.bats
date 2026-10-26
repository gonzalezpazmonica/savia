#!/usr/bin/env bats
# SE-272 S2 — Tests for KPI antagonist gate and validation
# Slice 2: Contractual KPIs with verification and anti-Goodhart

setup() {
  REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ANTAGONIST_SH="$REAL_ROOT/scripts/kpi-antagonist-gate.sh"
  export CATALOG_SH="$REAL_ROOT/scripts/kpi-catalog-validate.sh"
  export COMPUTE_SH="$REAL_ROOT/scripts/kpi-compute.sh"
  export CHAIN_SH="$REAL_ROOT/scripts/kpi-custody-chain.sh"
  export REVIEW_SH="$REAL_ROOT/scripts/kpi-review-report.sh"
  TMPDIR_KPI=$(mktemp -d)
  export TMPDIR_KPI
  export REPO_ROOT="$TMPDIR_KPI"
  export ENGAGEMENT="test-client/se272-test"
  export ENG_DIR="$REPO_ROOT/engagements/test-client/se272-test"
  mkdir -p "$ENG_DIR"

  # Create a valid KPI catalog for testing
  cat > "$ENG_DIR/kpis.yaml" << 'YAMLEOF'
version: 1
last_modified: "2026-07-25"

kpis:
  - id: "kpi-001"
    name: "Sprint Velocity"
    definition: "Average SP per sprint over 3 months"
    primary_source: "commit_history"
    formula: "sum(completed_sp) / count(sprints)"
    window_months: 3
    target_threshold: 40
    warning_threshold: 30
    antagonist_kpi_id: "kpi-002"
    version: 1
    signature_1:
      name: "Alice"
      date: "2026-01-01"
      role: "stakeholder"
    signature_2:
      name: "Bob"
      date: "2026-01-01"
      role: "delivery_manager"

  - id: "kpi-002"
    name: "Defect Escape Rate"
    definition: "Production defects / total defects"
    primary_source: "incident_log"
    formula: "prod_defects / total_defects * 100"
    window_months: 3
    target_threshold: 5
    warning_threshold: 10
    antagonist_kpi_id: "kpi-001"
    version: 1
    signature_1:
      name: "Alice"
      date: "2026-01-01"
      role: "stakeholder"
    signature_2:
      name: "Bob"
      date: "2026-01-01"
      role: "delivery_manager"
YAMLEOF
}

teardown() {
  rm -rf "$TMPDIR_KPI"
}

# ──────────────────────────────────────────────────────────────────────
# 1. antagonist-gate check passes for valid pair
# ──────────────────────────────────────────────────────────────────────

@test "kpi-antagonist-gate check passes with valid pairs" {
  REPO_ROOT="$TMPDIR_KPI" run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"PASSED"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 2. antagonist-gate blocks KPIs without antagonist
# ──────────────────────────────────────────────────────────────────────

@test "kpi-antagonist-gate blocks KPI without antagonist" {
  # Create catalog with missing antagonist
  cat > "$ENG_DIR/kpis.yaml" << 'YAMLEOF'
version: 1
kpis:
  - id: "bad-kpi-001"
    name: "Sprint Velocity"
    definition: "Average SP per sprint"
    primary_source: "commit_history"
    formula: "sum(sp) / count(sprints)"
    window_months: 3
    target_threshold: 40
    warning_threshold: 30
    antagonist_kpi_id: ""
    version: 1
    signature_1:
      name: "Alice"
      date: "2026-01-01"
      role: "stakeholder"
    signature_2:
      name: "Bob"
      date: "2026-01-01"
      role: "delivery_manager"
YAMLEOF

  REPO_ROOT="$TMPDIR_KPI" run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no antagonist"* || "$output" == *"BLOCKED"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 3. antagonist-gate validate-pair confirms valid pairing
# ──────────────────────────────────────────────────────────────────────

@test "kpi-antagonist-gate validate-pair confirms valid pair" {
  REPO_ROOT="$TMPDIR_KPI" run bash "$ANTAGONIST_SH" validate-pair \
    --kpi-id "kpi-001" \
    --antagonist-id "kpi-002" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"valid"* || "$output" == *"OK"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 4. antagonist-gate validate-pair rejects mismatched pair
# ──────────────────────────────────────────────────────────────────────

@test "kpi-antagonist-gate validate-pair rejects mismatched pair" {
  REPO_ROOT="$TMPDIR_KPI" run bash "$ANTAGONIST_SH" validate-pair \
    --kpi-id "kpi-001" \
    --antagonist-id "kpi-999" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# 5. kpi-catalog-validate passes for valid catalog
# ──────────────────────────────────────────────────────────────────────

@test "kpi-catalog-validate passes for valid catalog" {
  REPO_ROOT="$TMPDIR_KPI" run bash "$CATALOG_SH" validate --file "$ENG_DIR/kpis.yaml"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"PASS"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 6. kpi-catalog-validate fails for catalog without version header
# ──────────────────────────────────────────────────────────────────────

@test "kpi-catalog-validate fails without version header" {
  cat > "$ENG_DIR/kpis.yaml" << 'YAMLEOF'
kpis:
  - id: "kpi-001"
    name: "Test"
    primary_source: "commit_history"
    antagonist_kpi_id: "kpi-002"
YAMLEOF

  REPO_ROOT="$TMPDIR_KPI" run bash "$CATALOG_SH" validate --file "$ENG_DIR/kpis.yaml"
  [[ "$status" -ne 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# 7. kpi-catalog-validate detects missing antagonist reference
# ──────────────────────────────────────────────────────────────────────

@test "kpi-catalog-validate detects dangling antagonist reference" {
  cat > "$ENG_DIR/kpis.yaml" << 'YAMLEOF'
version: 1
kpis:
  - id: "kpi-001"
    name: "Sprint Velocity"
    definition: "Avg SP"
    primary_source: "commit_history"
    formula: "sum(sp)/count(sprints)"
    window_months: 3
    target_threshold: 40
    warning_threshold: 30
    antagonist_kpi_id: "kpi-999"
    version: 1
    signature_1:
      name: "A"
      date: "2026-01-01"
      role: "s"
    signature_2:
      name: "B"
      date: "2026-01-01"
      role: "d"
YAMLEOF

  REPO_ROOT="$TMPDIR_KPI" run bash "$CATALOG_SH" validate --file "$ENG_DIR/kpis.yaml"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"FAIL"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 8. kpi-custody-chain append and verify
# ──────────────────────────────────────────────────────────────────────

@test "kpi-custody-chain append and verify works" {
  REPO_ROOT="$TMPDIR_KPI" run bash "$CHAIN_SH" append \
    --engagement "$ENGAGEMENT" \
    --period "2026-07"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]

  # Second period
  REPO_ROOT="$TMPDIR_KPI" bash "$CHAIN_SH" append \
    --engagement "$ENGAGEMENT" \
    --period "2026-08"

  REPO_ROOT="$TMPDIR_KPI" run bash "$CHAIN_SH" verify --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"CHAIN OK"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 9. kpi-custody-chain detects tampered chain
# ──────────────────────────────────────────────────────────────────────

@test "kpi-custody-chain detects tampered chain" {
  REPO_ROOT="$TMPDIR_KPI" bash "$CHAIN_SH" append --engagement "$ENGAGEMENT" --period "2026-07"
  REPO_ROOT="$TMPDIR_KPI" bash "$CHAIN_SH" append --engagement "$ENGAGEMENT" --period "2026-08"

  # Tamper
  echo '{"tampered":true}' >> "$ENG_DIR/kpi-chain.jsonl"

  REPO_ROOT="$TMPDIR_KPI" run bash "$CHAIN_SH" verify --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"TAMPERED"* || "$output" == *"CHAIN FAIL"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 10. kpi-review-report generate
# ──────────────────────────────────────────────────────────────────────

@test "kpi-review-report generates period report" {
  REPO_ROOT="$TMPDIR_KPI" bash "$CHAIN_SH" append --engagement "$ENGAGEMENT" --period "2026-07"

  REPO_ROOT="$TMPDIR_KPI" run bash "$REVIEW_SH" generate \
    --engagement "$ENGAGEMENT" \
    --period "2026-07"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Review report generated"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 11. kpi-review-report amend with dual signatures
# ──────────────────────────────────────────────────────────────────────

@test "kpi-review-report amend records with dual signatures" {
  REPO_ROOT="$TMPDIR_KPI" run bash "$REVIEW_SH" amend \
    --engagement "$ENGAGEMENT" \
    --kpi-id "kpi-001" \
    --field "target_threshold" \
    --old-value "40" \
    --new-value "45" \
    --signature-1 "Alice,Stakeholder" \
    --signature-2 "Bob,Delivery Manager" \
    --justification "Updated based on Q2 performance review"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"Version bumped"* ]]
  [[ -f "$ENG_DIR/kpi-amendments.jsonl" ]]
  [[ -f "$ENG_DIR/kpi-versions.jsonl" ]]
}

# ──────────────────────────────────────────────────────────────────────
# 12. kpi-review-report version-catalog shows history
# ──────────────────────────────────────────────────────────────────────

@test "kpi-review-report version-catalog shows version history" {
  REPO_ROOT="$TMPDIR_KPI" bash "$REVIEW_SH" amend \
    --engagement "$ENGAGEMENT" \
    --kpi-id "kpi-001" \
    --field "target_threshold" \
    --old-value "40" \
    --new-value "45" \
    --signature-1 "Alice,Stakeholder" \
    --signature-2 "Bob,Delivery Manager"

  REPO_ROOT="$TMPDIR_KPI" bash "$REVIEW_SH" amend \
    --engagement "$ENGAGEMENT" \
    --kpi-id "kpi-001" \
    --field "warning_threshold" \
    --old-value "30" \
    --new-value "35" \
    --signature-1 "Alice,Stakeholder" \
    --signature-2 "Bob,Delivery Manager"

  REPO_ROOT="$TMPDIR_KPI" run bash "$REVIEW_SH" version-catalog --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"KPI Version Catalog"* ]]
  [[ "$output" == *"kpi-001"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 13. kpi-antagonist-gate anomaly detection
# ──────────────────────────────────────────────────────────────────────

@test "kpi-antagonist-gate anomaly runs without crash" {
  REPO_ROOT="$TMPDIR_KPI" bash "$CHAIN_SH" append --engagement "$ENGAGEMENT" --period "2026-07"
  REPO_ROOT="$TMPDIR_KPI" bash "$CHAIN_SH" append --engagement "$ENGAGEMENT" --period "2026-08"

  REPO_ROOT="$TMPDIR_KPI" run bash "$ANTAGONIST_SH" anomaly --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# 14. kpi-catalog-validate rejects self-declared source warning
# ──────────────────────────────────────────────────────────────────────

@test "kpi-catalog-validate warns on non-verifiable source" {
  cat > "$ENG_DIR/kpis.yaml" << 'YAMLEOF'
version: 1
kpis:
  - id: "kpi-001"
    name: "Self Reported"
    definition: "A self-reported metric"
    primary_source: "self_declared_survey"
    formula: "avg(responses)"
    window_months: 3
    target_threshold: 80
    warning_threshold: 60
    antagonist_kpi_id: "kpi-002"
    version: 1
    signature_1:
      name: "A"
      date: "2026-01-01"
      role: "s"
    signature_2:
      name: "B"
      date: "2026-01-01"
      role: "d"
  - id: "kpi-002"
    name: "Quality Check"
    definition: "QA check metric"
    primary_source: "qa_certificates"
    formula: "pass/total*100"
    window_months: 3
    target_threshold: 95
    warning_threshold: 90
    antagonist_kpi_id: "kpi-001"
    version: 1
    signature_1:
      name: "A"
      date: "2026-01-01"
      role: "s"
    signature_2:
      name: "B"
      date: "2026-01-01"
      role: "d"
YAMLEOF

  REPO_ROOT="$TMPDIR_KPI" run bash "$CATALOG_SH" validate --file "$ENG_DIR/kpis.yaml"
  # May pass or fail - self_declared_survey warns but catalog may still pass
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  # Must at least mention the warning
  [[ "$output" == *"self_declared_survey"* || "$output" == *"WARN"* || "$output" == *"warn"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 15. kpi-compute.sh exists and is executable
# ──────────────────────────────────────────────────────────────────────

@test "kpi-compute scripts exist and are executable" {
  [[ -x "$ANTAGONIST_SH" ]]
  [[ -x "$CATALOG_SH" ]]
  [[ -x "$COMPUTE_SH" ]]
  [[ -x "$CHAIN_SH" ]]
  [[ -x "$REVIEW_SH" ]]
}

# ── Comportamiento: mensajes, clasificación y anomalías (SE-456) ──────────────
# Usa el catálogo del setup: kpi-001 "Sprint Velocity" ↔ kpi-002 "Defect Escape Rate".

write_kpis() {  # write_kpis <bloques "id|nombre|antagonista" ...>
  {
    echo 'version: 1'
    echo 'kpis:'
    local spec id name ant
    for spec in "$@"; do
      IFS='|' read -r id name ant <<<"$spec"
      echo "  - id: \"$id\""
      echo "    name: \"$name\""
      echo "    definition: \"d\""
      echo "    antagonist_kpi_id: \"$ant\""
      echo "    signature_1:"
      echo "      name: \"Alice\""
    done
  } > "$ENG_DIR/kpis.yaml"
}

@test "kpi-antagonist-gate check: lista cada KPI con su antagonista y resultado PASSED" {
  run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Antagonist Gate Check — $ENGAGEMENT"* ]]
  [[ "$output" == *"OK:   KPI 'kpi-001' (Sprint Velocity) → antagonist 'kpi-002'"* ]]
  [[ "$output" == *"OK:   KPI 'kpi-002' (Defect Escape Rate) → antagonist 'kpi-001'"* ]]
  [[ "$output" == *"RESULT: PASSED"* ]]
}

@test "kpi-antagonist-gate check: KPI de eficiencia sin antagonista → FAIL, BLOCKED y exit 1, también el último del fichero" {
  write_kpis "a|Defect Escape Rate|b" "b|Code Quality|a" "c|Cycle Time|"
  run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: KPI 'c' (Cycle Time) is efficiency-type and has NO antagonist"* ]]
  [[ "$output" == *"RESULT: BLOCKED — 1 KPI(s) without antagonist"* ]]
}

@test "kpi-antagonist-gate check: KPI que no es de eficiencia sin antagonista solo avisa (WARN, exit 0)" {
  write_kpis "a|Customer Satisfaction|" "b|Defect Rate|"
  run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: KPI 'a' (Customer Satisfaction) has no antagonist (non-efficiency, advisory)"* ]]
  [[ "$output" == *"WARN: KPI 'b'"* ]]
  [[ "$output" == *"RESULT: PASSED"* ]]
}

@test "kpi-antagonist-gate check: cada patrón de eficiencia, sin distinguir mayúsculas, exige antagonista" {
  for n in "Velocity" "THROUGHPUT" "Speed of release" "Cycle time" "Lead Time" "Delivery rate" "Productivity index"; do
    write_kpis "x|$n|"
    run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT"
    [ "$status" -eq 1 ] || { echo "no bloqueó: $n"; false; }
  done
  write_kpis "x|Escape Quality|"
  run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
}

@test "kpi-antagonist-gate check: cuenta todos los bloqueados" {
  write_kpis "a|Velocity|" "b|Throughput|" "c|Quality|"
  run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED — 2 KPI(s) without antagonist"* ]]
}

@test "kpi-antagonist-gate check: errores de uso" {
  run bash "$ANTAGONIST_SH" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"check: --engagement is required"* ]]
  run bash "$ANTAGONIST_SH" check --engagement "$ENGAGEMENT" --nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"check: unknown argument: --nope"* ]]
  run bash "$ANTAGONIST_SH" check --engagement otro/inexistente
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: KPI catalog not found"* ]]
}

@test "kpi-antagonist-gate validate-pair: el nombre del antagonista sale de su propio bloque" {
  run bash "$ANTAGONIST_SH" validate-pair --kpi-id kpi-001 --antagonist-id kpi-002 --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: KPI 'kpi-001' (Sprint Velocity) ↔ antagonist 'kpi-002' (Defect Escape Rate)"* ]]
  [[ "$output" == *"Pairing is valid"* ]]
  [[ "$output" != *"WARN"* ]]
}

@test "kpi-antagonist-gate validate-pair: el antagonista declarado debe coincidir (mensaje con ambos ids)" {
  run bash "$ANTAGONIST_SH" validate-pair --kpi-id kpi-001 --antagonist-id kpi-009 --engagement "$ENGAGEMENT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: KPI 'kpi-001' declares antagonist 'kpi-002', not 'kpi-009'"* ]]
  [[ "$output" != *"Pairing is valid"* ]]
}

@test "kpi-antagonist-gate validate-pair: antagonista que no parece de calidad avisa pero valida" {
  write_kpis "a|Velocity|b" "b|Team Size|a"
  run bash "$ANTAGONIST_SH" validate-pair --kpi-id a --antagonist-id b --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Antagonist 'b' (Team Size) does not appear to be a quality KPI"* ]]
  [[ "$output" == *"Pairing is valid"* ]]
}

@test "kpi-antagonist-gate validate-pair: palabras de calidad evitan el aviso" {
  for q in "Defect Density" "Error Budget" "Incident Count" "Rework" "Stability" "Reliability" "User Satisfaction" "NPS"; do
    write_kpis "a|Velocity|b" "b|$q|a"
    run bash "$ANTAGONIST_SH" validate-pair --kpi-id a --antagonist-id b --engagement "$ENGAGEMENT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]] || { echo "aviso inesperado con: $q"; false; }
  done
}

@test "kpi-antagonist-gate validate-pair: KPI no eficiente no evalúa la calidad del antagonista" {
  write_kpis "a|Defect Rate|b" "b|Team Size|a"
  run bash "$ANTAGONIST_SH" validate-pair --kpi-id a --antagonist-id b --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARN"* ]]
}

@test "kpi-antagonist-gate validate-pair: faltan argumentos o catálogo → exit 1 con mensaje" {
  run bash "$ANTAGONIST_SH" validate-pair --antagonist-id x --engagement "$ENGAGEMENT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--kpi-id is required"* ]]
  run bash "$ANTAGONIST_SH" validate-pair --kpi-id x --engagement "$ENGAGEMENT"
  [[ "$output" == *"--antagonist-id is required"* ]]
  run bash "$ANTAGONIST_SH" validate-pair --kpi-id x --antagonist-id y
  [[ "$output" == *"--engagement is required"* ]]
  run bash "$ANTAGONIST_SH" validate-pair --kpi-id x --antagonist-id y --engagement otro/no
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: KPI catalog not found"* ]]
}

chain() {  # chain h1 h2 ... → una línea por periodo
  local i=0 h
  : > "$ENG_DIR/kpi-chain.jsonl"
  for h in "$@"; do
    i=$((i + 1))
    printf '{"period":"2026-%02d","data_hash":"%s"}\n' "$i" "$h" >> "$ENG_DIR/kpi-chain.jsonl"
  done
}

@test "kpi-antagonist-gate anomaly: sin cadena de datos → mensaje y exit 0" {
  run bash "$ANTAGONIST_SH" anomaly --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No KPI chain data available"* ]]
  [[ "$output" == *"Threshold: 30% abrupt change"* ]]
}

@test "kpi-antagonist-gate anomaly: menos de 2 periodos no se evalúa, y el umbral se refleja" {
  chain h1
  run bash "$ANTAGONIST_SH" anomaly --engagement "$ENGAGEMENT" --threshold-pct 45
  [ "$status" -eq 0 ]
  [[ "$output" == *"Threshold: 45% abrupt change"* ]]
  [[ "$output" == *"Need at least 2 periods for anomaly detection (have 1)"* ]]
}

@test "kpi-antagonist-gate anomaly: cambio y luego congelación se marca (h1,h2,h2)" {
  chain h1 h2 h2
  run bash "$ANTAGONIST_SH" anomaly --engagement "$ENGAGEMENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ANOMALY: Period 2026-03 shows no data change vs 2026-02"* ]]
  [[ "$output" == *"Total anomalies: 1"* ]]
  [[ "$output" == *"Goodhart"* ]]
}

@test "kpi-antagonist-gate anomaly: datos siempre distintos o siempre iguales no son anomalía" {
  chain h1 h2 h3 h4
  run bash "$ANTAGONIST_SH" anomaly --engagement "$ENGAGEMENT"
  [[ "$output" == *"No anomalies detected across 4 periods"* ]]
  chain h1 h1 h1
  run bash "$ANTAGONIST_SH" anomaly --engagement "$ENGAGEMENT"
  [[ "$output" == *"No anomalies detected across 3 periods"* ]]
  [[ "$output" != *"ANOMALY"* ]]
}

@test "kpi-antagonist-gate anomaly: dos periodos congelados tras un cambio cuentan una sola vez cada vez que se rompe la racha" {
  chain h1 h2 h2 h3 h3
  run bash "$ANTAGONIST_SH" anomaly --engagement "$ENGAGEMENT"
  [[ "$output" == *"Total anomalies: 2"* ]]
  [[ "$output" == *"Period 2026-03 shows no data change vs 2026-02"* ]]
  [[ "$output" == *"Period 2026-05 shows no data change vs 2026-04"* ]]
}

@test "kpi-antagonist-gate: sin argumentos o con --help imprime uso (exit 0); subcomando desconocido → 2" {
  run bash "$ANTAGONIST_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Anti-Goodhart gate"* ]]
  run bash "$ANTAGONIST_SH" --help
  [ "$status" -eq 0 ]
  run bash "$ANTAGONIST_SH" frobnicar
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown subcommand: frobnicar"* ]]
}
