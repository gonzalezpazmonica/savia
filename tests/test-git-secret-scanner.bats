#!/usr/bin/env bats
# SE-376 — git-secret-scanner: comportamiento de los tres scripts de la skill con un gitleaks
# falso (informe, código de salida y argumentos controlados). Ref: SE-239, SE-247 en
# docs/propuestas/ · .claude/skills/git-secret-scanner/SKILL.md
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  # Proyecto aislado: los informes van a $WORK/proj/output/security, nunca al repo real.
  mkdir -p "$WORK/proj/scripts" "$WORK/bin"
  cp "$REPO_ROOT/scripts/git-history-secret-scan.sh" "$REPO_ROOT/scripts/install-prepush-hook.sh" \
     "$REPO_ROOT/scripts/git-history-secret-remediate.sh" "$WORK/proj/scripts/"
  mkdir -p "$WORK/proj/scripts/lib"; cp "$REPO_ROOT/scripts/lib/gate-result.sh" "$WORK/proj/scripts/lib/"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/proj/scripts/pre-push-security-gate.sh"
  SCAN="$WORK/proj/scripts/git-history-secret-scan.sh"
  REPO="$WORK/repo"
  git init -q "$REPO"
  printf 'output/\n' > "$REPO/.gitignore"
  git -C "$REPO" add .gitignore
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -qm uno
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m dos
  # gitleaks falso: escribe $GL_REPORT en --report-path, apunta sus argumentos y sale con $GL_EXIT.
  cat > "$WORK/bin/gitleaks" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$GL_ARGS"
while [[ $# -gt 0 ]]; do [[ "$1" == --report-path ]] && { printf '%s' "${GL_REPORT:-[]}" > "$2"; }; shift; done
exit "${GL_EXIT:-0}"
STUB
  chmod +x "$WORK/bin/gitleaks"
  export GL_ARGS="$WORK/gl-args" PATH="$WORK/bin:$PATH"
  FIXTURE="FIXTURE-$RANDOM-NOT-A-SECRET"
}

teardown() { cd "$REPO_ROOT" || true; }

finding() { printf '{"RuleID":"%s","Description":"%s","File":"cfg.env","StartLine":3,"Commit":"abcdef1234","Secret":"%s","Match":"k=%s"}' "$1" "$2" "$FIXTURE" "$FIXTURE"; }

@test "safety: los tres scripts declaran set -uo pipefail" {
  for s in git-history-secret-scan.sh install-prepush-hook.sh git-history-secret-remediate.sh; do
    grep -q "set -uo pipefail" "$REPO_ROOT/scripts/$s"
  done
}

@test "scan: historial limpio ⇒ exit 0 y resumen LIMPIO" {
  GL_EXIT=0 run bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 0 ]
  grep -q "LIMPIO — 0 findings" "$WORK"/proj/output/security/history-scan-*-summary.md
}

@test "scan: un token de nube ⇒ exit 1 (CRITICAL) y el valor del secreto nunca llega al informe" {
  GL_EXIT=1 GL_REPORT="[$(finding aws-access-token 'AWS key')]" run bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 1 ]
  jsonl=$(ls "$WORK"/proj/output/security/history-scan-*.jsonl)
  python3 -c 'import json,sys; f=json.loads(open(sys.argv[1]).readline()); assert f["severity"]=="CRITICAL" and "Secret" not in f and "Match" not in f, f' "$jsonl"
  run grep -rF "$FIXTURE" "$WORK/proj/output"
  [ "$status" -ne 0 ]
}

@test "scan: una contraseña ⇒ HIGH (exit 1); solo una URL ⇒ MEDIUM (exit 2)" {
  GL_EXIT=1 GL_REPORT="[$(finding generic-password 'password in config')]" run bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 1 ]
  GL_EXIT=1 GL_REPORT="[$(finding jdbc-url 'connection_string with host')]" run bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 2 ]
}

@test "scan fail-closed: gitleaks que falla (exit 126) ⇒ exit 4, nunca «limpio»" {
  GL_EXIT=126 run bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 4 ]
  [[ "$output" == *"NO se ha comprobado"* ]]
}

