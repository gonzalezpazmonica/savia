#!/usr/bin/env bats
# SE-239 — Tests para git history secret scanning
# Ref: docs/propuestas/SE-239-git-history-secret-scanning.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_SCAN="$REPO_ROOT/scripts/git-history-secret-scan.sh"
  SCRIPT_REMEDIATE="$REPO_ROOT/scripts/git-history-secret-remediate.sh"
  SKILL_MD="$REPO_ROOT/.opencode/skills/git-secret-scanner/SKILL.md"
  GITLEAKS_CONFIG="$REPO_ROOT/.gitleaks.toml"
  TMPDIR_239="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_239"
}

# ── 1. git-history-secret-scan.sh existe y pasa bash -n ──────────────────────
@test "SE239-01: git-history-secret-scan.sh existe y pasa bash -n" {
  [[ -f "$SCRIPT_SCAN" ]]
  bash -n "$SCRIPT_SCAN"
}

# ── 2. git-history-secret-remediate.sh existe y pasa bash -n ─────────────────
@test "SE239-02: git-history-secret-remediate.sh existe y pasa bash -n" {
  [[ -f "$SCRIPT_REMEDIATE" ]]
  bash -n "$SCRIPT_REMEDIATE"
}

# ── 3. SKILL.md existe y ≤150 líneas ─────────────────────────────────────────
@test "SE239-03: git-secret-scanner/SKILL.md existe y tiene 150 líneas o menos" {
  [[ -f "$SKILL_MD" ]]
  local lines
  lines=$(wc -l < "$SKILL_MD")
  [[ "$lines" -le 150 ]]
}

# ── 4. Con gitleaks no disponible → muestra instrucciones de instalación ──────
@test "SE239-04: sin gitleaks muestra instrucciones de instalación" {
  local fake_home="$TMPDIR_239/nohome"
  mkdir -p "$fake_home/bin"
  # Crear un repo git de prueba con .gitignore
  local test_repo="$TMPDIR_239/testrepo"
  mkdir -p "$test_repo"
  git -C "$test_repo" init --quiet
  echo "output/" > "$test_repo/.gitignore"
  git -C "$test_repo" add .gitignore
  git -C "$test_repo" -c user.email="t@t.com" -c user.name="T" commit -m "init" --quiet

  # Crear una copia del script que apunte al test repo
  local test_script="$TMPDIR_239/git-history-secret-scan.sh"
  sed "s|REPO_ROOT=.*|REPO_ROOT=\"$test_repo\"|" "$SCRIPT_SCAN" > "$test_script"

  run env PATH="$fake_home/bin:$(dirname $(which git))" bash "$test_script" 2>&1
  # Debe mencionar instrucciones de instalación
  [[ "$output" == *"gitleaks"* ]] || [[ "$output" == *"install"* ]] || [[ "$output" == *"Instalación"* ]]
}

# ── 5. Con gitleaks no disponible → sugiere alternativa Docker ────────────────
@test "SE239-05: sin gitleaks sugiere alternativa Docker" {
  local fake_home="$TMPDIR_239/nohome2"
  mkdir -p "$fake_home/bin"
  local test_repo="$TMPDIR_239/testrepo2"
  mkdir -p "$test_repo"
  git -C "$test_repo" init --quiet
  echo "output/" > "$test_repo/.gitignore"
  git -C "$test_repo" add .gitignore
  git -C "$test_repo" -c user.email="t@t.com" -c user.name="T" commit -m "init" --quiet

  local test_script="$TMPDIR_239/scan2.sh"
  sed "s|REPO_ROOT=.*|REPO_ROOT=\"$test_repo\"|" "$SCRIPT_SCAN" > "$test_script"

  run env PATH="$fake_home/bin:$(dirname $(which git))" bash "$test_script" 2>&1
  [[ "$output" == *"docker"* ]] || [[ "$output" == *"Docker"* ]]
}

