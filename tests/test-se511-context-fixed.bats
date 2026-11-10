#!/usr/bin/env bats
# SE-511 S1 — medición del contexto fijo por turno (AC-1, AC-2, AC-4, AC-11).
# Ref: docs/specs/SE-511-contexto-fijo-por-turno-a-la-mitad.spec.md

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  S="$ROOT/scripts/context-fixed-measure.sh"
  T="$BATS_TEST_TMPDIR"   # BATS lo crea y lo limpia por test
}

# Raíz sintética: CLAUDE.md con un import y otro fichero; bytes conocidos.
mkroot() {
  mkdir -p "$T/r/docs"
  printf '# Raíz\n@docs/a.md\n' > "$T/r/CLAUDE.md"
  printf 'abcdefgh\n' > "$T/r/docs/a.md"
}
total_line() { echo "$output" | grep '^TOTAL'; }
jq_py() { python3 -c "import json,sys;d=json.load(sys.stdin);print($1)"; }

# ── AC-1 ──────────────────────────────────────────────────────────────────

@test "AC-1: be2fca5aa da 27.633 B exactos y 6.800-7.800 tokens" {
  if ! git -C "$ROOT" cat-file -e be2fca5aa^{commit} 2>/dev/null; then
    # En CI el clon es completo (fetch-depth: 0): si falta el commit, AC-1 no puede quedar sin verificar.
    if [ -n "${CI:-}${GITHUB_ACTIONS:-}" ]; then echo "be2fca5aa ausente en CI: AC-1 sin verificar" >&2; return 1; fi
    skip "be2fca5aa no está en este clon (clon superficial)"
  fi
  mkdir -p "$T/r"
  git -C "$ROOT" archive be2fca5aa CLAUDE.md docs/critical-facts.md .claude/profiles/savia.md \
    docs/rules/domain/radical-honesty.md docs/rules/domain/autonomous-safety.md \
    docs/rules/domain/caveman-default.md docs/rules/domain/knowledge-discovery-priority.md .gitignore | tar -x -C "$T/r"
  git -C "$T/r" init -q   # los imports locales (perfil activo, memoria externa) están gitignored
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned --json
  [ "$status" -eq 0 ]
  bytes=$(echo "$output" | jq_py 'd["bytes"]')
  tokens=$(echo "$output" | jq_py 'd["tokens"]')
  [ "$bytes" -eq 27633 ]
  [ "$tokens" -ge 6800 ] && [ "$tokens" -le 7800 ]
}

@test "AC-1: bytes, caracteres y tokens exactos en raíz sintética (multibyte)" {
  mkroot
  printf 'ñandú\n' >> "$T/r/docs/a.md"   # 7 B, 6 caracteres
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned --json
  [ "$status" -eq 0 ]
  expect_b=$(( $(wc -c < "$T/r/CLAUDE.md") + $(wc -c < "$T/r/docs/a.md") ))
  expect_c=$(( $(wc -m < "$T/r/CLAUDE.md") + $(wc -m < "$T/r/docs/a.md") ))
  got=$(echo "$output" | jq_py 'd["bytes"],d["chars"],d["tokens"]')
  [ "$got" = "$expect_b $expect_c $(( expect_c / 4 ))" ]
  [ "$expect_b" -ne "$expect_c" ]
}

@test "AC-1: dos ejecuciones en el repo dan la misma cifra" {
  run bash "$S" --versioned; [ "$status" -eq 0 ]; a="$(total_line)"
  run bash "$S" --versioned; b="$(total_line)"
  [ "$status" -eq 0 ]
  [ -n "$a" ] && [ "$a" = "$b" ]
}

@test "AC-1 negativo: sin modo, con dos modos o con --entry inválido sale con 2" {
  run bash "$S"; [ "$status" -eq 2 ]
  run bash "$S" --versioned --hooks; [ "$status" -eq 2 ]
  run bash "$S" --entry foo --versioned; [ "$status" -eq 2 ]
}

# ── AC-2 ──────────────────────────────────────────────────────────────────

@test "AC-2: @import a fichero inexistente -> exit != 0 y ningún TOTAL" {
  mkroot
  printf '@docs/no-existe.md\n' >> "$T/r/CLAUDE.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [ "$status" -ne 0 ]
  [[ "$output" == *"inexistente"* ]]
  [[ "$output" != *"TOTAL"* ]]
}

