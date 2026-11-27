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
  # Solo lo que mira el script (plugins y un hook): copiar .opencode entero arrastra
  # projects/ por los enlaces y agota /tmp.
  mkdir -p "$WS/.opencode/hooks"
  cp -RL "$ROOT/.opencode/plugins" "$WS/.opencode/plugins"
  cp "$ROOT/.opencode/hooks/context-sanitize-input.sh" "$WS/.opencode/hooks/"
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

@test "import multilinea con coma final no es canonico (fallo cerrado)" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from' $'import {\n  BEFORE_GUARDS,\n} from'
  shield
  wired_missing
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
  wired_missing
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

# ── Ronda 2 (revisión #1671): import en cadenas, ambigüedad léxica, sin python3 ──

@test "import real dentro de un template literal y uso presente" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' 'const s = `import { BEFORE_GUARDS } from "./lib/before-guards"`;'
  shield
  wired_missing
}

@test "import dentro de un template mas import real desde otro fichero" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' $'const s = `import { BEFORE_GUARDS } from "./lib/before-guards"`;\nimport { BEFORE_GUARDS } from "./fake.ts";'
  shield
  wired_missing
}

@test "import dentro de una cadena entre comillas simples" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' $'const s = \'import { BEFORE_GUARDS } from "./lib/before-guards"\';'
  shield
  wired_missing
}

@test "guard escondido tras una interpolacion anidada en un template de la lista" {
  sub "$GUARDS" $'  dataSovereigntyGate,\n  blockGitignoredReferences,' $'  `${`,dataSovereigntyGate,`}`,\n  blockGitignoredReferences,'
  shield
  wired_missing
}

@test "interpolacion dentro de un template en la fundacion es ambigua" {
  printf '\nconst t = `x ${1 + 1} y`;\n' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "guard escondido tras literales regex con comillas en la lista" {
  sub "$GUARDS" $'  dataSovereigntyGate,\n  blockGitignoredReferences,' $'  /\'/, \',dataSovereigntyGate,\', /\'/,\n  blockGitignoredReferences,'
  shield
  wired_missing
}

@test "literal regex en la fundacion es ambiguo" {
  printf '\nconst r = /"/;\n' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "sin python3 en PATH: inactive (fallo cerrado)" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$(command -v dirname)" "$BATS_TEST_TMPDIR/bin/dirname"
  run env PATH="$BATS_TEST_TMPDIR/bin" SAVIA_WORKSPACE_DIR="$WS" "$(command -v bash)" "$SCRIPT" --json
  wired_missing
}

@test "python3 que falla en PATH: inactive (fallo cerrado)" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$(command -v dirname)" "$BATS_TEST_TMPDIR/bin/dirname"
  printf '#!/bin/sh\nexit 3\n' > "$BATS_TEST_TMPDIR/bin/python3"
  chmod +x "$BATS_TEST_TMPDIR/bin/python3"
  run env PATH="$BATS_TEST_TMPDIR/bin" SAVIA_WORKSPACE_DIR="$WS" "$(command -v bash)" "$SCRIPT" --json
  wired_missing
}

# ── Ronda 3 (revisión #1671b): forma canónica estricta, fallo cerrado ──

@test "regex tras ) de un if invierte cadenas: import falso" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' 'import { BEFORE_GUARDS } from "./fake.ts";'
  printf '%s\n' 'if (1) /'"'"'/.test("");' "const s = '; import { BEFORE_GUARDS } from \"./lib/before-guards.ts\"; //';" >> "$FOUNDATION"
  shield
  wired_missing
}