# ── 6. git-history-secret-scan.sh acepta flag --since ────────────────────────
@test "SE239-06: git-history-secret-scan.sh acepta flag --since" {
  grep -q -- "--since" "$SCRIPT_SCAN"
}

# ── 7. El script genera report en output/security/ (no en raíz) ───────────────
@test "SE239-07: el script genera report en output/security/" {
  grep -q "output/security" "$SCRIPT_SCAN"
}

# ── 8. El script clasifica findings por severidad ─────────────────────────────
@test "SE239-08: el script clasifica findings CRITICAL/HIGH/MEDIUM/LOW" {
  grep -q "CRITICAL" "$SCRIPT_SCAN"
  grep -q "HIGH"     "$SCRIPT_SCAN"
  grep -q "MEDIUM"   "$SCRIPT_SCAN"
  grep -q "LOW"      "$SCRIPT_SCAN"
}

# ── 9. Exit code 1 cuando hay CRITICAL o HIGH ─────────────────────────────────
@test "SE239-09: exit code 1 definido para CRITICAL/HIGH findings" {
  grep -q "sys.exit(1)" "$SCRIPT_SCAN"
}

# ── 10. Exit code 2 cuando solo hay MEDIUM/LOW ────────────────────────────────
@test "SE239-10: exit code 2 definido para MEDIUM/LOW findings" {
  grep -q "sys.exit(2)" "$SCRIPT_SCAN"
}

# ── 11. Exit code 0 cuando no hay findings ────────────────────────────────────
@test "SE239-11: exit code 0 cuando no hay findings" {
  grep -q "exit 0" "$SCRIPT_SCAN"
}

# ── 12. git-history-secret-remediate.sh genera comando pero NO lo ejecuta ─────
@test "SE239-12: el script de remediation NO ejecuta git filter-repo automáticamente" {
  # No debe contener llamada directa a git filter-repo ni BFG sin comentario
  # Verifica que hay un echo que muestra el comando, no una ejecución directa
  grep -q "echo" "$SCRIPT_REMEDIATE"
  # El script debe mencionar que solo genera comandos
  grep -qi "genera\|genera el comando\|only genera\|no lo ejecuta\|No.*ejecuta" "$SCRIPT_REMEDIATE" || \
  grep -qi "human\|humano\|decide\|decide\|review" "$SCRIPT_REMEDIATE"
}

# ── 13. .gitleaks.toml existe con allowlist para hashes SHA256 ────────────────
@test "SE239-13: .gitleaks.toml existe y contiene allowlist para hashes SHA256" {
  [[ -f "$GITLEAKS_CONFIG" ]]
  grep -q "sha256\|SHA256\|[0-9a-f]\{64\}\|hash" "$GITLEAKS_CONFIG"
}

# ── 14. .gitleaks.toml excluye el patrón diff_hash= de firma de confidencialidad ──
@test "SE239-14: .gitleaks.toml excluye diff_hash= de la firma de confidencialidad" {
  [[ -f "$GITLEAKS_CONFIG" ]]
  grep -q "diff_hash" "$GITLEAKS_CONFIG"
}

# ── 15. SKILL.md menciona "gitleaks" o "secret" ──────────────────────────────
@test "SE239-15: SKILL.md menciona gitleaks o secret" {
  grep -qi "gitleaks\|secret" "$SKILL_MD"
}


# ═══════════════════════════════════════════════════════════════════════════
# Comportamiento: gitleaks simulado en el PATH, árbol temporal con git propio.
# ═══════════════════════════════════════════════════════════════════════════

