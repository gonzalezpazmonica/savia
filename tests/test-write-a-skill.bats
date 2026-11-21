#!/usr/bin/env bats
# SE-376 — calibración de write-a-skill contra su comportamiento real.
# Ref: docs/rules/domain/skill-template-protocol.md
# Ref: .claude/skills/write-a-skill/SKILL.md
#
# La skill delega en tres scripts: el auditor de catálogo, el generador de
# SKILLS.md / skills-manifest.json y el gate G14 de pre-push que invoca al
# auditor. Todos los casos usan catálogos sintéticos en mktemp -d.

SCRIPT="scripts/skill-catalog-auditor.sh"
GENERATOR="scripts/skills-md-generate.sh"
PREPUSH="scripts/pre-push-bats-critical.sh"

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d)"
  SK="$WORK/skills dir"
  mkdir -p "$SK"
  unset SAVIA_SESSION_ACTIVE SAVIA_PRE_PUSH_BATS_ACTIVE
}

teardown() {
  rm -rf "$WORK"
}

# make_skill <name> <description-frontmatter-lines> [extra-body-lines]
make_skill() {
  local name="$1" desc="$2" body_lines="${3:-5}" i
  mkdir -p "$SK/$name"
  {
    echo "---"
    echo "name: $name"
    printf '%s\n' "$desc"
    echo "---"
    echo ""
    echo "# Skill $name"
    echo ""
    echo "Lee scripts/ejemplo.sh antes de actuar sobre el catalogo."
    for ((i = 0; i < body_lines; i++)); do echo "linea $i"; done
  } > "$SK/$name/SKILL.md"
  printf '# Dominio\n\nPor que existe.\nConceptos.\nLimites.\n' > "$SK/$name/DOMAIN.md"
}

audit() { SAVIA_SKILLS_DIR="$SK" run bash "$REPO/$SCRIPT" "$@"; }

# El generador congela --apply si existe <raiz>/data/.cache-session-active (SE-371), y ese
# marcador lo crea el hook de una sesion viva en el repo real: la suite fallaba dentro de
# una sesion de Claude y pasaba en CI. Se ejecuta una copia en una raiz sintetica sin marcador.
gen() {
  mkdir -p "$WORK/fakeroot/scripts"
  cp "$REPO/$GENERATOR" "$WORK/fakeroot/scripts/skills-md-generate.sh"
  PROJECT_ROOT="$WORK" SKILLS_DIR="$SK" SKILLS_MD="$WORK/SKILLS.md" \
    SKILLS_MANIFEST="$WORK/manifest.json" run bash "$WORK/fakeroot/scripts/skills-md-generate.sh" "$@"
}

# ── Seguridad del objetivo ───────────────────────────────────────────────────

@test "targets declare set -uo pipefail" {
  run grep -c '^set -uo pipefail' "$REPO/$SCRIPT" "$REPO/$GENERATOR" "$REPO/$PREPUSH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SCRIPT:1"* ]]
  [[ "$output" == *"$GENERATOR:1"* ]]
}

# ── Auditor: casos positivos ─────────────────────────────────────────────────

@test "auditor: well-formed skill passes OK with exit 0" {
  make_skill buena 'description: "Usar cuando se audita el catalogo de skills."'
  audit --skill buena
  [ "$status" -eq 0 ]
  [[ "$output" == *"buena"*"OK"* ]]
}

@test "auditor: folded description (>) is read as text, not as '>'" {
  make_skill plegada "$(printf 'description: >\n  Detecta el bus factor por modulo del repositorio.\n  Usar cuando se analiza riesgo de conocimiento.')"
  audit --skill plegada
  [ "$status" -eq 0 ]
  [[ "$output" == *"plegada"*" OK "* ]]
  [[ "$output" != *"< 20 chars"* ]]
}

@test "auditor: literal (|-) description is read as text" {
  make_skill literal "$(printf 'description: |-\n  Usar cuando se necesita un literal multilinea\n  en la descripcion de la skill.')"
  audit --skill literal
  [ "$status" -eq 0 ]
  [[ "$output" != *"missing trigger"* ]]
}

