#!/usr/bin/env bats
# tests/test-se-261-health-v2.bats — Tests for workspace-health.sh v2 (SE-261)

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/workspace-health.sh"

setup() {
  [[ -x "$SCRIPT" ]] || skip "workspace-health.sh missing"
}

@test "T01: v1 output unchanged without --v2 flag" {
  run bash "$SCRIPT" --json
  [[ "$status" -eq 0 ]]
  [[ ! "$output" =~ "blast_radius" ]]
  [[ ! "$output" =~ "code_ownership" ]]
  [[ ! "$output" =~ "dead_code" ]]
  echo "$output" | grep -q '"skill_completeness"'
  echo "$output" | grep -q '"overall"'
}

@test "T02: v2 flag adds extended dimensions to JSON" {
  run bash "$SCRIPT" --json --v2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"version": 2'
  echo "$output" | grep -q '"blast_radius"'
  echo "$output" | grep -q '"code_ownership"'
  echo "$output" | grep -q '"dead_code"'
}

@test "T03: v2 dimensions have scores and grades" {
  run bash "$SCRIPT" --json --v2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"blast_radius".*"score"'
  echo "$output" | grep -q '"code_ownership".*"grade"'
  echo "$output" | grep -q '"dead_code".*"score"'
}

@test "T04: v2 summary mode shows extended header" {
  run bash "$SCRIPT" --summary --v2
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "v2" ]]
  [[ "$output" =~ "Blast radius" ]]
  [[ "$output" =~ "Code ownership" ]]
  [[ "$output" =~ "Dead code" ]]
}

@test "T05: v1 summary has original header" {
  run bash "$SCRIPT" --summary
  [[ "$status" -eq 0 ]]
  [[ ! "$output" =~ "v2" ]]
  [[ ! "$output" =~ "Blast radius" ]]
}

@test "T06: ci mode works with v2" {
  skip "ci mode requires security-scan.sh which is slow"
}

@test "T07: ci mode works without v2" {
  skip "ci mode requires security-scan.sh which is slow"
}

@test "T08: overall score is between 0 and 100" {
  run bash "$SCRIPT" --json --v2
  score=$(echo "$output" | grep -oE '"score": [0-9]+' | head -1 | grep -oE '[0-9]+')
  [[ -n "$score" ]]
  [[ "$score" -ge 0 ]]
  [[ "$score" -le 100 ]]
}

@test "T09: all v2 grades are valid letters" {
  run bash "$SCRIPT" --json --v2
  grades=$(echo "$output" | grep -oE '"grade": "[A-F]"' | grep -oE '[A-F]')
  [[ -n "$grades" ]]
  while IFS= read -r g; do
    [[ "$g" =~ ^[A-F]$ ]]
  done <<< "$grades"
}

@test "T10: dead_code dimension includes function counts" {
  run bash "$SCRIPT" --json --v2
  echo "$output" | grep -q '"dead_functions"'
  echo "$output" | grep -q '"total_functions"'
}

# ── S03k: pruebas de comportamiento sobre un árbol sintético ──
# El script calcula ROOT desde su propia ubicación: se copia a un árbol falso
# con stubs de security-scan/vuln-scan/blast-radius para que sea rápido y exacto.

mk_tree() {
  T="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$T/scripts" "$T/.opencode/skills" "$T/.opencode/commands" "$T/.opencode/hooks" "$T/tests/hooks" "$T/.github/workflows"
  cp "$SCRIPT" "$T/scripts/workspace-health.sh"
  printf '#!/usr/bin/env bash\necho OK\n' > "$T/scripts/security-scan.sh"
  printf '#!/usr/bin/env bash\necho OK\n' > "$T/scripts/vuln-scan.sh"
  W="$T/scripts/workspace-health.sh"
}

dim() { # dim <json> <dimension> <field>
  printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['dimensions']['$2']['$3'])"
}

overall() { # overall <json>
  printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin)['overall'];print(d['score'],d['grade'])"
}

@test "S03k health: skill_completeness = porcentaje de skills con SKILL.md" {
  mk_tree
  for s in a b c d; do mkdir -p "$T/.opencode/skills/$s"; done
  touch "$T/.opencode/skills/a/SKILL.md" "$T/.opencode/skills/b/SKILL.md" "$T/.opencode/skills/c/SKILL.md"
  run bash "$W" --json
  [ "$status" -eq 0 ]
  [ "$(dim "$output" skill_completeness score)" = "75" ]
  [ "$(dim "$output" skill_completeness detail)" = "3/4 skills have SKILL.md" ]
}