mk_tree() {
  TREE="$TMPDIR_239/tree"
  mkdir -p "$TREE/scripts" "$TREE/.claude/hooks/lib" "$TMPDIR_239/bin"
  cp "$SCRIPT_SCAN" "$TREE/scripts/"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$TREE/.claude/hooks/lib/"
  echo "output/" > "$TREE/.gitignore"
  git -C "$TREE" init -q
  for i in 1 2 3; do
    echo "$i" > "$TREE/f$i"
    git -C "$TREE" add -A
    git -C "$TREE" -c user.email=t@t -c user.name=T commit -qm "c$i"
  done
  # gitleaks falso: registra argumentos; copia FAKE_REPORT al --report-path; sale con FAKE_EXIT
  cat > "$TMPDIR_239/bin/gitleaks" <<'GL'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--report-path" ]] && out="$2"
  shift
done
[[ -n "${FAKE_SLEEP:-}" ]] && sleep "$FAKE_SLEEP"
[[ -n "${FAKE_REPORT:-}" ]] && cp "$FAKE_REPORT" "$out"
exit "${FAKE_EXIT:-0}"
GL
  chmod +x "$TMPDIR_239/bin/gitleaks"
  export FAKE_ARGS="$TMPDIR_239/args.txt"
}

SCAN_SH() { echo "$TREE/scripts/git-history-secret-scan.sh"; }

scan() {
  run env PATH="$TMPDIR_239/bin:$PATH" FAKE_ARGS="$FAKE_ARGS" "$@"
}

last_line() { printf '%s\n' "$output" | tail -1; }

report_with() {
  # report_with <RuleID> [<RuleID> ...]
  python3 - "$TMPDIR_239/report.json" "$@" <<'PY'
import json, sys
out, *rules = sys.argv[1:]
json.dump([{"RuleID": r, "Description": r, "File": "a.txt", "StartLine": 3,
            "Commit": "0123456789abcdef", "Secret": "SUPERSECRETVALUE", "Match": "key=SUPERSECRETVALUE"}
           for r in rules], open(out, "w"))
PY
  export FAKE_REPORT="$TMPDIR_239/report.json"
}

summary() { ls "$TREE"/output/security/history-scan-*-summary.md | head -1; }
jsonl() { ls "$TREE"/output/security/history-scan-*[0-9].jsonl | head -1; }

@test "SE239-B01: --help imprime los códigos de salida y sale 0 sin escanear" {
  mk_tree
  scan bash "$(SCAN_SH)" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Exit codes: 0=limpio, 1=CRITICAL/HIGH, 2=solo MEDIUM/LOW, 4=desconocido"* ]]
  [ ! -s "$FAKE_ARGS" ]
}

@test "SE239-B02: parámetro desconocido sale 1 y lo nombra" {
  mk_tree
  scan bash "$(SCAN_SH)" --nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"Parámetro desconocido: --nope"* ]]
}

@test "SE239-B03: .gitignore sin output/ aborta con 3 antes de llamar a gitleaks" {
  mk_tree
  echo "node_modules/" > "$TREE/.gitignore"
  scan bash "$(SCAN_SH)"
  [ "$status" -eq 3 ]
  [[ "$output" == *"output/security/ no está en .gitignore"* ]]
  [ ! -s "$FAKE_ARGS" ]
  [ ! -d "$TREE/output" ]
}

@test "SE239-B04: sin .gitignore en el repo objetivo el escaneo sigue" {
  mk_tree
  rm "$TREE/.gitignore"
  scan bash "$(SCAN_SH)"
  [ "$status" -eq 0 ]
}

@test "SE239-B05: sin gitleaks sale 4 con gate-result unknown y hueco missing_tool" {
  mk_tree
  rm "$TMPDIR_239/bin/gitleaks"
  mkdir -p "$TMPDIR_239/min"
  for b in bash git python3 date mktemp rm grep cat mkdir dirname sed timeout; do
    ln -sf "$(command -v $b)" "$TMPDIR_239/min/$b"
  done
  run env PATH="$TMPDIR_239/min" bash "$(SCAN_SH)"
  [ "$status" -eq 4 ]
  [[ "$output" == *"el historial NO se ha comprobado (gitleaks ausente)"* ]]
  [ "$(last_line)" = 'gate-result: {"result":"unknown","gaps":[{"check":"gitleaks","reason":"missing_tool"}]}' ]
}

