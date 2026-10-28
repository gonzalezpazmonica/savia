#!/usr/bin/env bats
# Ref: docs/specs/SE-433-merge-sprint.spec.md · docs/rules/domain/autonomous-safety-merge-sprint.md
# Tests de scripts/merge-sprint.sh con un gh falso: nunca toca GitHub.

SCRIPT="scripts/merge-sprint.sh"

setup() {
  TMPDIR_T="$(mktemp -d)"
  export MERGE_SPRINT_HOME="$TMPDIR_T/state"
  export MERGE_SPRINT_POLICY="$TMPDIR_T/policy.conf"
  export MERGE_SPRINT_POLL_S=0 MERGE_SPRINT_MAIN_POLLS=2 MERGE_SPRINT_CI_POLLS=1 MERGE_SPRINT_CI_SETTLE_S=0
  export MERGE_SPRINT_RESYNC=0   # los tests v1 no re-sincronizan; los v2 lo activan con v2_repo
  printf 'allowed_tiers=1,2,3\nttl_hours=12\nmax_merges=40\nmax_prs=50\n' > "$MERGE_SPRINT_POLICY"
  export FAKE="$TMPDIR_T/fake"; mkdir -p "$FAKE" "$TMPDIR_T/bin"
  # gh falso: estado en $FAKE/<pr>.{head,files,checks,state,base,repo,reopens,on_merge}, $FAKE/main_ci,
  # $FAKE/required (checks obligatorios de main), log de merges en $FAKE/merged y de llamadas en $FAKE/calls
  cat > "$TMPDIR_T/bin/gh" <<'EOF'
#!/usr/bin/env bash
F="$FAKE"; a="$*"; echo "$a" >> "$F/calls"
case "$1 $2" in
  "pr list") ls "$F" | sed -n 's/^\([0-9]*\)\.head$/\1/p' | while read -r n; do [[ "$(cat "$F/$n.state" 2>/dev/null || echo OPEN)" == OPEN ]] && echo "$n"; done | sort -n ;;
  "pr view")
    n=$3
    case "$a" in
      *headRefOid*) if [[ -f "$F/$n.branch" ]]; then git --git-dir="$BARE" rev-parse "refs/heads/$(cat "$F/$n.branch")"; else cat "$F/$n.head"; fi ;;
      *headRefName*) cat "$F/$n.branch" ;;
      *baseRefName*) cat "$F/$n.base" 2>/dev/null || echo main ;;
      *headRepository*) cat "$F/$n.repo" 2>/dev/null || echo owner/repo ;;
      *mergeStateStatus*) cat "$F/$n.mss" 2>/dev/null || echo CLEAN ;;
      *isDraft*) cat "$F/$n.draft" 2>/dev/null || echo true ;;
      *mergedBy*) cat "$F/$n.merged_by" 2>/dev/null || echo executor ;;
      *mergeCommit*) [[ -f "$F/$n.on_mc" ]] && bash "$F/$n.on_mc"; [[ -f "$F/$n.mc_fail" ]] && exit 1; printf 'c%039d\n' "$n" ;;
      *state*) [[ -f "$F/$n.state_fail" ]] && exit 1
               [[ "$a" == *"-q .state"* && -f "$F/$n.on_f5state" ]] && bash "$F/$n.on_f5state"   # consulta de f5-state.sh
               cat "$F/$n.state" 2>/dev/null || echo OPEN ;;
    esac ;;
  "pr diff") cat "$F/$3.files" ;;
  "pr checks") printf 'CI\t%s\n' "$(cat "$F/$3.checks" 2>/dev/null || echo pass)" ;;
  "pr ready"|"label create"|"label delete") exit 0 ;;
  "pr edit") exit 1 ;;   # como en GitHub desde la deprecación de Projects (classic)
  "label list") cat "$F/labels" 2>/dev/null ;;
  "pr merge") # rama protegida «al día»: rechaza el merge si main no está integrada en la rama del PR
              if [[ -f "$F/$3.require_uptodate" ]] && ! git --git-dir="$BARE" merge-base --is-ancestor refs/heads/main "refs/heads/$(cat "$F/$3.branch")"; then
                echo BEHIND > "$F/$3.mss"; exit 1; fi
              if [[ -f "$F/$3.reject" ]]; then n=$(cat "$F/$3.reject"); (( n > 0 )) && { echo $((n-1)) > "$F/$3.reject"; exit 1; }; fi
              echo "$3" >> "$F/merged"; echo MERGED > "$F/$3.state"
              [[ -f "$F/$3.on_merge" ]] && GHPPID=$PPID bash "$F/$3.on_merge"; exit 0 ;;
  *)
    case "$a" in
      api*protection/required_status_checks*) cat "$F/required" 2>/dev/null ;;
      api*/issues/*/events*) n=$(sed -E 's|.*/issues/([0-9]+)/events.*|\1|' <<<"$a"); cat "$F/$n.reopens" 2>/dev/null || echo 0 ;;
      api*check-runs*) cat "$F/main_ci" 2>/dev/null || echo pass ;;
      "api user"*) echo executor ;;
      "api -X POST repos/"*"/issues/"*"/labels"*|"api -X DELETE repos/"*"/issues/"*"/labels/"*) exit 0 ;;
      *) exit 1 ;;
    esac ;;
esac
EOF
  chmod +x "$TMPDIR_T/bin/gh"; export GH="$TMPDIR_T/bin/gh"; export PATH="$TMPDIR_T/bin:$PATH"
  echo CI > "$FAKE/required"
  # Repo git temporal con remoto bare: origin/main lleva el ejecutor y el clasificador de este árbol
  export BARE="$TMPDIR_T/origin.git"; git init -q --bare "$BARE"
  export MERGE_SPRINT_GIT_ROOT="$TMPDIR_T/clone"
  git clone -q "$BARE" "$MERGE_SPRINT_GIT_ROOT" 2>/dev/null
  git -C "$MERGE_SPRINT_GIT_ROOT" config user.email t@t; git -C "$MERGE_SPRINT_GIT_ROOT" config user.name t
  git -C "$MERGE_SPRINT_GIT_ROOT" config commit.gpgsign false
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/scripts"
  cp scripts/merge-sprint.sh scripts/risk-tier.py scripts/f5-state.sh "$MERGE_SPRINT_GIT_ROOT/scripts/"
  echo base > "$MERGE_SPRINT_GIT_ROOT/a.txt"; G add a.txt scripts; G commit -qm base; G branch -M main; G push -q origin main
}

G() { git -C "$MERGE_SPRINT_GIT_ROOT" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

teardown() { rm -rf "$TMPDIR_T"; }

sha_of() { printf '%040d' "$1" | tr 0 a; }

mkpr() {  # mkpr <n> <ficheros>
  sha_of "$1" > "$FAKE/$1.head"; echo "$2" > "$FAKE/$1.files"
}

review() {  # review <n> <verdict> <role> [reviewer] [p1]
  local f="$TMPDIR_T/rev-$1-$3.md"
  echo "VERDICT: $2 pr=$1 sha=$(sha_of "$1") role=$3 tier=2 reviewer=${4:-rev-agent} author=impl-agent p0=0 p1=${5:-0} p2=0 p2_blocking=0" > "$f"
  bash "$SCRIPT" review-register "$1" "$f"
}

regrant() {  # grant nuevo sobre el mismo manifiesto: un sprint parado solo se reanuda así
  bash "$SCRIPT" grant "$(sha256sum < "$MERGE_SPRINT_HOME/manifest.json" | cut -d' ' -f1)" >/dev/null
}

plan_and_grant() {
  run bash "$SCRIPT" plan; [ "$status" -eq 0 ]
  local d; d=$(echo "$output" | sed -n 's/^digest: //p')
  run bash "$SCRIPT" grant "$d"; [ "$status" -eq 0 ]
}

@test "script es bash estricto (set -uo pipefail)" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "positivo: PR revisado APPROVE con CI verde se mergea y queda en el ledger" {
  mkpr 10 "scripts/foo.sh"; review 10 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 10 "$FAKE/merged"
  run bash "$SCRIPT" verify-ledger
  [ "$status" -eq 0 ]
}

@test "positivo: serie ascendente aunque se registren en otro orden" {
  mkpr 12 "scripts/b.sh"; mkpr 11 "scripts/a.sh"
  review 12 APPROVE correctness; review 11 APPROVE correctness
  plan_and_grant
  bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/merged")" = "11,12" ]
}

