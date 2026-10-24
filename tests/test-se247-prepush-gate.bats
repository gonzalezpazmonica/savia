#!/usr/bin/env bats
# SE-247 — Tests para pre-push security gate
# Ref: docs/propuestas/SE-247-pre-push-security-gate.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_GATE="$REPO_ROOT/scripts/pre-push-security-gate.sh"
  SCRIPT_INSTALL="$REPO_ROOT/scripts/install-prepush-hook.sh"
  GATE_DOC="$REPO_ROOT/docs/rules/domain/pre-push-security-gate.md"
  GITLEAKS_CONFIG="$REPO_ROOT/.gitleaks.toml"
  TMPDIR_247="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_247"
}

# ── 1. pre-push-security-gate.sh existe y pasa bash -n ───────────────────────
@test "SE247-01: pre-push-security-gate.sh existe y pasa bash -n" {
  [[ -f "$SCRIPT_GATE" ]]
  bash -n "$SCRIPT_GATE"
}

# ── 2. install-prepush-hook.sh existe y pasa bash -n ─────────────────────────
@test "SE247-02: install-prepush-hook.sh existe y pasa bash -n" {
  [[ -f "$SCRIPT_INSTALL" ]]
  bash -n "$SCRIPT_INSTALL"
}

# ── 3. pre-push-security-gate.md existe y ≤150 líneas ────────────────────────
@test "SE247-03: pre-push-security-gate.md existe y tiene 150 líneas o menos" {
  [[ -f "$GATE_DOC" ]]
  local lines
  lines=$(wc -l < "$GATE_DOC")
  [[ "$lines" -le 150 ]]
}

# ── 4. Con SAVIA_PREPUSH_SECURITY=off → exit 0 sin ejecutar scan ──────────────
@test "SE247-04: SAVIA_PREPUSH_SECURITY=off produce exit 0 inmediato" {
  run env SAVIA_PREPUSH_SECURITY=off bash "$SCRIPT_GATE" <<< ""
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"SAVIA_PREPUSH_SECURITY=off"* ]] || [[ "$output" == *"skipped"* ]]
}

# ── 5. Si gitleaks no instalado → warning pero exit 0 ────────────────────────
@test "SE247-05: si gitleaks no instalado, warning pero continúa (exit 0)" {
  # Crear un wrapper que oculta gitleaks del PATH
  local fake_home="$TMPDIR_247/nohome"
  mkdir -p "$fake_home/bin"
  # Git sigue disponible, pero gitleaks no
  run env PATH="$fake_home/bin:$(dirname $(which git))" bash "$SCRIPT_GATE" \
    <<< "refs/heads/main abc123 refs/heads/main 0000000000000000000000000000000000000000"
  # exit 0 cuando gitleaks no existe (no bloquear)
  [[ "$status" -eq 0 ]]
}

# ── 6. El script verifica que output/security/ está en .gitignore ─────────────
@test "SE247-06: el script referencia output/security/ o .gitignore" {
  grep -qE '\.gitignore|output/' "$SCRIPT_GATE"
}

# ── 7. Con input vacío (no hay commits nuevos) → exit 0 ──────────────────────
@test "SE247-07: sin commits nuevos (stdin vacío), exit 0" {
  run bash "$SCRIPT_GATE" <<< ""
  [[ "$status" -eq 0 ]]
}

# ── 8. El hook genera output/security/pre-push-findings.jsonl cuando hay findings ──
@test "SE247-08: el script menciona pre-push-findings.jsonl como destino de findings" {
  grep -q "pre-push-findings.jsonl" "$SCRIPT_GATE"
}

# ── 9. pre-push-security-gate.md menciona "gitleaks" ─────────────────────────
@test "SE247-09: pre-push-security-gate.md menciona gitleaks" {
  grep -qi "gitleaks" "$GATE_DOC"
}

# ── 10. pre-push-security-gate.md menciona "SAVIA_PREPUSH_SECURITY" ──────────
@test "SE247-10: pre-push-security-gate.md menciona SAVIA_PREPUSH_SECURITY" {
  grep -q "SAVIA_PREPUSH_SECURITY" "$GATE_DOC"
}