@test "regex tras ) de un while es ambiguo" {
  printf '%s\n' 'while (0) /x/.test("");' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "cierre con .filter tras el corchete" {
  sub "$GUARDS" '] as const;' '].filter(() => false);'
  shield
  wired_missing
}

@test "cierre con && tras el corchete" {
  sub "$GUARDS" '] as const;' '] && [];'
  shield
  wired_missing
}

@test "cierre ] as const sin punto y coma es canonico" {
  sub "$GUARDS" '] as const;' '] as const'
  shield
  [ "$status" -eq 0 ]
}

@test "cierre ]; sin as const es canonico" {
  sub "$GUARDS" '] as const;' '];'
  shield
  [ "$status" -eq 0 ]
}

@test "cierre con codigo en la misma linea tras as const" {
  sub "$GUARDS" '] as const;' '] as const; foo();'
  shield
  wired_missing
}

@test "el identificador listado no esta importado (const local)" {
  sub "$GUARDS" 'import { dataSovereigntyGate } from "../guards/data-sovereignty-gate.ts";' 'const dataSovereigntyGate = async () => {};'
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *'"missing":["savia-foundation-wired"]'* ]]
}

@test "import del guard con alias no es canonico" {
  sub "$GUARDS" 'import { blockCredentialLeak } from' 'import { blockCredentialLeak as blockCredentialLeak } from'
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *'"missing":["block-credential-leak-wired"]'* ]]
}

@test "import del guard desde fuera de ../guards" {
  sub "$GUARDS" '"../guards/block-credential-leak.ts"' '"./otro.ts"'
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *'"missing":["block-credential-leak-wired"]'* ]]
}

@test "import del guard indentado no es canonico" {
  sub "$GUARDS" 'import { blockCredentialLeak } from' ' import { blockCredentialLeak } from'
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *'"missing":["block-credential-leak-wired"]'* ]]
}

@test "uso solo de tipo typeof BEFORE_GUARDS" {
  sub "$FOUNDATION" 'runGuardsOnVariants(BEFORE_GUARDS,' 'runGuardsOnVariants([] as typeof BEFORE_GUARDS,'
  shield
  wired_missing
}

@test "dos guards en una linea de la lista" {
  sub "$GUARDS" $'  blockCredentialLeak,\n  blockForcePush,' $'  blockCredentialLeak, blockForcePush,'
  shield
  wired_missing
}

@test "elemento con spread o llamada en la lista" {
  sub "$GUARDS" $'  blockForcePush,\n  blockBranchSwitchDirty,' $'  ...OTRA,\n  blockBranchSwitchDirty,'
  shield
  wired_missing
}

@test "elemento en la misma linea que la apertura" {
  sub "$GUARDS" 'export const BEFORE_GUARDS = [' 'export const BEFORE_GUARDS = [ toolCallHealing,'
  sub "$GUARDS" $'  toolCallHealing,\n  validateBashGlobal,' '  validateBashGlobal,'
  shield
  wired_missing
}

@test "elemento sin coma final antes del cierre" {
  sub "$GUARDS" $'  configSnapshot,\n] as const;' $'  configSnapshot\n] as const;'
  shield
  wired_missing
}

@test "import de la fundacion indentado no es canonico" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from' ' import { BEFORE_GUARDS } from'
  shield
  wired_missing
}

@test "import de la fundacion precedido de codigo en la misma linea" {
  sub "$FOUNDATION" 'import { BEFORE_GUARDS } from' 'void 0; import { BEFORE_GUARDS } from'
  shield
  wired_missing
}

# ── Ronda 4 (revisión #1671c): terminadores de línea, regex general, mutación ──

@test "U+2028 termina un comentario // en la lista" {
  sub "$GUARDS" 'export const BEFORE_GUARDS = [' $'export const BEFORE_GUARDS = [\n  //\xe2\x80\xa8], __fake = ['
  shield
  wired_missing
}