@test "reject: revisor igual al orquestador o al autor no se registra" {
  mkpr 13 "scripts/c.sh"
  run review 13 APPROVE correctness savia-orchestrator
  [ "$status" -ne 0 ]
  run review 13 APPROVE correctness impl-agent
  [ "$status" -ne 0 ]
}

@test "invalid: primera línea sin gramática VERDICT se rechaza" {
  mkpr 14 "scripts/d.sh"; echo "APTO — todo bien" > "$TMPDIR_T/r.md"
  run bash "$SCRIPT" review-register 14 "$TMPDIR_T/r.md"
  [ "$status" -eq 3 ]
}

@test "block: APPROVE con p1>0 cuenta como HOLD y el PR no entra en el manifiesto" {
  mkpr 15 "scripts/e.sh"; review 15 APPROVE correctness rev-agent 1
  run bash "$SCRIPT" plan
  [[ "$output" != *"#15"* ]]
}

@test "block: un HOLD previo excluye aunque luego haya APPROVE" {
  mkpr 16 "scripts/f.sh"; review 16 HOLD correctness; review 16 APPROVE correctness rev-b
  run bash "$SCRIPT" plan
  [[ "$output" != *"#16"* ]]
}

@test "block: tier 3 sin revisión de seguridad no entra; con ella sí" {
  mkpr 17 "scripts/auth-helper.sh"
  review 17 APPROVE correctness
  run bash "$SCRIPT" plan
  [[ "$output" != *"#17"* ]]
  review 17 APPROVE security rev-sec
  run bash "$SCRIPT" plan
  [[ "$output" == *"#17(t3)"* ]]
}

@test "boundary: tier 4 (gobernanza) nunca entra en el manifiesto" {
  mkpr 18 "config/merge-sprint-policy.conf"; review 18 APPROVE correctness; review 18 APPROVE security rev-sec
  run bash "$SCRIPT" plan
  [[ "$output" != *"#18"* ]]
}

@test "fail: CI roja aparca el PR y no mergea" {
  mkpr 19 "scripts/g.sh"; review 19 APPROVE correctness; echo fail > "$FAKE/19.checks"
  plan_and_grant
  run bash "$SCRIPT" run
  [ ! -s "$FAKE/merged" ]
  grep -q '"reason":"ci_roja"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "fail: main roja tras el merge para el sprint sin seguir" {
  mkpr 20 "scripts/h.sh"; mkpr 21 "scripts/i.sh"
  review 20 APPROVE correctness; review 21 APPROVE correctness; echo fail > "$FAKE/main_ci"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/merged")" = "20" ]
  [[ "$output" == *"STOP"* ]]
}

@test "block: STOP manual impide cualquier merge" {
  mkpr 22 "scripts/j.sh"; review 22 APPROVE correctness
  plan_and_grant
  bash "$SCRIPT" stop
  run bash "$SCRIPT" run
  [ ! -s "$FAKE/merged" ]
}

@test "block: head cambiado tras la revisión aparca el PR" {
  mkpr 23 "scripts/k.sh"; review 23 APPROVE correctness
  plan_and_grant
  printf '%040d' 9 > "$FAKE/23.head"
  run bash "$SCRIPT" run
  [ ! -s "$FAKE/merged" ]
}

@test "invalid: manifiesto alterado tras el grant aborta el run" {
  mkpr 24 "scripts/l.sh"; review 24 APPROVE correctness
  plan_and_grant
  echo '{"prs":[]}' > "$MERGE_SPRINT_HOME/manifest.json"
  run bash "$SCRIPT" run
  [ "$status" -eq 4 ]
}

@test "invalid: grant con digest distinto del manifiesto se rechaza" {
  mkpr 25 "scripts/m.sh"; review 25 APPROVE correctness
  bash "$SCRIPT" plan
  run bash "$SCRIPT" grant 0000
  [ "$status" -eq 3 ]
}

@test "invalid: ledger manipulado se detecta y el run aborta" {
  mkpr 26 "scripts/n.sh"; review 26 APPROVE correctness
  plan_and_grant
  sed -i '1s/GRANT/XXXXX/' "$MERGE_SPRINT_HOME/ledger.jsonl"
  echo '{"event":"x","prev":"bad"}' >> "$MERGE_SPRINT_HOME/ledger.jsonl"
  run bash "$SCRIPT" run
  [ "$status" -eq 4 ]
}

@test "boundary: max_merges=1 mergea solo uno" {
  sed -i 's/max_merges=40/max_merges=1/' "$MERGE_SPRINT_POLICY"
  mkpr 27 "scripts/o.sh"; mkpr 28 "scripts/p.sh"
  review 27 APPROVE correctness; review 28 APPROVE correctness
  plan_and_grant
  bash "$SCRIPT" run
  [ "$(wc -l < "$FAKE/merged")" -eq 1 ]
}

@test "error: política ausente falla cerrado" {
  rm -f "$MERGE_SPRINT_POLICY"
  run bash "$SCRIPT" plan
  [ "$status" -eq 2 ]
}

@test "empty: sin grant el run no mergea nada" {
  mkpr 29 "scripts/q.sh"; review 29 APPROVE correctness
  run bash "$SCRIPT" run
  [ "$status" -eq 3 ]
  [ ! -e "$FAKE/merged" ]
}

@test "error: revisión modificada tras registrarla invalida el PR" {
  mkpr 30 "scripts/r.sh"; review 30 APPROVE correctness
  for f in "$MERGE_SPRINT_HOME"/reviews/30-*; do echo "x" >> "$f"; done
  run bash "$SCRIPT" plan
  [[ "$output" != *"#30"* ]]
}

# ── v2: re-sync autónomo con main (repo git temporal con remoto bare; nunca GitHub) ──
v2_repo() { export MERGE_SPRINT_RESYNC=1; }
v2_pr() {  # v2_pr <n> <fichero> <contenido> : rama pr-<n> con un commit; registra la revisión sobre su head
  G switch -q -c "pr-$1" main; mkdir -p "$(dirname "$MERGE_SPRINT_GIT_ROOT/$2")"; echo "$3" > "$MERGE_SPRINT_GIT_ROOT/$2"; G add "$2"; G commit -qm "pr $1"; G push -q origin "pr-$1"; G switch -q main
  echo "pr-$1" > "$FAKE/$1.branch"; echo x > "$FAKE/$1.head"; echo "scripts/x$1.sh" > "$FAKE/$1.files"
  local s; s=$(git --git-dir="$BARE" rev-parse "refs/heads/pr-$1")
  echo "VERDICT: APPROVE pr=$1 sha=$s role=correctness tier=2 reviewer=rev-agent author=impl-agent p0=0 p1=0 p2=0 p2_blocking=0" > "$TMPDIR_T/r$1.md"
  bash "$SCRIPT" review-register "$1" "$TMPDIR_T/r$1.md"
}
main_moves() {  # main_moves <fichero> <contenido>
  echo "$2" > "$MERGE_SPRINT_GIT_ROOT/$1"; G add "$1"; G commit -qm "main $1"; G push -q origin main
}

@test "v2 positivo: PR desfasado sin conflicto se re-sincroniza, se empuja y se mergea" {
  v2_repo; v2_pr 40 b.txt pr40
  main_moves c.txt main1
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 40 "$FAKE/merged"
  git --git-dir="$BARE" merge-base --is-ancestor refs/heads/main refs/heads/pr-40
  grep -q '"event":"RESYNC"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "v2 conflict: conflicto real fuera de derivados aparca el PR sin mergear ni empujar" {
  v2_repo; v2_pr 41 a.txt pr41
  main_moves a.txt main-cambia-a
  local before; before=$(git --git-dir="$BARE" rev-parse refs/heads/pr-41)
  plan_and_grant
  run bash "$SCRIPT" run
  [ ! -e "$FAKE/merged" ]
  grep -q '"reason":"conflicto_real"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/pr-41)" = "$before" ]
}

