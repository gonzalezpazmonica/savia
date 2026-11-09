#!/usr/bin/env bats
# SE-243 — Attack Surface Mapping — BATS tests

setup() {
    cd "$BATS_TEST_DIRNAME/.."
    SKILL="$PWD/.opencode/skills/attack-surface-mapper/SKILL.md"
    # Isolated copy: both scripts derive output/security from their own path,
    # so nothing is written in the real repo. Fake tools on PATH log their argv:
    # no real scanner (nor Docker) is ever started.
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/scripts"
    cp scripts/attack-surface-map.sh scripts/surface-map-authorize.sh "$REPO/scripts/"
    SCRIPT="$REPO/scripts/attack-surface-map.sh"
    AUTHORIZE="$REPO/scripts/surface-map-authorize.sh"
    OUTPUT_DIR="$REPO/output/security"
    # Use a safe test target alias
    TEST_TARGET="test-target-se243.local"
    AUTH_FILE="${OUTPUT_DIR}/authorization-${TEST_TARGET}.txt"
    FAKEBIN="$BATS_TEST_TMPDIR/fakebin"
    TOOLLOG="$BATS_TEST_TMPDIR/tools.log"
    mkdir -p "$FAKEBIN" "$OUTPUT_DIR"
    for t in httpx theHarvester dnstwist docker; do
        printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "$t" "$TOOLLOG" > "$FAKEBIN/$t"
        chmod +x "$FAKEBIN/$t"
    done
    # subfinder -d <target> -silent -o <file>: logs argv, writes two subdomains.
    cat > "$FAKEBIN/subfinder" <<FAKE
#!/usr/bin/env bash
echo "subfinder \$*" >> "$TOOLLOG"
out="\${@: -1}"; printf 'a.%s\nb.%s\n' "\$2" "\$2" > "\$out"
FAKE
    chmod +x "$FAKEBIN/subfinder"
    export PATH="$FAKEBIN:$PATH"
}

# Test 1: attack-surface-map.sh exists and passes bash -n
@test "attack-surface-map.sh exists and passes bash -n" {
    [[ -f "$SCRIPT" ]]
    bash -n "$SCRIPT"
}

# Test 2: surface-map-authorize.sh exists and passes bash -n
@test "surface-map-authorize.sh exists and passes bash -n" {
    [[ -f "$AUTHORIZE" ]]
    bash -n "$AUTHORIZE"
}

# Test 3: attack-surface-mapper/SKILL.md exists and <= 150 lines
@test "attack-surface-mapper/SKILL.md exists and <= 150 lines" {
    [[ -f "$SKILL" ]]
    line_count=$(wc -l < "$SKILL")
    [[ "$line_count" -le 150 ]]
}

# Test 4: Without authorization file → exit 1 with explanatory message
@test "without authorization file, exits 1 with explanatory message" {
    run bash "$SCRIPT" --target "$TEST_TARGET"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ [Aa]uthor ]]
    [[ "$output" == *"Authorization file not found: $AUTH_FILE"* ]]
    [[ ! -e "$TOOLLOG" ]]
}

# Test 5: Authorization gate verifies file age (< 30 days passes, old fails)
@test "authorization gate accepts fresh file and rejects stale file" {
    # Fresh file (just created) should pass age check
    echo "AUTHORIZED" > "$AUTH_FILE"
    run bash "$SCRIPT" --target "$TEST_TARGET" --tools subfinder
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[auth] Authorization verified for target: $TEST_TARGET"* ]]

    # Simulate stale file by backdating (touch -d 31 days ago)
    if touch -d "31 days ago" "$AUTH_FILE" 2>/dev/null; then
        run bash "$SCRIPT" --target "$TEST_TARGET" --tools subfinder
        [[ "$status" -eq 1 ]]
        [[ "$output" =~ "older than 30 days" ]]
    else
        skip "touch -d not available on this platform"
    fi
}

# Test 6: attack-surface-map.sh accepts --target
@test "attack-surface-map.sh accepts --target flag" {
    grep -q -- '--target' "$SCRIPT"
}

# Test 7: attack-surface-map.sh accepts --tools
@test "attack-surface-map.sh accepts --tools flag" {
    grep -q -- '--tools' "$SCRIPT"
}

# Test 8: With subfinder not available, falls back to Docker
@test "script has Docker fallback for subfinder" {
    grep -q "projectdiscovery/subfinder" "$SCRIPT"
}

# Test 9: SKILL.md mentions authorization
@test "SKILL.md mentions authorization" {
    grep -qi "autorización\|authorization\|autorizar\|authorize" "$SKILL"
}

