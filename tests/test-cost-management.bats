#!/usr/bin/env bats
# Calibración SE-376 de la skill cost-management.
# Ref: docs/rules/domain/billing-model.md
# Ref: docs/rules/domain/cost-tracking.md
# Ref: .claude/skills/cost-management/SKILL.md
#
# La skill es prosa que ejecuta el agente: no hay script que registre horas,
# calcule el burn ni genere facturas. Lo único ejecutable es el validador de
# contrato scripts/test-cost-center.sh y la promesa de seguridad «los rates
# están git-ignorados», que depende del comportamiento real de .gitignore.

SCRIPT="scripts/test-cost-center.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  REPO_ROOT="$PWD"
  TMPDIR_T="$(mktemp -d)"
  # Repo git aislado con el .gitignore real: check-ignore sin tocar el checkout.
  GI_REPO="$TMPDIR_T/gi repo"
  mkdir -p "$GI_REPO"
  git -C "$GI_REPO" init -q
  cp "$REPO_ROOT/.gitignore" "$GI_REPO/.gitignore"
  # Árbol mínimo para ejecutar el validador de contrato fuera del checkout.
  FIX="$TMPDIR_T/fix tree"
  mkdir -p "$FIX/scripts" "$FIX/.opencode/commands" "$FIX/.opencode/skills/cost-management" "$FIX/docs/rules/domain"
  cp "$REPO_ROOT/$SCRIPT" "$FIX/scripts/"
  cp "$REPO_ROOT/.claude/commands/cost-center.md" "$FIX/.opencode/commands/"
  cp "$REPO_ROOT/.claude/skills/cost-management/SKILL.md" "$FIX/.opencode/skills/cost-management/"
  cp "$REPO_ROOT/docs/rules/domain/billing-model.md" "$REPO_ROOT/docs/rules/domain/cost-tracking.md" "$FIX/docs/rules/domain/"
}

teardown() {
  rm -rf "$TMPDIR_T"
}

ignored() { git -C "$GI_REPO" check-ignore -q "$1"; }

@test "target: validador de contrato existe y usa set -uo pipefail" {
  [ -f "$SCRIPT" ]
  run head -5 "$SCRIPT"
  [[ "$output" == *"set -uo pipefail"* ]]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "seguridad: el rate table global .flow-data/rates.json queda git-ignorado" {
  run git -C "$GI_REPO" check-ignore -v ".flow-data/rates.json"
  [ "$status" -eq 0 ]
}

@test "seguridad: overrides .rates.local.json ignorados en projects/ y en .flow-data/" {
  ignored "projects/sala-reservas/.rates.local.json"
  ignored ".flow-data/sala-reservas/.rates.local.json"
  # Proyecto de ejemplo publicado: el override de rates también debe quedar fuera.
  ignored "projects/proyecto-alpha/.rates.local.json"
}

@test "boundary: ledger, timesheets y budgets NO se ignoran (se versionan según billing-model)" {
  run git -C "$GI_REPO" check-ignore -q ".flow-data/ledger/sala-reservas.jsonl"
  [ "$status" -ne 0 ]
  run git -C "$GI_REPO" check-ignore -q ".flow-data/timesheets/@monica/2026-03.jsonl"
  [ "$status" -ne 0 ]
  run git -C "$GI_REPO" check-ignore -q ".flow-data/budgets/sala-reservas.json"
  [ "$status" -ne 0 ]
}

@test "boundary: invoices e informes en output/ quedan fuera del repo (no se versionan)" {
  ignored "output/invoices/acme-corp-2026-03.json"
  ignored "output/cost-report-2026-03.md"
}

@test "mutation: sin la regla de rates en .gitignore, rates.json deja de ignorarse (el test muerde)" {
  grep -v "rates" "$GI_REPO/.gitignore" > "$GI_REPO/.gitignore.new"
  mv "$GI_REPO/.gitignore.new" "$GI_REPO/.gitignore"
  run git -C "$GI_REPO" check-ignore -q ".flow-data/rates.json"
  [ "$status" -ne 0 ]
}

@test "contrato: el validador pasa completo sobre el estado real (exit 0, 0 failed)" {
  run bash "$FIX/scripts/test-cost-center.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 failed"* ]]
}

@test "negative: el validador falla (exit != 0) si el SKILL pierde el Flujo 5 de invoices" {
  sed -i 's/Flujo 5/Flujo cinco/' "$FIX/.opencode/skills/cost-management/SKILL.md"
  run bash "$FIX/scripts/test-cost-center.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Has Flow 5 (invoice)"* ]]
}

@test "negative: el validador falla si el comando no declara su tier de modelo" {
  sed -i '/^model_tier:/d' "$FIX/.opencode/commands/cost-center.md"
  run bash "$FIX/scripts/test-cost-center.sh"
  [ "$status" -ne 0 ]
}

@test "edge: SKILL ausente (empty tree) reporta error, no exit 0" {
  mv "$FIX/.opencode/skills/cost-management/SKILL.md" "$TMPDIR_T/SKILL.bak"
  run bash "$FIX/scripts/test-cost-center.sh"
  [ "$status" -gt 0 ]
  [[ "$output" == *"Skill file exists"* ]]
}

@test "regresión: billing-model no invierte el signo de CPI (CPI < 1.0 es sobrecoste)" {
  run grep -E "CPI > 1\.0, project over budget" docs/rules/domain/billing-model.md
  [ "$status" -ne 0 ]
  run grep -E "CPI < 1\.0" docs/rules/domain/billing-model.md
  [ "$status" -eq 0 ]
}

@test "regresión: SKILL y billing-model coinciden en la ruta del override de rates" {
  run grep -c "projects/{proj}/.rates.local.json\|projects/{project}/.rates.local.json" .claude/skills/cost-management/SKILL.md
  [ "$output" -ge 1 ]
  run grep -c "flow-data/{project}/.rates.local.json" .claude/skills/cost-management/SKILL.md
  [ "$output" -eq 0 ]
}

@test "boundary: ejemplo de forecast del SKILL es aritméticamente coherente (10.4% sobre BAC)" {
  eac=$(grep -oE "EAC = €[0-9,]+" .claude/skills/cost-management/SKILL.md | head -1 | tr -dc '0-9')
  bac=$(grep -oE "BAC = €[0-9,]+" .claude/skills/cost-management/SKILL.md | head -1 | tr -dc '0-9')
  [ -n "$eac" ] && [ -n "$bac" ]
  pct=$(LC_ALL=C awk -v e="$eac" -v b="$bac" 'BEGIN{printf "%.1f", (e-b)*100/b}')
  [ "$pct" = "10.4" ]
}