@test "S03k health: command_completeness solo cuenta frontmatter en la primera línea" {
  mk_tree
  printf -- '---\nname: x\n---\n' > "$T/.opencode/commands/ok.md"
  printf 'sin frontmatter\n---\n' > "$T/.opencode/commands/bad.md"
  run bash "$W" --json
  [ "$status" -eq 0 ]
  [ "$(dim "$output" command_completeness score)" = "50" ]
  [ "$(dim "$output" command_completeness detail)" = "1/2 commands have frontmatter" ]
}

@test "S03k health: maturity pondera stable=3 beta=2 alpha=1 sobre 3*total" {
  mk_tree
  for s in s1 s2 s3; do mkdir -p "$T/.opencode/skills/$s"; done
  printf -- '---\nmaturity: stable\n---\n' > "$T/.opencode/skills/s1/SKILL.md"
  printf -- '---\nsavia.maturity: beta\n---\n' > "$T/.opencode/skills/s2/SKILL.md"
  printf -- '---\n  maturity: alpha\n---\n' > "$T/.opencode/skills/s3/SKILL.md"
  run bash "$W" --json
  [ "$(dim "$output" maturity stable)" = "1" ]
  [ "$(dim "$output" maturity beta)" = "1" ]
  [ "$(dim "$output" maturity alpha)" = "1" ]
  # seis puntos de nueve posibles: 66 por división entera
  [ "$(dim "$output" maturity score)" = "66" ]
}

@test "S03k health: test_coverage cuenta hooks con un test tests/hooks/test-<nombre>*.bats" {
  mk_tree
  for h in h1 h2 h3 h4; do touch "$T/.opencode/hooks/$h.sh"; done
  touch "$T/tests/hooks/test-h1.bats" "$T/tests/hooks/test-h2-extra.bats"
  run bash "$W" --json
  [ "$(dim "$output" test_coverage tested)" = "2" ]
  [ "$(dim "$output" test_coverage total)" = "4" ]
  [ "$(dim "$output" test_coverage score)" = "50" ]
}

@test "S03k health: security es máximo si los dos escáneres pasan" {
  mk_tree
  run bash "$W" --json
  [ "$(dim "$output" security score)" = "100" ]
  [ "$(dim "$output" security findings)" = "0" ]
  [ "$(dim "$output" security vulns)" = "0" ]
}

@test "S03k health: FAIL en security-scan baja security a 50 y marca findings" {
  mk_tree
  printf '#!/usr/bin/env bash\necho "FAIL: algo"\n' > "$T/scripts/security-scan.sh"
  run bash "$W" --json
  [ "$(dim "$output" security score)" = "50" ]
  [ "$(dim "$output" security findings)" = "1" ]
  [ "$(dim "$output" security vulns)" = "0" ]
}

@test "S03k health: FAIL en vuln-scan baja security a 50 y marca vulns" {
  mk_tree
  printf '#!/usr/bin/env bash\necho "FAIL: cve"\n' > "$T/scripts/vuln-scan.sh"
  run bash "$W" --json
  [ "$(dim "$output" security score)" = "50" ]
  [ "$(dim "$output" security findings)" = "0" ]
  [ "$(dim "$output" security vulns)" = "1" ]
}

@test "S03k health: documentation cuenta los 7 ficheros requeridos presentes" {
  mk_tree
  touch "$T/LICENSE" "$T/README.md" "$T/CHANGELOG.md"
  run bash "$W" --json
  [ "$(dim "$output" documentation present)" = "3" ]
  [ "$(dim "$output" documentation required)" = "7" ]
  [ "$(dim "$output" documentation score)" = "42" ]
}

@test "S03k health: overall v1 con solo security al máximo vale 20 (su peso) y grado F" {
  mk_tree
  run bash "$W" --json
  [ "$(overall "$output")" = "20 F" ]
}

@test "S03k health: overall v1 con todo al máximo es 100 y grado A" {
  mk_tree
  mkdir -p "$T/.opencode/skills/a" "$T/docs"
  printf -- '---\nmaturity: stable\n---\n' > "$T/.opencode/skills/a/SKILL.md"
  printf -- '---\nx: 1\n---\n' > "$T/.opencode/commands/c.md"
  touch "$T/.opencode/hooks/h.sh" "$T/tests/hooks/test-h.bats"
  for d in LICENSE README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md docs/QUICK-START.md docs/ROADMAP.md; do touch "$T/$d"; done
  run bash "$W" --json
  [ "$(overall "$output")" = "100 A" ]
}

