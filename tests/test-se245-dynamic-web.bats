#!/usr/bin/env bats
# SE-245 — Dynamic Web Security Testing — BATS tests

setup() {
    cd "$BATS_TEST_DIRNAME/.."
    SCRIPT="$PWD/scripts/dynamic-web-security-test.sh"
    SKILL="$PWD/.opencode/skills/dynamic-web-tester/SKILL.md"
    OUTPUT_DIR="$PWD/output/security"
    TEST_HOST="localhost"
    TEST_TARGET="http://localhost:19999"
    AUTH_FILE="${OUTPUT_DIR}/authorization-${TEST_HOST}.txt"
}

teardown() {
    rm -f "${OUTPUT_DIR}/authorization-${TEST_HOST}.txt" 2>/dev/null || true
}

# Test 1: dynamic-web-security-test.sh exists and passes bash -n
@test "dynamic-web-security-test.sh exists and passes bash -n" {
    [[ -f "$SCRIPT" ]]
    bash -n "$SCRIPT"
}

# Test 2: dynamic-web-tester/SKILL.md exists and <= 150 lines
@test "dynamic-web-tester/SKILL.md exists and <= 150 lines" {
    [[ -f "$SKILL" ]]
    line_count=$(wc -l < "$SKILL")
    [[ "$line_count" -le 150 ]]
}

# Test 3: Without authorization file → exit 1
@test "without authorization file, exits 1" {
    rm -f "$AUTH_FILE" 2>/dev/null || true
    run bash "$SCRIPT" --target "$TEST_TARGET"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ [Aa]uthor ]]
}

# Test 4: dynamic-web-security-test.sh accepts --target
@test "dynamic-web-security-test.sh accepts --target flag" {
    grep -q -- '--target' "$SCRIPT"
}

# Test 5: --safe mode is default (on)
@test "safe mode is default (SAFE=true on startup)" {
    grep -q 'SAFE="true"' "$SCRIPT"
}

# Test 6: dynamic-web-security-test.sh accepts --tools
@test "dynamic-web-security-test.sh accepts --tools flag" {
    grep -q -- '--tools' "$SCRIPT"
}

# Test 7: sqlmap uses --level 1 --risk 1 --batch (non-aggressive)
@test "sqlmap invocation uses --level 1 --risk 1 --batch" {
    grep -q -- '"--level"' "$SCRIPT" || grep -q -- '--level' "$SCRIPT"
    grep -q -- '"--risk"' "$SCRIPT" || grep -q -- '--risk' "$SCRIPT"
    grep -q -- '"--batch"' "$SCRIPT" || grep -q -- '--batch' "$SCRIPT"
    # Verify the values are 1
    grep -q '"1"' "$SCRIPT"
}

# Test 8: Report goes to output/security/
@test "report is written to output/security/" {
    grep -q 'output/security' "$SCRIPT"
}

# Test 9: SKILL.md mentions authorization
@test "SKILL.md mentions authorization" {
    grep -qi "autorización\|authorization\|autorizar\|authorize" "$SKILL"
}

# Test 10: dynamic-web-security-test.sh has set -uo pipefail
@test "dynamic-web-security-test.sh has set -uo pipefail" {
    grep -q "set -uo pipefail" "$SCRIPT"
}

# ── S03t: comportamiento real en un árbol temporal con herramientas simuladas ──
# El script deriva REPO_ROOT de su propia ruta: se copia a un árbol aislado
# (BATS_TEST_TMPDIR, que bats limpia solo) para no tocar output/security/ del
# repo y se simulan dalfox/sqlmap/nuclei/docker.

s03t_sandbox() {
    SB="$BATS_TEST_TMPDIR/sb"
    mkdir -p "$SB/scripts" "$SB/output/security" "$SB/bin"
    cp "$SCRIPT" "$SB/scripts/dynamic-web-security-test.sh"
    CALLS="$SB/calls.log"
    : > "$CALLS"
    if [ "${1:-}" != "notools" ]; then
        for t in dalfox sqlmap nuclei; do
            printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\nexit 0\n' "$t" "$CALLS" > "$SB/bin/$t"
            chmod +x "$SB/bin/$t"
        done
    fi
    # docker simulado: "info" falla (sin demonio) y cualquier otro uso queda registrado
    printf '#!/usr/bin/env bash\nif [ "${1:-}" = info ]; then exit 1; fi\necho "docker $*" >> "%s"\nexit 0\n' "$CALLS" > "$SB/bin/docker"
    chmod +x "$SB/bin/docker"
    # PATH hermético: solo las utilidades que usa el script. Así un dalfox,
    # sqlmap, nuclei o docker real del host nunca entra en la prueba.
    mkdir -p "$SB/sys"
    for u in bash env cat cut date dirname basename head mkdir sed stat tr grep; do
        ln -sf "$(command -v "$u")" "$SB/sys/$u"
    done
    RUN="$SB/scripts/dynamic-web-security-test.sh"
}