# ── 11. install-prepush-hook.sh menciona ".git/hooks/pre-push" ───────────────
@test "SE247-11: install-prepush-hook.sh menciona .git/hooks/pre-push" {
  grep -q "pre-push" "$SCRIPT_INSTALL"
}

# ── 12. pre-push-security-gate.sh tiene set -uo pipefail ─────────────────────
@test "SE247-12: pre-push-security-gate.sh tiene set -uo pipefail o equivalente" {
  grep -qE "set -[a-z]*u[a-z]*(o pipefail)?|set -uo pipefail|set -euo pipefail" "$SCRIPT_GATE"
}

# ── 13. El script maneja el caso de repo sin commits (nuevo repo) ─────────────
@test "SE247-13: el script maneja SHA de cero (nuevo repo, rama nueva)" {
  local zero_sha="0000000000000000000000000000000000000000"
  run bash "$SCRIPT_GATE" <<< "refs/heads/main $zero_sha refs/heads/main $zero_sha"
  # Debe terminar con exit 0 (no hay commits que escanear)
  [[ "$status" -eq 0 ]]
}

# ── 14. La allowlist .gitleaks.toml existe en la raíz ────────────────────────
@test "SE247-14: .gitleaks.toml existe en la raíz del repo" {
  [[ -f "$GITLEAKS_CONFIG" ]]
}

# ── 15. El script menciona output/security/ como destino de reports ──────────
@test "SE247-15: el script menciona output/security/ como destino" {
  grep -q "output/security" "$SCRIPT_GATE"
}

# ── Comportamiento: gate ejecutado en un repo aislado con gitleaks simulado ──

mk_gate() {
  SB="$TMPDIR_247/repo"
  mkdir -p "$SB/scripts" "$SB/.claude/hooks/lib" "$TMPDIR_247/fakebin" "$TMPDIR_247/safebin"
  cp "$SCRIPT_GATE" "$SB/scripts/"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$SB/.claude/hooks/lib/"
  printf 'output/\n' > "$SB/.gitignore"
  local t
  for t in bash env python3 grep mktemp date mkdir rm cat sed head tr basename dirname; do
    command -v "$t" >/dev/null 2>&1 && ln -sf "$(command -v "$t")" "$TMPDIR_247/safebin/$t"
  done
  # gitleaks simulado: registra argumentos, copia el informe pedido y devuelve GL_EXIT
  cat > "$TMPDIR_247/fakebin/gitleaks" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$GL_ARGS"
rp=""; prev=""
for a in "$@"; do [[ "$prev" == "--report-path" ]] && rp="$a"; prev="$a"; done
[[ -n "${GL_REPORT:-}" && -n "$rp" ]] && printf '%s' "$GL_REPORT" > "$rp"
exit "${GL_EXIT:-0}"
EOS
  chmod +x "$TMPDIR_247/fakebin/gitleaks"
  export GL_ARGS="$TMPDIR_247/gl-args"
  S1="1111111111111111111111111111111111111111"
  S2="2222222222222222222222222222222222222222"
  Z="0000000000000000000000000000000000000000"
}

with_gitleaks() { ln -sf "$TMPDIR_247/fakebin/gitleaks" "$TMPDIR_247/safebin/gitleaks"; }

run_gate() {  # run_gate <línea stdin>
  run env PATH="$TMPDIR_247/safebin" bash "$SB/scripts/pre-push-security-gate.sh" <<< "$1"
}

FINDING='[{"RuleID":"aws-key","File":"src/a.py","StartLine":7,"Commit":"abcdef1234567890","Secret":"AKIAHIDDENVALUE"}]'

@test "gate: opt-out SAVIA_PREPUSH_SECURITY=off no invoca gitleaks" {
  mk_gate; with_gitleaks
  run env PATH="$TMPDIR_247/safebin" SAVIA_PREPUSH_SECURITY=off bash "$SB/scripts/pre-push-security-gate.sh" <<< "r $S1 r $S2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scan skipped"* ]]
  [ ! -e "$GL_ARGS" ]
}