@test "S03k health: overall v1 pondera skills (peso 20) y docs (peso 10)" {
  mk_tree
  mkdir -p "$T/.opencode/skills/a"
  touch "$T/.opencode/skills/a/SKILL.md"
  run bash "$W" --json
  # skills 20 + security 20 = 40
  [ "$(overall "$output")" = "40 F" ]
  touch "$T/LICENSE" "$T/README.md" "$T/CHANGELOG.md" "$T/CONTRIBUTING.md" "$T/SECURITY.md"
  run bash "$W" --json
  # docs 5 de 7 = 71, aporta 7 puntos con peso 10
  [ "$(overall "$output")" = "47 F" ]
}

@test "S03k health: --ci falla con exit 1 si overall < 60" {
  mk_tree
  run bash "$W" --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: Health score below 60%"* ]]
  [[ "$output" == *"Workspace Health: 20% (F)"* ]]
}

@test "S03k health: --ci pasa con exit 0 si overall >= 60" {
  mk_tree
  mkdir -p "$T/.opencode/skills/a"
  printf -- '---\nmaturity: stable\n---\n' > "$T/.opencode/skills/a/SKILL.md"
  printf -- '---\nx: 1\n---\n' > "$T/.opencode/commands/c.md"
  touch "$T/.opencode/hooks/h.sh" "$T/tests/hooks/test-h.bats"
  run bash "$W" --ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Health score"* ]]
}

@test "S03k health: sin skills ni comandos no divide por cero" {
  mk_tree
  run bash "$W" --json
  [ "$status" -eq 0 ]
  [ "$(dim "$output" skill_completeness score)" = "0" ]
  [ "$(dim "$output" command_completeness score)" = "0" ]
}

@test "S03k health: grade respeta los cortes 90/80/70/60" {
  mk_tree
  run bash -c "source <(sed -n '/^grade()/,/^}/p' '$W'); for n in 100 90 89 80 79 70 69 60 59 0; do printf '%s ' \"\$(grade \$n)\"; done"
  [ "$output" = "A A B B C C D D F F " ]
}

@test "S03k health: sin blast-radius.sh v2 avisa y deja el score por defecto 50" {
  mk_tree
  run bash "$W" --json --v2
  [ "$status" -eq 0 ]
  [ "$(dim "$output" blast_radius score)" = "50" ]
  [[ "$output" == *"blast-radius.sh not found"* ]]
}

@test "S03k health: blast score = 100 - mayor risk_score y lista ficheros con impacto" {
  mk_tree
  touch "$T/scripts/a.sh" "$T/scripts/b.sh"
  cat > "$T/scripts/blast-radius.sh" <<'EOS'
#!/usr/bin/env bash
case "$*" in
  *scripts/a.sh*) echo '{"risk_score": 30, "total_impacted": 2}' ;;
  *scripts/b.sh*) echo '{"risk_score": 10, "total_impacted": 0}' ;;
  *) echo '{"risk_score": 0, "total_impacted": 0}' ;;
esac
EOS
  chmod +x "$T/scripts/blast-radius.sh"
  run bash "$W" --json --v2
  [ "$(dim "$output" blast_radius score)" = "70" ]
  [[ "$output" == *'"top_fragile_files": "scripts/a.sh"'* ]]
}

@test "S03k health: blast score no baja de 0 con risk_score mayor que 100" {
  mk_tree
  printf '#!/usr/bin/env bash\necho "{\\"risk_score\\": 250, \\"total_impacted\\": 1}"\n' > "$T/scripts/blast-radius.sh"
  chmod +x "$T/scripts/blast-radius.sh"
  run bash "$W" --json --v2
  [ "$(dim "$output" blast_radius score)" = "0" ]
}

@test "S03k health: dead_code distingue funciones usadas por otro script de las muertas" {
  mk_tree
  # el script copiado define sus propias funciones (grade, pct, count_glob)
  # que nadie más referencia: son las muertas de base
  run bash "$W" --json --v2
  base_dead="$(dim "$output" dead_code dead_functions)"
  base_total="$(dim "$output" dead_code total_functions)"
  cat > "$T/scripts/lib.sh" <<'EOS'
used_fn() { echo 1; }
dead_fn() { echo 2; }
EOS
  printf '#!/usr/bin/env bash\nused_fn\n' > "$T/scripts/caller.sh"
  printf '#!/usr/bin/env bash\nused_fn\n' > "$T/scripts/caller2.sh"
  run bash "$W" --json --v2
  [ "$(dim "$output" dead_code total_functions)" = "$((base_total + 2))" ]
  [ "$(dim "$output" dead_code dead_functions)" = "$((base_dead + 1))" ]
}