@test "auditor: path with spaces in skills dir works" {
  make_skill espacios 'description: "Usar cuando la ruta del catalogo tiene espacios."'
  audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"TOTAL: 1"* ]]
}

# ── Auditor: casos negativos ─────────────────────────────────────────────────

@test "auditor: missing DOMAIN.md fails with exit 1" {
  make_skill sindominio 'description: "Usar cuando falta el fichero de dominio."'
  mv "$SK/sindominio/DOMAIN.md" "$WORK/"
  audit --skill sindominio
  [ "$status" -eq 1 ]
  [[ "$output" == *"DOMAIN.md missing"* ]]
}

@test "auditor: empty name value is rejected as invalid frontmatter" {
  make_skill vacia 'description: "Usar cuando el nombre esta vacio en el frontmatter."'
  sed -i 's/^name: vacia$/name:/' "$SK/vacia/SKILL.md"
  audit --skill vacia
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"*"name"* ]]
}

@test "auditor: --skill without a value is a usage error, not a full audit" {
  make_skill una 'description: "Usar cuando hay una sola skill."'
  audit --skill
  [ "$status" -eq 2 ]
  [[ "$output" != *"TOTAL:"* ]]
}

@test "auditor: unknown skill name fails" {
  audit --skill no-existe
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "auditor: explicit --skill _template is audited, not silently skipped" {
  make_skill _template 'description: "Usar cuando se copia la plantilla."'
  audit --skill _template
  [ "$status" -eq 0 ]
  [[ "$output" == *"TOTAL: 1"* ]]
}

@test "auditor: full scan still skips _template" {
  make_skill _template 'description: "Usar cuando se copia la plantilla."'
  make_skill real 'description: "Usar cuando hay una skill real."'
  audit
  [[ "$output" == *"TOTAL: 1"* ]]
  [[ "$output" != *"_template "* ]]
}

@test "auditor: description using 'User' does not count as trigger keyword" {
  make_skill usuario 'description: "User profile manager para el equipo completo."'
  audit --skill usuario
  [[ "$output" == *"missing trigger"* ]]
}

@test "auditor: capitalised 'When' counts as trigger keyword" {
  make_skill cuando 'description: "When a catalog drifts, regenerate the index safely."'
  audit --skill cuando
  [ "$status" -eq 0 ]
  [[ "$output" != *"missing trigger"* ]]
}

# ── Auditor: límites ─────────────────────────────────────────────────────────

@test "auditor: boundary 150 lines passes, 151 lines without final newline fails" {
  make_skill limite 'description: "Usar cuando se prueba el limite de lineas."' 0
  local n
  n=$(wc -l < "$SK/limite/SKILL.md")
  for ((i = n; i < 150; i++)); do echo "relleno $i" >> "$SK/limite/SKILL.md"; done
  audit --skill limite
  [ "$status" -eq 0 ]
  printf 'linea 151 sin salto final' >> "$SK/limite/SKILL.md"
  audit --skill limite
  [ "$status" -eq 1 ]
  [[ "$output" == *"151 lines > 150"* ]]
}

@test "auditor: empty catalog reports zero total and exit 0" {
  audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"TOTAL: 0"* ]]
}

@test "auditor: --json stays valid JSON with quotes and backslashes in names" {
  make_skill 'raro"nom\bre' 'description: "Usar cuando el nombre tiene comillas."'
  SAVIA_SKILLS_DIR="$SK" bash "$REPO/$SCRIPT" --json > "$WORK/out.json" 2>/dev/null
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[0]["skill"])' "$WORK/out.json"
  [ "$status" -eq 0 ]
  [ "$output" = 'raro"nom\bre' ]
}

# ── Generador SKILLS.md ──────────────────────────────────────────────────────

@test "generator: default mode is a dry run and writes nothing" {
  make_skill seca 'description: "Usar cuando se regenera el catalogo."'
  gen
  [ "$status" -eq 0 ]
  [[ "$output" == *"| seca |"* ]]
  [ ! -e "$WORK/SKILLS.md" ]
}