@test "v2 block: commit de código posterior a la revisión en un path de tier 3 para el sprint (prefiltro del juez)" {
  v2_repo; v2_pr 42 d.txt pr42
  plan_and_grant
  G switch -q pr-42; echo cambio-colado >> "$MERGE_SPRINT_GIT_ROOT/d.txt"; G commit -qam sneaky; G push -q origin pr-42; G switch -q main
  main_moves e.txt main2
  run bash "$SCRIPT" run
  [ ! -e "$FAKE/merged" ]
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_tier"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "boundary: 12 registros concurrentes dejan la cadena íntegra (cerrojo en chain_append)" {
  local n
  for n in $(seq 50 61); do mkpr "$n" "scripts/c$n.sh"; done
  for n in $(seq 50 61); do review "$n" APPROVE correctness >/dev/null & done
  wait
  [ "$(wc -l < "$MERGE_SPRINT_HOME/reviews.jsonl")" -eq 12 ]
  run bash "$SCRIPT" verify-ledger
  [ "$status" -eq 0 ]
}

@test "v3 positivo: main avanza tras el resync, el merge se rechaza por desfase y al reintentar se mergea" {
  v2_repo; v2_pr 50 f.txt pr50
  echo 1 > "$FAKE/50.reject"; echo DIRTY > "$FAKE/50.mss"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 50 "$FAKE/merged"
  grep -q '"event":"RETRY"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "v3 boundary: desfase persistente agota MERGE_SPRINT_TRIES y aparca sin mergear" {
  v2_repo; v2_pr 51 g.txt pr51
  echo 9 > "$FAKE/51.reject"; echo BEHIND > "$FAKE/51.mss"
  export MERGE_SPRINT_TRIES=2
  plan_and_grant
  run bash "$SCRIPT" run
  [ ! -e "$FAKE/merged" ]
  [ "$(grep -c '"event":"RETRY"' "$MERGE_SPRINT_HOME/ledger.jsonl")" -eq 2 ]
  grep -q '"reason":"main_movido_sin_converger"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "v3 block: merge rechazado sin desfase (CLEAN) aparca como merge_rechazado sin reintentar" {
  v2_repo; v2_pr 52 h.txt pr52
  echo 1 > "$FAKE/52.reject"
  plan_and_grant
  run bash "$SCRIPT" run
  [ ! -e "$FAKE/merged" ]
  ! grep -q '"event":"RETRY"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
  grep -q '"reason":"merge_rechazado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "v3 positivo: conflicto solo en el índice de reglas se trata como derivado y se mergea" {
  v2_repo; mkdir -p "$MERGE_SPRINT_GIT_ROOT/docs/rules"
  main_moves docs/rules/INDEX.md base-index
  v2_pr 53 docs/rules/INDEX.md index-pr53
  main_moves docs/rules/INDEX.md index-main
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 53 "$FAKE/merged"
  ! grep -q '"reason":"conflicto_real"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
}

pr_absorbs_main() {  # pr_absorbs_main <n> : el workflow remoto integra main en la rama del PR (merge, sin código propio)
  G switch -q "pr-$1"; G merge -q --no-edit main; G push -q origin "pr-$1"; G switch -q main
}

@test "v3 positivo: plan admite el PR si el head solo absorbió main tras la revisión (manifiesto con el sha revisado)" {
  v2_repo; v2_pr 60 i.txt pr60
  local reviewed; reviewed=$(git --git-dir="$BARE" rev-parse refs/heads/pr-60)
  main_moves j.txt main60; pr_absorbs_main 60
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"#60"* ]]
  grep -q "\"head\":\"$reviewed\"" "$MERGE_SPRINT_HOME/manifest.json"
}

@test "v3 block: plan excluye el PR si tras la revisión entró código propio aunque también absorbiera main" {
  v2_repo; v2_pr 61 k.txt pr61
  G switch -q pr-61; echo colado >> "$MERGE_SPRINT_GIT_ROOT/k.txt"; G commit -qam sneaky; G push -q origin pr-61; G switch -q main
  main_moves l.txt main61; pr_absorbs_main 61
  run bash "$SCRIPT" plan
  [[ "$output" != *"#61"* ]]
}

fake_scanner() {  # fake_scanner <salida> <exit> : escáner y firmador falsos en main del repo temporal
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/scripts"
  printf '#!/usr/bin/env bash\necho "%s"; exit %s\n' "$1" "$2" > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-scan.sh"
  printf '#!/usr/bin/env bash\ndate +%%s%%N > .confidentiality-signature\n' > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-sign.sh"
  G add scripts; G commit -qm "escáner falso"; G push -q origin main
}

@test "v3 positivo: escáner CLEAN sin avisos (exit 0) cuenta como aprobado y el PR se mergea" {
  v2_repo; fake_scanner "CLEAN — no violations" 0
  v2_pr 70 m.txt pr70
  main_moves n.txt main70
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 70 "$FAKE/merged"
  ! grep -q '"reason":"confidencialidad"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
}

@test "v3 block: escáner con violaciones (exit 1) aparca por confidencialidad aunque imprima PASSED" {
  v2_repo; fake_scanner "BLOCKED — PASSED es parte del texto" 1
  v2_pr 71 o.txt pr71
  main_moves p.txt main71
  plan_and_grant
  run bash "$SCRIPT" run
  [ ! -e "$FAKE/merged" ]
  grep -q '"reason":"confidencialidad"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

fake_sam() {  # SAM falso que, como el real, registra el último commit de .scm/registry.json
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/scripts"
  cat > "$MERGE_SPRINT_GIT_ROOT/scripts/generate-capability-map.py" <<'PY'
import os, time
os.makedirs(".scm", exist_ok=True)
open(".scm/registry.json", "w").write(str(time.time_ns()))
PY
  cat > "$MERGE_SPRINT_GIT_ROOT/scripts/sam.py" <<'PY'
import os, subprocess, sys
cur = subprocess.run(["git", "log", "-1", "--format=%H", "--", ".scm/registry.json"], capture_output=True, text=True).stdout.strip()
if sys.argv[1] == "generate":
    os.makedirs(".scm", exist_ok=True); open(".scm/sam.json", "w").write(cur)
else:
    print("SAM: FRESH" if os.path.exists(".scm/sam.json") and open(".scm/sam.json").read() == cur else "SAM: STALE")
PY
  G add scripts; G commit -qm "SAM falso"; G push -q origin main
}

@test "v3 positivo: el resync deja el SAM FRESH sobre el árbol commiteado (registry regenerado en el mismo paso)" {
  v2_repo; fake_sam
  v2_pr 80 q.txt pr80
  main_moves r.txt main80
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 80 "$FAKE/merged"
  local t="$TMPDIR_T/chk"; git clone -q -b pr-80 "$BARE" "$t"
  [ "$(cd "$t" && python3 scripts/sam.py check)" = "SAM: FRESH" ]
}

# ── v4: anomalías del run, vuelta a Draft, etiqueta de auto-rebase y reservas F5 ──

@test "AC-16 error: plan sin checks obligatorios en la protección de main falla cerrado" {
  mkpr 90 "scripts/s.sh"; review 90 APPROVE correctness; : > "$FAKE/required"
  run bash "$SCRIPT" plan
  [ "$status" -eq 4 ]
  [ ! -e "$MERGE_SPRINT_HOME/manifest.json" ]
}

@test "AC-16 block: checks obligatorios vivos reducidos o vacíos paran el sprint sin merge" {
  printf 'CI\nsecurity\n' > "$FAKE/required"
  mkpr 91 "scripts/t.sh"; review 91 APPROVE correctness
  plan_and_grant
  grep -q '"required_checks":\["CI","security"\]' "$MERGE_SPRINT_HOME/manifest.json"
  echo CI > "$FAKE/required"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ ! -e "$FAKE/merged" ]
  grep -q '"reason":"checks_obligatorios_reducidos"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  : > "$FAKE/required"; regrant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"checks_obligatorios_vacios"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-17 block: ejecutor distinto del blob del manifiesto para el sprint" {
  echo "# otra versión" >> "$MERGE_SPRINT_GIT_ROOT/scripts/merge-sprint.sh"; G commit -qam "ejecutor cambiado"; G push -q origin main
  mkpr 92 "scripts/u.sh"; review 92 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ ! -e "$FAKE/merged" ]
  grep -q '"reason":"blob_ejecutor"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-17 block: clasificador distinto del blob del manifiesto para el sprint" {
  echo "# otra versión" >> "$MERGE_SPRINT_GIT_ROOT/scripts/risk-tier.py"; G commit -qam "clasificador cambiado"; G push -q origin main
  mkpr 93 "scripts/v.sh"; review 93 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ ! -e "$FAKE/merged" ]
  grep -q '"reason":"blob_clasificador"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-17 block: revoke entre dos merges impide el siguiente" {
  mkpr 94 "scripts/w.sh"; mkpr 95 "scripts/x.sh"
  review 94 APPROVE correctness; review 95 APPROVE correctness
  echo "bash '$PWD/$SCRIPT' revoke" > "$FAKE/94.on_merge"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]   # spec §2.5 y AC: grant revocado es anomalía, exit ≠ 0
  [ "$(paste -sd, "$FAKE/merged")" = "94" ]
  grep -q '"reason":"grant_revocado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-18 block: PR reapuntado a otra base para el sprint por anomalía" {
  mkpr 96 "scripts/y.sh"; review 96 APPROVE correctness
  plan_and_grant
  echo develop > "$FAKE/96.base"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ ! -e "$FAKE/merged" ]
  grep -q '"reason":"pr_alterado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-18 block: PR con otro repo de head o cerrado y reabierto para el sprint" {
  mkpr 97 "scripts/z.sh"; review 97 APPROVE correctness
  plan_and_grant
  echo fork/repo > "$FAKE/97.repo"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  mv "$FAKE/97.repo" "$TMPDIR_T/97.repo.old"; echo 1 > "$FAKE/97.reopens"; regrant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ ! -e "$FAKE/merged" ]
  [ "$(grep -c '"reason":"pr_alterado"' "$MERGE_SPRINT_HOME/ledger.jsonl")" -eq 2 ]
}