@test "SE239-B06: historial limpio sale 0, escribe resumen LIMPIO y gate-result clean" {
  mk_tree
  FAKE_EXIT=0 scan bash "$(SCAN_SH)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK — sin findings en el historial."* ]]
  [ "$(last_line)" = 'gate-result: {"result":"clean","gaps":[]}' ]
  grep -q "LIMPIO — 0 findings" "$(summary)"
  grep -q "Rango\*\*: completo" "$(summary)"
  [ -z "$(ls "$TREE"/output/security/ | grep -v summary)" ]
}

@test "SE239-B07: finding CRITICAL sale 1, no vuelca el valor del secret y cuenta por severidad" {
  mk_tree
  report_with aws-access-token
  FAKE_EXIT=1 scan bash "$(SCAN_SH)"
  [ "$status" -eq 1 ]
  [ "$(last_line)" = 'gate-result: {"result":"findings","gaps":[]}' ]
  ! grep -q SUPERSECRETVALUE "$(jsonl)"
  grep -q '"severity": "CRITICAL"' "$(jsonl)"
  grep -q '^| CRITICAL | 1 |$' "$(summary)"
  grep -q '^| HIGH | 0 |$' "$(summary)"
  grep -q 'commit `01234567`' "$(summary)"
  ! grep -q SUPERSECRETVALUE "$(summary)"
}

@test "SE239-B08: la severidad sigue la regla: password es HIGH (1), uri es MEDIUM (2), otra cosa LOW (2)" {
  mk_tree
  report_with db-password
  FAKE_EXIT=1 scan bash "$(SCAN_SH)"
  [ "$status" -eq 1 ]
  grep -q '^| HIGH | 1 |$' "$(summary)"
  rm -rf "$TREE/output"
  report_with connection_string
  FAKE_EXIT=1 scan bash "$(SCAN_SH)"
  [ "$status" -eq 2 ]
  grep -q '^| MEDIUM | 1 |$' "$(summary)"
  rm -rf "$TREE/output"
  report_with generic-thing
  FAKE_EXIT=1 scan bash "$(SCAN_SH)"
  [ "$status" -eq 2 ]
  grep -q '^| LOW | 1 |$' "$(summary)"
  [ "$(last_line)" = 'gate-result: {"result":"findings","gaps":[]}' ]
}

@test "SE239-B09: una mezcla con un CRITICAL y un LOW sale 1 (gana la más grave)" {
  mk_tree
  report_with generic-thing private_key
  FAKE_EXIT=1 scan bash "$(SCAN_SH)"
  [ "$status" -eq 1 ]
  grep -q '^| CRITICAL | 1 |$' "$(summary)"
  grep -q '^| LOW | 1 |$' "$(summary)"
}

@test "SE239-B10: gitleaks con código distinto de 0/1 no se da por limpio (sale 4)" {
  mk_tree
  FAKE_EXIT=2 scan bash "$(SCAN_SH)"
  [ "$status" -eq 4 ]
  [[ "$output" == *"gitleaks falló (exit 2)"* ]]
  [ "$(last_line)" = 'gate-result: {"result":"unknown","gaps":[{"check":"gitleaks","reason":"unreadable"}]}' ]
}

@test "SE239-B11: tiempo agotado (exit 124) se registra como hueco timeout" {
  mk_tree
  FAKE_EXIT=124 scan bash "$(SCAN_SH)"
  [ "$status" -eq 4 ]
  [ "$(last_line)" = 'gate-result: {"result":"unknown","gaps":[{"check":"gitleaks","reason":"timeout"}]}' ]
}

@test "SE239-B12: GIT_HISTORY_SCAN_TIMEOUT corta un gitleaks lento y sale 4 con timeout" {
  mk_tree
  GIT_HISTORY_SCAN_TIMEOUT=1 FAKE_SLEEP=5 FAKE_EXIT=0 scan bash "$(SCAN_SH)"
  [ "$status" -eq 4 ]
  [[ "$(last_line)" == *'"reason":"timeout"'* ]]
}

