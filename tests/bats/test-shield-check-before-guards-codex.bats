#!/usr/bin/env bats
# SPEC-OC-01 / SE-510 AC-7: regresión de guard_registered (checks 6 y 7).
# Ref: docs/rules/domain/savia-shield-opencode.md
# Estrategia: copiar el árbol real; sembrar un fallo cada vez; comprobar exit y
# JSON exactos, incluido el guard sano. No se ejecuta ningún plugin ni hook TS.
# Ejecutar: bats tests/bats/test-shield-check-before-guards-codex.bats
set -uo pipefail

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$ROOT/scripts/savia-shield-check.sh"
  WS="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$WS/docs/rules/domain"
  # .opencode/hooks es un enlace: materializarlo evita un fixture incompleto
  # y garantiza que todas las mutaciones se quedan en el árbol temporal.
  cp -RL "$ROOT/.opencode" "$WS/.opencode"
  cp "$ROOT/docs/rules/domain/savia-shield-opencode.md" "$WS/docs/rules/domain/"
  FOUNDATION="$WS/.opencode/plugins/savia-foundation.ts"
  GUARDS="$WS/.opencode/plugins/lib/before-guards.ts"
}

# BATS gestiona y retira BATS_TEST_TMPDIR al terminar cada caso.
shield() {
  run env SAVIA_WORKSPACE_DIR="$WS" bash "$SCRIPT" --json
}

assert_shield() {
  local expected_exit="$1" expected_state="$2"
  shift 2
  printf 'exit=%s; JSON=%s\n' "$status" "$output"
  [ "$status" -eq "$expected_exit" ]
  python3 - "$output" "$expected_state" "$@" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
missing = set(sys.argv[3:])
all_components = {
    "data-sovereignty-gate", "data-sovereignty-audit", "sovereignty-patterns",
    "block-credential-leak", "context-sanitize-input", "savia-foundation-wired",
    "block-credential-leak-wired", "savia-shield-opencode-doc",
}
assert data["shield_status"] == sys.argv[2], data
assert set(data["missing"]) == missing, data
assert len(data["missing"]) == len(missing), data
assert set(data["components"]) == all_components - missing, data
assert len(data["components"]) == len(all_components - missing), data
PY
}

mutate_guard() {
  # Exigir una sola sustitución: un cambio de formato del origen no debe
  # convertir silenciosamente el caso negativo en una copia sin mutar.
  python3 - "$GUARDS" "$1" "$2" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
guard, mode = sys.argv[2:]
source = path.read_text()
needle = f"  {guard},\n"
assert source.count(needle) == 1, (guard, "fixture inesperado")
if mode == "other-list":
    source = source.replace(needle, "")
    source += f"\nconst OTHER_GUARDS = [\n  {guard},\n] as const;\n"
elif mode == "similar":
    source = source.replace(needle, f"  {guard}X,\n")
elif mode == "line-comment":
    source = source.replace(needle, f"  // {guard},\n")
elif mode == "block-comment":
    source = source.replace(needle, f"  /*\n  {guard},\n  */\n")
else:
    raise AssertionError(f"modo inesperado: {mode}")
path.write_text(source)
PY
}

replace_in_foundation() {
  python3 - "$FOUNDATION" "$1" "$2" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old, new = sys.argv[2:]
source = path.read_text()
assert source.count(old) == 1, "fixture de fundación inesperado"
path.write_text(source.replace(old, new))
PY
}

write_guard_list() {
  cat > "$GUARDS" <<'TS'
import { dataSovereigntyGate } from "../guards/data-sovereignty-gate.ts";
import { blockCredentialLeak } from "../guards/block-credential-leak.ts";
TS
  cat >> "$GUARDS"
}

@test "activo: copia del árbol real con import y uso de BEFORE_GUARDS" {
  shield
  assert_shield 0 active
}

@test "activo: BEFORE_GUARDS en varias líneas con comas finales" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [
  dataSovereigntyGate,
  blockCredentialLeak,
] as const;
TS
  shield
  assert_shield 0 active
}

@test "activo: comentario al final de la línea de ambos guards" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [
  dataSovereigntyGate, // protege los datos
  blockCredentialLeak, // protege las credenciales
] as const;
TS
  shield
  assert_shield 0 active
}

@test "inactivo: dataSovereigntyGate fuera de BEFORE_GUARDS pero en otra lista" {
  mutate_guard dataSovereigntyGate other-list
  shield
  assert_shield 2 inactive savia-foundation-wired
}

@test "inactivo: blockCredentialLeak fuera de BEFORE_GUARDS pero en otra lista" {
  mutate_guard blockCredentialLeak other-list
  shield
  assert_shield 2 inactive block-credential-leak-wired
}

@test "inactivo: fundación con solo un comentario sobre BEFORE_GUARDS" {
  cat > "$FOUNDATION" <<'TS'
// BEFORE_GUARDS se conectará aquí; hoy no hay import ni uso.
export default {};
TS
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: import de BEFORE_GUARDS sin uso en la fundación" {
  replace_in_foundation \
    'await runGuardsOnVariants(BEFORE_GUARDS, input, output);' \
    'await runGuardsOnVariants([], input, output);'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: uso de BEFORE_GUARDS sin import en la fundación" {
  replace_in_foundation 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' ''
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: BEFORE_GUARDS vacío aunque se importen los guards" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [] as const;
TS
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: nombre parecido dataSovereigntyGateX no es el guard" {
  mutate_guard dataSovereigntyGate similar
  shield
  assert_shield 2 inactive savia-foundation-wired
}

