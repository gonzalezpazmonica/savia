#!/usr/bin/env bats
# tests/test-se-270-s1-skills-lint.bats
# SE-270 Slice 1 — BATS tests for scripts/skills-lint.sh
#
# Verifies: description length checks, trigger phrases, IO declaration,
# frontmatter validation, JSON/table output modes.

bats_require_minimum_version 1.5.0

SCRIPT="scripts/skills-lint.sh"
SKILLS_BASE=".opencode/skills"

setup() {
  TMPDIR="$(mktemp -d)"
  ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  # Create a temporary skills dir structure
  mkdir -p "$TMPDIR/skills"
}

teardown() {
  rm -rf "$TMPDIR"
}

make_skill() {
  local name="$1" desc="$2" has_consumes="${3:-false}" has_produces="${4:-false}"
  local dir="$TMPDIR/skills/$name"
  mkdir -p "$dir"
  local consumes_block=""
  local produces_block=""
  if $has_consumes; then consumes_block="consumes:\n  - report"; fi
  if $has_produces; then produces_block="produces:\n  - CONTEXT.md"; fi
  cat > "$dir/SKILL.md" <<SKILLEOF
---
name: $name
description: "$desc"
$([ -n "$consumes_block" ] && echo -e "$consumes_block")
$([ -n "$produces_block" ] && echo -e "$produces_block")
---

# $name

Test skill body content here for SE-270 lint validation.
SKILLEOF
  cat > "$dir/DOMAIN.md" <<DOMAINEOF
---
name: $name
---

Domain content for $name test skill.
DOMAINEOF
}

# ── Script existence ───────────────────────────────────────────────────────────

@test "SE-270-S1: skills-lint.sh exists" {
  [[ -f "$ROOT/$SCRIPT" ]]
}

@test "SE-270-S1: skills-lint.sh is executable" {
  [[ -x "$ROOT/$SCRIPT" ]]
}

@test "SE-270-S1: set -uo pipefail present" {
  run grep -c 'set -uo pipefail' "$ROOT/$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "SE-270-S1: bash -n syntax check passes" {
  run bash -n "$ROOT/$SCRIPT"
  [[ "$status" -eq 0 ]]
}

@test "SE-270-S1: SE-270 reference present" {
  run grep -c 'SE-270' "$ROOT/$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "SE-270-S1: --help flag works" {
  run bash "$ROOT/$SCRIPT" --help
  [[ "$status" -eq 0 ]]
}

# ── Description length checks ──────────────────────────────────────────────────

@test "SE-270-S1: WARN on description < 150 chars" {
  make_skill "short-desc" "Usar cuando se necesita ayuda. Frase corta." false false
  run bash "$ROOT/$SCRIPT"
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" =~ "too short" ]]
}

@test "SE-270-S1: OK on description 150-500 chars" {
  local desc="Usar cuando se necesita analizar el impacto de la IA en la organización, evaluando métricas de productividad, automatización de tareas repetitivas, y cambios en los roles del equipo."
  make_skill "ok-desc" "$desc" false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ ! "$output" =~ "too short" ]]
  [[ ! "$output" =~ "too long" ]]
}

@test "SE-270-S1: WARN on description > 500 chars" {
  local desc="Usar cuando se necesita un análisis muy detallado y exhaustivo de todos los componentes del sistema, incluyendo métricas de rendimiento, seguridad, escalabilidad, mantenibilidad, disponibilidad, latencia, throughput, consumo de recursos, optimización de costes, y alineación con los objetivos estratégicos de la organización a largo plazo considerando todos los stakeholders y sus necesidades específicas documentadas en los OKRs del trimestre actual y el roadmap del producto para el próximo año fiscal completo y el siguiente."
  make_skill "long-desc" "$desc" false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" =~ "too long" ]]
}

# ── Trigger phrase checks ─────────────────────────────────────────────────────

@test "SE-270-S1: WARN if no trigger phrase in description" {
  make_skill "no-trigger" "Esta skill hace cosas importantes para el sistema." false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" =~ "no trigger phrase" ]]
}

@test "SE-270-S1: OK if 'Usar cuando' trigger present" {
  make_skill "with-trigger" "Usar cuando se necesita auditar la seguridad del proyecto con pipeline Red Team." false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ ! "$output" =~ "no trigger phrase" ]]
}

@test "SE-270-S1: OK if 'Use when' trigger present" {
  make_skill "english-trigger" "Use when you need to scan dependencies for known vulnerabilities." false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ ! "$output" =~ "no trigger phrase" ]]
}

@test "SE-270-S1: OK if action verb trigger present" {
  make_skill "action-verb" "Detecta el Bus Factor por modulo en un repositorio git usando el algoritmo CST." false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ ! "$output" =~ "no trigger phrase" ]]
}

# ── Input/Output declaration checks ───────────────────────────────────────────