@test "generator: truncation never splits a multibyte UTF-8 character" {
  # 96 ASCII bytes followed by accented chars: a byte cut at 97 lands mid-char.
  local pad
  pad=$(printf 'a%.0s' $(seq 1 96))
  make_skill acentos "description: \"${pad}áéíóúáéíóúáéíóú\""
  gen
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$WORK/gen.md"
  run iconv -f UTF-8 -t UTF-8 "$WORK/gen.md"
  [ "$status" -eq 0 ]
  run grep -c "${pad}á\.\.\. |" "$WORK/gen.md"
  [ "$output" = "1" ]
}

@test "generator: description of exactly 100 characters is not truncated" {
  local pad
  pad=$(printf 'b%.0s' $(seq 1 95))
  make_skill cien "description: \"${pad}ñáéíó\""
  gen
  [[ "$output" == *"${pad}ñáéíó |"* ]]
}

@test "generator: literal block description is extracted" {
  make_skill bloque "$(printf 'description: |\n  Usar cuando el texto es un bloque literal.')"
  gen
  [[ "$output" == *"| bloque |"*"Usar cuando el texto es un bloque literal. |"* ]]
}

@test "generator: --apply writes 0644 files next to the target" {
  make_skill permisos 'description: "Usar cuando se comprueban permisos."'
  umask 022
  gen --apply --manifest
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$WORK/SKILLS.md")" = "644" ]
  [ "$(stat -c %a "$WORK/manifest.json")" = "644" ]
}

@test "generator: --check --manifest is in sync after apply even when time passes" {
  make_skill tiempo 'description: "Usar cuando pasa el tiempo entre apply y check."'
  gen --apply --manifest
  sed -i 's/"generated_at": "[^"]*"/"generated_at": "2000-01-01T00:00:00Z"/' "$WORK/manifest.json"
  gen --check --manifest
  [ "$status" -eq 0 ]
  [[ "$output" == *"skills-manifest.json: in sync"* ]]
}

@test "generator: --check detects real drift in the manifest" {
  make_skill deriva 'description: "Usar cuando el manifiesto queda obsoleto."'
  gen --apply --manifest
  sed -i 's/Usar cuando el manifiesto/Texto obsoleto/' "$WORK/manifest.json"
  gen --check --manifest
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift detected in skills-manifest.json"* ]]
}

@test "generator: manifest is valid JSON and keeps pipes unescaped" {
  make_skill 'tu"bo' 'description: "Usar cuando a | b aparece en la descripcion."'
  gen --apply --manifest
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["skills"]; print(d["tu\"bo"]["description"])' "$WORK/manifest.json"
  [ "$status" -eq 0 ]
  [ "$output" = "Usar cuando a | b aparece en la descripcion." ]
  run grep -c 'a \\| b' "$WORK/SKILLS.md"
  [ "$output" = "1" ]
}

@test "generator: unknown argument is rejected with exit 2" {
  gen --bogus
  [ "$status" -eq 2 ]
}

@test "generator: missing skills dir fails with exit 3" {
  SK="$WORK/no-existe"
  gen
  [ "$status" -eq 3 ]
}

@test "generator: active session blocks --apply (SE-371) and writes nothing" {
  make_skill sesion 'description: "Usar cuando hay sesion activa."'
  SAVIA_SESSION_ACTIVE=1 PROJECT_ROOT="$WORK" SKILLS_DIR="$SK" SKILLS_MD="$WORK/SKILLS.md" \
    run bash "$REPO/$GENERATOR" --apply
  [ "$status" -eq 3 ]
  [ ! -e "$WORK/SKILLS.md" ]
}

@test "generator: el marcador de sesion activa (SE-371) bloquea --apply y no escribe nada" {
  make_skill marcador 'description: "Usar cuando hay marcador de sesion."'
  mkdir -p "$WORK/fakeroot/data"
  : > "$WORK/fakeroot/data/.cache-session-active"
  gen --apply
  [ "$status" -eq 3 ]
  [[ "$output" == *"sesión activa"* ]]
  [ ! -e "$WORK/SKILLS.md" ]
}