@test "SE239-B13: findings anunciados con informe vacío no son limpios (sale 4)" {
  mk_tree
  echo "[]" > "$TMPDIR_239/empty.json"
  export FAKE_REPORT="$TMPDIR_239/empty.json"
  FAKE_EXIT=1 scan bash "$(SCAN_SH)"
  [ "$status" -eq 4 ]
  [[ "$output" == *"informe está vacío o es ilegible"* ]]
  [[ "$(last_line)" == *'"check":"gitleaks-report","reason":"unreadable"'* ]]
}

@test "SE239-B14: tope de commits superado sin findings sale 4 con hueco history:limit" {
  mk_tree
  GIT_HISTORY_SCAN_MAX_COMMITS=2 FAKE_EXIT=0 scan bash "$(SCAN_SH)"
  [ "$status" -eq 4 ]
  [[ "$output" == *"3 commits superan el tope 2"* ]]
  [ "$(last_line)" = 'gate-result: {"result":"unknown","gaps":[{"check":"history","reason":"limit"}]}' ]
  grep -qx -- '--log-opts=--all -n 2' "$FAKE_ARGS"
}

@test "SE239-B15: tope igual al número de commits no es un hueco" {
  mk_tree
  GIT_HISTORY_SCAN_MAX_COMMITS=3 FAKE_EXIT=0 scan bash "$(SCAN_SH)"
  [ "$status" -eq 0 ]
  [ "$(last_line)" = 'gate-result: {"result":"clean","gaps":[]}' ]
  ! grep -q -- '--log-opts' "$FAKE_ARGS"
}

@test "SE239-B16: tope superado con findings informa findings y conserva el hueco" {
  mk_tree
  report_with aws-access-token
  GIT_HISTORY_SCAN_MAX_COMMITS=1 FAKE_EXIT=1 scan bash "$(SCAN_SH)"
  [ "$status" -eq 1 ]
  [ "$(last_line)" = 'gate-result: {"result":"findings","gaps":[{"check":"history","reason":"limit"}]}' ]
}

@test "SE239-B17: --since con una ref usa el rango ref..HEAD" {
  mk_tree
  scan bash "$(SCAN_SH)" --since HEAD~1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rango: desde HEAD~1"* ]]
  grep -qx -- '--log-opts=HEAD~1..HEAD' "$FAKE_ARGS"
  grep -q 'Rango\*\*: HEAD~1' "$(summary)"
}

@test "SE239-B18: --since con una fecha usa --since=fecha" {
  mk_tree
  scan bash "$(SCAN_SH)" --since 2020-01-01
  [ "$status" -eq 0 ]
  grep -qx -- '--log-opts=--since=2020-01-01' "$FAKE_ARGS"
}

@test "SE239-B19: --repo apunta gitleaks a otro repositorio y el config sólo se pasa si existe" {
  mk_tree
  other="$TMPDIR_239/other"
  mkdir -p "$other"
  git -C "$other" init -q
  scan bash "$(SCAN_SH)" --repo "$other"
  [ "$status" -eq 0 ]
  grep -qx -- "$other" "$FAKE_ARGS"
  ! grep -qx -- '--config' "$FAKE_ARGS"
  : > "$TREE/.gitleaks.toml"
  scan bash "$(SCAN_SH)"
  grep -qx -- '--config' "$FAKE_ARGS"
  grep -qx -- "$TREE/.gitleaks.toml" "$FAKE_ARGS"
}

@test "SE239-B20: gitleaks se invoca con informe json, sin banner y exit-code 1" {
  mk_tree
  scan bash "$(SCAN_SH)"
  grep -qx -- 'detect' "$FAKE_ARGS"
  grep -qx -- '--no-banner' "$FAKE_ARGS"
  grep -qx -- 'json' "$FAKE_ARGS"
  grep -qx -- '--exit-code' "$FAKE_ARGS"
}
