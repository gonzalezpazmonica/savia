#!/usr/bin/env bats
# SE-453 — contrato de resultado de los gates (clean / findings / unknown).
# Spec: docs/specs/SE-453-gate-result-contract.spec.md · Contrato: docs/rules/domain/gate-result-contract.md
# Cada caso fija un comportamiento: herramienta ausente, tope superado y guards sin jq.

setup_file() {
  # Directorios de PATH aislados: todo /usr/bin menos las herramientas que se quieren ausentes.
  mkpath() {
    local dir="$1"; shift
    local f name skip x
    mkdir -p "$dir"
    for f in /usr/bin/*; do
      name="${f##*/}"; skip=0
      for x in "$@"; do [[ "$name" == "$x" ]] && skip=1; done
      [[ $skip -eq 1 ]] && continue
      [[ -x "$f" ]] && ln -sf "$f" "$dir/$name"
    done
  }
  export NOJQ="$BATS_FILE_TMPDIR/nojq" NOTOOLS="$BATS_FILE_TMPDIR/notools" NOTRIVY="$BATS_FILE_TMPDIR/notrivy"
  mkpath "$NOJQ" jq
  mkpath "$NOTOOLS" jq gitleaks trivy docker
  mkpath "$NOTRIVY" gitleaks trivy docker
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  mkdir -p "$WORK/proj/scripts" "$WORK/proj/.claude/hooks/lib" "$WORK/bin"
  cp "$REPO_ROOT/scripts/git-history-secret-scan.sh" "$REPO_ROOT/scripts/dependency-scan.sh" \
     "$REPO_ROOT/scripts/pre-push-security-gate.sh" "$WORK/proj/scripts/"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$WORK/proj/.claude/hooks/lib/"
  REPO="$WORK/repo"
  git init -q "$REPO"
  printf 'output/\n' > "$REPO/.gitignore"
  git -C "$REPO" add .gitignore
  for m in uno dos tres; do
    git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "$m"
  done
  # gitleaks falso: informe vacío y salida $GL_EXIT.
  cat > "$WORK/bin/gitleaks" <<'STUB'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do [[ "$1" == --report-path ]] && printf '[]' > "$2"; shift; done
exit "${GL_EXIT:-0}"
STUB
  chmod +x "$WORK/bin/gitleaks"
}

last_result() { printf '%s\n' "$output" | grep '^gate-result: ' | tail -1 | sed 's/^gate-result: //'; }

# ── contrato común ───────────────────────────────────────────────────────────

@test "contrato: gate_result_emit imprime result y gaps con motivo válido" {
  source "$REPO_ROOT/.claude/hooks/lib/gate-result.sh"
  run gate_result_emit unknown "gitleaks:missing_tool" "history:limit"
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1].split(": ",1)[1]); assert d=={"result":"unknown","gaps":[{"check":"gitleaks","reason":"missing_tool"},{"check":"history","reason":"limit"}]}, d' "$output"
}

@test "contrato: un check con salto de línea o tabulador sale en una sola línea JSON válida (revisión #1355)" {
  source "$REPO_ROOT/.claude/hooks/lib/gate-result.sh"
  run gate_result_emit unknown $'a\nb\tc.md:unreadable'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1].split(": ",1)[1]); assert d["gaps"]==[{"check":"a_b_c.md","reason":"unreadable"}], d' "$output"
}

@test "contrato: rechaza estado inválido, motivo inválido y unknown sin hueco" {
  source "$REPO_ROOT/.claude/hooks/lib/gate-result.sh"
  run gate_result_emit mal; [ "$status" -ne 0 ]
  run gate_result_emit unknown "x:no_existe"; [ "$status" -ne 0 ]
  run gate_result_emit unknown; [ "$status" -ne 0 ]
  run gate_result_emit clean; [ "$status" -eq 0 ]
}

@test "contrato SE-468: acepta not_executed y no_baseline" {
  source "$REPO_ROOT/.claude/hooks/lib/gate-result.sh"
  run gate_result_emit unknown "evals:not_executed" "evals:no_baseline"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"reason":"not_executed"'* && "$output" == *'"reason":"no_baseline"'* ]]
}

# ── AC3: herramienta ausente ⇒ unknown, no hallazgo ──────────────────────────

@test "AC3: sin gitleaks, el escaneo de historial es unknown/missing_tool y no sale 1" {
  run env PATH="$NOTOOLS" /usr/bin/bash "$WORK/proj/scripts/git-history-secret-scan.sh" --repo "$REPO"
  [ "$status" -eq 4 ]
  [ "$status" -ne 1 ]
  r="$(last_result)"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["result"]=="unknown" and {"check":"gitleaks","reason":"missing_tool"} in d["gaps"], d' "$r"
}

