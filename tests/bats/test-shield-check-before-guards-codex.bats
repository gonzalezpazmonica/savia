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
  mkdir -p "$WS/docs/rules/domain" "$WS/.opencode/plugins/guards" \
    "$WS/.opencode/plugins/lib" "$WS/.opencode/hooks"
  # Solo los siete ficheros que lee el escudo; materializar el hook enlazado
  # evita copiar skills, node_modules o escribir accidentalmente en el origen.
  cp "$ROOT/.opencode/plugins/savia-foundation.ts" "$WS/.opencode/plugins/"
  cp "$ROOT/.opencode/plugins/guards/"{data-sovereignty-gate,data-sovereignty-audit,block-credential-leak}.ts \
    "$WS/.opencode/plugins/guards/"
  cp "$ROOT/.opencode/plugins/lib/"{before-guards,sovereignty-patterns}.ts \
    "$WS/.opencode/plugins/lib/"
  cp -L "$ROOT/.opencode/hooks/context-sanitize-input.sh" "$WS/.opencode/hooks/"
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

# Segunda revisión HOLD de #1671 (272990f): las expresiones posteriores al
# array y el origen/uso de los identificadores también forman parte del cableado.
# Los positivos de contraste son los casos 1–3: árbol real, `] as const;`
# y comentarios // al final de las líneas de guard. Se conservan sin cambios.

@test "inactivo: regex tras paréntesis no convierte una cadena en import canónico" {
  replace_in_foundation 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' \
    "$(cat <<'TS'
if (1) /'/.test(""); const s = '; import { BEFORE_GUARDS } from "./lib/before-guards.ts"; //';
import { BEFORE_GUARDS } from "./fake.ts";
TS
)"
  printf 'export const BEFORE_GUARDS = [] as const;\n' > "$WS/.opencode/plugins/fake.ts"
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: filter posterior al cierre elimina todos los guards" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [
  dataSovereigntyGate,
  blockCredentialLeak,
].filter(() => false);
TS
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: slice posterior al cierre exporta una lista vacía" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [
  dataSovereigntyGate,
  blockCredentialLeak,
].slice(0, 0);
TS
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: conjunción posterior al cierre sustituye los guards por una lista vacía" {
  write_guard_list <<'TS'
export const BEFORE_GUARDS = [
  dataSovereigntyGate,
  blockCredentialLeak,
] && [];
TS
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador local homónimo no sustituye al guard de soberanía importado" {
  cat > "$GUARDS" <<'TS'
const dataSovereigntyGate = async () => {};
import { blockCredentialLeak } from "../guards/block-credential-leak.ts";
export const BEFORE_GUARDS = [
  dataSovereigntyGate,
  blockCredentialLeak,
] as const;
TS
  shield
  assert_shield 2 inactive savia-foundation-wired
}

@test "inactivo: typeof BEFORE_GUARDS solo en una aserción de tipo no ejecuta guards" {
  replace_in_foundation \
    'await runGuardsOnVariants(BEFORE_GUARDS, input, output);' \
    'await runGuardsOnVariants([] as typeof BEFORE_GUARDS, input, output);'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: import canónico en línea propia dentro de template multilínea" {
  replace_in_foundation 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";' \
    "$(cat <<'TS'
const documentation = `
import { BEFORE_GUARDS } from "./lib/before-guards.ts";
`;
import { BEFORE_GUARDS } from "./fake.ts";
TS
)"
  printf 'export const BEFORE_GUARDS = [] as const;\n' > "$WS/.opencode/plugins/fake.ts"
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}


# Cuarta ronda: tercera revisión HOLD de #1671 (de0b8bdf).
# Los 32 casos anteriores se conservan íntegros. Los nuevos negativos exigen
# fallo cerrado, aunque el scanner actual todavía pueda informar active.
insert_comment_terminator() {
  python3 - "$GUARDS" "$1" <<'PY_TERMINATOR'
from pathlib import Path
import sys

path = Path(sys.argv[1])
terminator = chr(int(sys.argv[2], 16))
source = path.read_text()
opening = "export const BEFORE_GUARDS = [\n"
assert source.count(opening) == 1, "apertura del fixture inesperada"
payload = "  //" + terminator + "], __fake = [\n"
path.write_bytes(source.replace(opening, opening + payload).encode("utf-8"))
assert payload.encode("utf-8") in path.read_bytes(), "terminador no preservado"
PY_TERMINATOR
}