@test "generator: sin marcador ni variable --apply escribe SKILLS.md (negativo del bloqueo)" {
  make_skill libre 'description: "Usar cuando no hay sesion activa."'
  gen --apply
  [ "$status" -eq 0 ]
  [ -f "$WORK/SKILLS.md" ]
}

# ── G14: pre-push invoca al auditor sobre las skills modificadas ─────────────

make_fixture_repo() {
  FX="$WORK/repo"
  mkdir -p "$FX/scripts" "$FX/tests" "$FX/.claude/skills" "$FX/.opencode"
  cp "$REPO/$SCRIPT" "$FX/scripts/"
  ln -s ../.claude/skills "$FX/.opencode/skills"
  git -C "$FX" init -q -b main
  git -C "$FX" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m base
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
  git -C "$FX" checkout -q -b agent/x
}

@test "G14: a broken skill under .claude/skills blocks pre-push" {
  make_fixture_repo
  mkdir -p "$FX/.claude/skills/rota"
  printf -- '---\nname: rota\n---\n' > "$FX/.claude/skills/rota/SKILL.md"
  git -C "$FX" add -A
  git -C "$FX" -c user.email=t@example.invalid -c user.name=t commit -q -m rota
  cd "$FX"
  REPO_ROOT="$FX" run bash "$REPO/$PREPUSH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"G14 FAIL: skill 'rota'"* ]]
}

@test "G14: a valid skill under .claude/skills passes pre-push" {
  make_fixture_repo
  SK="$FX/.claude/skills"
  make_skill sana 'description: "Usar cuando la skill modificada es correcta."'
  git -C "$FX" add -A
  git -C "$FX" -c user.email=t@example.invalid -c user.name=t commit -q -m sana
  cd "$FX"
  REPO_ROOT="$FX" run bash "$REPO/$PREPUSH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"G14 skill quality gate passed"* ]]
}

# ── Huecos medidos por mutación en las suites previas ────────────────────────

@test "auditor: DOMAIN.md of 61 lines is a WARN boundary, 60 lines is OK" {
  make_skill dominio 'description: "Usar cuando se prueba el limite del dominio."'
  for i in $(seq 6 60); do echo "dominio $i" >> "$SK/dominio/DOMAIN.md"; done
  audit --skill dominio
  [[ "$output" == *"dominio"*" OK "* ]]
  echo "dominio 61" >> "$SK/dominio/DOMAIN.md"
  audit --skill dominio
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"*"DOMAIN.md: 61 lines (max 60)"* ]]
}

@test "generator: folded description is joined into one line" {
  make_skill doblada "$(printf 'description: >\n  Usar cuando el texto\n  ocupa varias lineas.\nlayer: peripheral')"
  gen
  [[ "$output" == *"| doblada |"*"| Usar cuando el texto ocupa varias lineas. |"* ]]
}

@test "generator: missing name falls back to the directory name" {
  make_skill anonima 'description: "Usar cuando falta el nombre."'
  sed -i '/^name: anonima$/d' "$SK/anonima/SKILL.md"
  gen
  [[ "$output" == *"| anonima | \`"* ]]
}

@test "generator: --check rejects a stale SKILLS.md with exit 1" {
  make_skill vieja 'description: "Usar cuando el indice esta obsoleto."'
  gen --apply
  echo "| fantasma | x | y |" >> "$WORK/SKILLS.md"
  gen --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift detected in SKILLS.md"* ]]
}

@test "auditor: 101-line SKILL.md is a WARN, not a FAIL (SE-208 boundary)" {
  make_skill larga 'description: "Usar cuando la skill supera las cien lineas."' 0
  local n
  n=$(wc -l < "$SK/larga/SKILL.md")
  for ((i = n; i < 101; i++)); do echo "relleno $i" >> "$SK/larga/SKILL.md"; done
  audit --skill larga
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"*"101 lines > 100"* ]]
}

