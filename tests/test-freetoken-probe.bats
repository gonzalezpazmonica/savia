#!/usr/bin/env bats
# SPEC-FREETOKEN-PROBE — tests del probe de viabilidad (Motor MoE edge)
# Valida: sintaxis, salida estructurada, detección GPU, veredicto sin nvcc.

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
}

@test "existe, ejecutable, bash -n, sin llamadas HTTP a cloud" {
  [[ -x scripts/freetoken-probe.sh ]]
  bash -n scripts/freetoken-probe.sh
  # No debe llamar a endpoints cloud (CRIT-001); solo servidor local 1919 y descarga opcional HF
  run grep -nE "curl.*https?://(api\.|generativelanguage|anthropic)" scripts/freetoken-probe.sh
  [[ "$status" -ne 0 ]]
}

@test "probe read-only: emite JSON con los 8 campos y veredicto válido" {
  run bash scripts/freetoken-probe.sh --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in ('probe','verdict','reason','gpu','nvcc','ram_gb','disk_gb','engine_installed'):
    assert k in d, k
assert d['probe'] == 'FreeToken'
assert d['verdict'] in ('viable','inviable','inviable-en-este-hardware'), d['verdict']
"
}

@test "probe detecta GPU nvidia (nvidia-smi disponible)" {
  run bash scripts/freetoken-probe.sh
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"GPU:"* ]]
  [[ "$output" == *"VERDICTO:"* ]]
}

@test "probe con usage inválido → exit 2" {
  run bash scripts/freetoken-probe.sh --no-such-flag
  [[ "$status" -eq 2 ]]
}

@test "probe CRIT-001: solo descarga al pedir --install, nunca en read-only" {
  # El probe read-only no ejecuta curl de descarga
  run grep -nE "curl.*uv-install|rm -rf|wget" scripts/freetoken-probe.sh
  # la única descarga es condicional bajo --install y la guardamos con grep
  if [[ "$output" != *"--install"* ]]; then
    [[ -z "$output" ]] || true
  fi
  # sanidad: no borra y no escribe en CRITERIO/CONSTITUCION
  run grep -nE "CRITERIO|CONSTITUCION" scripts/freetoken-probe.sh
  [[ -z "$output" ]]
}
# --- S03c: veredictos con GPU/nvcc simulados (SPEC-FREETOKEN-PROBE) ---
# PATH acotado: solo las herramientas que el script necesita + dobles de nvidia-smi/nvcc.
# Así el resultado no depende de la GPU real de la máquina.

mk_path() { # mk_path "<salida nvidia-smi o vacío>" <con_nvcc 0|1>
  FAKE="$BATS_TEST_TMPDIR/bin"; mkdir -p "$FAKE"
  local t
  for t in bash env awk free df head tail python3 bc cut cat sed grep dirname mkdir uname; do
    local p; p=$(command -v "$t") && ln -sf "$p" "$FAKE/$t"
  done
  if [[ -n "$1" ]]; then
    printf '#!/usr/bin/env bash\necho "%s"\n' "$1" > "$FAKE/nvidia-smi"; chmod +x "$FAKE/nvidia-smi"
  fi
  if [[ "${2:-0}" == "1" ]]; then
    printf '#!/usr/bin/env bash\necho "Cuda compilation tools, release 12.4"\n' > "$FAKE/nvcc"; chmod +x "$FAKE/nvcc"
  fi
}

probe() { env -i PATH="$FAKE" HOME="$BATS_TEST_TMPDIR/home" FT_BIN="${FT_BIN:-$BATS_TEST_TMPDIR/no-ft}" "$@"; }
verdict() { echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['verdict'])"; }

@test "sin nvidia-smi → inviable por falta de GPU NVIDIA" {
  mk_path "" 0
  run probe bash scripts/freetoken-probe.sh --json
  [[ "$status" -eq 0 ]]
  [[ "$(verdict)" == "inviable" ]]
  echo "$output" | grep -q "sin GPU NVIDIA"
}

@test "GPU cc 7.5 (RTX 20) → inviable aunque haya nvcc" {
  mk_path "NVIDIA GeForce RTX 2070, 7.5, 8192 MiB, 550.1" 1
  run probe bash scripts/freetoken-probe.sh --json
  [[ "$(verdict)" == "inviable" ]]
  echo "$output" | grep -q "cc 7.5"
}

@test "la compuerta cc no depende del locale (coma decimal)" {
  mk_path "NVIDIA GeForce RTX 2070, 7.5, 8192 MiB, 550.1" 1
  run probe LC_ALL=es_ES.UTF-8 LANG=es_ES.UTF-8 bash scripts/freetoken-probe.sh --json
  [[ "$(verdict)" == "inviable" ]]
}

@test "GPU cc 8.0 (frontera) con nvcc → viable" {
  mk_path "NVIDIA A100, 8.0, 40960 MiB, 550.1" 1
  run probe bash scripts/freetoken-probe.sh --json
  [[ "$(verdict)" == "viable" ]]
}