@test "SE-270-S1: WARN if no consumes/produces declared" {
  make_skill "no-io" "Usar cuando se necesita auditar la seguridad del proyecto." false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" =~ "no consumes/produces" ]]
}

@test "SE-270-S1: OK if consumes declared" {
  make_skill "has-consumes" "Usar cuando se necesita procesar datos del proyecto." true false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ ! "$output" =~ "no consumes/produces" ]]
}

@test "SE-270-S1: OK if produces declared" {
  make_skill "has-produces" "Usar cuando se necesita generar informes de rendimiento." false true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ ! "$output" =~ "no consumes/produces" ]]
}

@test "SE-270-S1: OK if both consumes and produces declared" {
  make_skill "has-both" "Usar cuando se necesita transformar especificaciones en código." true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ ! "$output" =~ "no consumes/produces" ]]
}

# ── Missing SKILL.md ──────────────────────────────────────────────────────────

@test "SE-270-S1: FAIL if SKILL.md missing" {
  local dir="$TMPDIR/skills/no-md"
  mkdir -p "$dir"
  cat > "$dir/DOMAIN.md" <<DOMAINEOF
---
name: no-md
---
domain
DOMAINEOF
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" =~ "SKILL.md missing" ]]
}

# ── Missing frontmatter fields ────────────────────────────────────────────────

@test "SE-270-S1: FAIL if frontmatter missing name" {
  local dir="$TMPDIR/skills/no-name"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" <<'EOF'
---
description: "Usar cuando se necesita algo."
---

# no-name
EOF
  cat > "$dir/DOMAIN.md" <<'DOMAINEOF'
---
name: no-name
---
domain
DOMAINEOF
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" =~ "missing frontmatter" ]]
}

@test "SE-270-S1: FAIL if frontmatter missing description" {
  local dir="$TMPDIR/skills/no-desc"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" <<'EOF'
---
name: no-desc
---

# no-desc
EOF
  cat > "$dir/DOMAIN.md" <<'DOMAINEOF'
---
name: no-desc
---
domain
DOMAINEOF
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" =~ "missing frontmatter" ]]
}

# ── JSON mode ─────────────────────────────────────────────────────────────────

@test "SE-270-S1: --json flag produces valid JSON" {
  make_skill "json-test" "Usar cuando se necesita validar la salida JSON del linter de skills en el workspace." true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" bash "$ROOT/$SCRIPT" --json 2>/dev/null | python3 -c "import json,sys; json.load(sys.stdin)"
  [[ "$?" -eq 0 ]]
}

# ── --skill filter ────────────────────────────────────────────────────────────

@test "SE-270-S1: --skill flag filters single skill" {
  make_skill "target-a" "Usar cuando se necesita auditar el target A del sistema de routing." true true
  make_skill "target-b" "Usar cuando se necesita auditar el target B del sistema de routing." false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT" --skill target-a
  [[ "$output" =~ "target-a" ]]
  [[ ! "$output" =~ "target-b" ]]
}

# ── Exit codes ────────────────────────────────────────────────────────────────

@test "SE-270-S1: exit 1 on WARN issues" {
  make_skill "warn-skill" "Corta." false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$status" -eq 1 ]]
}

@test "SE-270-S1: exit 1 on FAIL issues" {
  local dir="$TMPDIR/skills/fail-skill"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" <<'EOF'
---
name: fail-skill
---

# fail
EOF
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$status" -eq 1 ]]
}

@test "SE-270-S1: exit 0 when all OK" {
  make_skill "perfect" "Usar cuando se necesita validar y auditar la seguridad del proyecto mediante un pipeline completo que incluye análisis estático, dinámico y revisión de dependencias con reportes detallados." true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$status" -eq 0 ]]
}

# ── Skips _template ──────────────────────────────────────────────────────────

@test "SE-270-S1: skips _template directory" {
  local dir="$TMPDIR/skills/_template"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" <<'EOF'
---
name: _template
description: "TEMPLATE"
---

# template
EOF
  make_skill "real-skill" "Usar cuando se necesita auditar la seguridad del proyecto con pipeline Red Team Blue Team." true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ ! "$output" =~ "_template" ]]
}

# ── S03n: comportamiento discriminante ──────────────────────────────────────

