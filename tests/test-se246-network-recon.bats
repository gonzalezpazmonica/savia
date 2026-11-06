#!/usr/bin/env bats
# SE-246 — Network Recon — BATS tests

setup() {
    cd "$BATS_TEST_DIRNAME/.."
    SCRIPT="$PWD/scripts/network-recon.sh"
    SKILL="$PWD/.opencode/skills/network-recon/SKILL.md"
    OUTPUT_DIR="$PWD/output/security"
    TEST_TARGET="test-recon-se246.local"
    AUTH_FILE="${OUTPUT_DIR}/authorization-${TEST_TARGET}.txt"
}

teardown() {
    rm -f "${OUTPUT_DIR}/authorization-${TEST_TARGET}.txt" 2>/dev/null || true
}

# Test 1: network-recon.sh exists and passes bash -n
@test "network-recon.sh exists and passes bash -n" {
    [[ -f "$SCRIPT" ]]
    bash -n "$SCRIPT"
}

# Test 2: network-recon/SKILL.md exists and <= 150 lines
@test "network-recon/SKILL.md exists and <= 150 lines" {
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

# Test 4: network-recon.sh accepts --target
@test "network-recon.sh accepts --target flag" {
    grep -q -- '--target' "$SCRIPT"
}

# Test 5: network-recon.sh accepts --ports
@test "network-recon.sh accepts --ports flag" {
    grep -q -- '--ports' "$SCRIPT"
}

# Test 6: network-recon.sh accepts --mode
@test "network-recon.sh accepts --mode flag" {
    grep -q -- '--mode' "$SCRIPT"
}

# Test 7: Discovery mode does not use aggressive nmap flags (-A, -O, --script)
@test "discovery mode does not include aggressive nmap flags" {
    # Must not have -A or -O as standalone nmap flags in the run_rustscan_nmap function
    # The safe args should only be -sV -T3 --open
    ! grep -E 'nmap_safe_args.*"-A"' "$SCRIPT"
    ! grep -E 'nmap_safe_args.*"-O"' "$SCRIPT"
    ! grep -E 'nmap_safe_args.*"--script=exploit"' "$SCRIPT"
}

# Test 8: With nmap not available, script has Docker fallback
@test "script has Docker fallback for nmap" {
    grep -q "instrumentisto/nmap" "$SCRIPT"
}

# Test 9: SKILL.md mentions authorization
@test "SKILL.md mentions authorization" {
    grep -qi "autorización\|authorization\|autorizar\|authorize" "$SKILL"
}

# Test 10: network-recon.sh has set -uo pipefail
@test "network-recon.sh has set -uo pipefail" {
    grep -q "set -uo pipefail" "$SCRIPT"
}

# ── S03r: la puerta de autorización y los argumentos, por comportamiento ─────
# Ref: SE-246. El script se copia a un árbol aislado ($BATS_TEST_TMPDIR, que
# bats limpia) con nmap/httpx falsos que registran sus argumentos y un docker
# falso que falla: ningún test escanea nada de verdad.

tree() {
  T="$BATS_TEST_TMPDIR/t"; mkdir -p "$T/scripts" "$T/output/security" "$T/bin"
  cp "$SCRIPT" "$T/scripts/"
  NR="$T/scripts/network-recon.sh"
  printf '#!/bin/sh\necho "$@" >> "%s/nmap.args"\n' "$T" > "$T/bin/nmap"
  printf '#!/bin/sh\ncat >/dev/null; echo "$@" >> "%s/httpx.args"\n' "$T" > "$T/bin/httpx"
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/docker"
  chmod +x "$T/bin/"*
  export PATH="$T/bin:$PATH"
  if [ "$(command -v rustscan)" != "" ]; then skip "real rustscan installed: would scan"; fi
}
auth() { printf '%b' "$2" > "$T/output/security/authorization-$1.txt"; }

@test "gate: valid authorization runs a discovery scan with safe nmap args only" {
  tree; auth host.invalid 'AUTHORIZED\ntarget: host.invalid\n'
  run bash "$NR" --target host.invalid --ports 80,443
  [ "$status" -eq 0 ]
  [[ "$output" == *"[auth] Authorization verified for target: host.invalid"* ]]
  [ "$(cat "$T/nmap.args")" = "-p 80,443 -sV -T3 --open -oJ $T/output/security/network-recon-host.invalid-$(date +%Y%m%d)/services.json host.invalid" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["target"]=="host.invalid" and d["mode"]=="discovery" and d["ports"]=="80,443", d' "$T/output/security/network-recon-host.invalid-$(date +%Y%m%d).json"
}

@test "gate: default ports use --top-ports 1000" {
  tree; auth host.invalid 'AUTHORIZED\n'
  run bash "$NR" --target host.invalid
  [ "$status" -eq 0 ]
  [[ "$(cat "$T/nmap.args")" == "--top-ports 1000 -sV -T3 --open "* ]]
}

@test "gate: missing authorization file blocks before any scan" {
  tree
  run bash "$NR" --target host.invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *"Authorization file not found"* ]]
  [ ! -e "$T/nmap.args" ]
}

