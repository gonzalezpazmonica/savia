#!/usr/bin/env bats
# SPEC-OC-01 / SE-510 AC-7: cableado de guards (checks 6 y 7) de savia-shield-check.sh.
# Casos propios, complementarios a test-shield-check-before-guards-codex.bats:
# alias, import de otro fichero, lista exportada con otro nombre, cadenas,
# tipos, import multilínea y ruta nueva. Fallo cerrado ante cualquier duda.
# Ejecutar: bats tests/bats/test-shield-check-before-guards-claude.bats
set -uo pipefail

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$ROOT/scripts/savia-shield-check.sh"
  WS="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$WS/docs/rules/domain"
  cp -RL "$ROOT/.opencode" "$WS/.opencode"
  cp "$ROOT/docs/rules/domain/savia-shield-opencode.md" "$WS/docs/rules/domain/"
  FOUNDATION="$WS/.opencode/plugins/savia-foundation.ts"
  GUARDS="$WS/.opencode/plugins/lib/before-guards.ts"
}

shield() { run env SAVIA_WORKSPACE_DIR="$WS" bash "$SCRIPT" --json; }

# $1 fichero, $2 texto exacto a sustituir (una vez), $3 reemplazo
sub() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, ("fixture inesperado", sys.argv[2])
p.write_text(s.replace(sys.argv[2], sys.argv[3]))
PY
}

wired_missing() {
  [ "$status" -eq 2 ] \
    && [[ "$output" == *'"shield_status":"inactive"'* ]] \
    && [[ "$output" == *'savia-foundation-wired'* ]] \
    && [[ "$output" == *'block-credential-leak-wired'* ]]
}

@test "arbol real: active, exit 0, nada que falte" {
  shield
  [ "$status" -eq 0 ]
  [[ "$output" == *'"shield_status":"active"'* ]]
  [[ "$output" == *'"missing":[]'* ]]
}

@test "import sin extension .ts sigue valiendo" {
  sub "$FOUNDATION" 'from "./lib/before-guards.ts"' 'from "./lib/before-guards"'
  shield
  [ "$status" -eq 0 ]
}

@test "import multilinea con coma final sigue valiendo" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from' $'import {\n  BEFORE_GUARDS,\n} from'
  shield
  [ "$status" -eq 0 ]
}

@test "import con alias: el nombre BEFORE_GUARDS ya no esta importado" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from' 'import { BEFORE_GUARDS as OTHER } from'
  shield
  wired_missing
}

@test "import con alias y uso del alias: fallo cerrado" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from' 'import { BEFORE_GUARDS as BG } from'
  sub "$FOUNDATION" 'runGuardsOnVariants(BEFORE_GUARDS,' 'runGuardsOnVariants(BG,'
  shield
  wired_missing
}

@test "import de otro fichero con el mismo nombre BEFORE_GUARDS" {
  sub "$FOUNDATION" './lib/before-guards.ts' './lib/otra-lista.ts'
  shield
  wired_missing
}

@test "import de before-guards fuera de lib (ruta parecida)" {
  sub "$FOUNDATION" './lib/before-guards.ts' './before-guards.ts'
  shield
  wired_missing
}

@test "import de before-guards-old en vez de before-guards" {
  sub "$FOUNDATION" './lib/before-guards.ts' './lib/before-guards-old.ts'
  shield
  wired_missing
}

@test "import type no cuenta como import de valor" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from' 'import type { BEFORE_GUARDS } from'
  shield
  wired_missing
}

@test "import comentado con // y uso presente" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' '// import { BEFORE_GUARDS } from "./lib/before-guards.ts";'
  shield
  wired_missing
}

@test "uso solo dentro de una cadena" {
  sub "$FOUNDATION" 'runGuardsOnVariants(BEFORE_GUARDS,' 'runGuardsOnVariants("BEFORE_GUARDS",'
  shield
  wired_missing
}

@test "uso solo dentro de un comentario de linea" {
  sub "$FOUNDATION" 'await runGuardsOnVariants(BEFORE_GUARDS, input, output);' '// await runGuardsOnVariants(BEFORE_GUARDS, input, output);'
  shield
  wired_missing
}

@test "uso solo dentro de un comentario de bloque" {
  sub "$FOUNDATION" 'await runGuardsOnVariants(BEFORE_GUARDS, input, output);' '/* await runGuardsOnVariants(BEFORE_GUARDS, input, output); */'
  shield
  wired_missing
}

@test "la lista se llama BEFORE_GUARDS_V2 en before-guards.ts" {
  sub "$GUARDS" 'export const BEFORE_GUARDS = [' 'export const BEFORE_GUARDS_V2 = ['
  shield
  wired_missing
}

@test "BEFORE_GUARDS vacia y la lista real con otro nombre" {
  sub "$GUARDS" 'export const BEFORE_GUARDS = [' $'export const BEFORE_GUARDS = [] as const;\nexport const REAL_GUARDS = ['
  shield
  wired_missing
}

@test "la lista BEFORE_GUARDS no se exporta" {
  sub "$GUARDS" 'export const BEFORE_GUARDS = [' 'const BEFORE_GUARDS = ['
  shield
  wired_missing
}

@test "guards solo en otra lista anterior a BEFORE_GUARDS" {
  sub "$GUARDS" 'export const BEFORE_GUARDS = [' $'const AUDIT = [\n  blockCredentialLeak,\n  dataSovereigntyGate,\n];\nexport const BEFORE_GUARDS = ['
  sub "$GUARDS" $'  blockCredentialLeak,\n  blockForcePush,' '  blockForcePush,'
  sub "$GUARDS" $'  dataSovereigntyGate,\n  blockGitignoredReferences,' '  blockGitignoredReferences,'
  shield
  wired_missing
}

@test "guard solo como cadena dentro de BEFORE_GUARDS" {
  sub "$GUARDS" $'  blockCredentialLeak,\n  blockForcePush,' $'  "blockCredentialLeak",\n  blockForcePush,'
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *'"missing":["block-credential-leak-wired"]'* ]]
}

@test "guard solo en el import, no en la lista" {
  sub "$GUARDS" $'  blockCredentialLeak,\n  blockForcePush,' '  blockForcePush,'
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *'"missing":["block-credential-leak-wired"]'* ]]
}

@test "dos listas BEFORE_GUARDS: ambiguo, fallo cerrado" {
  printf '\nexport const BEFORE_GUARDS = [\n  dataSovereigntyGate,\n  blockCredentialLeak,\n];\n' >> "$GUARDS"
  shield
  wired_missing
}

@test "before-guards.ts vacio" {
  : > "$GUARDS"
  shield
  wired_missing
}

@test "fundacion vacia" {
  : > "$FOUNDATION"
  shield
  wired_missing
}

@test "lista sin cierre: fallo cerrado" {
  sub "$GUARDS" '] as const;' ''
  shield
  wired_missing
}

@test "workspace sin .opencode: inactive limpio" {
  python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$WS/.opencode"
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *'"shield_status":"inactive"'* ]]
}