# Test 10: surface-map-authorize.sh creates file in output/security/
@test "surface-map-authorize.sh creates auth file in output/security/" {
    grep -q "output/security" "$AUTHORIZE"
    grep -q "authorization-" "$AUTHORIZE"
}

# ── Behaviour of the authorization gate and of --target (S03s) ──
L63=$(printf 'a%.0s' $(seq 63))

@test "gate: a file saying NOT AUTHORIZED or UNAUTHORIZED is rejected and no tool runs (security)" {
    for content in "NOT AUTHORIZED" "UNAUTHORIZED" "# AUTHORIZED is required here"; do
        printf '%s\n' "$content" > "$AUTH_FILE"
        run bash "$SCRIPT" --target "$TEST_TARGET" --tools subfinder
        [[ "$status" -eq 1 ]]
        [[ "$output" == *"does not contain 'AUTHORIZED'"* ]]
    done
    [[ ! -e "$TOOLLOG" ]]
}

@test "gate: file written by surface-map-authorize is accepted end to end" {
    run bash "$AUTHORIZE" --target "$TEST_TARGET" <<< "AUTHORIZED"
    [[ "$status" -eq 0 ]]
    [[ "$(head -1 "$AUTH_FILE")" == "AUTHORIZED" ]]
    grep -qx "target: $TEST_TARGET" "$AUTH_FILE"
    grep -qx "valid_days: 30" "$AUTH_FILE"
    run bash "$SCRIPT" --target "$TEST_TARGET" --tools subfinder
    [[ "$status" -eq 0 ]]
}

@test "gate: 29-day-old authorization is still valid (boundary)" {
    echo "AUTHORIZED" > "$AUTH_FILE"
    touch -d "29 days ago" "$AUTH_FILE"
    run bash "$SCRIPT" --target "$TEST_TARGET" --tools subfinder
    [[ "$status" -eq 0 ]]
}

@test "scan: target reaches the tool as one argv value and the JSON report counts subdomains" {
    echo "AUTHORIZED" > "$AUTH_FILE"
    run bash "$SCRIPT" --target "$TEST_TARGET" --tools subfinder,dnstwist
    [[ "$status" -eq 0 ]]
    grep -q "^subfinder -d $TEST_TARGET -silent -o " "$TOOLLOG"
    grep -qx "dnstwist --registered --format json $TEST_TARGET" "$TOOLLOG"
    report=$(ls "$OUTPUT_DIR"/surface-map-"$TEST_TARGET"-*.json)
    run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["target"]==sys.argv[2] and d["subdomains_found"]==2 and d["tools"]=="subfinder,dnstwist", d' "$report" "$TEST_TARGET"
    [[ "$status" -eq 0 ]]
}

@test "scan: unknown tool is reported and nothing is run" {
    echo "AUTHORIZED" > "$AUTH_FILE"
    run bash "$SCRIPT" --target "$TEST_TARGET" --tools nmap
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[warn] Unknown tool: nmap"* ]]
    [[ ! -e "$TOOLLOG" ]]
}

@test "scan: target starting with '-' is rejected even with an authorization file (argv injection)" {
    bad="-v.example.com"
    echo "AUTHORIZED" > "${OUTPUT_DIR}/authorization-${bad}.txt"
    run bash "$SCRIPT" --target "$bad" --tools dnstwist
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--target must be a domain name"* ]]
    [[ ! -e "$TOOLLOG" ]]
}

@test "scan: target with quotes is rejected before it can break the JSON report" {
    bad='x".example.com'
    echo "AUTHORIZED" > "${OUTPUT_DIR}/authorization-${bad}.txt"
    run bash "$SCRIPT" --target "$bad" --tools nmap
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--target must be a domain name"* ]]
    [[ -z "$(ls "$OUTPUT_DIR" | grep surface-map)" ]]
}

@test "scan: --target or --tools without a value is a usage error, not an unbound variable" {
    run bash "$SCRIPT" --target
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ERROR: --target needs a value"* ]]
    run bash "$SCRIPT" --target "$TEST_TARGET" --tools
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ERROR: --tools needs a value"* ]]
}

@test "authorize: path-like target is rejected and no authorization file is written" {
    run bash "$AUTHORIZE" --target "../../escaped.example.com" <<< "AUTHORIZED"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--target must be a domain name"* ]]
    [[ "$output" != *"Authorization file created"* ]]
    [[ -z "$(find "$BATS_TEST_TMPDIR" -name '*escaped*')" ]]
}

@test "authorize: anything other than AUTHORIZED aborts without writing" {
    run bash "$AUTHORIZE" --target "$TEST_TARGET" <<< "yes"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Aborted. Authorization not granted."* ]]
    [[ ! -e "$AUTH_FILE" ]]
}