@test "auditor: description over 200 characters warns, 200 accented characters do not" {
  local base
  base=$(printf 'á%.0s' $(seq 1 188))
  make_skill justa "description: \"Usar cuando ${base}\""
  audit --skill justa
  [[ "$output" == *"justa"*" OK "* ]]
  make_skill excesiva "description: \"Usar cuando ${base}x\""
  audit --skill excesiva
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"*"201 chars > 200"* ]]
}

# ── Revisión maker-checker: borrado legítimo y deriva de cabecera ────────────

@test "G14: deleting a skill is legitimate and does not block pre-push" {
  make_fixture_repo
  SK="$FX/.claude/skills"
  make_skill vieja 'description: "Usar cuando la skill va a borrarse."'
  make_skill otra 'description: "Usar cuando la skill va a renombrarse."'
  git -C "$FX" add -A
  git -C "$FX" -c user.email=t@example.invalid -c user.name=t commit -q -m base2
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
  git -C "$FX" rm -q -r .claude/skills/vieja
  git -C "$FX" mv .claude/skills/otra .claude/skills/renombrada
  git -C "$FX" -c user.email=t@example.invalid -c user.name=t commit -q -m borrar
  cd "$FX"
  REPO_ROOT="$FX" run bash "$REPO/$PREPUSH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping deleted skill: vieja"* ]]
  [[ "$output" == *"auditing skill: renombrada"* ]]
  [[ "$output" == *"G14 skill quality gate passed"* ]]
}

@test "generator: --check detects drift in manifest version" {
  make_skill version 'description: "Usar cuando cambia la version del manifiesto."'
  gen --apply --manifest
  sed -i 's/"version": "1.0"/"version": "0.9"/' "$WORK/manifest.json"
  gen --check --manifest
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift detected in skills-manifest.json"* ]]
}

# ── SE-376 S03 grupo 7: mutantes del auditor que sobrevivían ─────────────────

# raw_skill <name> <contenido-SKILL.md>: SKILL.md literal + DOMAIN.md valido
raw_skill() {
  mkdir -p "$SK/$1"
  printf '%s\n' "$2" > "$SK/$1/SKILL.md"
  printf '# Dominio\n\nPor que existe.\nConceptos.\nLimites.\n' > "$SK/$1/DOMAIN.md"
}

# padded_skill <name> <total-lines>: SKILL.md valido con exactamente N lineas
padded_skill() {
  make_skill "$1" 'description: "Usar cuando se prueba el limite de lineas."' 0
  while [ "$(wc -l < "$SK/$1/SKILL.md")" -lt "$2" ]; do echo "relleno" >> "$SK/$1/SKILL.md"; done
}

@test "auditor: unknown flag is a usage error with exit 1 and a message" {
  run bash -c 'SAVIA_SKILLS_DIR="$1" bash "$2/$3" --nope' _ "$SK" "$REPO" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown flag: --nope"* ]]
}

@test "auditor: description of exactly 20 characters does not warn, 19 does" {
  make_skill veinte 'description: "Usar cuando abcdefgh"'
  audit --skill veinte
  [[ "$output" != *"< 20 chars"* ]]
  make_skill diecinueve 'description: "Usar cuando abcdefg"'
  audit --skill diecinueve
  [[ "$output" == *"< 20 chars"* ]]
}

@test "auditor: description key in the body does not count as frontmatter description" {
  raw_skill sindesc "$(printf -- '---\nname: sindesc\n---\n\n# Skill\n\ndescription: texto en el cuerpo, no en el frontmatter\nLee scripts/ejemplo.sh y mas contenido.')"
  audit --skill sindesc
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing frontmatter 'description'"* ]]
}

@test "auditor: empty name reports only the name, not a phantom missing description" {
  make_skill soloname 'description: "Usar cuando solo falta el nombre del frontmatter."'
  sed -i 's/^name: soloname$/name:/' "$SK/soloname/SKILL.md"
  audit --skill soloname
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing frontmatter 'name'"* ]]
  [[ "$output" != *"missing frontmatter 'description'"* ]]
}

