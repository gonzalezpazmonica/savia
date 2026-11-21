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