@test "AC3b: un historial limpio es result clean sin huecos" {
  run env PATH="$WORK/bin:$PATH" bash "$WORK/proj/scripts/git-history-secret-scan.sh" --repo "$REPO"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = '{"result":"clean","gaps":[]}' ]
}

@test "AC3c: gitleaks que falla ⇒ unknown, nunca clean" {
  run env GL_EXIT=126 PATH="$WORK/bin:$PATH" bash "$WORK/proj/scripts/git-history-secret-scan.sh" --repo "$REPO"
  [ "$status" -eq 4 ]
  [[ "$(last_result)" == *'"result":"unknown"'* ]]
}

@test "dependency-scan: sin Trivy ni Docker ⇒ exit 2 y unknown/missing_tool" {
  mkdir -p "$WORK/dep"
  run env PATH="$NOTRIVY" DEP_SCAN_OUTPUT_DIR="$WORK/out" /usr/bin/bash "$WORK/proj/scripts/dependency-scan.sh" --path "$WORK/dep"
  [ "$status" -eq 2 ]
  r="$(last_result)"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["result"]=="unknown" and d["gaps"][0]["reason"]=="missing_tool", d' "$r"
}

@test "pre-push: sin gitleaks avisa unknown, registra no medido y deja pasar; con SAVIA_GATE_UNKNOWN=block bloquea" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  line="refs/heads/x $sha refs/heads/x 0000000000000000000000000000000000000000"
  run env PATH="$NOTOOLS" /usr/bin/bash -c "echo '$line' | bash '$WORK/proj/scripts/pre-push-security-gate.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"result":"unknown"'* ]]
  python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).readline()); assert d["hook"]=="pre-push-security-gate" and d["reason"]=="missing_tool", d' "$WORK/proj/output/unmeasured-gates.jsonl"
  run env PATH="$NOTOOLS" SAVIA_GATE_UNKNOWN=block /usr/bin/bash -c "echo '$line' | bash '$WORK/proj/scripts/pre-push-security-gate.sh'"
  [ "$status" -eq 1 ]
}

# ── AC4: tope superado ⇒ unknown/limit ───────────────────────────────────────

@test "AC4: más commits que el tope ⇒ unknown con hueco limit, nunca clean" {
  run env GIT_HISTORY_SCAN_MAX_COMMITS=1 PATH="$WORK/bin:$PATH" bash "$WORK/proj/scripts/git-history-secret-scan.sh" --repo "$REPO"
  [ "$status" -eq 4 ]
  r="$(last_result)"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["result"]=="unknown" and {"check":"history","reason":"limit"} in d["gaps"], d' "$r"
}

@test "AC4b: dentro del tope sigue siendo clean" {
  run env GIT_HISTORY_SCAN_MAX_COMMITS=10 PATH="$WORK/bin:$PATH" bash "$WORK/proj/scripts/git-history-secret-scan.sh" --repo "$REPO"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = '{"result":"clean","gaps":[]}' ]
}

@test "AC4c: timeout de gitleaks ⇒ unknown con hueco timeout" {
  cat > "$WORK/bin/gitleaks" <<'STUB'
#!/usr/bin/env bash
sleep 5
STUB
  run env GIT_HISTORY_SCAN_TIMEOUT=1 PATH="$WORK/bin:$PATH" bash "$WORK/proj/scripts/git-history-secret-scan.sh" --repo "$REPO"
  [ "$status" -eq 4 ]
  [[ "$(last_result)" == *'"reason":"timeout"'* ]]
}

# ── AC5/AC6: guards blocking sin jq ──────────────────────────────────────────

guard() { # guard <hook> <path> <json>
  printf '%s' "$3" | env PATH="$2" /usr/bin/bash "$REPO_ROOT/.claude/hooks/$1.sh"
}
ghtoken() { printf 'ghp_%s' "$(printf 'A%.0s' $(seq 1 36))"; }

@test "AC5: sin jq, block-credential-leak con un token de GitHub sale 2" {
  run guard block-credential-leak "$NOJQ" "{\"tool_input\":{\"command\":\"curl -H x $(ghtoken)\"}}"
  [ "$status" -eq 2 ]
}

@test "AC5: sin jq, block-force-push con git push --force sale 2" {
  run guard block-force-push "$NOJQ" '{"tool_input":{"command":"git push --force origin feat"}}'
  [ "$status" -eq 2 ]
}

@test "AC5: sin jq, block-infra-destructive y agent-git-discipline siguen bloqueando" {
  run guard block-infra-destructive "$NOJQ" '{"tool_input":{"command":"terraform destroy"}}'
  [ "$status" -eq 2 ]
  run guard agent-git-discipline "$NOJQ" '{"tool_input":{"command":"git reset --hard HEAD~1"}}'
  [ "$status" -eq 2 ]
}