@test "auditor: SKILL.md of exactly 100 lines is OK, 150 is WARN, 151 is FAIL" {
  padded_skill l100 100
  audit --skill l100
  [ "$status" -eq 0 ]
  [[ "$output" == *"l100"*" OK "* ]]
  padded_skill l150 150
  audit --skill l150
  [ "$status" -eq 0 ]
  [[ "$output" == *"l150"*" WARN "*"> 100"* ]]
  padded_skill l151 151
  audit --skill l151
  [ "$status" -eq 1 ]
  [[ "$output" == *"l151"*" FAIL "*"> 150"* ]]
}

@test "auditor: skill without any file path reference warns but exits 0" {
  raw_skill sinruta "$(printf -- '---\nname: sinruta\ndescription: "Usar cuando no hay ninguna referencia a ficheros."\n---\n\n# Skill\n\nTexto largo sin ninguna ruta de fichero en todo el cuerpo.')"
  audit --skill sinruta
  [ "$status" -eq 0 ]
  [[ "$output" == *"sinruta"*" WARN "*"no file path reference"* ]]
}

@test "auditor: a FAIL is never downgraded to WARN by a later warning" {
  raw_skill falla "$(printf -- '---\nname:\ndescription: "Usar cuando falla y ademas no hay ruta alguna."\n---\n\n# Skill\n\nTexto largo sin ninguna ruta de fichero en todo el cuerpo.')"
  audit --skill falla
  [ "$status" -eq 1 ]
  [[ "$output" == *"falla"*" FAIL "* ]]
  [[ "$output" == *"no file path reference"* ]]
}

@test "auditor: empty consumes/produces in frontmatter fail (4 variants)" {
  local k
  for k in 'consumes: []' 'produces: []' 'consumes: ""' 'produces: ""'; do
    raw_skill vacio "$(printf -- '---\nname: vacio\ndescription: "Usar cuando se declara una lista vacia."\n%s\n---\n\n# Skill\n\nLee scripts/ejemplo.sh y mas contenido.' "$k")"
    audit --skill vacio
    [ "$status" -eq 1 ] || { echo "no fallo con: $k"; false; }
    [[ "$output" == *"${k%%:*} is empty"* ]]
  done
}

@test "auditor: empty savia.consumes/savia.produces strings fail" {
  local k
  for k in consumes produces; do
    raw_skill vacio "$(printf -- '---\nname: vacio\ndescription: "Usar cuando se declara una lista vacia."\nmetadata:\n  savia.%s: ""\n---\n\n# Skill\n\nLee scripts/ejemplo.sh y mas contenido.' "$k")"
    audit --skill vacio
    [ "$status" -eq 1 ]
    [[ "$output" == *"savia.$k is empty string"* ]]
  done
}

@test "auditor: non-empty consumes passes, and consumes in the body is not frontmatter" {
  raw_skill lleno "$(printf -- '---\nname: lleno\ndescription: "Usar cuando se declara una lista con datos."\nconsumes: [spec]\n---\n\n# Skill\n\nconsumes: []\nproduces: ""\nLee scripts/ejemplo.sh y mas contenido.')"
  audit --skill lleno
  [ "$status" -eq 0 ]
  [[ "$output" != *"is empty"* ]]
}

@test "auditor: consumes at file line 41 is read, at line 42 is ignored (cap of 40+1 lines)" {
  local pad
  pad="$(printf 'x%s: a\n' $(seq 1 37))"
  raw_skill l41 "$(printf -- '---\nname: l41\ndescription: "Usar cuando se prueba el limite del frontmatter."\n%s\nconsumes: []\n---\n\n# Skill\n\nLee scripts/ejemplo.sh y mas contenido.' "$pad")"
  [ "$(grep -n '^consumes' "$SK/l41/SKILL.md" | cut -d: -f1)" -eq 41 ]
  audit --skill l41
  [ "$status" -eq 1 ]
  raw_skill l42 "$(printf -- '---\nname: l42\ndescription: "Usar cuando se prueba el limite del frontmatter."\n%s\nxx: a\nconsumes: []\n---\n\n# Skill\n\nLee scripts/ejemplo.sh y mas contenido.' "$pad")"
  [ "$(grep -n '^consumes' "$SK/l42/SKILL.md" | cut -d: -f1)" -eq 42 ]
  audit --skill l42
  [ "$status" -eq 0 ]
}