@test "scan fail-closed: findings con informe empty o ilegible ⇒ exit 4" {
  GL_EXIT=1 GL_REPORT='[]' run bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 4 ]
  GL_EXIT=1 GL_REPORT='no es json' run bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 4 ]
}

@test "scan: --since con una ref limita a ref..HEAD; con una fecha usa --since=" {
  GL_EXIT=0 run bash "$SCAN" --repo "$REPO" --since HEAD~1
  grep -qx -- "--log-opts=HEAD~1..HEAD" "$GL_ARGS"
  GL_EXIT=0 run bash "$SCAN" --repo "$REPO" --since 2026-01-01
  grep -qx -- "--log-opts=--since=2026-01-01" "$GL_ARGS"
}

@test "scan: un repo sin output/ en .gitignore se rechaza (exit 3) antes de escanear" {
  printf 'node_modules/\n' > "$REPO/.gitignore"
  rm -f "$GL_ARGS"
  run bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 3 ]
  [ ! -e "$GL_ARGS" ]
}

@test "scan: sin gitleaks ⇒ exit 4 (unknown, SE-453) con instrucciones; parámetro inválido ⇒ exit 1" {
  run env PATH="/usr/bin:/bin" bash "$SCAN" --repo "$REPO"
  [ "$status" -eq 4 ]
  [[ "$output" == *"gitleaks no está instalado"* ]]
  run bash "$SCAN" --nada
  [ "$status" -eq 1 ]
}

@test "remediate: solo imprime el comando; el repo no cambia" {
  head_before=$(git -C "$REPO" rev-parse HEAD)
  run bash -c "cd '$REPO' && bash '$WORK/proj/scripts/git-history-secret-remediate.sh' --commit abcdef12 --file cfg.env"
  [ "$status" -eq 0 ]
  [[ "$output" == *'git filter-repo --path "cfg.env" --invert-paths'* ]]
  [[ "$output" == *"Rota el secret inmediatamente"* ]]
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 2 ]
}

@test "remediate: sin --commit ni --file ⇒ exit 1; fuera de un repo ⇒ exit 1" {
  run bash -c "cd '$REPO' && bash '$WORK/proj/scripts/git-history-secret-remediate.sh'"
  [ "$status" -eq 1 ]
  run bash -c "cd '$WORK' && bash '$WORK/proj/scripts/git-history-secret-remediate.sh' --file x"
  [ "$status" -eq 1 ]
}

@test "prepush: en un worktree instala donde git lee los hooks (dir común), no en .git/worktrees" {
  git -C "$REPO" worktree add -q "$WORK/wt" -b rama
  run bash "$WORK/proj/scripts/install-prepush-hook.sh" --repo "$WORK/wt"
  [ "$status" -eq 0 ]
  [ -x "$(git -C "$WORK/wt" rev-parse --git-path hooks/pre-push)" ]
  [ ! -e "$REPO/.git/worktrees/wt/hooks/pre-push" ]
}

@test "prepush: respeta core.hooksPath, es idempotente y guarda backup de un hook ajeno" {
  git -C "$REPO" config core.hooksPath .githooks
  mkdir -p "$REPO/.githooks"
  printf '#!/usr/bin/env bash\necho ajeno\n' > "$REPO/.githooks/pre-push"
  run bash "$WORK/proj/scripts/install-prepush-hook.sh" --repo "$REPO"
  [ "$status" -eq 0 ]
  grep -q "SE-247" "$REPO/.githooks/pre-push"
  ls "$REPO"/.githooks/pre-push.bak.* >/dev/null
  run bash "$WORK/proj/scripts/install-prepush-hook.sh" --repo "$REPO"
  [[ "$output" == *"ya instalado — sin cambios"* ]]
}

@test "prepush: un directorio que no es repo ⇒ exit 1" {
  run bash "$WORK/proj/scripts/install-prepush-hook.sh" --repo "$WORK/bin"
  [ "$status" -eq 1 ]
}