@test "authorize: empty stdin aborts (fail-closed)" {
    run bash "$AUTHORIZE" --target "$TEST_TARGET" < /dev/null
    [[ "$status" -eq 1 ]]
    [[ ! -e "$AUTH_FILE" ]]
}

@test "authorize: missing --target value, no args and unknown option are usage errors" {
    run bash "$AUTHORIZE" --target < /dev/null
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ERROR: --target needs a value"* ]]
    run bash "$AUTHORIZE" < /dev/null
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ERROR: --target is required"* ]]
    run bash "$AUTHORIZE" --bogus < /dev/null
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "authorize: 253-char domain passes validation, 254 chars is rejected (boundary)" {
    ok="$L63.$L63.$L63.$(printf 'b%.0s' $(seq 61))"
    [[ ${#ok} -eq 253 ]]
    run bash "$AUTHORIZE" --target "$ok" <<< "no"
    [[ "$output" == *"Aborted. Authorization not granted."* ]]
    long="$L63.$L63.$L63.$(printf 'b%.0s' $(seq 62))"
    [[ ${#long} -eq 254 ]]
    run bash "$AUTHORIZE" --target "$long" <<< "no"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--target must be a domain name"* ]]
}

@test "authorize: single label and 64-char label are rejected" {
    for bad in localhost "$L63"a.example.com "a..example.com" "-a.example.com" "a-.example.com" "a.example-"; do
        run bash "$AUTHORIZE" --target "$bad" <<< "AUTHORIZED"
        [[ "$status" -eq 1 ]]
        [[ "$output" == *"--target must be a domain name"* ]]
    done
}

@test "scan: single-label and over-long (254 chars) targets are rejected before the gate" {
    long="$L63.$L63.$L63.$(printf 'b%.0s' $(seq 62))"
    # No authorization file for the 254-char name: the filesystem refuses the name.
    echo "AUTHORIZED" > "${OUTPUT_DIR}/authorization-localhost.txt"
    for bad in localhost "$long"; do
        run bash "$SCRIPT" --target "$bad" --tools subfinder
        [[ "$status" -eq 1 ]]
        [[ "$output" == *"--target must be a domain name"* ]]
    done
    [[ ! -e "$TOOLLOG" ]]
}

@test "scan: theHarvester and httpx receive the target and the subdomain list" {
    echo "AUTHORIZED" > "$AUTH_FILE"
    run bash "$SCRIPT" --target "$TEST_TARGET" --tools subfinder,httpx,theharvester
    [[ "$status" -eq 0 ]]
    grep -qE "^theHarvester -d $TEST_TARGET -b bing,crtsh -f $OUTPUT_DIR/attack-surface-$TEST_TARGET-[0-9]{8}/raw/harvest$" "$TOOLLOG"
    grep -qE "^httpx -l $OUTPUT_DIR/attack-surface-$TEST_TARGET-[0-9]{8}/subdomains.txt -silent -json -o " "$TOOLLOG"
}

@test "scan: without native tools it falls back to Docker images with the same target" {
    # Only a fake docker on PATH (plus the system dirs, which have no scanner).
    [ -z "$(PATH=/usr/bin:/bin command -v subfinder theHarvester dnstwist httpx)" ] || skip "a real scanner is installed in /usr/bin"
    DOCKBIN="$BATS_TEST_TMPDIR/dockbin"; mkdir -p "$DOCKBIN"
    cat > "$DOCKBIN/docker" <<FAKE
#!/usr/bin/env bash
echo "docker \$*" >> "$TOOLLOG"
[ "\$1" = run ] && [[ "\$*" == *subfinder* ]] && printf 'a.x\n'
exit 0
FAKE
    chmod +x "$DOCKBIN/docker"
    echo "AUTHORIZED" > "$AUTH_FILE"
    PATH="$DOCKBIN:/usr/bin:/bin" run bash "$SCRIPT" --target "$TEST_TARGET" --tools subfinder,httpx,theharvester,dnstwist
    [[ "$status" -eq 0 ]]
    grep -qx "docker run --rm projectdiscovery/subfinder -d $TEST_TARGET -silent" "$TOOLLOG"
    grep -qx "docker run --rm -i projectdiscovery/httpx -silent -json" "$TOOLLOG"
    grep -qx "docker run --rm secsi/theharvester -d $TEST_TARGET -b bing,crtsh" "$TOOLLOG"
    grep -qx "docker run --rm elceef/dnstwist --registered --format json $TEST_TARGET" "$TOOLLOG"
    [[ "$output" == *"[subfinder] Done (Docker fallback)"* ]]
}