s03t_authorize() { printf '%b\n' "${2:-AUTHORIZED}" > "$SB/output/security/authorization-$1.txt"; }

s03t_run() { run env PATH="$SB/bin:$SB/sys" "$SB/sys/bash" "$RUN" "$@"; }

@test "authorized host runs only the requested tool with its exact conservative arguments" {
    s03t_sandbox; s03t_authorize localhost
    s03t_run --target http://localhost:19999/app --tools sqli
    [ "$status" -eq 0 ]
    grep -qx 'sqlmap -u http://localhost:19999/app --forms --batch --level 1 --risk 1 --output-dir .*/sqlmap --quiet' "$CALLS"
    run grep -c -E '^(dalfox|nuclei)' "$CALLS"
    [ "$output" = "0" ]
}

@test "default tools run xss, sqli and nuclei in that order" {
    s03t_sandbox; s03t_authorize localhost
    s03t_run --target http://localhost:19999
    [ "$status" -eq 0 ]
    [ "$(cut -d' ' -f1 "$CALLS" | tr '\n' ' ')" = "dalfox sqlmap nuclei " ]
    grep -q '^dalfox url http://localhost:19999 --output .*dalfox-results.json --format json --silence' "$CALLS"
    grep -q '^nuclei -u http://localhost:19999 -tags xss,sqli,lfi -silent -json -o .*nuclei-results.json' "$CALLS"
}

@test "missing authorization file blocks before any scanner runs" {
    s03t_sandbox
    s03t_run --target http://localhost:19999
    [ "$status" -eq 1 ]
    [[ "$output" == *"Authorization file not found"* ]]
    [ ! -s "$CALLS" ]
    [ -z "$(ls "$SB/output/security")" ]
}

@test "authorization file without the word AUTHORIZED blocks and runs nothing" {
    s03t_sandbox; s03t_authorize localhost "yes, go ahead"
    s03t_run --target http://localhost:19999
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not start with the line 'AUTHORIZED'"* ]]
    [ ! -s "$CALLS" ]
}

@test "authorization file saying UNAUTHORIZED must not authorize the scan" {
    s03t_sandbox; s03t_authorize localhost "UNAUTHORIZED"
    s03t_run --target http://localhost:19999
    [ "$status" -eq 1 ]
    [ ! -s "$CALLS" ]
}

@test "authorization file saying NOT AUTHORIZED must not authorize the scan" {
    s03t_sandbox; s03t_authorize localhost "NOT AUTHORIZED"
    s03t_run --target http://localhost:19999
    [ "$status" -eq 1 ]
    [ ! -s "$CALLS" ]
}

# P1-1 de la revisión de seguridad: una denylist de negaciones fallaba abierta.
# Cada variante contiene AUTHORIZED como palabra suelta sin negador pegado.
@test "negated or annotated AUTHORIZED variants must not authorize the scan" {
    s03t_sandbox
    for v in 'NOT  AUTHORIZED' 'NOT\tAUTHORIZED' 'NOT YET AUTHORIZED' 'NOT\nAUTHORIZED' \
             'Authorization REVOKED (was AUTHORIZED)' 'AUTHORIZED by owner' ' AUTHORIZED' 'authorized'; do
        s03t_authorize localhost "$v"
        s03t_run --target http://localhost:19999 --tools nuclei
        [ "$status" -eq 1 ] || { echo "aceptó: $v"; false; }
        [ ! -s "$CALLS" ] || { echo "lanzó escáner con: $v"; false; }
    done
}

