#!/usr/bin/env bats
# Ref: docs/specs/SE-433-merge-sprint.spec.md · análisis de mutantes de noviembre de 2026 (K2, K4, K5, K6, K8, K10)
# Pruebas que MATAN seis mutantes de scripts/merge-sprint.sh que sobrevivían a las suites test-merge-sprint*.bats.
# El gh falso ejecuta el filtro --jq real de main_ci sobre un JSON de check-runs (el de las otras suites lo esquivaba).
# Cada prueba pasa con el ejecutor real y falla con el mutante correspondiente (ver la tabla en la PR).

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
      api*check-runs*)
        if [[ -f "$F/main_ci.json" ]]; then   # filtro --jq REAL del ejecutor sobre check-runs de verdad
          expr=""; prev=""; for x in "$@"; do [[ "$prev" == --jq ]] && expr="$x"; prev="$x"; done
          jq -r "$expr" "$F/main_ci.json"
        else cat "$F/main_ci" 2>/dev/null || echo pass; fi ;;
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
  cp scripts/merge-sprint.sh scripts/risk-tier.py scripts/f5-state.sh scripts/merge-registry-resolve.py "$MERGE_SPRINT_GIT_ROOT/scripts/"
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


# Un informe de revisión bien formado; p2b = p2_blocking
verdict_file() {  # verdict_file <pr-en-el-informe> <verdict> <p0> <p1> <p2b> → ruta
  local f="$TMPDIR_T/v-$1-$2-$3$4$5.md"
  echo "VERDICT: $2 pr=$1 sha=$(sha_of "$1") role=correctness tier=2 reviewer=rev-agent author=impl-agent p0=$3 p1=$4 p2=0 p2_blocking=$5" > "$f"
  echo "$f"
}

# ── K2: un hallazgo bloqueante (p2_blocking) degrada APPROVE a HOLD ──
@test "K2 block: APPROVE con p2_blocking=1 se registra como HOLD y el PR no entra en el plan" {
  mkpr 40 "scripts/m1.sh"
  run bash "$SCRIPT" review-register 40 "$(verdict_file 40 APPROVE 0 0 1)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"correctness HOLD"* ]]
  grep -q '"verdict":"HOLD"' "$MERGE_SPRINT_HOME/reviews.jsonl"
  run bash "$SCRIPT" plan
  [[ "$output" != *"#40"* ]]
}

@test "K2 positivo: el mismo informe sin p2_blocking sí es APPROVE y entra en el plan" {
  mkpr 41 "scripts/m2.sh"
  run bash "$SCRIPT" review-register 41 "$(verdict_file 41 APPROVE 0 0 0)"
  [[ "$output" == *"correctness APPROVE"* ]]
  run bash "$SCRIPT" plan
  [[ "$output" == *"#41"* ]]
}

# ── K6: el PR del informe debe coincidir con el pedido en la orden ──
@test "K6 block: informe de otro PR no se registra (salida 3, sin línea nueva)" {
  mkpr 42 "scripts/m3.sh"; mkpr 43 "scripts/m4.sh"
  run bash "$SCRIPT" review-register 42 "$(verdict_file 43 APPROVE 0 0 0)"
  [ "$status" -eq 3 ]
  [[ "$output" == *"≠ 42"* ]]
  [ ! -s "$MERGE_SPRINT_HOME/reviews.jsonl" ]
  run bash "$SCRIPT" plan
  [[ "$output" != *"#42"* && "$output" != *"#43"* ]]
}

@test "K6 positivo: informe del mismo PR se registra" {
  mkpr 44 "scripts/m5.sh"
  run bash "$SCRIPT" review-register 44 "$(verdict_file 44 APPROVE 0 0 0)"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MERGE_SPRINT_HOME/reviews.jsonl")" -eq 1 ]
}

# ── K5: sin checks obligatorios legibles no hay «verde» ──
@test "K5 block: gh pr checks sin ninguna línea → pendiente, el PR no se mergea" {
  mkpr 45 "scripts/m6.sh"; review 45 APPROVE correctness; : > "$FAKE/45.checks"
  # el gh falso imprime «CI<TAB>» con estado vacío: la lista de estados queda vacía
  plan_and_grant
  run bash "$SCRIPT" run
  [ ! -s "$FAKE/merged" ]
  grep -q '"reason":"ci_pendiente"' "$MERGE_SPRINT_HOME/ledger.jsonl"
}

@test "K5 positivo: con el check en verde el mismo PR sí se mergea" {
  mkpr 46 "scripts/m7.sh"; review 46 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  grep -qx 46 "$FAKE/merged"
}

# ── K4 / K8 / K10: main tras el merge solo sigue si hay check-runs y todos son verdes ──
# Dos PR; el primero se mergea y main queda como diga main_ci.json; si no es verde el segundo no se mergea.
two_prs() { mkpr 50 "scripts/n1.sh"; mkpr 51 "scripts/n2.sh"; review 50 APPROVE correctness; review 51 APPROVE correctness; plan_and_grant; }

@test "K4 block: check-run de main 'cancelled' para el sprint tras el primer merge" {
  two_prs
  echo '{"check_runs":[{"conclusion":"success"},{"conclusion":"cancelled"}]}' > "$FAKE/main_ci.json"
  run bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/merged")" = "50" ]
  [[ "$output" == *"STOP: main 'fail'"* ]]
}

@test "K8 block: check-run de main 'timed_out' para el sprint tras el primer merge" {
  two_prs
  echo '{"check_runs":[{"conclusion":"success"},{"conclusion":"timed_out"}]}' > "$FAKE/main_ci.json"
  run bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/merged")" = "50" ]
  [[ "$output" == *"STOP: main 'fail'"* ]]
}

@test "K10 block: main sin ningún check-run no cuenta como verde (agota y para)" {
  two_prs
  echo '{"check_runs":[]}' > "$FAKE/main_ci.json"
  run bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/merged")" = "50" ]
  [[ "$output" == *"STOP: main 'pending'"* ]]
}

@test "K10 block: check-run de main sin conclusión (en curso) agota y para" {
  two_prs
  echo '{"check_runs":[{"conclusion":"success"},{"conclusion":null}]}' > "$FAKE/main_ci.json"
  run bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/merged")" = "50" ]
  [[ "$output" == *"STOP: main 'pending'"* ]]
}

@test "K4/K8/K10 control: main con todos los check-runs en success deja pasar los dos PR" {
  two_prs
  echo '{"check_runs":[{"conclusion":"success"},{"conclusion":"success"}]}' > "$FAKE/main_ci.json"
  run bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/merged")" = "50,51" ]
}

@test "K4 control: 'failure' en main también para (el filtro real, no el atajo del gh falso)" {
  two_prs
  echo '{"check_runs":[{"conclusion":"failure"}]}' > "$FAKE/main_ci.json"
  run bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/merged")" = "50" ]
  [[ "$output" == *"STOP: main 'fail'"* ]]
}