@test "AC5: sin jq, un comando con comillas escapadas se evalúa entero" {
  run guard block-credential-leak "$NOJQ" "{\"tool_input\":{\"command\":\"echo \\\"hola\\\" && curl $(ghtoken)\"}}"
  [ "$status" -eq 2 ]
}

@test "AC5: sin jq y con un command que no se puede extraer, sale 2 (nunca 0 sin evaluar)" {
  run guard block-credential-leak "$NOJQ" '{"tool_input":{"command":5}}'
  [ "$status" -eq 2 ]
  run guard block-force-push "$NOJQ" '{"tool_input":{"command":5}}'
  [ "$status" -eq 2 ]
}

@test "AC5: sin jq, comando inocuo sale 0 y entrada sin command sale 0" {
  run guard block-credential-leak "$NOJQ" '{"tool_input":{"command":"ls -la"}}'
  [ "$status" -eq 0 ]
  run guard block-force-push "$NOJQ" '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
  [ "$status" -eq 0 ]
}

@test "AC6: con jq, token ⇒ 2 y ls -la ⇒ 0 (sin cambios)" {
  command -v jq >/dev/null
  run guard block-credential-leak "$PATH" "{\"tool_input\":{\"command\":\"curl $(ghtoken)\"}}"
  [ "$status" -eq 2 ]
  run guard block-credential-leak "$PATH" '{"tool_input":{"command":"ls -la"}}'
  [ "$status" -eq 0 ]
  run guard block-force-push "$PATH" '{"tool_input":{"command":"git push --force origin feat"}}'
  [ "$status" -eq 2 ]
  run guard block-force-push "$PATH" '{"tool_input":{"command":"ls -la"}}'
  [ "$status" -eq 0 ]
}

# ── AC7: hooks no marcados sin jq ⇒ 0 + registro de no medido ────────────────

@test "AC7: sin jq, un hook no marcado sale 0 y registra la línea en unmeasured-gates.jsonl" {
  proj="$WORK/p7"; mkdir -p "$proj"
  run env PATH="$NOJQ" CLAUDE_PROJECT_DIR="$proj" /usr/bin/bash -c "echo '{}' | bash '$REPO_ROOT/.claude/hooks/acm-turn-marker.sh'"
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).readline()); assert d["hook"]=="acm-turn-marker" and d["reason"]=="missing_tool", d' "$proj/output/unmeasured-gates.jsonl"
}

@test "AC7: el registro no se duplica el mismo día" {
  proj="$WORK/p7b"; mkdir -p "$proj"
  for _ in 1 2 3; do
    env PATH="$NOJQ" CLAUDE_PROJECT_DIR="$proj" /usr/bin/bash -c "echo '{}' | bash '$REPO_ROOT/.claude/hooks/acm-turn-marker.sh'"
  done
  [ "$(wc -l < "$proj/output/unmeasured-gates.jsonl")" -eq 1 ]
}

# ── consumidor: contador unknown frente al baseline (D3) ─────────────────────

@test "gate-unknown-check: dentro del baseline PASS; por encima WARN y con ENFORCE=1 FAIL" {
  S="$REPO_ROOT/.claude/hooks/lib/gate-result.sh"
  echo 0 > "$WORK/base"
  : > "$WORK/log"
  run env GATE_UNMEASURED_LOG="$WORK/log" GATE_UNKNOWN_BASELINE="$WORK/base" bash "$S" check
  [ "$status" -eq 0 ]; [[ "$output" == PASS* ]]
  printf '{"hook":"x","reason":"missing_tool","day":"%s"}\n' "$(date +%Y-%m-%d)" > "$WORK/log"
  run env GATE_UNMEASURED_LOG="$WORK/log" GATE_UNKNOWN_BASELINE="$WORK/base" bash "$S" check
  [ "$status" -eq 0 ]; [[ "$output" == WARN* ]]
  run env GATE_UNKNOWN_ENFORCE=1 GATE_UNMEASURED_LOG="$WORK/log" GATE_UNKNOWN_BASELINE="$WORK/base" bash "$S" check
  [ "$status" -eq 1 ]; [[ "$output" == FAIL* ]]
}

@test "gate-unknown-check: baseline ausente o log corrupto fallan cerrado" {
  S="$REPO_ROOT/.claude/hooks/lib/gate-result.sh"
  run env GATE_UNKNOWN_BASELINE="$WORK/no-existe" bash "$S" check
  [ "$status" -eq 1 ]
  echo 0 > "$WORK/base"; echo 'no json' > "$WORK/log"
  run env GATE_UNMEASURED_LOG="$WORK/log" GATE_UNKNOWN_BASELINE="$WORK/base" bash "$S" check
  [ "$status" -eq 1 ]
}
