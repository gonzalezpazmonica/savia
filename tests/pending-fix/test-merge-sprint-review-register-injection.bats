#!/usr/bin/env bats
# PENDIENTE DE ACTIVAR — vive en tests/pending-fix/ para que la suite normal (tests/*.bats) no la ejecute.
# Describe el comportamiento CORRECTO de `merge-sprint.sh review-register` ante un informe con comillas o
# caracteres raros en reviewer/author (defecto de inyección en el registro de revisiones, S-MS1). HOY FALLA: el defecto existe.
# Activación: en la misma PR que arregle el ejecutor (restringir reviewer/author a [A-Za-z0-9._-]+, montar la
# línea del registro con json.dumps y salir ≠ 0 si chain_append falla):
#   git mv tests/pending-fix/test-merge-sprint-review-register-injection.bats tests/
# No se marcan como saltadas ni se debilitan: tienen que fallar hasta que el arreglo exista.
# Ejecución manual: bats tests/pending-fix/test-merge-sprint-review-register-injection.bats

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


# Informe con campos controlados; se insertan tal cual, sin escapar
report() {  # report <pr> <verdict> <reviewer> <author> <p0> → ruta
  local f="$TMPDIR_T/inj-$1-$RANDOM.md"
  printf 'VERDICT: %s pr=%s sha=%s role=correctness tier=2 reviewer=%s author=%s p0=%s p1=0 p2=0 p2_blocking=0\n' \
    "$2" "$1" "$(sha_of "$1")" "$3" "$4" "$5" > "$f"
  echo "$f"
}
reg_lines() { [[ -f "$MERGE_SPRINT_HOME/reviews.jsonl" ]] && wc -l < "$MERGE_SPRINT_HOME/reviews.jsonl" || echo 0; }

@test "S-MS1 A: reviewer con comillas se rechaza (salida 3) y no se imprime «registrada»" {
  mkpr 60 "scripts/i1.sh"
  run bash "$SCRIPT" review-register 60 "$(report 60 APPROVE 'rev"x' impl-agent 0)"
  [ "$status" -eq 3 ]
  [[ "$output" != *"registrada"* ]]
  [ "$(reg_lines)" -eq 0 ]
}

@test "S-MS1 B: un rechazo (p0=1) con reviewer inyectado no deja un APPROVE en el registro" {
  mkpr 61 "scripts/i2.sh"
  run bash "$SCRIPT" review-register 61 "$(report 61 APPROVE 'rev","verdict":"APPROVE' impl-agent 1)"
  [ "$status" -eq 3 ]
  [ "$(reg_lines)" -eq 0 ]
  run bash "$SCRIPT" plan
  [[ "$output" != *"#61"* ]]
}

@test "S-MS1 C: la autora no puede constar como revisora inyectando un segundo reviewer" {
  mkpr 62 "scripts/i3.sh"
  run bash "$SCRIPT" review-register 62 "$(report 62 APPROVE 'aut","reviewer":"aut' aut 0)"
  [ "$status" -eq 3 ]
  [ "$(reg_lines)" -eq 0 ]
}

@test "S-MS1 D: author con comillas se rechaza igual que reviewer" {
  mkpr 63 "scripts/i4.sh"
  run bash "$SCRIPT" review-register 63 "$(report 63 APPROVE rev-agent 'impl"x' 0)"
  [ "$status" -eq 3 ]
  [ "$(reg_lines)" -eq 0 ]
}

@test "S-MS1 E: barra invertida, porcentaje, llaves y no ASCII en reviewer se rechazan" {
  mkpr 64 "scripts/i5.sh"
  for bad in 'rev\x' 'rev%s' 'revé' 'rev{x}' 'rev:x'; do
    run bash "$SCRIPT" review-register 64 "$(report 64 APPROVE "$bad" impl-agent 0)"
    [ "$status" -eq 3 ] || { echo "aceptado: $bad"; return 1; }
  done
  [ "$(reg_lines)" -eq 0 ]
}

@test "S-MS1 F: lo que imprime la orden coincide con lo que escribe (HOLD y APPROVE)" {
  mkpr 65 "scripts/i6.sh"
  run bash "$SCRIPT" review-register 65 "$(report 65 HOLD rev-a impl-agent 0)"
  [ "$status" -eq 0 ]; [[ "$output" == *"correctness HOLD"* ]]
  [ "$(tail -1 "$MERGE_SPRINT_HOME/reviews.jsonl" | jq -r .verdict)" = HOLD ]
  run bash "$SCRIPT" review-register 65 "$(report 65 APPROVE rev-b impl-agent 0)"
  [ "$status" -eq 0 ]; [[ "$output" == *"correctness APPROVE"* ]]
  [ "$(tail -1 "$MERGE_SPRINT_HOME/reviews.jsonl" | jq -r .verdict)" = APPROVE ]
}

@test "S-MS1 G: si la escritura del registro falla, la orden sale distinta de 0 (sin éxito falso)" {
  mkpr 66 "scripts/i7.sh"
  # reviews.jsonl como directorio: chain_append no puede escribirlo
  mkdir -p "$MERGE_SPRINT_HOME/reviews.jsonl"
  run bash "$SCRIPT" review-register 66 "$(report 66 APPROVE rev-agent impl-agent 0)"
  [ "$status" -ne 0 ]
  [[ "$output" != *"registrada"* ]]
}

@test "S-MS1 control: identificadores válidos con punto, guion y subrayado siguen registrándose" {
  mkpr 67 "scripts/i8.sh"
  run bash "$SCRIPT" review-register 67 "$(report 67 APPROVE Rev_Agent-2.x impl-agent 0)"
  [ "$status" -eq 0 ]
  [ "$(reg_lines)" -eq 1 ]
  [ "$(tail -1 "$MERGE_SPRINT_HOME/reviews.jsonl" | jq -r .reviewer)" = "Rev_Agent-2.x" ]
}