@test "AC-22 positivo: PR aparcado tras gh pr ready vuelve a Draft; sin ready no se toca" {
  mkpr 98 "scripts/aa.sh"; review 98 APPROVE correctness; echo 1 > "$FAKE/98.reject"
  mkpr 99 "scripts/ab.sh"; review 99 APPROVE correctness; echo fail > "$FAKE/99.checks"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -q '"reason":"merge_rechazado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  grep -qx 'pr ready 98 -R .* --undo' "$FAKE/calls"
  ! grep -q 'pr ready 99' "$FAKE/calls" || false
}

@test "AC-23 positivo: se etiquetan los PRs del manifiesto antes del primer merge y al terminar se retira la etiqueta de los no mergeados" {
  mkpr 100 "scripts/ac.sh"; review 100 APPROVE correctness
  mkpr 101 "scripts/ad.sh"; review 101 APPROVE correctness; echo fail > "$FAKE/101.checks"
  plan_and_grant
  local id; id=$(sha256sum < "$MERGE_SPRINT_HOME/manifest.json" | cut -c1-12)
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -q "api -X POST repos/.*/issues/100/labels -f labels\[\]=merge-sprint:$id" "$FAKE/calls"
  grep -q "api -X POST repos/.*/issues/101/labels -f labels\[\]=merge-sprint:$id" "$FAKE/calls"
  [ "$(grep -n -- "/labels -f labels" "$FAKE/calls" | tail -1 | cut -d: -f1)" -lt "$(grep -n '^pr merge' "$FAKE/calls" | head -1 | cut -d: -f1)" ]
  grep -q "api -X DELETE repos/.*/issues/101/labels/merge-sprint:$id" "$FAKE/calls"
  ! grep -q "api -X DELETE repos/.*/issues/100/labels" "$FAKE/calls" || false
}

auto_rebase_list_step() {  # ejecuta el paso «List open PRs» del workflow real con un gh simulado
  python3 -c 'import sys,yaml
w=yaml.safe_load(open(".github/workflows/auto-rebase-open-prs.yml"))
print(next(s["run"] for s in w["jobs"]["rebase"]["steps"] if s.get("name")=="List open PRs"))' > "$TMPDIR_T/step.sh"
  mkdir -p "$TMPDIR_T/wf"
  printf '#!/usr/bin/env bash\ncat "%s"\n' "$TMPDIR_T/prs.json" > "$TMPDIR_T/wf/gh"; chmod +x "$TMPDIR_T/wf/gh"
  : > "$TMPDIR_T/gh_output"
  PATH="$TMPDIR_T/wf:$PATH" GITHUB_OUTPUT="$TMPDIR_T/gh_output" bash "$TMPDIR_T/step.sh"
}

@test "AC-23 positivo: el workflow de auto-rebase omite los PRs con etiqueta merge-sprint:<id>" {
  cat > "$TMPDIR_T/prs.json" <<'JSON'
[{"number":7,"headRefName":"a","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","labels":[{"name":"merge-sprint:abc123abc123"}]},
 {"number":8,"headRefName":"b","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","labels":[{"name":"bug"}]},
 {"number":9,"headRefName":"c","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","labels":[]}]
JSON
  run auto_rebase_list_step
  [ "$status" -eq 0 ]
  local prs; prs=$(sed -n '/^prs<<EOF$/,/^EOF$/p' "$TMPDIR_T/gh_output" | sed '1d;$d')
  [ "$(jq -c '[.[].number]' <<<"$prs")" = "[8,9]" ]
}

@test "AC-25 boundary: dos run concurrentes, el segundo termina con error sin tocar nada" {
  mkpr 102 "scripts/ae.sh"; review 102 APPROVE correctness
  plan_and_grant
  exec 7>"$MERGE_SPRINT_HOME/run.lock"; flock -n 7
  run bash "$SCRIPT" run
  exec 7>&-
  [ "$status" -eq 3 ]
  [[ "$output" == *"otro sprint en curso"* ]]
  [ ! -e "$FAKE/merged" ]
}

@test "AC-25 positivo: proceso muerto entre el merge y el ledger; el siguiente run reconcilia con la reserva F5" {
  mkpr 103 "scripts/af.sh"; mkpr 104 "scripts/ag.sh"
  review 103 APPROVE correctness; review 104 APPROVE correctness
  echo 'kill -9 $GHPPID' > "$FAKE/103.on_merge"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -ne 0 ]
  ! grep -q '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
  mv "$FAKE/103.on_merge" "$TMPDIR_T/103.on_merge.old"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep '"pr":"103"' | grep -q '"equivalence":"reconciled"'
  ! grep -q '"reason":"merge_externo"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
  [ "$(paste -sd, "$FAKE/merged")" = "103,104" ]
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["merged"])' "$MERGE_SPRINT_HOME/grant.json")" -eq 2 ]
}