@test "gate: valor distinto de off (on) sí escanea" {
  mk_gate; with_gitleaks
  run env PATH="$TMPDIR_247/safebin" SAVIA_PREPUSH_SECURITY=on bash "$SB/scripts/pre-push-security-gate.sh" <<< "r $S1 r $S2"
  [ "$status" -eq 0 ]
  [ -e "$GL_ARGS" ]
}

@test "gate: stdin vacío -> sin commits nuevos, no escanea" {
  mk_gate; with_gitleaks
  run_gate ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sin commits nuevos que escanear"* ]]
  [ ! -e "$GL_ARGS" ]
}

@test "gate: SHA local a cero (borrado de rama) -> no escanea" {
  mk_gate; with_gitleaks
  run_gate "r $Z r $S2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sin commits nuevos"* ]]
  [ ! -e "$GL_ARGS" ]
}

@test "gate: rama nueva (remoto a cero) escanea todo lo local con --log-opts=<sha>" {
  mk_gate; with_gitleaks
  run_gate "r $S1 r $Z"
  [ "$status" -eq 0 ]
  grep -qxF -- "--log-opts=$S1" "$GL_ARGS"
}

@test "gate: remoto vacío también cuenta como rama nueva" {
  mk_gate; with_gitleaks
  run_gate "r $S1 r"
  grep -qxF -- "--log-opts=$S1" "$GL_ARGS"
}

@test "gate: rama existente escanea solo el rango remoto..local" {
  mk_gate; with_gitleaks
  run_gate "r $S1 r $S2"
  grep -qxF -- "--log-opts=$S2..$S1" "$GL_ARGS"
}

@test "gate: solo se lee el primer par de refs de stdin" {
  mk_gate; with_gitleaks
  run env PATH="$TMPDIR_247/safebin" bash "$SB/scripts/pre-push-security-gate.sh" < <(printf 'r %s r %s\nr %s r %s\n' "$S1" "$S2" "$S2" "$S1")
  [ "$status" -eq 0 ]
  grep -qxF -- "--log-opts=$S2..$S1" "$GL_ARGS"
}

@test "gate: gitleaks recibe --source del repo, formato json, --exit-code 1 y --no-banner" {
  mk_gate; with_gitleaks
  run_gate "r $S1 r $S2"
  grep -qxF -- "detect" "$GL_ARGS"
  grep -qxF -- "$SB" "$GL_ARGS"
  grep -qxF -- "--report-format" "$GL_ARGS"
  grep -qxF -- "json" "$GL_ARGS"
  grep -qxF -- "--no-banner" "$GL_ARGS"
  [ "$(grep -A1 -x -- '--exit-code' "$GL_ARGS" | tail -1)" = "1" ]
}

@test "gate: con .gitleaks.toml en el repo se pasa --config; sin él no" {
  mk_gate; with_gitleaks
  run_gate "r $S1 r $S2"
  ! grep -qxF -- "--config" "$GL_ARGS"
  : > "$SB/.gitleaks.toml"
  run_gate "r $S1 r $S2"
  grep -qxF -- "--config" "$GL_ARGS"
  grep -qxF -- "$SB/.gitleaks.toml" "$GL_ARGS"
}

@test "gate: gitleaks limpio -> exit 0, mensaje OK y sin fichero de findings" {
  mk_gate; with_gitleaks
  GL_EXIT=0 run_gate "r $S1 r $S2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK — sin secrets detectados"* ]]
  [ ! -e "$SB/output/security/pre-push-findings.jsonl" ]
}

@test "gate: secreto detectado -> exit 1, lista regla/fichero/línea/commit corto y NO el valor" {
  mk_gate; with_gitleaks
  GL_EXIT=1 GL_REPORT="$FINDING" run_gate "r $S1 r $S2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SECRETS DETECTADOS"* ]]
  [[ "$output" == *"1 finding(s) detectado(s)"* ]]
  [[ "$output" == *"[aws-key] src/a.py:7 (commit abcdef12)"* ]]
  [[ "$output" != *"AKIAHIDDENVALUE"* ]]
  [[ "$output" == *"git push --no-verify"* ]]
}

@test "gate: hallazgo sin Commit se muestra como staged" {
  mk_gate; with_gitleaks
  GL_EXIT=1 GL_REPORT='[{"RuleID":"r1","File":"f","StartLine":1}]' run_gate "r $S1 r $S2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[r1] f:1 (commit staged)"* ]]
}