@test "U+2029 en un comentario de la fundacion" {
  printf '%s\n' $'// x\xe2\x80\xa9const y = 1;' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "U+0085 en la fundacion" {
  printf '%s\n' $'const y = 1;\xc2\x85' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "CR suelto en before-guards.ts" {
  printf '// x\rconst y = 1;\n' >> "$GUARDS"
  shield
  wired_missing
}

@test "CRLF en ambos ficheros sigue valiendo" {
  python3 - "$FOUNDATION" "$GUARDS" <<'PY'
import sys
from pathlib import Path
for f in sys.argv[1:]:
    p = Path(f); p.write_bytes(p.read_bytes().replace(b"\n", b"\r\n"))
PY
  shield
  [ "$status" -eq 0 ]
}

@test "regex tras await en la fundacion" {
  printf '%s\n' 'await /`/;' 'const BEFORE_GUARDS: any[] = [];' 'const __s = `' 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' '`;' '// `' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "regex tras yield, instanceof, new, extends, void, typeof, in" {
  local w
  for w in yield instanceof new extends void typeof in of return; do
    cp "$FOUNDATION" "$BATS_TEST_TMPDIR/f.bak"
    printf '%s\n' "x = $w /a/;" >> "$FOUNDATION"
    shield
    wired_missing || { echo "no ambiguo con $w: $output"; false; }
    cp "$BATS_TEST_TMPDIR/f.bak" "$FOUNDATION"
  done
}

@test "barra tras comillas es ambigua" {
  printf '%s\n' 'const d = "a" / 2;' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "barra tras llave de cierre es ambigua" {
  printf '%s\n' '{ }/x/;' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "barra tras identificador no reservado y tras numero es division valida" {
  printf '%s\n' 'const q = total / 2 / 3.5;' >> "$FOUNDATION"
  shield
  [ "$status" -eq 0 ]
}

@test "mutar BEFORE_GUARDS con splice en la fundacion" {
  printf '%s\n' 'BEFORE_GUARDS.splice(0);' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "asignar length o indice de BEFORE_GUARDS en la fundacion" {
  printf '%s\n' 'BEFORE_GUARDS.length = 0;' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "asignar un elemento por indice en la fundacion" {
  printf '%s\n' 'BEFORE_GUARDS[0] = null;' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "reasignar BEFORE_GUARDS en la fundacion" {
  printf '%s\n' 'BEFORE_GUARDS = [];' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "el import del guard viene de otro fichero de ../guards" {
  sub "$GUARDS" '"../guards/block-credential-leak.ts"' '"../guards/noop.ts"'
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *'"missing":["block-credential-leak-wired"]'* ]]
}

@test "identificador con escape unicode en before-guards.ts" {
  printf '%s\n' 'BEFORE_GUARDS.length = 0;' >> "$GUARDS"
  shield
  wired_missing
}

@test "escape unicode fuera de cadenas en la fundacion" {
  printf '%s\n' 'BEFORE_GUARDS.length = 0;' >> "$FOUNDATION"
  shield
  wired_missing
}

# ── Ronda 5 (revisión de la suite de Codex): etiquetas, for await, caracteres Cf ──

@test "regex tras for await (...)" {
  printf '%s\n' 'async function f(xs: any) { for await (const x of xs) /`/.test(""); }' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "regex tras break con etiqueta y salto de linea" {
  printf '%s\n' 'a: for (;;) { break a' '/`/.test(""); }' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "regex tras continue con etiqueta y salto de linea" {
  printf '%s\n' 'a: for (;;) { continue a' '/`/.test(""); }' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "BOM en medio de la fundacion" {
  printf '%s\n' $'if\xef\xbb\xbf (1) /`/.test("");' >> "$FOUNDATION"
  shield
  wired_missing
}

@test "ZWJ (categoria Cf) en before-guards.ts" {
  printf '%s\n' $'const x\xe2\x80\x8d = 1;' >> "$GUARDS"
  shield
  wired_missing
}

@test "BOM en la posicion 0 de ambos ficheros sigue valiendo" {
  python3 - "$FOUNDATION" "$GUARDS" <<'PY'
import sys
from pathlib import Path
for f in sys.argv[1:]:
    p = Path(f); p.write_bytes(b"\xef\xbb\xbf" + p.read_bytes())
PY
  shield
  [ "$status" -eq 0 ]
}

@test "division normal tras identificador sigue siendo valida" {
  printf '%s\n' 'const r = total / 2;' >> "$FOUNDATION"
  shield
  [ "$status" -eq 0 ]
}