@test "AC-26 block: PR del manifiesto mergeado sin reserva de este grant para el sprint por anomalía" {
  mkpr 105 "scripts/ah.sh"; mkpr 106 "scripts/ai.sh"
  review 105 APPROVE correctness; review 106 APPROVE correctness
  plan_and_grant
  echo MERGED > "$FAKE/105.state"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"merge_externo"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "AC-20 block: fichero STOP creado entre los checks y el merge impide el merge" {
  mkpr 107 "scripts/aj.sh"; review 107 APPROVE correctness
  plan_and_grant
  # el gh falso crea el STOP justo al responder la consulta de checks
  echo "touch '$MERGE_SPRINT_HOME/STOP'" > "$FAKE/checks_hook"
  sed -i 's|"pr checks") printf|"pr checks") [[ -f "$F/checks_hook" ]] \&\& bash "$F/checks_hook"; printf|' "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE/merged" ]
  grep -q '"reason":"stop_antes_de_merge"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

# ── v5: juez de cambios posteriores al grant (§2.7) ──
jpr() {  # jpr <n> <fichero> <contenido> : PR v2 cuyo diff declarado es el fichero real
  v2_repo; v2_pr "$1" "$2" "$3"; echo "$2" > "$FAKE/$1.files"
}
fix_commit() {  # fix_commit <n> <orden> : commit del agente «fixer» en la rama del PR
  G switch -q "pr-$1"; (cd "$MERGE_SPRINT_GIT_ROOT" && eval "$2")
  G add -A; git -C "$MERGE_SPRINT_GIT_ROOT" -c user.email=f@f -c user.name=fixer -c commit.gpgsign=false commit -qm fix
  G push -q origin "pr-$1"; G switch -q main
}
no_request() { ! compgen -G "$MERGE_SPRINT_HOME/judge/*/*.request.json" >/dev/null; }

@test "AC-11 block: delta que toca un fichero fuera de files para sin solicitar al juez" {
  v2_repo; main_moves scripts/otro.sh base
  jpr 110 scripts/d.sh l1; plan_and_grant
  fix_commit 110 'echo otro >> scripts/otro.sh'
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_fuera_de_files"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request; [ ! -e "$FAKE/merged" ]
}

@test "AC-11 block: delta que toca un path de gobernanza para sin solicitar al juez" {
  jpr 111 scripts/d.sh l1; plan_and_grant
  fix_commit 111 'echo "# x" >> scripts/risk-tier.py'
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_tier"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request
}

@test "AC-11 block: delta que añade un fichero para sin solicitar al juez" {
  jpr 112 scripts/d.sh l1; plan_and_grant
  fix_commit 112 'echo nuevo > scripts/nuevo.sh'
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_alta_baja"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request
}

@test "AC-11 block: delta que elimina un @test para sin solicitar al juez" {
  jpr 113 tests/t.bats $'@test "a" {\n  [ 1 -eq 1 ]\n}\n@test "b" {\n  true\n}'
  plan_and_grant
  fix_commit 113 "sed -i '4,6d' tests/t.bats"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_tests_eliminados"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request
}

@test "AC-11 boundary: delta de más de 200 líneas para; uno de 200 se solicita al juez" {
  jpr 114 scripts/d.sh l1; plan_and_grant
  fix_commit 114 'seq 1 201 >> scripts/d.sh'
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_tamano"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request
}

@test "AC-11 boundary: delta de 200 líneas en un fichero del PR pasa el prefiltro y queda awaiting_judge" {
  export MERGE_SPRINT_JUDGE_POLLS=1
  jpr 115 scripts/d.sh l1; plan_and_grant
  fix_commit 115 'seq 1 200 >> scripts/d.sh'
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [[ "$output" == *"espera al juez"* ]]
  ls "$MERGE_SPRINT_HOME"/judge/*/115-*.request.json
  grep -q '"event":"JUDGE_REQUEST"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

judge_setup() {  # judge_setup <n> : PR con commit de arreglo tras el grant, solicitud emitida y sprint en pausa
  export MERGE_SPRINT_JUDGE_POLLS=1
  jpr "$1" scripts/d.sh l1; plan_and_grant
  H0=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["prs"][0]["head"])' "$MERGE_SPRINT_HOME/manifest.json")
  fix_commit "$1" 'echo l2 >> scripts/d.sh'
  H1=$(git --git-dir="$BARE" rev-parse "refs/heads/pr-$1")
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [[ "$output" == *"espera al juez"* ]]
  grep -q '"event":"PAUSE"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}
verdict() {  # verdict <n> <línea> : registra un veredicto del juez
  local f; f=$(mktemp "$TMPDIR_T/v.XXXX"); echo "$2" > "$f"
  bash "$SCRIPT" review-register "$1" "$f"
}
safe_line() { echo "JUDGE: SAFE pr=$1 from=$H0 to=$H1 judge=${2:-judge-agent} fix_author=f@f scope=unchanged security=unchanged reason=${3:-implementa_p2}"; }

@test "AC-12 positivo: SAFE válido → CI nueva sobre to y merge con --match-head-commit to; manifiesto y grant intactos" {
  judge_setup 120
  local mbefore; mbefore=$(sha256sum < "$MERGE_SPRINT_HOME/manifest.json")
  local gbefore; gbefore=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("merged"); print(json.dumps(d,sort_keys=True))' "$MERGE_SPRINT_HOME/grant.json")
  verdict 120 "$(safe_line 120)"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 120 "$FAKE/merged"
  grep -q "pr merge 120 .*--match-head-commit $H1" "$FAKE/calls"
  grep '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep -q '"equivalence":"judge_safe"'
  [ "$(sha256sum < "$MERGE_SPRINT_HOME/manifest.json")" = "$mbefore" ]
  [ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("merged"); print(json.dumps(d,sort_keys=True))' "$MERGE_SPRINT_HOME/grant.json")" = "$gbefore" ]
}

@test "AC-12 block: veredicto STOP del juez para el sprint" {
  judge_setup 121
  verdict 121 "JUDGE: STOP pr=121 from=$H0 to=$H1 judge=judge-agent fix_author=f@f scope=changed security=unchanged reason=amplia"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_stop"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "AC-12 block: SAFE con scope=changed cuenta como STOP" {
  judge_setup 122
  verdict 122 "JUDGE: SAFE pr=122 from=$H0 to=$H1 judge=judge-agent fix_author=f@f scope=changed security=unchanged reason=x"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_stop"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-12 invalid: veredicto con formato inválido para el sprint" {
  judge_setup 123
  verdict 123 "JUDGE: SAFE pr=123 from=$H0 to=$H1 judge=judge-agent"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_formato"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "AC-12 invalid: from o to erróneos paran el sprint" {
  judge_setup 124
  local h0=$H0; H0=$(printf '%040d' 1)
  verdict 124 "$(safe_line 124)"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_from_to"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "AC-12 block: judge igual al email git del autor del arreglo para el sprint (id ≠ email: límite declarado)" {
  judge_setup 125
  verdict 125 "$(safe_line 125 f@f)"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_no_independiente"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-12 block: judge igual al autor original o al orquestador para el sprint" {
  judge_setup 126
  verdict 126 "$(safe_line 126 impl-agent)"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_no_independiente"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-12 block: dos veredictos para el mismo (pr, to) paran el sprint" {
  judge_setup 127
  verdict 127 "$(safe_line 127 judge-a r1)"; verdict 127 "$(safe_line 127 judge-b r2)"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_duplicado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "AC-12 block: plazo del juez vencido sin veredicto para el sprint" {
  export MERGE_SPRINT_JUDGE_MIN=0 MERGE_SPRINT_JUDGE_POLLS=1
  jpr 128 scripts/d.sh l1; plan_and_grant
  fix_commit 128 'echo l2 >> scripts/d.sh'
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_plazo"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "AC-12 error: veredicto alterado tras registrarlo para el sprint" {
  judge_setup 129
  verdict 129 "$(safe_line 129)"
  for f in "$MERGE_SPRINT_HOME"/judge/129-*.verdict.md; do echo x >> "$f"; done
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_alterado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

# ── v6: correcciones de la revisión independiente de la PR #1375 ──

@test "AC-26 block: merge rechazado y luego mergeado fuera del sprint no se reconcilia como propio" {
  mkpr 140 "scripts/ba.sh"; review 140 APPROVE correctness; echo 1 > "$FAKE/140.reject"
  plan_and_grant
  run bash "$SCRIPT" run
  grep -q '"reason":"merge_rechazado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  echo MERGED > "$FAKE/140.state"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"merge_externo"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  ! grep -q '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
}

@test "AC-26 block: reserva submitted con merge real de otro head o de otra cuenta para por merge_externo" {
  mkpr 141 "scripts/bb.sh"; review 141 APPROVE correctness
  echo 'kill -9 $GHPPID' > "$FAKE/141.on_merge"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -ne 0 ]
  mv "$FAKE/141.on_merge" "$TMPDIR_T/141.on_merge.old"
  printf '%040d' 7 > "$FAKE/141.head"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  sha_of 141 > "$FAKE/141.head"; echo otra-cuenta > "$FAKE/141.merged_by"; regrant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ "$(grep -c '"reason":"merge_externo"' "$MERGE_SPRINT_HOME/ledger.jsonl")" -eq 2 ]
  ! grep -q '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
}

@test "§2.7 boundary: commit nuevo tras una solicitud al juez la deja obsoleta y se solicita el head nuevo" {
  judge_setup 142
  fix_commit 142 'echo l3 >> scripts/d.sh'
  local h2; h2=$(git --git-dir="$BARE" rev-parse refs/heads/pr-142)
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [[ "$output" == *"espera al juez"* ]]
  [ -n "$(find "$MERGE_SPRINT_HOME/judge" -name "142-$h2.request.json")" ]
}

@test "§2.7 boundary: una solicitud caducada de un grant anterior no bloquea el grant nuevo del mismo manifiesto" {
  judge_setup 143
  local f; f=$(find "$MERGE_SPRINT_HOME/judge" -name '143-*.request.json')
  python3 -c 'import json,sys; q=json.load(open(sys.argv[1])); q["requested_epoch"]-=7200; json.dump(q,open(sys.argv[1],"w"))' "$f"
  run bash "$SCRIPT" grant "$(sha256sum < "$MERGE_SPRINT_HOME/manifest.json" | cut -d' ' -f1)"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [[ "$output" == *"espera al juez"* ]]
  ! grep -q '"reason":"judge_plazo"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
  [ "$(find "$MERGE_SPRINT_HOME/judge" -name '143-*.request.json' | wc -l)" -eq 2 ]
}

@test "D6 positivo: en pausa awaiting_judge el PR conserva la etiqueta; un STOP del juez la retira" {
  judge_setup 144
  grep -q "api -X POST repos/.*/issues/144/labels -f labels\[\]=merge-sprint:" "$FAKE/calls"
  ! grep -q "api -X DELETE repos/.*/issues/144/labels" "$FAKE/calls" || false
  verdict 144 "JUDGE: STOP pr=144 from=$H0 to=$H1 judge=judge-agent fix_author=f@f scope=changed security=unchanged reason=amplia"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q "api -X DELETE repos/.*/issues/144/labels/merge-sprint:" "$FAKE/calls"
}

@test "AC-22 boundary: PR que ya no era Draft no se toca con ready ni vuelve a Draft al aparcarse" {
  mkpr 145 "scripts/bc.sh"; review 145 APPROVE correctness; echo 1 > "$FAKE/145.reject"; echo false > "$FAKE/145.draft"
  plan_and_grant
  run bash "$SCRIPT" run
  grep -q '"reason":"merge_rechazado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  ! grep -q 'pr ready 145' "$FAKE/calls" || false
}

@test "§2.7 boundary: un derivado grande en el delta no rompe la solicitud al juez ni viaja en su diff" {
  export MERGE_SPRINT_JUDGE_POLLS=1
  jpr 146 scripts/d.sh l1; plan_and_grant
  fix_commit 146 'mkdir -p .scm && python3 -c "print(\"x\"*300000)" > .scm/big.json && echo l2 >> scripts/d.sh'
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [[ "$output" == *"espera al juez"* ]]
  local f; f=$(find "$MERGE_SPRINT_HOME/judge" -name '146-*.request.json')
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["diff"]; assert "scripts/d.sh" in d and ".scm/" not in d' "$f"
}

@test "AC-11 block: borrar una línea cuyo contenido empieza por «--assert» cuenta como aserción eliminada" {
  jpr 147 tests/t.sh $'echo a\n--assert x\necho b'
  plan_and_grant
  fix_commit 147 "sed -i '2d' tests/t.sh"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_tests_eliminados"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request
}

@test "AC-11 block: añadir skip a un test lo debilita y para sin solicitar al juez" {
  jpr 148 tests/t.bats $'@test "a" {\n  [ 1 -eq 1 ]\n}'
  plan_and_grant
  fix_commit 148 "sed -i '2i\\  skip \"luego\"' tests/t.bats"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_tests_debilitados"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request
}

@test "AC-12 block: judge igual al orquestador (savia-orquestadora) para el sprint" {
  judge_setup 149
  verdict 149 "$(safe_line 149 savia-orquestadora)"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_no_independiente"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "AC-12 block: fix_author del veredicto distinto del autor real del arreglo para el sprint" {
  judge_setup 150
  verdict 150 "JUDGE: SAFE pr=150 from=$H0 to=$H1 judge=judge-agent fix_author=otro@x scope=unchanged security=unchanged reason=x"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_fix_author"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "AC-12 block: veredicto registrado después del plazo para el sprint" {
  judge_setup 151
  sleep 1; verdict 151 "$(safe_line 151)"
  export MERGE_SPRINT_JUDGE_MIN=0
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_plazo"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "D6 positivo: plan borra etiquetas merge-sprint huérfanas, nunca la del grant vigente ni otras; con un run en curso no toca nada" {
  mkpr 152 "scripts/bd.sh"; review 152 APPROVE correctness
  plan_and_grant
  local id; id=$(sha256sum < "$MERGE_SPRINT_HOME/manifest.json" | cut -c1-12)
  printf 'merge-sprint:aaaaaaaaaaaa\nmerge-sprint:%s\nbug\n' "$id" > "$FAKE/labels"
  exec 7>"$MERGE_SPRINT_HOME/run.lock"; flock -n 7
  run bash "$SCRIPT" plan
  exec 7>&-
  ! grep -q '^label delete' "$FAKE/calls" || false
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  grep -q '^label delete merge-sprint:aaaaaaaaaaaa ' "$FAKE/calls"
  ! grep -q "^label delete merge-sprint:$id" "$FAKE/calls" || false
  ! grep -q '^label delete bug' "$FAKE/calls" || false
}

# ── v7: segunda revisión independiente de la PR #1375 ──

@test "AC-18 block: base cambiada mientras se espera al juez para el sprint antes del merge de la cola" {
  judge_setup 160
  verdict 160 "$(safe_line 160)"
  # el gh falso reapunta la base al responder la consulta de checks de la cola (después del bucle principal)
  echo "echo develop > '$FAKE/160.base'" > "$FAKE/checks_hook"
  sed -i 's|"pr checks") printf|"pr checks") [[ -f "$F/checks_hook" ]] \&\& bash "$F/checks_hook"; printf|' "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"pr_alterado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
  ! grep -q '^pr merge 160' "$FAKE/calls" || false
}

@test "AC-18 positivo: sin cambios de metadatos durante la espera de CI el merge sigue adelante" {
  mkpr 161 "scripts/ca.sh"; review 161 APPROVE correctness
  plan_and_grant
  echo "true" > "$FAKE/checks_hook"
  sed -i 's|"pr checks") printf|"pr checks") [[ -f "$F/checks_hook" ]] \&\& bash "$F/checks_hook"; printf|' "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 161 "$FAKE/merged"
}

@test "AC-18 block: repo de head cambiado durante la espera de CI del bucle principal para el sprint" {
  mkpr 162 "scripts/cb.sh"; review 162 APPROVE correctness
  plan_and_grant
  echo "echo fork/otro > '$FAKE/162.repo'" > "$FAKE/checks_hook"
  sed -i 's|"pr checks") printf|"pr checks") [[ -f "$F/checks_hook" ]] \&\& bash "$F/checks_hook"; printf|' "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"pr_alterado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "boundary: revoke espera al cerrojo del contador y no se pierde ni se recrea el grant" {
  mkpr 163 "scripts/cc.sh"; review 163 APPROVE correctness
  plan_and_grant
  exec 7>"$MERGE_SPRINT_HOME/grant.json.lock"; flock -n 7
  run timeout 2 bash "$SCRIPT" revoke
  exec 7>&-
  [ "$status" -eq 124 ]
  [ -f "$MERGE_SPRINT_HOME/grant.json" ]
  run bash "$SCRIPT" revoke
  [ "$status" -eq 0 ]
  [ ! -f "$MERGE_SPRINT_HOME/grant.json" ]
}

@test "boundary: plan omite un PR con fork borrado (repo de head «/») sin vaciar el manifiesto" {
  mkpr 164 "scripts/cd.sh"; review 164 APPROVE correctness; echo / > "$FAKE/164.repo"
  mkpr 165 "scripts/ce.sh"; review 165 APPROVE correctness
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [[ "$output" != *"#164"* ]]
  [[ "$output" == *"#165(t"* ]]
}

@test "positivo: PR cerrado con fork borrado durante el sprint se aparca y el siguiente se mergea" {
  mkpr 166 "scripts/cf.sh"; review 166 APPROVE correctness
  mkpr 167 "scripts/cg.sh"; review 167 APPROVE correctness
  plan_and_grant
  echo CLOSED > "$FAKE/166.state"; echo / > "$FAKE/166.repo"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -q '"reason":"no_abierto"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ "$(paste -sd, "$FAKE/merged")" = "167" ]
}

@test "AC-11 positivo: borrar un comentario con «should» fuera de los tests no cuenta como aserción eliminada" {
  export MERGE_SPRINT_JUDGE_POLLS=1
  jpr 168 scripts/d.sh $'echo a\n# this should go\necho b'
  plan_and_grant
  fix_commit 168 "sed -i '2d' scripts/d.sh"
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [[ "$output" == *"espera al juez"* ]]
  ! grep -q '"reason":"judge_prefiltro_tests_eliminados"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
}

@test "AC-11 block: borrar una línea con «should» en un fichero de test sigue contando como aserción eliminada" {
  jpr 169 tests/t.sh $'echo a\nresult should be 1\necho b'
  plan_and_grant
  fix_commit 169 "sed -i '2d' tests/t.sh"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_prefiltro_tests_eliminados"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request
}

@test "D6 boundary: solo se borran etiquetas merge-sprint:<12 hex>; ni «merge-sprint:x bug», ni comodines, ni «bug»" {
  mkpr 170 "scripts/ch.sh"; review 170 APPROVE correctness
  printf 'merge-sprint:x bug\nbug\nmerge-sprint:*\nmerge-sprint:bbbbbbbbbbbb\n' > "$FAKE/labels"
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  grep -q '^label delete merge-sprint:bbbbbbbbbbbb -R' "$FAKE/calls"
  [ "$(grep -c '^label delete' "$FAKE/calls")" -eq 1 ]
}

@test "AC-23 boundary: el workflow solo pausa etiquetas merge-sprint:<12 hex>, no cualquier merge-sprint:*" {
  cat > "$TMPDIR_T/prs.json" <<'JSON'
[{"number":7,"headRefName":"a","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","labels":[{"name":"merge-sprint:abc123abc123"}]},
 {"number":8,"headRefName":"b","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","labels":[{"name":"merge-sprint:cualquiera"}]}]
JSON
  run auto_rebase_list_step
  [ "$status" -eq 0 ]
  local prs; prs=$(sed -n '/^prs<<EOF$/,/^EOF$/p' "$TMPDIR_T/gh_output" | sed '1d;$d')
  [ "$(jq -c '[.[].number]' <<<"$prs")" = "[8]" ]
}

@test "F5: las reservas consultan el estado del PR en el repo del ejecutor (-R), no en el del directorio" {
  mkpr 171 "scripts/ci.sh"; review 171 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -q '^pr view 171 -R [^ ]* --json state -q .state$' "$FAKE/calls"
  ! grep -q '^pr view 171 --json state' "$FAKE/calls" || false
}

# ── v8: P2 baratos de la segunda revisión independiente ──

@test "P1 boundary: si f5 close falla tras el merge, el MERGED ya está en el ledger una vez y al reconciliar no se duplica" {
  mkpr 180 "scripts/da.sh"; review 180 APPROVE correctness
  echo 'echo OPEN > "$FAKE/180.state"' > "$FAKE/180.on_merge"   # latencia de la API: aún no se ve MERGED
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"f5_close"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ "$(grep -c '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl")" -eq 1 ]
  [ "$(jq -r .merged "$MERGE_SPRINT_HOME/grant.json")" -eq 1 ]
  echo MERGED > "$FAKE/180.state"; regrant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(grep -c '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl")" -eq 1 ]
  ! grep -q '"reason":"merge_externo"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
  [ "$(jq -r .state "$MERGE_SPRINT_HOME"/reservations/*/pr.merge__180.json)" = closed ]
}

@test "P2 boundary: si la consulta de isDraft falla (vacío) no se llama a ready ni el PR vuelve a Draft" {
  mkpr 181 "scripts/db.sh"; review 181 APPROVE correctness; echo 1 > "$FAKE/181.reject"; : > "$FAKE/181.draft"
  plan_and_grant
  run bash "$SCRIPT" run
  grep -q '"reason":"merge_rechazado"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  ! grep -q 'pr ready 181' "$FAKE/calls" || false
  ! grep -q 'pr ready 181 .*--undo' "$FAKE/calls" || false
}

@test "P2 positivo: PR en Draft sigue saliendo de Draft con ready antes del merge" {
  mkpr 182 "scripts/dc.sh"; review 182 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  grep -q 'pr ready 182' "$FAKE/calls"
  grep -qx 182 "$FAKE/merged"
}

@test "P2 block: plan no admite un PR cuya base no es la configurada" {
  mkpr 183 "scripts/dd.sh"; review 183 APPROVE correctness; echo release > "$FAKE/183.base"
  mkpr 184 "scripts/de.sh"; review 184 APPROVE correctness
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [[ "$output" != *"#183"* ]]
  [[ "$output" == *"#184(t"* ]]
}

@test "P2 boundary: grant.json conserva modo 0600 tras actualizar el contador" {
  mkpr 185 "scripts/df.sh"; review 185 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$MERGE_SPRINT_HOME/grant.json")" = 600 ]
}

@test "P2 boundary: la equivalencia del head se calcula contra origin/<BASE>, no contra origin/main fijo" {
  export MERGE_SPRINT_BASE=trunk
  G branch trunk main; G push -q origin trunk
  G switch -q -c feat main; mkdir -p "$MERGE_SPRINT_GIT_ROOT/scripts"; echo f > "$MERGE_SPRINT_GIT_ROOT/scripts/fa.sh"; G add scripts/fa.sh; G commit -qm feat
  local r; r=$(G rev-parse HEAD)
  G switch -q trunk; echo t > "$MERGE_SPRINT_GIT_ROOT/scripts/tb.sh"; G add scripts/tb.sh; G commit -qm trunk-avanza; G push -q origin trunk
  G switch -q main; echo m > "$MERGE_SPRINT_GIT_ROOT/a.txt"; G commit -qam main-diverge; G push -q origin main
  G switch -q feat; G merge -q --no-edit trunk
  local h; h=$(G rev-parse HEAD)
  echo "$h" > "$FAKE/186.head"; echo "scripts/fa.sh scripts/tb.sh" > "$FAKE/186.files"; echo trunk > "$FAKE/186.base"
  echo "VERDICT: APPROVE pr=186 sha=$r role=correctness tier=2 reviewer=rev-agent author=impl-agent p0=0 p1=0 p2=0 p2_blocking=0" > "$TMPDIR_T/rev186.md"
  bash "$SCRIPT" review-register 186 "$TMPDIR_T/rev186.md"
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"#186(t"* ]]
}