# Construcción del informe: el backtick pertenece al regex; la declaración
# local de lista vacía es código, y el supuesto import solo texto del template.
# El uso final opera sobre la lista local. El escáner defectuoso invierte estados.
write_regex_import_decoy() {
  printf '%s\n' "$1" > "$FOUNDATION"
  cat >> "$FOUNDATION" <<'TS'
const BEFORE_GUARDS: any[] = [];
const __s = `
import { BEFORE_GUARDS } from "./lib/before-guards.ts";
`;
// `
run(BEFORE_GUARDS);
TS
}

@test "inactivo: U+2028 termina el comentario y desvía los guards a __fake" {
  insert_comment_terminator 2028
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: U+2029 termina el comentario y desvía los guards a __fake" {
  insert_comment_terminator 2029
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: CR suelto termina el comentario y desvía los guards a __fake" {
  insert_comment_terminator 000D
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: U+0085 como fin de línea ambiguo dentro del comentario" {
  # NEL no termina // en ECMAScript; se pide rechazo conservador de esta forma.
  insert_comment_terminator 0085
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: fichero de guards con todos los finales CR sueltos" {
  # Política solicitada: no aceptar terminadores distintos de LF/CRLF,
  # incluso cuando read_text() normaliza CR y la sintaxis JS sea equivalente.
  python3 - "$GUARDS" <<'PY_CR'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_bytes()
assert b"\n" in source and b"\r" not in source
path.write_bytes(source.replace(b"\n", b"\r"))
assert b"\r" in path.read_bytes() and b"\n" not in path.read_bytes()
PY_CR
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras await oculta la lista local vacía" {
  write_regex_import_decoy 'await /`/;'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras yield oculta la lista local vacía" {
  write_regex_import_decoy 'function* probe() { yield /`/; }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras instanceof oculta la lista local vacía" {
  write_regex_import_decoy 'function probe() { return {} instanceof /`/; }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras new oculta la lista local vacía" {
  # No se invoca probe: el módulo es ejecutable sin construir el RegExp.
  write_regex_import_decoy 'function probe() { new /`/; }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras extends oculta la lista local vacía" {
  # No se invoca probe: la superclase no se evalúa al cargar el módulo.
  write_regex_import_decoy 'function probe() { class Probe extends /`/ {} }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras typeof oculta la lista local vacía" {
  write_regex_import_decoy 'typeof /`/;'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras delete oculta la lista local vacía" {
  write_regex_import_decoy 'delete /`/;'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras void oculta la lista local vacía" {
  write_regex_import_decoy 'void /`/;'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras debugger y ASI no es división" {
  write_regex_import_decoy $'debugger\n/`/;'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras break con etiqueta y ASI no es división" {
  write_regex_import_decoy $'outer: for (; false;) { break outer\n/`/; }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras continue con etiqueta y ASI no es división" {
  write_regex_import_decoy $'outer: for (; false;) { continue outer\n/`/; }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: BOM entre return y regex no oculta la palabra clave" {
  write_regex_import_decoy $'function probe() { return\uFEFF/`/; }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras await separado por comentario de bloque" {
  write_regex_import_decoy 'await /* separación válida */ /`/;'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras yield delegado tampoco es división" {
  write_regex_import_decoy 'function* probe() { yield* /`/; }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras return con construcción del informe" {
  write_regex_import_decoy 'function probe() { return /`/; }'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "activo: división normal a / b conserva el cableado real" {
  printf '\nconst a = 8, b = 2; const quotient = a / b;\n' >> "$FOUNDATION"
  shield
  assert_shield 0 active
}

@test "activo: división tras llamada x) / 2 conserva el cableado real" {
  printf '\nconst x = 8; const quotient = Number(x) / 2;\n' >> "$FOUNDATION"
  shield
  assert_shield 0 active
}

@test "activo: división arr[0] / n conserva el cableado real" {
  printf '\nconst arr = [8], n = 2; const quotient = arr[0] / n;\n' >> "$FOUNDATION"
  shield
  assert_shield 0 active
}

@test "activo: CRLF en ambos ficheros conserva el cableado real" {
  python3 - "$GUARDS" "$FOUNDATION" <<'PY_CRLF'
from pathlib import Path
import sys

for name in sys.argv[1:]:
    path = Path(name)
    source = path.read_bytes()
    assert b"\n" in source and b"\r" not in source
    path.write_bytes(source.replace(b"\n", b"\r\n"))
    assert b"\r\n" in path.read_bytes()
PY_CRLF
  shield
  assert_shield 0 active
}

@test "inactivo: U+0085 sustituye todos los finales de línea de los guards" {
  python3 - "$GUARDS" <<'PY_NEL'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_bytes()
assert b"\n" in source and b"\xc2\x85" not in source
path.write_bytes(source.replace(b"\n", b"\xc2\x85"))
assert b"\xc2\x85" in path.read_bytes() and b"\n" not in path.read_bytes()
PY_NEL
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: regex tras paréntesis de for await no es división" {
  write_regex_import_decoy 'for await (const item of []) /`/;'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: BOM entre if y paréntesis no convierte regex en división" {
  write_regex_import_decoy $'if\uFEFF(false) /`/;'
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}


# Quinta ronda: revisión completa HOLD b4bd7e2. Se conservan los 59 casos;
# las entradas ambiguas deben fallar cerrado en cualquiera de los dos módulos.
# Fixtures sintéticos mínimos: los tokens canónicos son texto para JS, código
# para el escáner defectuoso. No se cargan plugins ni se ejecutan guards reales.
mutate_lexical_fixture() {
  python3 - "$GUARDS" "$FOUNDATION" "$@" <<'PY_LEXICAL'
from pathlib import Path
import sys
import unicodedata

guards, foundation = map(Path, sys.argv[1:3])
target, mode = sys.argv[3:5]
assert target in ("guards", "foundation"), target
path = guards if target == "guards" else foundation
source = path.read_text()
if mode in ("hashbang", "hashbang-bom", "html-close", "html-close-indent", "html-open"):
    prefix = {
        "hashbang": "#!/*\n",
        "hashbang-bom": "\ufeff#!/*\n",
        "html-close": "// cabecera\n--> /*\n",
        "html-close-indent": "// cabecera\n  \t--> /*\n",
        "html-open": "<!-- /*\n",
    }[mode]
    if target == "guards":
        decoy = (
            'import { dataSovereigntyGate } from "../guards/data-sovereignty-gate.ts";\n'
            'import { blockCredentialLeak } from "../guards/block-credential-leak.ts";\n'
            'export const BEFORE_GUARDS = [\n'
            '  dataSovereigntyGate,\n  blockCredentialLeak,\n] as const;\n'
        )
        real = 'export const BEFORE_GUARDS: any[] = [];'
    else:
        decoy = ('import { BEFORE_GUARDS } from "./lib/before-guards.ts";\n'
                 'run(BEFORE_GUARDS);\n')
        real = 'const BEFORE_GUARDS: any[] = []; export default BEFORE_GUARDS;'
    source = prefix + 'const __real = ` */\n' + decoy + '\n`;\n' + real + ' // `\n'
    assert source.startswith(prefix) and decoy in source and real in source
elif mode == "identifier":
    char = chr(int(sys.argv[5], 16))
    category = sys.argv[6]
    assert not char.isascii() and unicodedata.category(char) == category
    if target == "foundation" and category in ("Mn", "Mc", "Pc"):
        old = 'await runGuardsOnVariants(BEFORE_GUARDS, input, output);'
        new = f'await runGuardsOnVariants(BEFORE_GUARDS{char}, input, output);'
        assert source.count(old) == 1, "uso canónico inesperado"
        source = source.replace(old, new)
        source = f'const {{ a: BEFORE_GUARDS{char} }} = {{ a: [] as any[] }};\n' + source
    else:
        # Rechazo conservador solicitado: un identificador Unicode sin uso no
        # desactiva guards, pero la política exige ASCII fuera de texto/comentarios.
        source += f'\nconst __probe{char} = 0;\n'
elif mode in ("control-space", "unicode-space"):
    char = chr(int(sys.argv[5], 16))
    assert char.isspace() and char not in " \t\r\n"
    if mode == "control-space":
        assert ord(char) < 32  # Python lo acepta como \s; ECMAScript no.
    old = ('  dataSovereigntyGate,\n' if target == "guards" else
           'import { BEFORE_GUARDS } from "./lib/before-guards.ts";\n')
    assert source.count(old) == 1, "línea canónica inesperada"
    source = source.replace(old, old.rstrip("\n") + char + "\n")
elif mode == "raw-newline-string":
    # El escáner acepta LF dentro de comillas simples; JS da SyntaxError.
    source += "\nconst __invalid = 'primera\nsegunda';\n"
elif mode in ("unicode-comment", "unicode-string", "html-comment", "html-string"):
    text = ("a\u0301 \u0903 \u203f \u0430 \u03bf" if mode.startswith("unicode")
            else "#!/* <!-- -->")
    source += (f"\n/* {text} */\n" if mode.endswith("comment") else
               f"\nconst __text = '{text}';\n")
else:
    raise AssertionError(f"modo inesperado: {mode}")
encoded = source.encode("utf-8")
path.write_bytes(encoded)
assert path.read_bytes() == encoded, "fixture alterado al escribir"
PY_LEXICAL
}

@test "inactivo: hashbang #!/* en primera línea con señuelo del informe en before-guards.ts" {
  mutate_lexical_fixture guards hashbang
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: hashbang #!/* en primera línea con señuelo del informe en savia-foundation.ts" {
  mutate_lexical_fixture foundation hashbang
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: BOM inicial y hashbang #!/* con señuelo en before-guards.ts" {
  mutate_lexical_fixture guards hashbang-bom
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: BOM inicial y hashbang #!/* con señuelo en savia-foundation.ts" {
  mutate_lexical_fixture foundation hashbang-bom
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: HTML --> a principio de línea con señuelo en before-guards.ts" {
  mutate_lexical_fixture guards html-close
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: HTML --> a principio de línea con señuelo en savia-foundation.ts" {
  mutate_lexical_fixture foundation html-close
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: HTML --> tras espacios y tabulador con señuelo en before-guards.ts" {
  mutate_lexical_fixture guards html-close-indent
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: HTML --> tras espacios y tabulador con señuelo en savia-foundation.ts" {
  mutate_lexical_fixture foundation html-close-indent
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: HTML <!-- fuera de cadenas con señuelo en before-guards.ts" {
  mutate_lexical_fixture guards html-open
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: HTML <!-- fuera de cadenas con señuelo en savia-foundation.ts" {
  mutate_lexical_fixture foundation html-open
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con marca combinante U+0301 en before-guards.ts" {
  mutate_lexical_fixture guards identifier 0301 Mn
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con marca combinante U+0301 en savia-foundation.ts" {
  mutate_lexical_fixture foundation identifier 0301 Mn
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con marca espaciadora U+0903 en before-guards.ts" {
  mutate_lexical_fixture guards identifier 0903 Mc
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con marca espaciadora U+0903 en savia-foundation.ts" {
  mutate_lexical_fixture foundation identifier 0903 Mc
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con conector U+203F en before-guards.ts" {
  mutate_lexical_fixture guards identifier 203F Pc
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con conector U+203F en savia-foundation.ts" {
  mutate_lexical_fixture foundation identifier 203F Pc
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con a cirílica U+0430 en before-guards.ts" {
  mutate_lexical_fixture guards identifier 0430 Ll
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con a cirílica U+0430 en savia-foundation.ts" {
  mutate_lexical_fixture foundation identifier 0430 Ll
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con o griega U+03BF en before-guards.ts" {
  mutate_lexical_fixture guards identifier 03BF Ll
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: identificador con o griega U+03BF en savia-foundation.ts" {
  mutate_lexical_fixture foundation identifier 03BF Ll
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: falso espacio Python U+001C fuera de cadenas en before-guards.ts" {
  mutate_lexical_fixture guards control-space 001C
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: falso espacio Python U+001C fuera de cadenas en savia-foundation.ts" {
  mutate_lexical_fixture foundation control-space 001C
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: falso espacio Python U+001D fuera de cadenas en before-guards.ts" {
  mutate_lexical_fixture guards control-space 001D
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: falso espacio Python U+001D fuera de cadenas en savia-foundation.ts" {
  mutate_lexical_fixture foundation control-space 001D
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: falso espacio Python U+001E fuera de cadenas en before-guards.ts" {
  mutate_lexical_fixture guards control-space 001E
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: falso espacio Python U+001E fuera de cadenas en savia-foundation.ts" {
  mutate_lexical_fixture foundation control-space 001E
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: falso espacio Python U+001F fuera de cadenas en before-guards.ts" {
  mutate_lexical_fixture guards control-space 001F
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: falso espacio Python U+001F fuera de cadenas en savia-foundation.ts" {
  mutate_lexical_fixture foundation control-space 001F
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: espacio no ASCII U+00A0 en código de before-guards.ts" {
  mutate_lexical_fixture guards unicode-space 00A0
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: espacio no ASCII U+00A0 en código de savia-foundation.ts" {
  mutate_lexical_fixture foundation unicode-space 00A0
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: espacio no ASCII U+3000 en código de before-guards.ts" {
  mutate_lexical_fixture guards unicode-space 3000
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: espacio no ASCII U+3000 en código de savia-foundation.ts" {
  mutate_lexical_fixture foundation unicode-space 3000
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: LF literal dentro de cadena simple en before-guards.ts" {
  mutate_lexical_fixture guards raw-newline-string
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "inactivo: LF literal dentro de cadena simple en savia-foundation.ts" {
  mutate_lexical_fixture foundation raw-newline-string
  shield
  assert_shield 2 inactive savia-foundation-wired block-credential-leak-wired
}

@test "activo: Unicode Mn Mc Pc y letras dentro de comentario en before-guards.ts" {
  mutate_lexical_fixture guards unicode-comment
  shield
  assert_shield 0 active
}

@test "activo: Unicode Mn Mc Pc y letras dentro de comentario en savia-foundation.ts" {
  mutate_lexical_fixture foundation unicode-comment
  shield
  assert_shield 0 active
}

@test "activo: Unicode Mn Mc Pc y letras dentro de cadena en before-guards.ts" {
  mutate_lexical_fixture guards unicode-string
  shield
  assert_shield 0 active
}

@test "activo: Unicode Mn Mc Pc y letras dentro de cadena en savia-foundation.ts" {
  mutate_lexical_fixture foundation unicode-string
  shield
  assert_shield 0 active
}

@test "activo: tokens HTML y hashbang dentro de comentario en before-guards.ts" {
  mutate_lexical_fixture guards html-comment
  shield
  assert_shield 0 active
}

@test "activo: tokens HTML y hashbang dentro de comentario en savia-foundation.ts" {
  mutate_lexical_fixture foundation html-comment
  shield
  assert_shield 0 active
}

@test "activo: tokens HTML y hashbang dentro de cadena en before-guards.ts" {
  mutate_lexical_fixture guards html-string
  shield
  assert_shield 0 active
}

@test "activo: tokens HTML y hashbang dentro de cadena en savia-foundation.ts" {
  mutate_lexical_fixture foundation html-string
  shield
  assert_shield 0 active
}