@test "AC-2: ciclo de imports -> exit != 0 y ningún TOTAL" {
  mkroot
  printf '@CLAUDE.md\n' >> "$T/r/docs/a.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [ "$status" -ne 0 ]
  [[ "$output" == *"ciclo"* ]]
  [[ "$output" != *"TOTAL"* ]]
}

@test "AC-2 control: import ausente pero gitignored NO es error; sin gitignore sí lo es" {
  mkroot
  printf '@.local/perfil.md\n' >> "$T/r/CLAUDE.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [ "$status" -ne 0 ]
  git -C "$T/r" init -q
  printf '.local/\n' > "$T/r/.gitignore"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [ "$status" -eq 0 ]
  [[ "$output" == *"TOTAL"* ]]
}

@test "AC-2: prosa con @imports, código en línea y bloques no cuentan como import" {
  mkroot
  printf 'Los @imports se cargan; usa `@docs/falso.md` o\n```\n@docs/falso2.md\n```\n' >> "$T/r/CLAUDE.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [ "$status" -eq 0 ]
}

@test "AC-2: import repetido (diamante) cuenta una vez" {
  mkroot
  printf '@docs/a.md\n' >> "$T/r/CLAUDE.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'len(d["pieces"])')" -eq 2 ]
}

@test "AC-2: import anidado se resuelve desde la raíz, no desde el fichero importador" {
  mkroot
  printf '@b.md\n' >> "$T/r/docs/a.md"
  printf 'raiz\n' > "$T/r/b.md"; printf 'hermano-mas-largo\n' > "$T/r/docs/b.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py '[p["name"] for p in d["pieces"]][-1]')" = "b.md" ]
  rm "$T/r/b.md"   # solo existe junto al importador -> inexistente (error, no cifra falsa)
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [ "$status" -eq 1 ]
  [[ "$output" == *"inexistente"* ]]
}

# ── hooks (D2) ────────────────────────────────────────────────────────────

mkhooks() {
  mkdir -p "$T/h/.claude" "$T/h/tests/fixtures/context-fixed"
  git -C "$T/h" init -q   # --hooks exige git y un commit: mide en un worktree desechable de HEAD
  printf '# x\n' > "$T/h/CLAUDE.md"
  cp "$ROOT/tests/fixtures/context-fixed/turn.json" "$T/h/tests/fixtures/context-fixed/turn.json"
  sethooks "$@"
  gitc add -A; gitc commit -q --allow-empty -m fixture
}
gitc() { git -C "$T/h" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
# Escribe settings.json con un hook de SessionStart por argumento (sin commit).
sethooks() {
  python3 - "$T/h/.claude/settings.json" "$@" <<'PY'
import json, sys
json.dump({"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": c} for c in sys.argv[2:]]}],
                     "UserPromptSubmit": []}}, open(sys.argv[1], "w"))
PY
}

@test "hooks: captura additionalContext JSON (no el envoltorio) y es estable" {
  mkhooks "printf '%s' '{\"hookSpecificOutput\":{\"additionalContext\":\"12345678\"}}'"
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'd["chars"]')" -eq 8 ]
}

@test "hooks: stdout plano cuenta entero" {
  mkhooks "printf 'abcd'"
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'd["chars"]')" -eq 4 ]
}

@test "hooks negativo: hook no determinista -> exit != 0 sin total" {
  # Determinista para el test: la 1.ª ejecución deja una marca y la 2.ª imprime otra cosa.
  mkhooks 'mkdir -p data; if [ -e data/n ]; then printf ab; else : > data/n; printf a; fi'
  printf 'data/\n' > "$T/h/.gitignore"
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks
  [ "$status" -eq 1 ]
  [[ "$output" == *"no determinista"* ]]
  [[ "$output" != *"TOTAL"* ]]
  [ ! -e "$T/h/data/n" ]   # la marca la creó la medición: se limpia también al fallar
}

@test "hooks negativo: hook que sale con código != 0 -> exit 1 sin total (no cuenta 0 en silencio)" {
  mkhooks "printf 'abcd'; exit 1"
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks
  [ "$status" -eq 1 ]
  [[ "$output" == *"código 1"* ]]
  [[ "$output" != *"TOTAL"* ]]
}

@test "hooks: sin exclusiones; un hook que escribe en el repo se mide y no toca la raíz" {
  mkdir -p "$T/h/scripts"
  printf 'mkdir -p data; : > data/.marker; printf zzzz\n' > "$T/h/scripts/windows-links.sh"
  mkhooks 'bash "$CLAUDE_PROJECT_DIR"/scripts/windows-links.sh repair'
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'd["hooks"][0]["status"]')" = "medido" ]
  [ "$(echo "$output" | jq_py 'd["chars"]')" -eq 4 ]
  [ ! -e "$T/h/data/.marker" ]
  [ "$(git -C "$T/h" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]   # temporal retirado
}