@test "gate: los findings se guardan en JSONL con scan_ts y se acumulan entre ejecuciones" {
  mk_gate; with_gitleaks
  GL_EXIT=1 GL_REPORT="$FINDING" run_gate "r $S1 r $S2"
  GL_EXIT=1 GL_REPORT="$FINDING" run_gate "r $S1 r $S2"
  local f="$SB/output/security/pre-push-findings.jsonl"
  [ "$(wc -l < "$f")" -eq 2 ]
  python3 - "$f" <<'EOP'
import json, sys, re
for l in open(sys.argv[1]):
    d = json.loads(l)
    assert d["RuleID"] == "aws-key", d
    assert re.fullmatch(r"\d{8}-\d{6}", d["scan_ts"]), d["scan_ts"]
EOP
}

@test "gate: .gitignore sin output/ avisa y no escribe findings, pero sigue bloqueando" {
  mk_gate; with_gitleaks
  printf 'node_modules/\n' > "$SB/.gitignore"
  GL_EXIT=1 GL_REPORT="$FINDING" run_gate "r $S1 r $S2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no está en .gitignore"* ]]
  [ ! -e "$SB/output/security/pre-push-findings.jsonl" ]
}

@test "gate: .gitignore con output/ no emite el aviso" {
  mk_gate; with_gitleaks
  GL_EXIT=1 GL_REPORT="$FINDING" run_gate "r $S1 r $S2"
  [[ "$output" != *"no está en .gitignore"* ]]
  [ -s "$SB/output/security/pre-push-findings.jsonl" ]
}

@test "gate: sin .gitignore no hay aviso y se escriben los findings" {
  mk_gate; with_gitleaks
  unlink "$SB/.gitignore"
  GL_EXIT=1 GL_REPORT="$FINDING" run_gate "r $S1 r $S2"
  [[ "$output" != *"no está en .gitignore"* ]]
  [ -s "$SB/output/security/pre-push-findings.jsonl" ]
}

@test "gate: gitleaks falla pero el informe es []: bloquea igualmente y no escribe JSONL" {
  mk_gate; with_gitleaks
  GL_EXIT=1 GL_REPORT='[]' run_gate "r $S1 r $S2"
  [ "$status" -eq 1 ]
  [[ "$output" != *"finding(s) detectado(s)"* ]]
  [ ! -s "$SB/output/security/pre-push-findings.jsonl" ]
}

@test "gate: gitleaks falla con informe ilegible: bloquea (fallo cerrado)" {
  mk_gate; with_gitleaks
  GL_EXIT=1 GL_REPORT='no es json' run_gate "r $S1 r $S2"
  [ "$status" -eq 1 ]
}

@test "gate: gitleaks ausente -> exit 0, resultado unknown y registro de no medido" {
  mk_gate
  run_gate "r $S1 r $S2"
  [ "$status" -eq 0 ]
  [[ "$output" == *'gate-result: {"result":"unknown","gaps":[{"check":"gitleaks","reason":"missing_tool"}]}'* ]]
  [[ "$output" == *"Push continúa SIN escaneo"* ]]
  grep -q '"hook":"pre-push-security-gate","reason":"missing_tool"' "$SB/output/unmeasured-gates.jsonl"
}

@test "gate: gitleaks ausente con SAVIA_GATE_UNKNOWN=block -> bloquea el push (exit 1)" {
  mk_gate
  run env PATH="$TMPDIR_247/safebin" SAVIA_GATE_UNKNOWN=block bash "$SB/scripts/pre-push-security-gate.sh" <<< "r $S1 r $S2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"push bloqueado"* ]]
  [[ "$output" != *"Push continúa"* ]]
}

@test "gate: gitleaks ausente con SAVIA_GATE_UNKNOWN=warn sigue (exit 0)" {
  mk_gate
  run env PATH="$TMPDIR_247/safebin" SAVIA_GATE_UNKNOWN=warn bash "$SB/scripts/pre-push-security-gate.sh" <<< "r $S1 r $S2"
  [ "$status" -eq 0 ]
}