@test "auditor: body of exactly 20 non-whitespace characters passes, 19 fails" {
  raw_skill b20 "$(printf -- '---\nname: b20\ndescription: "Usar cuando se prueba el cuerpo minimo."\n---\n\nabcdefghij abcde/fghi')"
  audit --skill b20
  [[ "$output" != *"body too short"* ]]
  raw_skill b19 "$(printf -- '---\nname: b19\ndescription: "Usar cuando se prueba el cuerpo minimo."\n---\n\nabcdefghij abcde/fgh')"
  audit --skill b19
  [ "$status" -eq 1 ]
  [[ "$output" == *"body too short"* ]]
}

@test "auditor: DOMAIN.md of 3 lines fails, 4 lines passes" {
  make_skill dom3 'description: "Usar cuando se prueba el dominio minimo."'
  printf 'a\nb\nc\n' > "$SK/dom3/DOMAIN.md"
  audit --skill dom3
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty or too short (3 lines, min 4)"* ]]
  printf 'a\nb\nc\nd\n' > "$SK/dom3/DOMAIN.md"
  audit --skill dom3
  [ "$status" -eq 0 ]
}

@test "auditor: a clean skill shows '-' as reason and the summary counts each state" {
  make_skill ok 'description: "Usar cuando todo esta correcto en la skill."'
  audit --skill ok
  [[ "$output" =~ ok[[:space:]]+OK[[:space:]]+-($|$'\n') ]]
  make_skill aviso 'description: "Usar cuando hay un aviso de longitud."' 110
  make_skill roto 'description: "Usar cuando esta roto."'
  mv "$SK/roto/DOMAIN.md" "$WORK/roto-domain.md"
  audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"PASS: 1 | WARN: 1 | FAIL: 1 | TOTAL: 3"* ]]
}

# ── SE-376 S03 grupo 7: mutantes del generador que sobrevivían ───────────────

@test "generator: manifest of two skills without name/maturity is valid JSON with fallbacks" {
  local d
  for d in alfa beta; do
    mkdir -p "$SK/$d"
    printf -- '---\ndescription: "Usar cuando falta el nombre en %s."\n---\n\n# Skill\n' "$d" > "$SK/$d/SKILL.md"
  done
  gen --apply --manifest
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))["skills"]
assert sorted(m) == ["alfa", "beta"], sorted(m)
assert all(v["maturity"] == "unknown" for v in m.values()), m
'  "$WORK/manifest.json"
  [ "$status" -eq 0 ]
}

@test "generator: --apply into a missing directory fails with exit 1 and writes nothing" {
  make_skill uno 'description: "Usar cuando el destino no existe."'
  mkdir -p "$WORK/fakeroot/scripts"
  cp "$REPO/$GENERATOR" "$WORK/fakeroot/scripts/skills-md-generate.sh"
  SKILLS_MD="$WORK/nodir/SKILLS.md" PROJECT_ROOT="$WORK" SKILLS_DIR="$SK" \
    run bash "$WORK/fakeroot/scripts/skills-md-generate.sh" --apply
  [ "$status" -eq 1 ]
  [ ! -e "$WORK/nodir" ]
}

@test "generator: unwritable manifest destination fails with exit 1 after SKILLS.md" {
  make_skill uno 'description: "Usar cuando el manifiesto no se puede escribir."'
  mkdir -p "$WORK/fakeroot/scripts"
  cp "$REPO/$GENERATOR" "$WORK/fakeroot/scripts/skills-md-generate.sh"
  PROJECT_ROOT="$WORK" SKILLS_DIR="$SK" SKILLS_MD="$WORK/SKILLS.md" SKILLS_MANIFEST="$WORK/nodir/m.json" \
    run bash "$WORK/fakeroot/scripts/skills-md-generate.sh" --apply --manifest
  [ "$status" -eq 1 ]
  [ ! -e "$WORK/nodir" ]
}