@test "inactivo: nombre parecido blockCredentialLeakX no es el guard" {
  mutate_guard blockCredentialLeak similar
  shield
  assert_shield 2 inactive block-credential-leak-wired
}

@test "inactivo: dataSovereigntyGate comentado con doble barra en BEFORE_GUARDS" {
  mutate_guard dataSovereigntyGate line-comment
  shield
  assert_shield 2 inactive savia-foundation-wired
}

@test "inactivo: blockCredentialLeak comentado con doble barra en BEFORE_GUARDS" {
  mutate_guard blockCredentialLeak line-comment
  shield
  assert_shield 2 inactive block-credential-leak-wired
}

@test "inactivo: dataSovereigntyGate dentro de un comentario de bloque en BEFORE_GUARDS" {
  mutate_guard dataSovereigntyGate block-comment
  shield
  assert_shield 2 inactive savia-foundation-wired
}

@test "inactivo: blockCredentialLeak dentro de un comentario de bloque en BEFORE_GUARDS" {
  mutate_guard blockCredentialLeak block-comment
  shield
  assert_shield 2 inactive block-credential-leak-wired
}

@test "inactivo: fichero before-guards.ts ausente con import y uso conservados" {
  mv "$GUARDS" "$BATS_TEST_TMPDIR/before-guards.ts.bak"
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: fichero savia-foundation.ts ausente con BEFORE_GUARDS intacto" {
  mv "$FOUNDATION" "$BATS_TEST_TMPDIR/savia-foundation.ts.bak"
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

# Una sintaxis ambigua puede invalidar la lista completa. También se admite
# conservar blockCredentialLeak si se consigue analizarlo sin aceptar el texto
# dataSovereigntyGate como identificador. El resto de componentes sigue presente.
assert_ambiguous_list_inactive() {
  printf 'exit=%s; JSON=%s\n' "$status" "$output"
  [ "$status" -eq 2 ]
  python3 - "$output" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
missing = set(data["missing"])
assert data["shield_status"] == "inactive", data
assert missing in (
    {"savia-foundation-wired"},
    {"savia-foundation-wired", "block-credential-leak-wired"},
), data
all_components = {
    "data-sovereignty-gate", "data-sovereignty-audit", "sovereignty-patterns",
    "block-credential-leak", "context-sanitize-input", "savia-foundation-wired",
    "block-credential-leak-wired", "savia-shield-opencode-doc",
}
assert len(data["missing"]) == len(missing), data
assert set(data["components"]) == all_components - missing, data
assert len(data["components"]) == len(all_components - missing), data
PY
}

@test "inactivo: import ficticio dentro de cadena con uso de BEFORE_GUARDS" {
  cat > "$FOUNDATION" <<'TS'
const s = 'import { BEFORE_GUARDS } from "./lib/before-guards"';
run(BEFORE_GUARDS);
TS
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: import ficticio dentro de template con uso de BEFORE_GUARDS" {
  cat > "$FOUNDATION" <<'TS'
const s = `import { BEFORE_GUARDS } from "./lib/before-guards"`;
run(BEFORE_GUARDS);
TS
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: import real de fake.ts y señuelo dentro de cadena" {
  cat > "$FOUNDATION" <<'TS'
import { BEFORE_GUARDS } from "./fake.ts";
const s = 'import { BEFORE_GUARDS } from "./lib/before-guards"';
run(BEFORE_GUARDS);
TS
  printf 'export const BEFORE_GUARDS = [] as const;\n' > "$WS/.opencode/plugins/fake.ts"
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: import real de fake.ts y señuelo dentro de template" {
  cat > "$FOUNDATION" <<'TS'
import { BEFORE_GUARDS } from "./fake.ts";
const s = `import { BEFORE_GUARDS } from "./lib/before-guards"`;
run(BEFORE_GUARDS);
TS
  printf 'export const BEFORE_GUARDS = [] as const;\n' > "$WS/.opencode/plugins/fake.ts"
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: template con interpolación anidada oculta dataSovereigntyGate" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [ blockCredentialLeak, `${`,dataSovereigntyGate,`}` ] as const;
TS
  shield
  assert_ambiguous_list_inactive
}

@test "inactivo: regex con comillas no convierte una cadena en guard" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [ /'/, ',dataSovereigntyGate,', /'/ ] as const;
TS
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex con comillas y blockCredentialLeak real no activan el escudo" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [ blockCredentialLeak, /'/, ',dataSovereigntyGate,', /'/ ] as const;
TS
  shield
  assert_ambiguous_list_inactive
}

@test "inactivo: python3 ausente en PATH hermético con árbol válido" {
  local isolated_bin="$BATS_TEST_TMPDIR/bin"
  local bash_exe
  bash_exe="$(command -v bash)"
  mkdir -p "$isolated_bin"
  # Solo las herramientas de shell que usa el script; nunca heredar PATH.
  ln -s "$bash_exe" "$isolated_bin/bash"
  ln -s "$(command -v dirname)" "$isolated_bin/dirname"
  run env PATH="$isolated_bin" "$bash_exe" -c 'command -v python3'
  [ "$status" -eq 1 ]
  [ -z "$output" ]

  # PATH afecta únicamente al proceso probado. La aserción JSON conserva Python.
  run env PATH="$isolated_bin" SAVIA_WORKSPACE_DIR="$WS" "$bash_exe" "$SCRIPT" --json
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}
