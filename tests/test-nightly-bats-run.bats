#!/usr/bin/env bats
# Tests de scripts/nightly-bats-run.sh: el ejecutor de la suite nocturna (nightly-full-bats.yml).
# Usa un bats falso (NIGHTLY_BATS_BIN) que decide el código de salida por el contenido de la suite.

SCRIPT="scripts/nightly-bats-run.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  T="$BATS_TEST_TMPDIR"
  OUT="$T/out"
  mkdir -p "$T/suites"
  # bats falso: registra la suite en orden y sale con el código que pida su línea `rc=`.
  cat > "$T/fakebats" <<EOF
#!/bin/bash
echo "\$1" >> "$T/order.log"
grep -q '^kill-runner' "\$1" && kill -KILL "\$(ps -o ppid= -p \$PPID | tr -d ' ')"
exit "\$(sed -n 's/^rc=//p' "\$1")"
EOF
  chmod +x "$T/fakebats"
  export NIGHTLY_BATS_BIN="$T/fakebats" NIGHTLY_TIMEOUT_S=30
}

suite() {  # suite <nombre> <rc> [serial|kill]
  local f="$T/suites/$1"
  { [[ "${3:-}" == serial ]] && echo '# nightly: serial'
    [[ "${3:-}" == kill ]] && echo 'kill-runner'
    echo "rc=$2"; } > "$f"
  printf '%s' "$f"
}

@test "sintaxis válida" { bash -n "$SCRIPT"; }

@test "cuenta total y fallidas; solo key=value por stdout" {
  a=$(suite ok.bats 0); b=$(suite ko.bats 1)
  run bash "$SCRIPT" "$OUT" "$a" "$b"
  [ "$status" -eq 0 ]
  [ "$output" = $'total=2\nfailed=1' ]
  grep -qF "1 $b" "$OUT/failed.txt"
  run grep -qF "$a" "$OUT/failed.txt"
  [ "$status" -ne 0 ]
  grep -q '1/2 suites pass' "$OUT/summary.md"
}

@test "todas verdes: failed=0" {
  a=$(suite a.bats 0); b=$(suite b.bats 0)
  run bash "$SCRIPT" "$OUT" "$a" "$b"
  [ "$output" = $'total=2\nfailed=0' ]
  [ ! -s "$OUT/failed.txt" ]
}

@test "ruta con espacios y metacaracteres se ejecuta como una sola suite" {
  a=$(suite 'con espacio;$(touch PWNED).bats' 1)
  run bash "$SCRIPT" "$OUT" "$a"
  [ "$status" -eq 0 ]
  [ "$output" = $'total=1\nfailed=1' ]
  grep -qxF "$a" "$T/order.log"
  [ ! -e PWNED ]
  [ ! -e "$T/PWNED" ]
  grep -qF "1 $a" "$OUT/failed.txt"
}

@test "las suites marcadas serial corren después del lote paralelo" {
  s=$(suite s.bats 0 serial); p1=$(suite p1.bats 0); p2=$(suite p2.bats 0)
  run bash "$SCRIPT" "$OUT" "$s" "$p1" "$p2"
  [ "$output" = $'total=3\nfailed=0' ]
  grep -qxF "$s" "$OUT/serial.txt"
  run grep -qxF "$s" "$OUT/parallel.txt"
  [ "$status" -ne 0 ]
  [ "$(tail -1 "$T/order.log")" = "$s" ]
}

@test "una suite que no registra su código cuenta como fallo missing" {
  # xargs avisa por stderr del hijo muerto por señal (y deja de lanzar más: también serían missing).
  bats_require_minimum_version 1.5.0
  k=$(suite killed.bats 0 kill); a=$(suite a.bats 0)
  run --separate-stderr bash "$SCRIPT" "$OUT" "$k" "$a"
  [ "$status" -eq 0 ]
  [ "$output" = $'total=2\nfailed=1' ]
  grep -qxF "missing $k" "$OUT/failed.txt"
  grep -q 'missing' "$OUT/summary.md"
}

@test "sin suites: sale 2 y no imprime contadores (fail-closed)" {
  run bash "$SCRIPT" "$OUT" ""
  [ "$status" -eq 2 ]
  [[ "$output" != *total=* ]]
}

@test "el workflow nocturno usa el script y no persiste credenciales" {
  grep -q 'bash scripts/nightly-bats-run.sh /tmp/nightly >> "\$GITHUB_OUTPUT"' .github/workflows/nightly-full-bats.yml
  grep -q 'persist-credentials: false' .github/workflows/nightly-full-bats.yml
}
