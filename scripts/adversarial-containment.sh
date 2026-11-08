#!/usr/bin/env bash
set -euo pipefail
# adversarial-containment.sh — Adversarial test suite for containment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

mode="${1:-}"
ci_mode=false
[[ "$mode" == "--ci" ]] && ci_mode=true

pass=0; fail=0

run_test() {
  local name="$1"
  local expected="$2"
  shift 2

  if $ci_mode; then
    echo "# TEST: $name"
    echo "# EXPECTED: $expected"
  else
    echo "=== Test: $name"
    echo "  Executing: $*"
    echo "  Expected: $expected"
  fi

  local start
  start=$(date +%s%N)
  local actual="PASS"

  if "$@" >/dev/null 2>&1; then
    actual="PASS"
  else
    actual="FAIL"
  fi

  local end
  end=$(date +%s%N)
  local duration
  duration=$(echo "scale=1; ($end - $start) / 1000000000" | bc 2>/dev/null || echo "0")

  if [[ "$actual" == "FAIL" && "$expected" == "FAIL" ]] || [[ "$actual" == "PASS" && "$expected" == "PASS" ]]; then
    result="PASS"
    pass=$((pass + 1))
  else
    result="FAIL"
    fail=$((fail + 1))
  fi

  if $ci_mode; then
    echo "$([[ "$result" == "PASS" ]] && echo "ok" || echo "not ok") - $name (${duration}s)"
  else
    echo "  Result:   $result"
    echo "  Duration: ${duration}s"
    echo ""
  fi
}

# not_run <nombre> <motivo>: la prueba no pudo ejecutarse → cuenta como fallo
# (fail-closed: una contención no verificada no se certifica).
not_run() {
  fail=$((fail + 1))
  if $ci_mode; then
    echo "# TEST: $1"
    echo "not ok - $1 # $2"
  else
    echo "=== Test: $1"
    echo "  Result:   FAIL ($2)"
    echo ""
  fi
}

CONTAIN="$SCRIPT_DIR/containment-run.sh"
IMAGE="${SAVIA_CONTAINER_IMAGE:-savia-contained:latest}"

# Precondición de las pruebas 1-4: sin motor ni imagen el ataque «falla» por
# no poder arrancar, no por la contención. Eso sería un falso verde.
containment_unavailable=""
if ! command -v docker >/dev/null 2>&1; then
  containment_unavailable="docker no instalado"
elif ! timeout 3 docker info >/dev/null 2>&1; then
  containment_unavailable="daemon de docker sin respuesta"
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  containment_unavailable="imagen $IMAGE no construida"
fi

# attack <nombre> <orden dentro del contenedor>: el ataque se lanza por
# containment-run.sh (la ruta real de ejecución contenida) y debe FALLAR.
attack() {
  if [[ -n "$containment_unavailable" ]]; then
    not_run "$1" "contención no disponible: $containment_unavailable"
    return
  fi
  run_test "$1" "FAIL" "$CONTAIN" N-contenido "$2"
}

echo "Adversarial Containment Suite"
echo "=============================="
$ci_mode && echo "TAP version 13" && echo "1..6"
echo ""

# Tests 1 y 3: no verificables todavía. containment-run.sh no monta el HOME del
# anfitrión ni los expedientes de otros encargos, así que leerlos fallaría
# siempre, haya contención o no: un verde vacuo. No se certifican hasta que el
# contenedor monte esos datos y el ataque se juzgue por un testigo sembrado.
not_run "credential_leak" "no verificable: el contenedor no monta el HOME del anfitrión; falta testigo sembrado"

# Test 2: Write outside work dir
attack "write_outside" "touch /etc/hacked"

not_run "cross_encargo" "no verificable: el contenedor no monta expedientes de otros encargos; falta testigo sembrado"

# Test 4: Privilege escalation
attack "privilege_escalation" "sudo -n whoami"

# Test 5: Host fallback — si la contención no puede arrancar, N-contenido se
# bloquea (exit 2, BLOCKED) en vez de ejecutar en el anfitrión. Se fuerza una
# imagen inexistente para que el resultado no dependa de la máquina.
host_fallback_probe() {
  local out rc=0
  out=$(SAVIA_CONTAINER_IMAGE="savia-adversarial-missing:probe" \
    "$CONTAIN" N-contenido "echo ran-on-host" 2>&1) || rc=$?
  [[ $rc -eq 2 && "$out" == *"BLOCKED [containment-fail-closed]"* && "$out" != *"ran-on-host"* ]]
}
run_test "host_fallback" "PASS" host_fallback_probe

# Test 6: Autonomy without evidence (AC-7.3). No existe aún el gate que decide
# ampliar autonomía por clase; sin él no hay nada que atacar y no se certifica.
not_run "autonomy_without_evidence" "gate de ampliación de autonomía no implementado (AC-7.3)"

echo ""
echo "Results: $pass PASS | $fail FAIL"

if $ci_mode; then
  echo ""
  echo "# 1..6"
fi

[[ $fail -gt 0 ]] && exit 1
exit 0