# Descripción de longitud exacta N que empieza por un disparador.
desc_of_len() {
  local n="$1" base="Usar cuando "
  local pad=$(( n - ${#base} ))
  printf '%s%s' "$base" "$(printf 'x%.0s' $(seq 1 "$pad"))"
}

# Escribe una SKILL.md con frontmatter arbitrario (líneas extra en $3).
write_skill_md() {
  local name="$1" desc="$2" extra="${3:-}"
  mkdir -p "$TMPDIR/skills/$name"
  printf -- '---\nname: %s\ndescription: "%s"\n%b---\n' "$name" "$desc" "$extra" \
    > "$TMPDIR/skills/$name/SKILL.md"
}

@test "S03n: frontera inferior — 149 caracteres es too short y 150 no" {
  make_skill "len-149" "$(desc_of_len 149)" true true
  make_skill "len-150" "$(desc_of_len 150)" true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" == *"too short (149 chars"* ]]
  run grep -cE '^len-150 +OK' <<<"$output"
  [ "$output" = "1" ]
}

@test "S03n: frontera superior — 500 caracteres es OK y 501 too long" {
  make_skill "len-500" "$(desc_of_len 500)" true true
  make_skill "len-501" "$(desc_of_len 501)" true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" == *"too long (501 chars, max 500)"* ]]
  run grep -cE '^len-500 +OK' <<<"$output"
  [ "$output" = "1" ]
}

@test "S03n: el disparador no distingue mayúsculas" {
  make_skill "lower-trig" "$(desc_of_len 200 | sed 's/^Usar cuando/usar CUANDO/')" true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"no trigger phrase"* ]]
}

@test "S03n: sin disparador la skill queda WARN, no FAIL, y sale 1" {
  make_skill "no-trig" "$(desc_of_len 200 | sed 's/^Usar cuando/Texto plano/')" true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [ "$status" -eq 1 ]
  run grep -cE '^no-trig +WARN +no trigger phrase' <<<"$output"
  [ "$output" = "1" ]
}

@test "S03n: solo consumes avisa de produces y solo produces avisa de consumes" {
  make_skill "only-c" "$(desc_of_len 200)" true false
  make_skill "only-p" "$(desc_of_len 200)" false true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  local out="$output"
  run grep -cE '^only-c +WARN +no produces declared' <<<"$out"
  [ "$output" = "1" ]
  run grep -cE '^only-p +WARN +no consumes declared' <<<"$out"
  [ "$output" = "1" ]
}

@test "S03n: lectura dual SE-333 — metadata.savia.consumes/produces cuenta como declarado" {
  write_skill_md "meta-io" "$(desc_of_len 200)" 'metadata:\n  savia.consumes: spec\n  savia.produces: informe\n'
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -cE '^meta-io +OK' <<<"$output"
  [ "$output" = "1" ]
}

@test "S03n: consumes y produces vacíos no cuentan como declarados" {
  write_skill_md "empty-io" "$(desc_of_len 200)" 'consumes: []\nproduces: ""\n'
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no consumes/produces declared"* ]]
}

@test "S03n: sin SKILL.md la skill es FAIL (no WARN) y cuenta en el resumen" {
  mkdir -p "$TMPDIR/skills/hueca"
  make_skill "buena" "$(desc_of_len 200)" true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PASS: 1 | WARN: 0 | FAIL: 1 | TOTAL: 2"* ]]
  run grep -cE '^hueca +FAIL +SKILL.md missing' <<<"$output"
  [ "$output" = "1" ]
}

@test "S03n: resumen cuenta OK y WARN por separado y excluye _template" {
  make_skill "_template" "x" false false
  make_skill "a-ok" "$(desc_of_len 200)" true true
  make_skill "b-warn" "corta" true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT"
  [[ "$output" == *"PASS: 1 | WARN: 1 | FAIL: 0 | TOTAL: 2"* ]]
}

@test "S03n: --json devuelve estado y motivos por skill y stderr solo trae el resumen" {
  make_skill "j-ok" "$(desc_of_len 200)" true true
  make_skill "j-warn" "corta" true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run --separate-stderr bash "$ROOT/$SCRIPT" --json
  [ "$status" -eq 1 ]
  [ "$stderr" = "PASS: 1 | WARN: 1 | FAIL: 0 | TOTAL: 2" ]
  python3 -c '
import json,sys
d={r["skill"]:r for r in json.loads(sys.argv[1])}
assert d["j-ok"]["status"]=="OK" and d["j-ok"]["reasons"]=="-", d
assert d["j-warn"]["status"]=="WARN" and "too short (5 chars" in d["j-warn"]["reasons"], d
' "$output"
}

@test "S03n: --skill con skill inexistente falla con exit 1 y mensaje" {
  make_skill "existe" "$(desc_of_len 200)" true true
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT" --skill no-existe
  [ "$status" -eq 1 ]
  [[ "$output" == *"skill 'no-existe' not found"* ]]
}

@test "S03n: --skill filtra también el resumen y el código de salida" {
  make_skill "sana" "$(desc_of_len 200)" true true
  make_skill "rota" "corta" false false
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT" --skill sana
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: 1 | WARN: 0 | FAIL: 0 | TOTAL: 1"* ]]
}

@test "S03n: directorio de skills inexistente da error y exit 1 (fail-closed)" {
  SAVIA_SKILLS_DIR="$TMPDIR/no-hay" run bash "$ROOT/$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: failed to parse skills"* ]]
}

@test "S03n: flag desconocido da exit 1" {
  SAVIA_SKILLS_DIR="$TMPDIR/skills" run bash "$ROOT/$SCRIPT" --nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown flag: --nope"* ]]
}