# ── v9: tercera revisión independiente de la PR #1375 (P1 y P2) ──
killrun_hook() {  # killrun_hook <fichero> : gancho del gh falso que mata con kill -9 el run y sus subprocesos
  cat > "$1" <<'EOF'
p=$PPID; pids=()
while [ "$p" -gt 1 ]; do
  c=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  case "$c" in *merge-sprint.sh*|*f5-state.sh*|*/bin/gh*) pids=("$p" "${pids[@]}") ;; *) break ;; esac
  p=$(awk '{print $4}' "/proc/$p/stat")
done
kill -9 "${pids[@]}"
EOF
}
merged_events() { grep '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep -c "\"pr\":\"$1\""; }
resv_state() { jq -r .state "$MERGE_SPRINT_HOME"/reservations/*/pr.merge__"$1".json; }

@test "P1 positivo: proceso muerto tras el merge, al leer el commit de merge; el siguiente run lo registra una vez" {
  mkpr 200 "scripts/ea.sh"; mkpr 201 "scripts/eb.sh"
  review 200 APPROVE correctness; review 201 APPROVE correctness
  killrun_hook "$FAKE/200.on_mc"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -ne 0 ]
  [ "$(merged_events 200)" -eq 0 ]
  [ "$(resv_state 200)" = submitted ]   # la reserva no se cierra antes del ledger
  mv "$FAKE/200.on_mc" "$TMPDIR_T/200.on_mc.old"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(merged_events 200)" -eq 1 ]
  grep '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep '"pr":"200"' | grep -q '"equivalence":"reconciled"'
  [ "$(paste -sd, "$FAKE/merged")" = "200,201" ]
  [ "$(jq -r .merged "$MERGE_SPRINT_HOME/grant.json")" -eq 2 ]
}

@test "P1 boundary: proceso muerto en f5 close, con el MERGED ya escrito; al reconciliar no se duplica ni se cuenta dos veces" {
  mkpr 202 "scripts/ec.sh"; mkpr 203 "scripts/ed.sh"
  review 202 APPROVE correctness; review 203 APPROVE correctness
  killrun_hook "$FAKE/202.on_f5state"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -ne 0 ]
  [ "$(merged_events 202)" -eq 1 ]
  [ "$(resv_state 202)" = submitted ]
  mv "$FAKE/202.on_f5state" "$TMPDIR_T/202.on_f5state.old"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(merged_events 202)" -eq 1 ]
  [ "$(resv_state 202)" = closed ]
  [ "$(paste -sd, "$FAKE/merged")" = "202,203" ]
  [ "$(jq -r .merged "$MERGE_SPRINT_HOME/grant.json")" -eq 2 ]
}

@test "P1 error: commit de merge ilegible tras el merge para sin escribir un MERGED con commit vacío" {
  mkpr 204 "scripts/ee.sh"; review 204 APPROVE correctness; touch "$FAKE/204.mc_fail"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"merge_commit_ilegible"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ "$(merged_events 204)" -eq 0 ]
  [ "$(resv_state 204)" = submitted ]
}

@test "P1 positivo: SAFE sobre un head que otro merge del sprint dejó detrás de main se re-sincroniza y se mergea sin otro juicio" {
  export MERGE_SPRINT_JUDGE_POLLS=1
  jpr 205 scripts/d.sh l1; jpr 206 scripts/e.sh l1
  plan_and_grant
  H0=$(python3 -c 'import json,sys; print(next(p["head"] for p in json.load(open(sys.argv[1]))["prs"] if p["pr"]==205))' "$MERGE_SPRINT_HOME/manifest.json")
  fix_commit 205 'echo l2 >> scripts/d.sh'
  H1=$(git --git-dir="$BARE" rev-parse refs/heads/pr-205)
  # el merge de #206 avanza main como un squash en GitHub; #205 exige rama al día
  cat > "$FAKE/206.on_merge" <<'EOF'
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
c=$(git --git-dir="$BARE" commit-tree "$(git --git-dir="$BARE" rev-parse 'refs/heads/pr-206^{tree}')" -p refs/heads/main -m "squash 206")
git --git-dir="$BARE" update-ref refs/heads/main "$c"
EOF
  touch "$FAKE/205.require_uptodate"
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [ "$(paste -sd, "$FAKE/merged")" = "206" ]
  verdict 205 "$(safe_line 205)"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(paste -sd, "$FAKE/merged")" = "206,205" ]
  local h2; h2=$(git --git-dir="$BARE" rev-parse refs/heads/pr-205)
  [ "$h2" != "$H1" ]
  grep -q "pr merge 205 .*--match-head-commit $h2" "$FAKE/calls"
  grep '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep '"pr":"205"' | grep '"equivalence":"judge_safe"' | grep -q '"judge_ref"'
}

@test "P2 block: tras main roja, un run con el mismo grant no mergea nada; con un grant nuevo sí" {
  mkpr 207 "scripts/ef.sh"; mkpr 208 "scripts/eg.sh"
  review 207 APPROVE correctness; review 208 APPROVE correctness; echo fail > "$FAKE/main_ci"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(paste -sd, "$FAKE/merged")" = "207" ]
  echo pass > "$FAKE/main_ci"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ "$(paste -sd, "$FAKE/merged")" = "207" ]
  grep -q '"cause":"main_fail"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  regrant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(paste -sd, "$FAKE/merged")" = "207,208" ]
}

@test "P2 boundary: un veredicto tardío de una solicitud obsoleta se ignora y el sprint sigue en pausa" {
  judge_setup 209
  fix_commit 209 'echo l3 >> scripts/d.sh'
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  verdict 209 "$(safe_line 209)"   # SAFE para el to anterior (H1)
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [[ "$output" == *"espera al juez"* ]]
  ! grep -q '"reason":"judge_from_to"' "$MERGE_SPRINT_HOME/ledger.jsonl" || false
  [ ! -e "$FAKE/merged" ]
}

@test "P2 block: estado ilegible al etiquetar para el sprint en vez de dejar el PR sin etiqueta" {
  mkpr 210 "scripts/eh.sh"; review 210 APPROVE correctness
  plan_and_grant
  touch "$FAKE/210.state_fail"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"etiqueta_fallida"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "P2 boundary: el run siguiente a una pausa no re-sincroniza el PR que espera al juez aunque main avance" {
  judge_setup 211
  main_moves z.txt m1
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/pr-211)" = "$H1" ]
  ! grep '"event":"RESYNC"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep -q '"pr":"211"' || false
}

@test "P2 error: judge.jsonl manipulado hace fallar run y verify-ledger con exit 4" {
  judge_setup 212
  verdict 212 "$(safe_line 212)"; verdict 999 "JUDGE: STOP otro"
  sed -i '1s/"pr":212/"pr":213/' "$MERGE_SPRINT_HOME/judge.jsonl"
  run bash "$SCRIPT" run
  [ "$status" -eq 4 ]
  run bash "$SCRIPT" verify-ledger
  [ "$status" -eq 4 ]
  [ ! -e "$FAKE/merged" ]
}

@test "P2 block: run con una base distinta de la del manifiesto para por anomalía" {
  mkpr 213 "scripts/ei.sh"; review 213 APPROVE correctness
  plan_and_grant
  MERGE_SPRINT_BASE=trunk run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"base_distinta"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "P2 block: solicitud al juez alterada en el directorio de estado (autores vaciados) para antes de aceptar el SAFE" {
  judge_setup 214
  local f; f=$(find "$MERGE_SPRINT_HOME/judge" -name '214-*.request.json')
  python3 -c 'import json,sys; q=json.load(open(sys.argv[1])); q["authors"]=[]; json.dump(q,open(sys.argv[1],"w"),sort_keys=True,indent=1)' "$f"
  verdict 214 "$(safe_line 214 impl-agent)"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_solicitud_alterada"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}

@test "P2 block: delta solo en un commit de merge (sin autor de arreglo) para sin solicitar al juez" {
  export MERGE_SPRINT_JUDGE_POLLS=1
  jpr 215 scripts/d.sh l1; plan_and_grant
  main_moves z.txt m1
  G switch -q pr-215; G merge -q --no-ff --no-commit main
  echo l2 >> "$MERGE_SPRINT_GIT_ROOT/scripts/d.sh"; G add -A
  git -C "$MERGE_SPRINT_GIT_ROOT" -c user.email=f@f -c user.name=fixer -c commit.gpgsign=false commit -qm "merge con arreglo"
  G push -q origin pr-215; G switch -q main
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"judge_fix_author_vacio"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  no_request
}

@test "P2 block: f5-state.sh distinto del blob del manifiesto para el sprint" {
  echo "# otra versión" >> "$MERGE_SPRINT_GIT_ROOT/scripts/f5-state.sh"; G commit -qam "f5 cambiado"; G push -q origin main
  mkpr 216 "scripts/ej.sh"; review 216 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  grep -q '"reason":"blob_f5"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [ ! -e "$FAKE/merged" ]
}