@test "gate: 'NOT AUTHORIZED' file is rejected (substring bypass)" {
  # Antes: grep -q AUTHORIZED aceptaba «NOT AUTHORIZED» y «UNAUTHORIZED».
  tree; auth host.invalid 'NOT AUTHORIZED\n'
  run bash "$NR" --target host.invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not start with the line 'AUTHORIZED'"* ]]
  [ ! -e "$T/nmap.args" ]
  auth host.invalid 'UNAUTHORIZED\n'
  run bash "$NR" --target host.invalid
  [ "$status" -eq 1 ]
  [ ! -e "$T/nmap.args" ]
}

@test "gate: empty authorization file is rejected" {
  tree; auth host.invalid ''
  run bash "$NR" --target host.invalid
  [ "$status" -eq 1 ]
  [ ! -e "$T/nmap.args" ]
}

@test "gate: CRLF authorization written on Windows is accepted" {
  tree; auth host.invalid 'AUTHORIZED\r\n'
  run bash "$NR" --target host.invalid
  [ "$status" -eq 0 ]
}

@test "gate: authorization boundary, 29 days passes and 31 days fails" {
  tree; auth host.invalid 'AUTHORIZED\n'
  touch -d "29 days ago" "$T/output/security/authorization-host.invalid.txt"
  run bash "$NR" --target host.invalid
  [ "$status" -eq 0 ]
  touch -d "31 days ago" "$T/output/security/authorization-host.invalid.txt"
  run bash "$NR" --target host.invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *"older than 30 days"* ]]
}

@test "gate: authorization dated in the future is rejected" {
  # Antes: edad negativa → nunca caducaba.
  tree; auth host.invalid 'AUTHORIZED\n'
  touch -d "+400 days" "$T/output/security/authorization-host.invalid.txt"
  run bash "$NR" --target host.invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *"in the future"* ]]
  [ ! -e "$T/nmap.args" ]
}

@test "gate: --ports with injected nmap options is rejected (argument injection)" {
  # Antes: «80 --script=exploit» se expandía sin comillas y llegaba a nmap.
  tree; auth host.invalid 'AUTHORIZED\n'
  run bash "$NR" --target host.invalid --ports "80 --script=exploit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid --ports"* ]]
  [ ! -e "$T/nmap.args" ]
}

@test "gate: --ports accepts lists and ranges" {
  tree; auth host.invalid 'AUTHORIZED\n'
  run bash "$NR" --target host.invalid --ports 1-1024,8080
  [ "$status" -eq 0 ]
  [[ "$(cat "$T/nmap.args")" == "-p 1-1024,8080 "* ]]
}

@test "gate: target starting with '-' is rejected before reaching nmap" {
  tree; auth "-iL" 'AUTHORIZED\n'
  run bash "$NR" --target "-iL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid --target"* ]]
  [ ! -e "$T/nmap.args" ]
}

@test "gate: target with spaces or traversal is rejected" {
  tree
  run bash "$NR" --target "a b"
  [ "$status" -eq 1 ]
  run bash "$NR" --target "x/../../y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid --target"* ]]
}

@test "gate: unknown mode is rejected after authorization, without scanning" {
  tree; auth host.invalid 'AUTHORIZED\n'
  run bash "$NR" --target host.invalid --mode exploit
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown mode 'exploit'"* ]]
  [ ! -e "$T/nmap.args" ]
}

@test "gate: missing --target and unknown option exit 1 with usage" {
  tree
  run bash "$NR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--target is required"* ]]
  run bash "$NR" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "gate: unreadable authorization date fails closed with a clear error" {
  tree; auth host.invalid 'AUTHORIZED\n'
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/stat"; chmod +x "$T/bin/stat"
  run bash "$NR" --target host.invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read the authorization file date"* ]]
  [ ! -e "$T/nmap.args" ]
}