@test "S03k health: dead_code score = 100 menos el porcentaje de muertas" {
  mk_tree
  run bash "$W" --json --v2
  dead="$(dim "$output" dead_code dead_functions)"
  total="$(dim "$output" dead_code total_functions)"
  [ "$total" -gt 0 ]
  [ "$(dim "$output" dead_code score)" = "$((100 - dead * 100 / total))" ]
}

@test "S03k health: v2 --ci imprime línea Blast/Ownership/DeadCode" {
  mk_tree
  run bash "$W" --ci --v2
  [[ "$output" == *"Blast:"*"Ownership:"*"DeadCode:"* ]]
}

@test "S03k health: v1 --ci no imprime línea v2" {
  mk_tree
  run bash "$W" --ci
  [[ "$output" != *"Ownership:"* ]]
}

@test "S03k health: ownership 0 y sin warning en árbol git de un solo autor" {
  mk_tree
  git -C "$T" init -q
  git -C "$T" -c user.email=a@a -c user.name=A add -A
  git -C "$T" -c user.email=a@a -c user.name=A commit -qm x
  run bash "$W" --json --v2
  [ "$(dim "$output" code_ownership score)" = "0" ]
  [[ "$output" != *"no git repo"* ]]
}

@test "S03k health: ownership sube con ficheros tocados por 2 autores" {
  mk_tree
  git -C "$T" init -q
  echo 1 > "$T/f.txt"
  git -C "$T" add -A
  git -C "$T" -c user.email=a@a -c user.name=A commit -qm x
  echo 2 >> "$T/f.txt"
  git -C "$T" -c user.email=b@b -c user.name=B commit -qam y
  run bash "$W" --json --v2
  [ "$(dim "$output" code_ownership score)" -gt 0 ]
}

@test "S03k health: fuera de un repo git, ownership avisa" {
  mk_tree
  GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" run bash "$W" --json --v2
  [[ "$output" == *"no git repo, cannot measure"* ]]
}

@test "S03k health: summary v2 incluye Top fragile none y recuento de funciones" {
  mk_tree
  run bash "$W" --summary --v2
  [[ "$output" == *"Top fragile: none"* ]]
  [[ "$output" == *"Dead functions:"* ]]
}

@test "S03k health: --ci falla justo por debajo de 60 (55) y pasa en el corte" {
  mk_tree
  mkdir -p "$T/.opencode/skills/a"
  touch "$T/.opencode/skills/a/SKILL.md"
  printf -- '---\nx: 1\n---\n' > "$T/.opencode/commands/c.md"
  # skills 20 + commands 15 + security 20 = 55
  run bash "$W" --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Workspace Health: 55% (F)"* ]]
}

@test "S03k health: blast lista como máximo 3 ficheros frágiles" {
  mk_tree
  for n in 1 2 3 4 5; do touch "$T/scripts/f$n.sh"; done
  printf '#!/usr/bin/env bash\necho "{\\"risk_score\\": 5, \\"total_impacted\\": 1}"\n' > "$T/scripts/blast-radius.sh"
  chmod +x "$T/scripts/blast-radius.sh"
  run bash "$W" --json --v2
  frag="$(printf '%s' "$output" | python3 -c "import sys,json;print(json.load(sys.stdin)['dimensions']['blast_radius']['top_fragile_files'])")"
  [ "$(wc -w <<< "$frag")" -eq 3 ]
}

@test "S03k health: v2 declara version 2 y v1 no declara version" {
  mk_tree
  run bash "$W" --json --v2
  [ "$(printf '%s' "$output" | python3 -c "import sys,json;print(json.load(sys.stdin)['version'])")" = "2" ]
  run bash "$W" --json
  [[ "$output" != *'"version"'* ]]
}

@test "S03k health: overall v2 pondera ownership con peso 10" {
  mk_tree
  git -C "$T" init -q
  git -C "$T" add -A
  git -C "$T" -c user.email=a@a -c user.name=A commit -qm uno
  for f in $(git -C "$T" ls-files); do echo "# x" >> "$T/$f"; done
  git -C "$T" -c user.email=b@b -c user.name=B commit -qam dos
  run bash "$W" --json --v2
  [ "$(dim "$output" code_ownership score)" = "100" ]
  # security 15 + blast por defecto 50*10 + ownership 100*10, dead 0 => 30
  [ "$(overall "$output")" = "30 F" ]
}
