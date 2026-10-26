#!/usr/bin/env bats
# tests/bats/test-spec-046-visual-diff.bats — SPEC-046: Visual Diff QA at Merge Time

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/visual-diff-merge-check.sh"
TMP_DIR=""

setup() {
    TMP_DIR="$(mktemp -d)"
    mkdir -p "$TMP_DIR/baseline" "$TMP_DIR/candidate" "$TMP_DIR/output"
    # Create tiny fake PNG files (1x1 pixel, identical)
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' \
        > "$TMP_DIR/baseline/home--desktop.png"
    cp "$TMP_DIR/baseline/home--desktop.png" "$TMP_DIR/candidate/home--desktop.png"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ── test 1: missing --pr-id → exit 3 ─────────────────────────────────────────
@test "SPEC-046: missing --pr-id exits with code 3" {
    run bash "$SCRIPT" \
        --baseline-dir "$TMP_DIR/baseline" \
        --candidate-dir "$TMP_DIR/candidate"
    [ "$status" -eq 3 ]
}

# ── test 2: missing baseline dir → exit 3 ────────────────────────────────────
@test "SPEC-046: missing baseline-dir exits with code 3" {
    run bash "$SCRIPT" --pr-id "PR-TEST" \
        --baseline-dir "/nonexistent/path" \
        --candidate-dir "$TMP_DIR/candidate"
    [ "$status" -eq 3 ]
}

# ── test 3: identical screenshots → PASS (exit 0) ────────────────────────────
@test "SPEC-046: identical screenshots → PASS exit 0" {
    run bash "$SCRIPT" \
        --pr-id "PR-IDENTICAL" \
        --baseline-dir "$TMP_DIR/baseline" \
        --candidate-dir "$TMP_DIR/candidate" \
        --output-base "$TMP_DIR/output" \
        --dry-run
    [ "$status" -eq 0 ]
}

# ── test 4: report.json is created ───────────────────────────────────────────
@test "SPEC-046: report.json created after run" {
    run bash "$SCRIPT" \
        --pr-id "PR-REPORT" \
        --baseline-dir "$TMP_DIR/baseline" \
        --candidate-dir "$TMP_DIR/candidate" \
        --output-base "$TMP_DIR/output" \
        --dry-run
    [ -f "$TMP_DIR/output/PR-REPORT/report.json" ]
}

# ── test 5: report.json contains required fields ─────────────────────────────
@test "SPEC-046: report.json has pr_id, status, score fields" {
    bash "$SCRIPT" \
        --pr-id "PR-FIELDS" \
        --baseline-dir "$TMP_DIR/baseline" \
        --candidate-dir "$TMP_DIR/candidate" \
        --output-base "$TMP_DIR/output" \
        --dry-run >/dev/null 2>&1 || true

    REPORT="$TMP_DIR/output/PR-FIELDS/report.json"
    [ -f "$REPORT" ]
    grep -q '"pr_id"' "$REPORT"
    grep -q '"status"' "$REPORT"
    grep -q '"score"' "$REPORT"
}

# ── test 6: no screenshots → SKIP (exit 0, status=SKIP) ──────────────────────
@test "SPEC-046: no matched screenshots → SKIP status in report" {
    mkdir -p "$TMP_DIR/empty-baseline" "$TMP_DIR/empty-candidate"
    bash "$SCRIPT" \
        --pr-id "PR-EMPTY" \
        --baseline-dir "$TMP_DIR/empty-baseline" \
        --candidate-dir "$TMP_DIR/empty-candidate" \
        --output-base "$TMP_DIR/output" \
        --dry-run >/dev/null 2>&1 || true

    REPORT="$TMP_DIR/output/PR-EMPTY/report.json"
    [ -f "$REPORT" ]
    grep -q '"SKIP"' "$REPORT"
}

# ── test 7: report.md is created ─────────────────────────────────────────────
@test "SPEC-046: report.md is created alongside report.json" {
    bash "$SCRIPT" \
        --pr-id "PR-MD" \
        --baseline-dir "$TMP_DIR/baseline" \
        --candidate-dir "$TMP_DIR/candidate" \
        --output-base "$TMP_DIR/output" \
        --dry-run >/dev/null 2>&1 || true

    [ -f "$TMP_DIR/output/PR-MD/report.md" ]
}

# ── Comportamiento: puntuación y puerta con `compare` simulado (SE-456) ───────
# `compare` real depende de ImageMagick; se sustituye por un ejecutable que
# imprime la métrica MAE normalizada pedida en FAKE_MAE, de modo que el
# porcentaje de diferencia es exacto (FAKE_MAE=0.08 equivale a un 8 %).

fake_compare() {
    mkdir -p "$TMP_DIR/bin"
    cat > "$TMP_DIR/bin/compare" <<'EOS'
#!/usr/bin/env bash
echo "1234 (${FAKE_MAE:-0})" >&2
exit 1
EOS
    chmod +x "$TMP_DIR/bin/compare"
}

run_vd() {  # run_vd <pr> <mae> [args extra...]
    local pr="$1" mae="$2"; shift 2
    fake_compare
    FAKE_MAE="$mae" PATH="$TMP_DIR/bin:$PATH" run bash "$SCRIPT" --pr-id "$pr" \
        --baseline-dir "$TMP_DIR/baseline" --candidate-dir "$TMP_DIR/candidate" \
        --output-base "$TMP_DIR/output" "$@"
    REPORT="$TMP_DIR/output/$pr/report.json"
}

@test "SPEC-046: diferencia 0 % → PASS con nota máxima, exit 0 y vistas listadas" {
    run_vd PR-ZERO 0
    [ "$status" -eq 0 ]
    [ "$(jq -r .status "$REPORT")" = "PASS" ]
    [ "$(jq -r .score "$REPORT")" -eq 100 ]
    [ "$(jq -r .pairs_analyzed "$REPORT")" -eq 1 ]
    [ "$(jq -r .gate_action "$REPORT")" = "auto-pass" ]
    [ "$(jq -r '.pairs[0].view' "$REPORT")" = "home--desktop.png" ]
}

@test "SPEC-046: diferencia menor del 1 % sigue produciendo un report.json válido" {
    run_vd PR-SMALL 0.004
    [ "$status" -eq 0 ]
    jq -e . "$REPORT" >/dev/null
    [ "$(jq -r .status "$REPORT")" = "PASS" ]
    [ "$(jq '.avg_pixel_diff_pct < 1' "$REPORT")" = "true" ]
    [ "$(jq '.pairs[0].pixel_diff_pct < 1' "$REPORT")" = "true" ]
}

@test "SPEC-046: 8 % de diferencia → pixel 92, semántica 100, nota final 95, PASS" {
    run_vd PR-8 0.08
    [ "$status" -eq 0 ]
    [ "$(jq -r .pixel_score "$REPORT")" -eq 92 ]
    [ "$(jq -r .semantic_score "$REPORT")" -eq 100 ]
    [ "$(jq -r .score "$REPORT")" -eq 95 ]
    [ "$(jq -r .status "$REPORT")" = "PASS" ]
}

@test "SPEC-046: 50 % de diferencia → auto-fail: semántica 40, nota 46, FAIL, con --blocking true sale 1" {
    run_vd PR-50 0.50 --blocking true
    [ "$status" -eq 1 ]
    [ "$(jq -r .pixel_score "$REPORT")" -eq 50 ]
    [ "$(jq -r .semantic_score "$REPORT")" -eq 40 ]
    [ "$(jq -r .score "$REPORT")" -eq 46 ]
    [ "$(jq -r .status "$REPORT")" = "FAIL" ]
    [ "$(jq -r .gate_action "$REPORT")" = "block" ]
    [ "$(jq -r .blocking "$REPORT")" = "true" ]
}

@test "SPEC-046: el mismo FAIL sin --blocking no bloquea (exit 0) pero queda registrado" {
    run_vd PR-50NB 0.50
    [ "$status" -eq 0 ]
    [ "$(jq -r .status "$REPORT")" = "FAIL" ]
    [ "$(jq -r .blocking "$REPORT")" = "false" ]
}

@test "SPEC-046: zona intermedia con --dry-run → semántica = pixel, REVIEW y exit 2" {
    run_vd PR-25 0.25 --dry-run
    [ "$status" -eq 2 ]
    [ "$(jq -r .pixel_score "$REPORT")" -eq 75 ]
    [ "$(jq -r .semantic_score "$REPORT")" -eq 75 ]
    [ "$(jq -r .score "$REPORT")" -eq 75 ]
    [ "$(jq -r .status "$REPORT")" = "REVIEW" ]
    [ "$(jq -r .gate_action "$REPORT")" = "informational-warning" ]
}

@test "SPEC-046: zona intermedia sin --dry-run suma 5 de indulgencia semántica" {
    run_vd PR-25B 0.25
    [ "$status" -eq 2 ]
    [ "$(jq -r .semantic_score "$REPORT")" -eq 80 ]
    [ "$(jq -r .score "$REPORT")" -eq 77 ]
}

@test "SPEC-046: REVIEW nunca bloquea aunque --blocking sea true (exit 2, no 1)" {
    run_vd PR-25C 0.25 --blocking true
    [ "$status" -eq 2 ]
}

@test "SPEC-046: límite 90 en la nota final: 12 % cae en PASS justo" {
    run_vd PR-12 0.12
    [ "$status" -eq 0 ]
    [ "$(jq -r .pixel_score "$REPORT")" -eq 88 ]
    [ "$(jq -r .semantic_score "$REPORT")" -eq 93 ]
    [ "$(jq -r .score "$REPORT")" -eq 90 ]
    [ "$(jq -r .status "$REPORT")" = "PASS" ]
}

@test "SPEC-046: el informe markdown lista pares, métricas y vistas sin pareja" {
    echo "x" > "$TMP_DIR/baseline/solo-base.png"
    run_vd PR-MDX 0
    [ "$status" -eq 0 ]
    md="$TMP_DIR/output/PR-MDX/report.md"
    grep -q "^# Visual Diff Report — PR PR-MDX" "$md"
    grep -q '^\*\*Status:\*\* PASS | \*\*Score:\*\* 100' "$md"
    grep -q 'home--desktop.png`: pixel_diff=' "$md"
    grep -q "## Unmatched" "$md"
    grep -q 'solo-base.png' "$md"
    [ -f "$TMP_DIR/output/PR-MDX/diffs/home--desktop-diff.txt" ]
}

@test "SPEC-046: sin vistas sin pareja el markdown no tiene sección Unmatched" {
    run_vd PR-NOUN 0
    ! grep -q "## Unmatched" "$TMP_DIR/output/PR-NOUN/report.md"
}

@test "SPEC-046: varias parejas promedian la diferencia" {
    cp "$TMP_DIR/baseline/home--desktop.png" "$TMP_DIR/baseline/b.png"
    cp "$TMP_DIR/baseline/home--desktop.png" "$TMP_DIR/candidate/b.png"
    run_vd PR-TWO 0.10
    [ "$(jq -r .pairs_analyzed "$REPORT")" -eq 2 ]
    [ "$(jq -r '.pairs|length' "$REPORT")" -eq 2 ]
    [ "$(jq '.avg_pixel_diff_pct == 10' "$REPORT")" = "true" ]
    [ "$(jq -r .pixel_score "$REPORT")" -eq 90 ]
}

@test "SPEC-046: sin ImageMagick usa el tamaño de fichero como proxy de la diferencia" {
    # 1000 bytes frente a 900: 10 % de diferencia
    head -c 1000 /dev/zero > "$TMP_DIR/baseline/home--desktop.png"
    head -c 900 /dev/zero > "$TMP_DIR/candidate/home--desktop.png"
    mkdir -p "$TMP_DIR/nobin"
    for t in bash bc find sort mkdir cat date wc basename head grep xargs printf echo tr cut; do
        p="$(command -v "$t" 2>/dev/null)" && [[ -x "$p" ]] && ln -sf "$p" "$TMP_DIR/nobin/$t"
    done
    PATH="$TMP_DIR/nobin" run "$TMP_DIR/nobin/bash" "$SCRIPT" --pr-id PR-SIZE \
        --baseline-dir "$TMP_DIR/baseline" --candidate-dir "$TMP_DIR/candidate" \
        --output-base "$TMP_DIR/output" --dry-run
    REPORT="$TMP_DIR/output/PR-SIZE/report.json"
    [ -f "$REPORT" ]
    jq -e . "$REPORT" >/dev/null
    [ "$(jq -r .pixel_score "$REPORT")" -eq 90 ]
    [ "$(jq '.avg_pixel_diff_pct == 10' "$REPORT")" = "true" ]
}

@test "SPEC-046: argumento desconocido y candidate-dir inexistente salen con 3 y mensaje" {
    run bash "$SCRIPT" --zzz
    [ "$status" -eq 3 ]
    [[ "$output" == *"Unknown arg: --zzz"* ]]
    run bash "$SCRIPT" --pr-id X --baseline-dir "$TMP_DIR/baseline" --candidate-dir /no/existe
    [ "$status" -eq 3 ]
    [[ "$output" == *"--candidate-dir '/no/existe' not found"* ]]
}

@test "SPEC-046: baseline sin pareja en el candidato → SKIP con motivo y exit 0" {
    rm "$TMP_DIR/baseline/home--desktop.png"
    echo x > "$TMP_DIR/baseline/otra.png"
    run bash "$SCRIPT" --pr-id PR-SKIP --baseline-dir "$TMP_DIR/baseline" \
        --candidate-dir "$TMP_DIR/candidate" --output-base "$TMP_DIR/output"
    [ "$status" -eq 0 ]
    r="$TMP_DIR/output/PR-SKIP/report.json"
    [ "$(jq -r .status "$r")" = "SKIP" ]
    [ "$(jq -r .reason "$r")" = "no_matched_pairs" ]
    [ "$(jq -r .pairs_analyzed "$r")" -eq 0 ]
    [ "$(jq -r .score "$r")" = "null" ]
}