@test "hooks: no borra ficheros ajenos que aparecen en la raíz durante la medición" {
  # Simula otra sesión que guarda un fichero en la raíz mientras corren los hooks.
  mkhooks "mkdir -p '$T/h/data'; printf trabajo > '$T/h/data/ajeno.md'; printf ok"
  printf 'data/\n' > "$T/h/.gitignore"
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks
  [ "$status" -eq 0 ]
  [ "$(cat "$T/h/data/ajeno.md")" = "trabajo" ]
}

@test "hooks: la cifra no depende de la rama del checkout" {
  mkhooks 'git branch --show-current'
  gitc checkout -q -b a
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks --json
  [ "$status" -eq 0 ]; a=$(echo "$output" | jq_py 'd["chars"]')
  gitc checkout -q -b rama-con-un-nombre-largo
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks --json
  [ "$status" -eq 0 ]; b=$(echo "$output" | jq_py 'd["chars"]')
  [ "$a" = "$b" ]
}

@test "hooks: mide los cambios sin commit (settings modificado y script nuevo sin versionar)" {
  mkhooks "printf ab"
  mkdir -p "$T/h/scripts"; printf 'printf abcdef\n' > "$T/h/scripts/nuevo.sh"
  sethooks 'bash "$CLAUDE_PROJECT_DIR"/scripts/nuevo.sh'
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'd["chars"]')" -eq 6 ]
}

@test "hooks: espera a los procesos en segundo plano de un hook antes del siguiente" {
  # Sin la espera, el 2.º hook ve «tarde» solo en la 2.ª ejecución -> no determinista.
  mkhooks '(sleep 0.5; : > tarde) >/dev/null 2>&1 & printf a' 'if [ -e tarde ]; then printf bb; else printf c; fi'
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'd["chars"]')" -eq 3 ]
}

@test "hooks negativo: raíz sin git -> exit 1" {
  mkhooks "printf ok"
  rm -rf "$T/h/.git"
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks
  [ "$status" -eq 1 ]
  [[ "$output" == *"repositorio git"* ]]
}

@test "hooks negativo: repositorio sin commits -> exit 1 sin total" {
  mkhooks "printf ok"
  rm -rf "$T/h/.git"; git -C "$T/h" init -q
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks
  [ "$status" -eq 1 ]
  [[ "$output" == *"commit"* ]]
  [[ "$output" != *"TOTAL"* ]]
}

@test "hooks negativo: fixture ausente -> exit != 0" {
  mkhooks "echo hola"
  rm "$T/h/tests/fixtures/context-fixed/turn.json"
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks
  [ "$status" -ne 0 ]
}

@test "hooks: el repo real da la misma cifra en dos ejecuciones y no escribe en el árbol" {
  before="$(git -C "$ROOT" status --porcelain --ignored -uall | md5sum)"
  run bash "$S" --hooks; [ "$status" -eq 0 ]; a="$(total_line)"
  run bash "$S" --hooks; b="$(total_line)"
  [ "$status" -eq 0 ]
  [ -n "$a" ] && [ "$a" = "$b" ]
  [ "$before" = "$(git -C "$ROOT" status --porcelain --ignored -uall | md5sum)" ]
}

# ── AC-4 ──────────────────────────────────────────────────────────────────

cur_tokens() { bash "$S" "--$1" --json | jq_py 'd["tokens"]'; }

@test "AC-4: los baselines versionados coinciden con la medición actual (sin holgura)" {
  [ "$(tr -d '[:space:]' < "$ROOT/.ci-baseline/context-fixed-tokens.count")" = "$(cur_tokens versioned)" ]
  [ "$(tr -d '[:space:]' < "$ROOT/.ci-baseline/context-fixed-hooks-tokens.count")" = "$(cur_tokens hooks)" ]
}