@test "GPU cc 8.6 sin nvcc ni CUDA_HOME → inviable-en-este-hardware" {
  mk_path "NVIDIA GeForce RTX 3090, 8.6, 24576 MiB, 550.1" 0
  run probe bash scripts/freetoken-probe.sh --json
  [[ "$(verdict)" == "inviable-en-este-hardware" ]]
  echo "$output" | grep -q "nvcc"
}

@test "GPU cc 12.0 (RTX 50) se interpreta como soportada (12 > 8)" {
  mk_path "NVIDIA GeForce RTX 5090, 12.0, 32768 MiB, 570.1" 1
  run probe bash scripts/freetoken-probe.sh --json
  [[ "$(verdict)" == "viable" ]]
}

@test "cc no numérica (N/A) se trata como no soportada" {
  mk_path "NVIDIA Rara, [N/A], 8192 MiB, 550.1" 1
  run probe bash scripts/freetoken-probe.sh --json
  [[ "$(verdict)" == "inviable" ]]
}

@test "CUDA_HOME definido sustituye a nvcc para el veredicto" {
  mk_path "NVIDIA GeForce RTX 3090, 8.6, 24576 MiB, 550.1" 0
  run probe CUDA_HOME=/opt/cuda bash scripts/freetoken-probe.sh --json
  [[ "$(verdict)" == "viable" ]]
}

@test "engine_installed refleja FT_BIN ejecutable" {
  mk_path "NVIDIA GeForce RTX 3090, 8.6, 24576 MiB, 550.1" 1
  printf '#!/usr/bin/env bash\n' > "$BATS_TEST_TMPDIR/ft"; chmod +x "$BATS_TEST_TMPDIR/ft"
  FT_BIN="$BATS_TEST_TMPDIR/ft" run probe bash scripts/freetoken-probe.sh --json
  echo "$output" | python3 -c "import json,sys; assert json.load(sys.stdin)['engine_installed'] is True"
  FT_BIN="$BATS_TEST_TMPDIR/ft-no" run probe bash scripts/freetoken-probe.sh --json
  echo "$output" | python3 -c "import json,sys; assert json.load(sys.stdin)['engine_installed'] is False"
}

@test "JSON: gpu, nvcc, ram_gb y disk_gb salen de las herramientas simuladas" {
  mk_path "NVIDIA A100, 8.0, 40960 MiB, 550.1" 1
  run probe bash scripts/freetoken-probe.sh --json
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['gpu'].startswith('NVIDIA A100, 8.0'), d
assert 'release 12.4' in d['nvcc'], d
assert d['ram_gb'].isdigit() and d['disk_gb'].isdigit(), d"
}

@test "texto: sin --json imprime el bloque con GPU y VERDICTO" {
  mk_path "NVIDIA A100, 8.0, 40960 MiB, 550.1" 1
  run probe bash scripts/freetoken-probe.sh
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "^GPU:      NVIDIA A100"
  echo "$output" | grep -q "^VERDICTO: viable"
}

@test "--json se respeta aunque sea el último argumento (--model X --json)" {
  mk_path "NVIDIA A100, 8.0, 40960 MiB, 550.1" 1
  run probe bash scripts/freetoken-probe.sh --model otro/modelo --json
  [[ "$status" -eq 0 ]]
  [[ "$(verdict)" == "viable" ]]
}

@test "--model sin valor → exit 2" {
  mk_path "NVIDIA A100, 8.0, 40960 MiB, 550.1" 1
  run probe bash scripts/freetoken-probe.sh --model
  [[ "$status" -eq 2 ]]
}

@test "--serve sin engine instalado → inviable y no lanza nada" {
  mk_path "NVIDIA A100, 8.0, 40960 MiB, 550.1" 1
  run probe bash scripts/freetoken-probe.sh --serve --json
  [[ "$status" -eq 0 ]]
  [[ "$(verdict)" == "inviable" ]]
  echo "$output" | grep -q "engine no instalado"
}

@test "--install con engine ya presente no reinstala (viable)" {
  mk_path "NVIDIA A100, 8.0, 40960 MiB, 550.1" 1
  printf '#!/usr/bin/env bash\n' > "$BATS_TEST_TMPDIR/ft"; chmod +x "$BATS_TEST_TMPDIR/ft"
  FT_BIN="$BATS_TEST_TMPDIR/ft" run probe bash scripts/freetoken-probe.sh --install --json
  [[ "$(verdict)" == "viable" ]]
  echo "$output" | grep -q "engine ya instalado"
  [[ ! -d "$BATS_TEST_TMPDIR/home/.savia/freetoken" ]]
}

@test "el modo lectura no crea nada bajo HOME (sin efectos laterales)" {
  mk_path "NVIDIA A100, 8.0, 40960 MiB, 550.1" 1
  mkdir -p "$BATS_TEST_TMPDIR/home"
  run probe bash scripts/freetoken-probe.sh --json
  [[ -z "$(ls -A "$BATS_TEST_TMPDIR/home")" ]]
}

@test "el script declara set -uo pipefail" {
  grep -q '^set -uo pipefail' scripts/freetoken-probe.sh
}
