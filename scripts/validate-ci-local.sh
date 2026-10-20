#!/usr/bin/env bash
# ── validate-ci-local.sh — Parallel CI validation ────────────────────────
# Runs checks in parallel for speed (~5x faster on Windows).
# Usage: bash scripts/validate-ci-local.sh [--quick] [--clean-state] | --clean-state-only [--repo DIR]
# SE-407 S1: incluye la frescura de los artefactos generados (bloquea); --quick omite solo sam.py check.
# SE-407 S2: --clean-state añade el estado limpio al cerrar (advisory: solo PASS/WARN).
set -uo pipefail

# Ningún test debe heredar GIT_DIR/GIT_WORK_TREE/... del agente: operarían sobre el repo real.
source "$(dirname "${BASH_SOURCE[0]}")/lib/mock-env.sh"; git_env_clean

QUICK_MODE=false; CLEAN_STATE=false; CLEAN_ONLY=false
CLEAN_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) QUICK_MODE=true ;;
    --clean-state) CLEAN_STATE=true ;;
    --clean-state-only) CLEAN_ONLY=true ;;
    --repo) CLEAN_REPO="${2:-}"; shift ;;
  esac
  shift
done

# ── SE-407 S2: estado limpio al cerrar (advisory, nunca bloquea) ──────────
# Tres dimensiones en líneas PASS/WARN: checkout principal sin cambios fuera de output/;
# worktrees agent/* retirables (sin cambios y con su contenido ya en main, también tras
# squash por patch-id); commits en main posteriores a la última actualización del traspaso
# privado (~/.savia/session-handoff.md o $SAVIA_HANDOFF_FILE; nunca dentro del repo).
clean_state_report() {
  local REPO="$1" MAIN_REF PRIMARY DIRTY RETIRABLE path branch base files merged pid HANDOFF LAST AFTER
  if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: $REPO no es un repositorio git" >&2
    return 2
  fi
  MAIN_REF=origin/main
  git -C "$REPO" rev-parse -q --verify "$MAIN_REF" >/dev/null || MAIN_REF=main

  # 1. Checkout principal: el primer worktree de la lista es el principal.
  PRIMARY=$(git -C "$REPO" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
  DIRTY=$(git -C "$PRIMARY" status --porcelain --untracked-files=all 2>/dev/null | awk '{p=substr($0, 4)} p !~ /^output\// {n++} END {print n+0}')
  if [[ "$DIRTY" -eq 0 ]]; then
    echo "PASS Checkout principal limpio"
  else
    echo "WARN Checkout principal: $DIRTY cambios fuera de output/ ($PRIMARY)"
  fi

  # 2. Worktrees agent/* retirables.
  RETIRABLE=0
  while IFS=$'\t' read -r path branch; do
    [[ "$branch" == agent/* ]] || continue
    [[ -z "$(git -C "$path" status --porcelain 2>/dev/null)" ]] || continue
    base=$(git -C "$REPO" merge-base "$MAIN_REF" "$branch" 2>/dev/null) || continue
    files=$(git -C "$REPO" diff --name-only "$base" "$branch")
    merged=false
    if [[ -z "$files" ]] || git -C "$REPO" diff --quiet "$MAIN_REF" "$branch" -- $files; then
      merged=true
    else
      # Squash merge seguido de otros cambios en los mismos ficheros: el diff completo de la
      # rama coincide (patch-id) con un commit de main posterior a la base (últimos 500).
      pid=$(git -C "$REPO" diff "$base" "$branch" | git patch-id --stable | cut -d' ' -f1)
      if [[ -n "$pid" ]] && git -C "$REPO" log -p -500 --format='commit %H' "$base..$MAIN_REF" \
          | git patch-id --stable | cut -d' ' -f1 | grep -qx "$pid"; then
        merged=true
      fi
    fi
    if $merged; then
      echo "WARN Worktree retirable: $branch ($path): su contenido ya está en main y no tiene cambios"
      RETIRABLE=$((RETIRABLE + 1))
    fi
  done < <(git -C "$REPO" worktree list --porcelain | awk '
    /^worktree /{p=substr($0, 10)} /^branch refs\/heads\//{b=substr($0, 19); print p "\t" b}')
  [[ "$RETIRABLE" -eq 0 ]] && echo "PASS Worktrees agent/*: ninguno retirable"

  # 3. Traspaso de sesión: privado, fuera del repo público; nunca se versiona.
  HANDOFF="${SAVIA_HANDOFF_FILE:-$HOME/.savia/session-handoff.md}"
  if git -C "$REPO" cat-file -e "$MAIN_REF:docs/propuestas/session-handoff.md" 2>/dev/null; then
    echo "WARN Traspaso: docs/propuestas/session-handoff.md está versionado en $MAIN_REF; es estado interno y debe salir del repo público"
  fi
  if [[ ! -f "$HANDOFF" ]]; then
    echo "WARN Traspaso: no existe el traspaso privado ($HANDOFF)"
  else
    LAST=$(stat -c %Y "$HANDOFF" 2>/dev/null || stat -f %m "$HANDOFF")
    AFTER=$(git -C "$REPO" rev-list --count --since="@$LAST" "$MAIN_REF")
    if [[ "$AFTER" -gt 0 ]]; then
      echo "WARN Traspaso: $AFTER commit(s) en main desde la última actualización del traspaso privado"
    else
      echo "PASS Traspaso al día"
    fi
  fi
}

if $CLEAN_ONLY; then
  clean_state_report "$CLEAN_REPO"
  exit $?
fi
TMPDIR_CI=$(mktemp -d 2>/dev/null || echo "/tmp/ci-$$"); mkdir -p "$TMPDIR_CI"
trap 'rm -rf "$TMPDIR_CI"' EXIT

echo ""
echo "--- Validacion CI Local — pm-workspace (parallel) ---"
echo ""

# ── Check functions (each writes result to tmpfile) ──────────────────────
check_coherence() {
  local out="$TMPDIR_CI/9-coherence"
  local g
  g=$(bash "$(dirname "${BASH_SOURCE[0]}")/coherence-gates.sh" 2>&1)
  if echo "$g" | grep -q "WARN coherence"; then
    echo "WARN Coherence: $(echo "$g" | grep -c WARN) gate(s) en advisory" > "$out"
  else
    echo "PASS Coherence: negative-tests, chaos, entropy, debt-budget" > "$out"
  fi
}

check_branch() {
  local out="$TMPDIR_CI/0-branch"
  local b; b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$b" == "main" || "$b" == "master" ]]; then
    echo "FAIL Branch: on $b" > "$out"
  else echo "PASS Branch: $b" > "$out"; fi
}

check_file_sizes() {
  local out="$TMPDIR_CI/1-sizes" fails=0 checked=0
  for pattern in ".opencode/commands/*.md" ".opencode/skills/*/SKILL.md" ".opencode/agents/*.md"; do
    for file in $pattern; do
      [ -f "$file" ] || continue; checked=$((checked+1))
      local lines; lines=$(wc -l < "$file")
      [ "$lines" -gt 150 ] && { echo "FAIL Size: $file ($lines lines)" >> "$out.fails"; fails=$((fails+1)); }
    done
  done
  if [ "$fails" -gt 0 ]; then cat "$out.fails" > "$out"
  else echo "PASS Sizes: $checked files OK" > "$out"; fi
  rm -f "$out.fails"
}

check_frontmatter() {
  local out="$TMPDIR_CI/2-frontmatter" fails=0 legacy=0
  for file in .opencode/commands/*.md; do
    [ -f "$file" ] || continue
    if head -1 "$file" | grep -q "^---$"; then
      grep -q "^name:" "$file" || { echo "FAIL FM: $file missing name" >> "$out.f"; fails=$((fails+1)); }
      grep -q "^description:" "$file" || { echo "FAIL FM: $file missing description" >> "$out.f"; fails=$((fails+1)); }
    else legacy=$((legacy+1)); fi
  done
  if [ "$fails" -gt 0 ]; then cat "$out.f" > "$out"
  else echo "PASS Frontmatter OK ($legacy legacy)" > "$out"; fi
  rm -f "$out.f"
}

check_settings_json() {
  local out="$TMPDIR_CI/3-settings"
  if [ -f ".claude/settings.json" ]; then
    if python3 -c "import json; json.load(open('.claude/settings.json'))" 2>/dev/null; then
      echo "PASS settings.json valid" > "$out"
    else echo "FAIL settings.json invalid JSON" > "$out"; fi
  else echo "WARN settings.json not found" > "$out"; fi
}

check_changelog() {
  local out="$TMPDIR_CI/4-changelog"
  if [ ! -f "CHANGELOG.md" ]; then echo "FAIL CHANGELOG.md not found" > "$out"; return; fi
  local m; m="<""<""<""<""<""<""<"
  if grep -qE "^${m}" CHANGELOG.md; then echo "FAIL CHANGELOG: merge conflict markers" > "$out"; return; fi
  local vers; vers=$(grep -oP '(?<=^## \[)[0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md)
  local dups; dups=$(echo "$vers" | sort | uniq -d)
  if [ -n "$dups" ]; then echo "FAIL CHANGELOG: duplicate versions: $dups" > "$out"; return; fi
  local count; count=$(echo "$vers" | wc -l)
  echo "PASS CHANGELOG OK ($count versions)" > "$out"
}

check_required_files() {
  local out="$TMPDIR_CI/5-required" fails=0
  for f in LICENSE README.md CHANGELOG.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md; do
    [ -f "$f" ] || { echo "FAIL Missing: $f" >> "$out.f"; fails=$((fails+1)); }
  done
  if [ "$fails" -gt 0 ]; then cat "$out.f" > "$out"
  else echo "PASS Required files present" > "$out"; fi
  rm -f "$out.f"
}

check_secrets() {
  local out="$TMPDIR_CI/6-secrets"
  if grep -rn --include="*.md" --include="*.sh" --include="*.json" --include="*.yml" \
    -E '[a-z0-9]{52}' --exclude-dir=".git" --exclude-dir="node_modules" \
    --exclude-dir="projects" \
    --exclude-dir="output" \
    . 2>/dev/null | grep -v "mock\|example\|placeholder\|test-data\|\"hash\"\|sha256\|Hash:" > /dev/null 2>&1; then
    echo "WARN Possible secret pattern detected" > "$out"
  else echo "PASS No secrets detected" > "$out"; fi
}

# ── SE-407 S1: artefactos generados al día ───────────────────────────────
# Usa los --check de cada generador (no los reimplementa). Cada línea:
# artefacto|comprobación|cómo regenerarlo. SAVIA_FRESH_CHECKS_FOR_TESTS solo para tests.
FRESH_CHECKS_DEFAULT='rule-manifest.json|bash scripts/rule-manifest-generate.sh --check|bash scripts/rule-manifest-generate.sh
settings-hooks pin|bash scripts/contract-pin.sh check settings-hooks|revisar el cambio de .claude/settings.json y, si es intencionado, bash scripts/contract-pin.sh pin settings-hooks --path .claude/settings.json
.scm/sam.json|python3 scripts/sam.py check|python3 scripts/generate-capability-map.py, commit y python3 scripts/sam.py generate
docs/propuestas/INDEX.md|bash scripts/propuestas-index-gen.sh --check|bash scripts/propuestas-index-gen.sh
planning-state.json|bash scripts/roadmap.sh validate|corregir planning-state.json/LOG.md según el error y bash scripts/roadmap.sh render'
REPO_ROOT_CI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

check_generated_fresh() {
  local i=0 name check regen
  while IFS='|' read -r name check regen; do
    [[ -z "${name// /}" ]] && continue
    # --quick puede omitir sam.py check (el más lento), nunca los otros.
    if $QUICK_MODE && [[ "$check" == *"sam.py check"* ]]; then continue; fi
    i=$((i+1))
    ( if (cd "$REPO_ROOT_CI" && bash -c "$check") >/dev/null 2>&1; then
        echo "PASS Generado al día: $name"
      else
        echo "FAIL Generado desfasado: $name → regenerar: $regen"
      fi ) > "$TMPDIR_CI/8-fresh-$i" &
  done <<< "${SAVIA_FRESH_CHECKS_FOR_TESTS:-$FRESH_CHECKS_DEFAULT}"
  wait
}

# ── SE-425: lockfiles versionados coherentes con su package.json (aviso) ──
# Comparación estática de dependencias declaradas (sin red): `npm ci` en CI fallaría igual.
LOCK_DIRS_DEFAULT='scripts projects/savia-vaults'
check_lockfiles() {
  local i=0 dir
  for dir in ${SAVIA_LOCK_DIRS_FOR_TESTS:-$LOCK_DIRS_DEFAULT}; do
    [[ "$dir" = /* ]] || dir="$REPO_ROOT_CI/$dir"
    [[ -f "$dir/package.json" ]] || continue
    i=$((i+1))
    local rel="${dir#"$REPO_ROOT_CI"/}"
    if [[ ! -f "$dir/package-lock.json" ]]; then
      echo "WARN Lockfile ausente: $rel/package-lock.json → npm install --package-lock-only --prefix $rel" > "$TMPDIR_CI/8-lock-$i"
    elif python3 - "$dir" <<'PY' 2>/dev/null
import json, sys
d = sys.argv[1]
pkg = json.load(open(f"{d}/package.json")); root = json.load(open(f"{d}/package-lock.json"))["packages"][""]
keys = ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies")
sys.exit(0 if all(pkg.get(k, {}) == root.get(k, {}) for k in keys) else 1)
PY
    then
      echo "PASS Lockfile al día: $rel" > "$TMPDIR_CI/8-lock-$i"
    else
      echo "WARN Lockfile desfasado: $rel/package.json cambió sin su lock → npm install --package-lock-only --prefix $rel" > "$TMPDIR_CI/8-lock-$i"
    fi
  done
}

# ── SE-407 S2: estado limpio al cerrar (advisory) ─────────────────────────
check_clean_state() {
  clean_state_report "$REPO_ROOT_CI" 2>&1 | grep -E '^(PASS|WARN) ' > "$TMPDIR_CI/9b-clean-state"
}

# ── SE-453: gates en «unknown» frente al baseline (primer ciclo: aviso) ──
check_gate_unknown() {
  bash "$REPO_ROOT_CI/.claude/hooks/lib/gate-result.sh" check > "$TMPDIR_CI/9c-gate-unknown" 2>&1
}

# ── Run checks in parallel ───────────────────────────────────────────────
check_branch &
check_coherence &
check_file_sizes &
check_frontmatter &
check_settings_json &
check_changelog &
check_generated_fresh &
check_lockfiles &
check_gate_unknown &
$CLEAN_STATE && check_clean_state &
if ! $QUICK_MODE; then
  check_required_files &
  check_secrets &
fi
wait

# ── Collect results ──────────────────────────────────────────────────────
PASS=0; FAIL=0; WARN=0; ERRORS=""
for f in "$TMPDIR_CI"/*; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    case "$line" in
      PASS*) PASS=$((PASS+1)); echo "  OK ${line#PASS }" ;;
      FAIL*) FAIL=$((FAIL+1)); ERRORS+="  ${line#FAIL }\n"; echo "  FAIL ${line#FAIL }" ;;
      WARN*) WARN=$((WARN+1)); echo "  WARN ${line#WARN }" ;;
    esac
  done < "$f"
done

echo ""
echo "--- Results: $PASS passed, $FAIL failed, $WARN warnings ---"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n  BLOCKED:\n$ERRORS"
  echo "  Run again after fixing: bash scripts/validate-ci-local.sh"
  exit 1
fi
echo ""
echo "  safe to push"
exit 0