@test "first line exactly AUTHORIZED authorizes, also with CRLF and notes on later lines" {
    s03t_sandbox
    for v in 'AUTHORIZED' 'AUTHORIZED\r' 'AUTHORIZED\nscope: localhost, owner ticket 42'; do
        s03t_authorize localhost "$v"
        : > "$CALLS"
        s03t_run --target http://localhost:19999 --tools nuclei
        [ "$status" -eq 0 ] || { echo "rechazó: $v"; false; }
        [ "$(cut -d' ' -f1 "$CALLS")" = "nuclei" ]
    done
}

@test "authorization is per host: a file for another host does not cover the target" {
    s03t_sandbox; s03t_authorize otherhost
    s03t_run --target http://localhost:19999
    [ "$status" -eq 1 ]
    [[ "$output" == *"authorization-localhost.txt"* ]]
    [ ! -s "$CALLS" ]
}

@test "host is extracted without scheme, port or path" {
    s03t_sandbox; s03t_authorize example.org
    s03t_run --target "https://example.org:8443/a/b?c=d" --tools nuclei
    [ "$status" -eq 0 ]
    [[ "$output" == *"Host: example.org"* ]]
    [[ "$output" == *"Authorization verified for host: example.org"* ]]
}

@test "authorization file 29 days old still valid, 31 days old expired" {
    s03t_sandbox; s03t_authorize localhost
    touch -d '29 days ago' "$SB/output/security/authorization-localhost.txt"
    s03t_run --target http://localhost:19999 --tools nuclei
    [ "$status" -eq 0 ]
    touch -d '31 days ago' "$SB/output/security/authorization-localhost.txt"
    : > "$CALLS"
    s03t_run --target http://localhost:19999 --tools nuclei
    [ "$status" -eq 1 ]
    [[ "$output" == *"older than 30 days"* ]]
    [ ! -s "$CALLS" ]
}

@test "missing --target exits 1 with usage and nothing is run" {
    s03t_sandbox; s03t_authorize localhost
    s03t_run --tools xss
    [ "$status" -eq 1 ]
    [[ "$output" == *"--target is required"* ]]
    [ ! -s "$CALLS" ]
}

@test "unknown option exits 1" {
    s03t_sandbox; s03t_authorize localhost
    s03t_run --target http://localhost:19999 --aggressive
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: --aggressive"* ]]
    [ ! -s "$CALLS" ]
}

@test "unknown tool name is warned and skipped while valid tools still run" {
    s03t_sandbox; s03t_authorize localhost
    s03t_run --target http://localhost:19999 --tools bogus,nuclei
    [ "$status" -eq 0 ]
    [[ "$output" == *"[warn] Unknown tool: bogus"* ]]
    [ "$(cut -d' ' -f1 "$CALLS")" = "nuclei" ]
}

@test "consolidated JSON report is valid and records target, host, safe mode and tools" {
    s03t_sandbox; s03t_authorize localhost
    s03t_run --target http://localhost:19999 --tools nuclei
    [ "$status" -eq 0 ]
    rep="$(ls "$SB"/output/security/dynamic-test-localhost-*.json)"
    run python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
assert d['target']=='http://localhost:19999', d
assert d['host']=='localhost'
assert d['safe_mode'] is True
assert d['tools']=='nuclei'
assert d['nuclei_results'].endswith('nuclei-results.json')
" "$rep"
    [ "$status" -eq 0 ]
}

@test "scanner binaries missing and no docker daemon: each tool is skipped with exit 0" {
    s03t_sandbox notools; s03t_authorize localhost
    s03t_run --target http://localhost:19999
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dalfox] SKIP"* ]]
    [[ "$output" == *"[sqlmap] SKIP"* ]]
    [[ "$output" == *"[nuclei] SKIP"* ]]
    [ ! -s "$CALLS" ]
}

@test "authorization file with a future timestamp is rejected, a fresh one is accepted" {
    s03t_sandbox; s03t_authorize localhost
    touch -d '10 days' "$SB/output/security/authorization-localhost.txt"
    s03t_run --target http://localhost:19999 --tools nuclei
    [ "$status" -eq 1 ]
    [[ "$output" == *"future timestamp"* ]]
    [ ! -s "$CALLS" ]
    touch "$SB/output/security/authorization-localhost.txt"
    s03t_run --target http://localhost:19999 --tools nuclei
    [ "$status" -eq 0 ]
}