@test "AC-4: --versioned --check pasa con baseline igual y falla con baseline menor" {
  cur=$(cur_tokens versioned); mkdir -p "$T/b"
  echo "$cur" > "$T/b/context-fixed-tokens.count"
  CI_BASELINE_DIR="$T/b" run bash "$S" --versioned --check
  [ "$status" -eq 0 ]
  echo $(( cur - 1 )) > "$T/b/context-fixed-tokens.count"
  CI_BASELINE_DIR="$T/b" run bash "$S" --versioned --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "AC-4: --hooks --check pasa con baseline igual y falla con baseline menor" {
  cur=$(cur_tokens hooks); mkdir -p "$T/b"
  echo "$cur" > "$T/b/context-fixed-hooks-tokens.count"
  CI_BASELINE_DIR="$T/b" run bash "$S" --hooks --check
  [ "$status" -eq 0 ]
  echo $(( cur - 1 )) > "$T/b/context-fixed-hooks-tokens.count"
  CI_BASELINE_DIR="$T/b" run bash "$S" --hooks --check
  [ "$status" -eq 1 ]
}

@test "AC-4: baseline ausente o basura -> exit != 0 (fail-closed)" {
  mkdir -p "$T/b"
  CI_BASELINE_DIR="$T/b" run bash "$S" --versioned --check
  [ "$status" -ne 0 ]
  echo "abc" > "$T/b/context-fixed-tokens.count"
  CI_BASELINE_DIR="$T/b" run bash "$S" --versioned --check
  [ "$status" -ne 0 ]
}

@test "AC-4: una subida real del contexto (CLAUDE.md +400 B) rompe el gate" {
  mkroot; mkdir -p "$T/b"
  CONTEXT_FIXED_ROOT="$T/r" bash "$S" --versioned --json | jq_py 'd["tokens"]' > "$T/b/context-fixed-tokens.count"
  CONTEXT_FIXED_ROOT="$T/r" CI_BASELINE_DIR="$T/b" run bash "$S" --versioned --check
  [ "$status" -eq 0 ]
  head -c 400 /dev/zero | tr '\0' 'x' >> "$T/r/CLAUDE.md"
  CONTEXT_FIXED_ROOT="$T/r" CI_BASELINE_DIR="$T/b" run bash "$S" --versioned --check
  [ "$status" -eq 1 ]
}

@test "AC-4: ci-extended-checks incluye el gate y falla si el baseline baja" {
  mkdir -p "$T/b"; cp "$ROOT"/.ci-baseline/*.count "$ROOT"/.ci-baseline/*.pct "$T/b/"
  echo 1 > "$T/b/context-fixed-tokens.count"
  CI_BASELINE_DIR="$T/b" run bash "$ROOT/scripts/ci-extended-checks.sh"
  # La línea del gate debe llevar el FAIL del trinquete, no un ERROR de otra causa.
  [[ "$output" == *"❌ Contexto fijo (versioned): FAIL: versionado"*"> baseline 1"* ]]
}

@test "--check sin baseline posible (--local, --entry opencode) sale con 2, no con 0" {
  run bash "$S" --local --check; [ "$status" -eq 2 ]
  run bash "$S" --versioned --entry opencode --check; [ "$status" -eq 2 ]
  [[ "$output" == *"--check solo existe"* ]]
}

@test "--json --check deja stdout como JSON puro con el veredicto dentro" {
  mkroot; mkdir -p "$T/b"; echo 1 > "$T/b/context-fixed-tokens.count"
  CONTEXT_FIXED_ROOT="$T/r" CI_BASELINE_DIR="$T/b" run --separate-stderr bash "$S" --versioned --json --check
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq_py 'd["check"]["ok"]')" = "False" ]
  [[ "$stderr" == FAIL:* ]]
}

@test "--local --json con aviso deja stdout como JSON puro" {
  mkroot
  head -c 30000 /dev/zero | tr '\0' 'x' >> "$T/r/docs/a.md"
  CONTEXT_FIXED_ROOT="$T/r" run --separate-stderr bash "$S" --local --json
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq_py 'd["warning"]')" == AVISO* ]]
}

@test "imports fuera de la raíz (.. o absolutos) -> exit 1 aunque el fichero exista" {
  mkroot; printf 'fuera\n' > "$T/fuera.md"
  printf '@../fuera.md\n' >> "$T/r/CLAUDE.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [ "$status" -eq 1 ]; [[ "$output" == *"fuera de la raíz"* ]]
  rm -rf "$T/r"; mkroot; printf '@%s\n' "$T/fuera.md" >> "$T/r/CLAUDE.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [ "$status" -eq 1 ]; [[ "$output" == *"fuera de la raíz"* ]]
}

# Raíz con un fichero local (gitignored) que importa algo roto.
mklocalbroken() {
  mkroot; git -C "$T/r" init -q
  printf '.claude/\n' > "$T/r/.gitignore"
  mkdir -p "$T/r/.claude/profiles"
  printf '@docs/privado-cliente-x.md\n' > "$T/r/.claude/profiles/active-user.md"
  printf '@.claude/profiles/active-user.md\n' >> "$T/r/CLAUDE.md"
}

@test "--versioned no recorre ficheros locales: un import roto dentro de uno no rompe la medición" {
  mklocalbroken
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'len(d["pieces"])')" -eq 2 ]
  [[ "$output" != *"privado-cliente-x"* ]]
}

@test "AC-11 negativo: errores con ficheros locales no imprimen su ruta ni lo que importan" {
  mklocalbroken
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --local
  [ "$status" -eq 1 ]
  [[ "$output" == *"inexistente"* ]]
  [[ "$output" != *"privado-cliente-x"* ]]
  [[ "$output" != *"active-user"* ]]
  printf '@CLAUDE.md\n' > "$T/r/.claude/profiles/active-user.md"     # ciclo vía fichero local
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --local
  [ "$status" -eq 1 ]
  [[ "$output" == *"ciclo"* ]]
  [[ "$output" != *"active-user"* ]]
  printf '\xff\xfe\n' > "$T/r/.claude/profiles/active-user.md"       # ilegible (no UTF-8)
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --local
  [ "$status" -eq 1 ]
  [[ "$output" == *"ilegible"* ]]
  [[ "$output" != *"active-user"* ]]
}

# ── AC-11 ─────────────────────────────────────────────────────────────────

@test "AC-11: --local suma piezas gitignored sin imprimir ruta ni contenido" {
  mkroot
  git -C "$T/r" init -q
  printf '.claude/\n' > "$T/r/.gitignore"
  mkdir -p "$T/r/.claude/profiles"
  printf 'Nombre: SecretoPersonal123 /home/persona/privado\n' > "$T/r/.claude/profiles/active-user.md"
  printf '@.claude/profiles/active-user.md\n' >> "$T/r/CLAUDE.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --local
  [ "$status" -eq 0 ]
  [[ "$output" == *"local-1"* ]]
  [[ "$output" != *"SecretoPersonal123"* ]]
  [[ "$output" != *"active-user"* ]]
  [[ "$output" != *"/home/persona"* ]]
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --local --json
  [[ "$output" != *"SecretoPersonal123"* ]]
  [[ "$output" != *"active-user"* ]]
  # --versioned no cuenta la pieza local
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --versioned
  [[ "$output" != *"local-1"* ]]
}

@test "AC-11: --local avisa por encima de 6.000 tokens y no falla" {
  mkroot
  head -c 30000 /dev/zero | tr '\0' 'x' >> "$T/r/docs/a.md"
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --local
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO"* ]]
}

@test "AC-11: --local en raíz pequeña no avisa" {
  mkroot
  CONTEXT_FIXED_ROOT="$T/r" run bash "$S" --local
  [ "$status" -eq 0 ]
  [[ "$output" != *"AVISO"* ]]
}

@test "AC-11 boundary: --local con 6.000 tokens exactos no avisa; con 6.001 sí" {
  mkroot   # se completa hasta el límite exacto: 6.000 tokens = 24.000 caracteres
  have=$(( $(wc -m < "$T/r/CLAUDE.md") + $(wc -m < "$T/r/docs/a.md") ))
  head -c $(( 6000 * 4 - have )) /dev/zero | tr '\0' 'x' >> "$T/r/docs/a.md"
  CONTEXT_FIXED_ROOT="$T/r" run --separate-stderr bash "$S" --local --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'd["tokens"]')" -eq 6000 ]
  [[ "$output$stderr" != *"AVISO"* ]]
  printf 'xxxx' >> "$T/r/docs/a.md"
  CONTEXT_FIXED_ROOT="$T/r" run --separate-stderr bash "$S" --local --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_py 'd["tokens"]')" -eq 6001 ]
  [[ "$output" == *"AVISO"* ]]
}

@test "hooks timeout: un hook colgado -> exit 1 sin total y sin procesos huérfanos" {
  mkhooks 'sleep 300 & printf a; sleep 300'
  CONTEXT_FIXED_ROOT="$T/h" run bash "$S" --hooks
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin respuesta a tiempo"* ]]
  [[ "$output" != *"TOTAL"* ]]
  [ "$(git -C "$T/h" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]
}

@test "safety: el script usa set -uo pipefail y python3 -I" {
  grep -q '^set -uo pipefail' "$S"
  grep -q 'exec python3 -I' "$S"
}
