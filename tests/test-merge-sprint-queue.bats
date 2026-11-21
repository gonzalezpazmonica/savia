#!/usr/bin/env bats
# Ref: docs/specs/SE-433-merge-sprint.spec.md · docs/rules/domain/autonomous-safety-merge-sprint.md
# Modo cola (merge queue de GitHub) de scripts/merge-sprint.sh con un gh falso que imita la cola: nunca toca GitHub.
# El gh falso es el de test-merge-sprint.bats más la cola: $FAKE/queue_enabled (la rama base exige cola),
# $FAKE/<pr>.queue_outcome (merge | eject:<motivo> | move | mergemoved | wait), $FAKE/<pr>.on_poll (se ejecuta
# una vez en la primera consulta de la cola), log de entradas en $FAKE/enqueued y de salidas en $FAKE/dequeued.
# Fallos simulados: $FAKE/dequeue_fail (la mutación falla y la PR sigue en la cola), $FAKE/<pr>.state_fail (leer el
# estado falla), $FAKE/<pr>.lag (la primera consulta de la cola dice «fuera» aunque siga dentro: desfase de GitHub).
# Entrada en la cola: mutación enqueuePullRequest con expectedHeadOid (GitHub la rechaza si el head no coincide).
# $FAKE/queue_method (método de la cola; SQUASH si no existe), $FAKE/<pr>.enqueue_lost (encola y sale con error:
# respuesta perdida), $FAKE/<pr>.enqueue_auto (no entra: deja un auto-merge pendiente), $FAKE/<pr>.automerge
# (auto-merge pendiente; lo quita disablePullRequestAutoMerge), $FAKE/<pr>.on_enqueue (se ejecuta al encolar).
# Con $FAKE/queue_enabled, «gh pr merge» encola aunque se pida --squash (comportamiento documentado de gh).
# $FAKE/<pr>.merge_on_enqueue (GitHub la fusiona al encolar, antes de la primera lectura), $FAKE/<pr>.merge_lost
# (serie: «gh pr merge» fusiona y sale con error: respuesta perdida), $FAKE/<pr>.fresh_lag (la primera lectura tras
# encolar dice «fuera» aunque haya entrado), $FAKE/<pr>.term_after_enqueue (SIGTERM al ejecutor justo después de que
# GitHub acepte la entrada), $FAKE/<pr>.stale_when_stopped (con el sprint parado, una lectura «fuera» desfasada),
# $FAKE/<pr>.merge_on_dequeue (GitHub la fusiona justo antes de la retirada), $FAKE/<pr>.lag_secs (serie: el estado
# MERGED tarda esos segundos en verse).

SCRIPT="scripts/merge-sprint.sh"

setup() {
  TMPDIR_T="$(mktemp -d)"
  export MERGE_SPRINT_HOME="$TMPDIR_T/state"
  export MERGE_SPRINT_POLICY="$TMPDIR_T/policy.conf"
  export MERGE_SPRINT_POLL_S=0 MERGE_SPRINT_MAIN_POLLS=2 MERGE_SPRINT_CI_POLLS=1 MERGE_SPRINT_CI_SETTLE_S=0
  export MERGE_SPRINT_QUEUE_POLLS=5
  unset MERGE_SPRINT_QUEUE
  # RESYNC=1 (el valor por defecto): el modo cola nunca re-sincroniza aunque esté activo; un resync aquí fallaría.
  export MERGE_SPRINT_RESYNC=1
  printf 'allowed_tiers=1,2,3\nttl_hours=12\nmax_merges=40\nmax_prs=50\n' > "$MERGE_SPRINT_POLICY"
  export FAKE="$TMPDIR_T/fake"; mkdir -p "$FAKE" "$TMPDIR_T/bin"
  cat > "$TMPDIR_T/bin/gh" <<'EOF'
#!/usr/bin/env bash
F="$FAKE"; a="$*"; echo "$a" >> "$F/calls"
# $F/<pr>.lag_reads: tantas lecturas de mergeCommit/state como diga, tras fusionar, aún no ven la fusión.
lagged() { local f="$F/$1.lag_reads" k; [[ -f "$f" && -f "$F/$1.merged_at" ]] || return 1; k=$(cat "$f"); (( k > 0 )) || return 1; echo $((k-1)) > "$f"; }
case "$1 $2" in
  "pr list") ls "$F" | sed -n 's/^\([0-9]*\)\.head$/\1/p' | while read -r n; do [[ "$(cat "$F/$n.state" 2>/dev/null || echo OPEN)" == OPEN ]] && echo "$n"; done | sort -n ;;
  "pr view")
    n=$3
    case "$a" in
      *"--json id "*) echo "PR_$n" ;;
      *headRefOid*) cat "$F/$n.head" ;;
      *headRefName*) echo "agent/b-$n" ;;
      *baseRefName*) echo main ;;
      *headRepository*) echo owner/repo ;;
      *mergeStateStatus*) echo CLEAN ;;
      *isDraft*) echo true ;;
      *mergedBy*) echo executor ;;
      *mergeCommit*) lagged "$n" && exit 0
                     [[ "$(cat "$F/$n.state" 2>/dev/null)" == MERGED ]] && printf 'c%039d\n' "$n"; exit 0 ;;   # sin fusión no hay commit
      *state*) [[ -f "$F/$n.state_fail" ]] && exit 1; lagged "$n" && { echo OPEN; exit 0; }
               # $F/<pr>.lag_secs: durante esos segundos tras fusionar, el estado aún se ve OPEN (desfase por tiempo).
               if [[ -f "$F/$n.lag_secs" && -s "$F/$n.merged_at" ]] && awk -v a="$(date +%s.%N)" -v b="$(cat "$F/$n.merged_at")" \
                    -v l="$(cat "$F/$n.lag_secs")" 'BEGIN{exit !(a<b+l)}'; then echo OPEN; exit 0; fi
               cat "$F/$n.state" 2>/dev/null || echo OPEN ;;
    esac ;;
  "pr diff") cat "$F/$3.files" ;;
  "pr checks") printf 'CI\t%s\n' "$(cat "$F/$3.checks" 2>/dev/null || echo pass)" ;;
  "pr ready"|"label create"|"label delete") exit 0 ;;
  "label list") exit 0 ;;
  "pr merge")
    if [[ -f "$F/queue_enabled" ]]; then
      # Cola activa: gh encola aunque se pida --squash y sale con 0; GitHub decide después.
      echo "$3" >> "$F/enqueued"; touch "$F/$3.inqueue"; [[ -f "$F/$3.enqueue_lost" ]] && exit 1; exit 0
    fi
    echo "$3" >> "$F/merged"; echo MERGED > "$F/$3.state"; date +%s.%N > "$F/$3.merged_at"; [[ -f "$F/$3.merge_lost" ]] && exit 1; exit 0 ;;
  *)
    case "$a" in
      "api graphql"*enqueuePullRequest*)
        n=$(sed -E 's/.* -f id=PR_([0-9]+).*/\1/' <<<"$a"); h=$(sed -E 's/.* -f h=([0-9a-f]+).*/\1/' <<<"$a")
        if [[ -f "$F/$n.on_enqueue" ]]; then bash "$F/$n.on_enqueue"; mv "$F/$n.on_enqueue" "$F/$n.on_enqueue.done"; fi
        [[ -f "$F/queue_enabled" && "$h" == "$(cat "$F/$n.head")" ]] || exit 1
        if [[ -f "$F/$n.enqueue_auto" ]]; then touch "$F/$n.automerge"; exit 0; fi
        # GitHub fusiona antes de la primera lectura (grupo ya probado): nunca se ve dentro de la cola.
        if [[ -f "$F/$n.merge_on_enqueue" ]]; then echo "$n" >> "$F/enqueued"; echo "$n" >> "$F/merged"; echo MERGED > "$F/$n.state"; exit 0; fi
        echo "$n" >> "$F/enqueued"; touch "$F/$n.inqueue" "$F/$n.fresh"
        # GitHub ya aceptó la entrada y el ejecutor recibe SIGTERM antes de leer la respuesta.
        [[ -f "$F/$n.term_after_enqueue" ]] && { mv "$F/$n.term_after_enqueue" "$F/$n.term_after_enqueue.done"; kill -TERM "$PPID"; }
        [[ -f "$F/$n.enqueue_lost" ]] && exit 1; exit 0 ;;
      "api graphql"*disablePullRequestAutoMerge*)
        n=$(sed -E 's/.* -f id=PR_([0-9]+).*/\1/' <<<"$a"); [[ -f "$F/dequeue_fail" ]] && exit 1
        if [[ -f "$F/$n.automerge" ]]; then mv "$F/$n.automerge" "$F/$n.automerge.off"; echo "$n" >> "$F/automerge_disabled"; fi
        exit 0 ;;
      "api graphql"*mergeQueue*)
        [[ -f "$F/queue_enabled" ]] || exit 0
        if [[ -f "$F/queue_method" ]]; then cat "$F/queue_method"; else echo SQUASH; fi; exit 0 ;;
      "api graphql"*isInMergeQueue*)
        n=$(sed -E 's/.* -F n=([0-9]+).*/\1/' <<<"$a")
        # La lectura que verifica la entrada (justo tras encolar) solo ve la PR dentro; GitHub decide en las siguientes.
        if [[ -f "$F/$n.fresh" && -f "$F/$n.fresh_lag" ]]; then mv "$F/$n.fresh_lag" "$F/$n.fresh_lag.done"; echo false; exit 0; fi
        if [[ -f "$F/$n.fresh" ]]; then mv "$F/$n.fresh" "$F/$n.fresh.done"; echo true; exit 0; fi
        # Desfase en la limpieza: con el sprint ya parado, la primera lectura dice «fuera» aunque siga dentro.
        if [[ -f "$F/$n.stale_when_stopped" && -e "$MERGE_SPRINT_HOME/STOP" && -f "$F/$n.inqueue" ]]; then
          mv "$F/$n.stale_when_stopped" "$F/$n.stale_when_stopped.done"; echo false; exit 0
        fi
        if [[ -f "$F/$n.on_poll" ]]; then bash "$F/$n.on_poll"; mv "$F/$n.on_poll" "$F/$n.on_poll.done"; fi
        if [[ -f "$F/$n.lag" && -f "$F/$n.inqueue" ]]; then rm "$F/$n.lag"; echo false; exit 0; fi
        if [[ ! -f "$F/$n.inqueue" ]]; then if [[ -f "$F/$n.automerge" ]]; then echo auto; else echo false; fi; exit 0; fi
        o=$(cat "$F/$n.queue_outcome" 2>/dev/null || echo merge)
        case "$o" in
          wait) echo true; exit 0 ;;
          merge) echo "$n" >> "$F/merged"; echo MERGED > "$F/$n.state" ;;
          mergemoved) echo "$n" >> "$F/merged"; echo MERGED > "$F/$n.state"; printf '%040d' 9 | tr 0 f > "$F/$n.head" ;;
          eject:*) echo "${o#eject:}" > "$F/$n.eject_reason" ;;
          move) printf '%040d' 8 | tr 0 e > "$F/$n.head" ;;
        esac
        mv "$F/$n.inqueue" "$F/$n.left"; echo false ;;
      "api graphql"*RemovedFromMergeQueueEvent*) n=$(sed -E 's/.* -F n=([0-9]+).*/\1/' <<<"$a"); cat "$F/$n.eject_reason" 2>/dev/null; exit 0 ;;
      "api graphql"*dequeuePullRequest*)
        n=$(sed -E 's/.* -f id=PR_([0-9]+).*/\1/' <<<"$a")
        # GitHub fusiona la PR justo antes de que llegue la retirada: la mutación ya no la encuentra en la cola.
        if [[ -f "$F/$n.merge_on_dequeue" ]]; then
          mv "$F/$n.merge_on_dequeue" "$F/$n.merge_on_dequeue.done"; echo "$n" >> "$F/merged"; echo MERGED > "$F/$n.state"
          [[ -f "$F/$n.inqueue" ]] && mv "$F/$n.inqueue" "$F/$n.left"; exit 1
        fi
        [[ -f "$F/dequeue_fail" ]] && exit 1; echo "$n" >> "$F/dequeued"
        [[ -f "$F/$n.inqueue" ]] && mv "$F/$n.inqueue" "$F/$n.left"; exit 0 ;;
      api*protection/required_status_checks*) cat "$F/required" 2>/dev/null ;;
      api*/issues/*/events*) echo 0 ;;
      api*check-runs*) cat "$F/main_ci" 2>/dev/null || echo pass ;;
      "api user"*) echo executor ;;
      "api -X POST repos/"*"/issues/"*"/labels"*|"api -X DELETE repos/"*"/issues/"*"/labels/"*) exit 0 ;;
      *) exit 1 ;;
    esac ;;
esac
EOF
  chmod +x "$TMPDIR_T/bin/gh"; export GH="$TMPDIR_T/bin/gh"; export PATH="$TMPDIR_T/bin:$PATH"
  echo CI > "$FAKE/required"
  export BARE="$TMPDIR_T/origin.git"; git init -q --bare "$BARE"
  export MERGE_SPRINT_GIT_ROOT="$TMPDIR_T/clone"
  git clone -q "$BARE" "$MERGE_SPRINT_GIT_ROOT" 2>/dev/null
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/scripts"
  cp scripts/merge-sprint.sh scripts/risk-tier.py scripts/f5-state.sh scripts/merge-registry-resolve.py "$MERGE_SPRINT_GIT_ROOT/scripts/"
  echo base > "$MERGE_SPRINT_GIT_ROOT/a.txt"; G add a.txt scripts; G commit -qm base; G branch -M main; G push -q origin main
  export SCRIPT_ABS="$PWD/$SCRIPT"
}

G() { git -C "$MERGE_SPRINT_GIT_ROOT" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

teardown() { rm -rf "$TMPDIR_T"; }

sha_of() { printf '%040d' "$1" | tr 0 a; }

mkpr() { sha_of "$1" > "$FAKE/$1.head"; echo "$2" > "$FAKE/$1.files"; }

review() {  # review <n> <verdict> <role>
  local f="$TMPDIR_T/rev-$1-$3.md"
  echo "VERDICT: $2 pr=$1 sha=$(sha_of "$1") role=$3 tier=2 reviewer=rev-agent author=impl-agent p0=0 p1=0 p2=0 p2_blocking=0" > "$f"
  bash "$SCRIPT" review-register "$1" "$f"
}

plan_and_grant() {
  run bash "$SCRIPT" plan; [ "$status" -eq 0 ]
  local d; d=$(echo "$output" | sed -n 's/^digest: //p')
  run bash "$SCRIPT" grant "$d"; [ "$status" -eq 0 ]
}

queue_on() { export MERGE_SPRINT_QUEUE=1; touch "$FAKE/queue_enabled"; }

ledger_has() {  # ledger_has <evento> <pr> [reason] → 0 si el ledger tiene ese evento para el PR
  python3 -c 'import json,sys
ev=[json.loads(l) for l in open(sys.argv[1])]
sys.exit(0 if any(e.get("event")==sys.argv[2] and e.get("pr")==sys.argv[3] and (len(sys.argv)<5 or e.get("reason")==sys.argv[4]) for e in ev) else 1)' "$MERGE_SPRINT_HOME/ledger.jsonl" "$@"
}

@test "cola positivo: dos PR autorizadas entran en la cola en orden, sin re-sincronizar, y GitHub las fusiona" {
  queue_on
  mkpr 30 "scripts/a.sh"; mkpr 31 "scripts/b.sh"
  review 30 APPROVE correctness; review 31 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(paste -sd, "$FAKE/enqueued")" = "30,31" ]
  [ "$(paste -sd, "$FAKE/merged")" = "30,31" ]
  # Entran las dos antes de la primera espera: la cola las prueba en paralelo.
  # Antes de encolar la 31 solo hay una consulta de la cola: la verificación de la entrada de la 30, ninguna espera.
  second_in=$(grep -n 'enqueuePullRequest.* -f id=PR_31' "$FAKE/calls" | cut -d: -f1)
  [ "$(head -n "$second_in" "$FAKE/calls" | grep -c 'isInMergeQueue')" -eq 1 ]
  # Entrada con enqueuePullRequest atada a la cabeza revisada; nunca gh pr merge en modo cola.
  grep -q "enqueuePullRequest.* -f id=PR_30 -f h=$(sha_of 30)" "$FAKE/calls"
  run grep -c '^pr merge' "$FAKE/calls"
  [ "$output" = 0 ]
  ledger_has QUEUED 30
  ledger_has MERGED 30
  ledger_has MERGED 31
  run bash "$SCRIPT" verify-ledger
  [ "$status" -eq 0 ]
}

@test "cola negativo: sin MERGE_SPRINT_QUEUE ni política el ejecutor sigue en serie (squash) y no consulta la cola" {
  export MERGE_SPRINT_RESYNC=0
  mkpr 32 "scripts/a.sh"; review 32 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -q "^pr merge 32 -R .* --squash --match-head-commit $(sha_of 32)" "$FAKE/calls"
  run grep -c 'api graphql' "$FAKE/calls"
  [ "$output" = 0 ]
  [ ! -e "$FAKE/enqueued" ]
}

@test "cola política: merge_queue=1 en la política activa el modo cola sin variable de entorno" {
  touch "$FAKE/queue_enabled"; echo merge_queue=1 >> "$MERGE_SPRINT_POLICY"
  mkpr 33 "scripts/a.sh"; review 33 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 33 "$FAKE/enqueued"
  grep -qx 33 "$FAKE/merged"
}

@test "cola invalid: un valor de modo que no sea 0 ni 1 falla cerrado sin fusionar" {
  touch "$FAKE/queue_enabled"
  mkpr 34 "scripts/a.sh"; review 34 APPROVE correctness
  plan_and_grant
  MERGE_SPRINT_QUEUE=yes run bash "$SCRIPT" run
  [ "$status" -eq 2 ]
  [ ! -e "$FAKE/merged" ]
  [ ! -e "$FAKE/enqueued" ]
}

@test "cola invalid: merge_queue con otro valor en la política falla cerrado" {
  touch "$FAKE/queue_enabled"; echo merge_queue=si >> "$MERGE_SPRINT_POLICY"
  mkpr 48 "scripts/a.sh"; review 48 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 2 ]
  [ ! -e "$FAKE/enqueued" ]
}

@test "cola fail: GitHub expulsa la PR; se aparca con su motivo, se libera la reserva y la siguiente se fusiona" {
  queue_on
  mkpr 35 "scripts/a.sh"; mkpr 36 "scripts/b.sh"
  review 35 APPROVE correctness; review 36 APPROVE correctness
  echo "eject:CI failed on merge group" > "$FAKE/35.queue_outcome"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  run grep -cx 35 "$FAKE/merged"
  [ "$output" = 0 ]
  grep -qx 36 "$FAKE/merged"
  ledger_has PARK 35 cola_expulsada
  ledger_has QUEUE_EJECT 35 ci_failed_on_merge_group
  run find "$MERGE_SPRINT_HOME/reservations" -name 'pr.merge__35.head'
  [ -z "$output" ]
}

@test "cola fail: la cabeza se mueve mientras espera; se aparca como head_movido y no se fusiona" {
  queue_on
  mkpr 37 "scripts/a.sh"; review 37 APPROVE correctness
  echo move > "$FAKE/37.queue_outcome"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE/merged" ]
  ledger_has PARK 37 head_movido
}

@test "cola block: fusionada con una cabeza distinta de la revisada es anomalía (exit 5) y no se registra MERGED" {
  queue_on
  mkpr 38 "scripts/a.sh"; review 38 APPROVE correctness
  echo mergemoved > "$FAKE/38.queue_outcome"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"cola_head_distinto"* ]]
  run ledger_has MERGED 38
  [ "$status" -ne 0 ]
}

@test "cola block: cabeza movida tras la revisión no llega a entrar en la cola" {
  queue_on
  mkpr 39 "scripts/a.sh"; review 39 APPROVE correctness
  plan_and_grant
  printf '%040d' 7 | tr 0 d > "$FAKE/39.head"
  run bash "$SCRIPT" run
  RUN_STATUS=$status; RUN_OUT=$output
  run grep -c 'enqueuePullRequest.* -f id=PR_39' "$FAKE/calls"
  [ "$output" = 0 ]
  [ ! -e "$FAKE/merged" ]
  # El motivo es la cabeza movida, no cualquier otro fallo del run: la cabeza nueva no es equivalente a la revisada
  # (aquí no existe en git, así que la comprobación de equivalencia la aparca como ilegible) y el run termina limpio.
  [ "$RUN_STATUS" -eq 0 ]
  ledger_has PARK 39 equivalencia_ilegible
  [[ "$RUN_OUT" == *"aparcado #39: equivalencia_ilegible"* ]]
}

@test "cola block: grant revocado mientras la PR espera en la cola; se saca de la cola y el run para con anomalía" {
  queue_on
  mkpr 40 "scripts/a.sh"; review 40 APPROVE correctness
  echo wait > "$FAKE/40.queue_outcome"
  echo "bash '$SCRIPT_ABS' revoke >/dev/null" > "$FAKE/40.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"grant_revocado"* ]]
  grep -qx 40 "$FAKE/dequeued"
  [ ! -e "$FAKE/merged" ]
}

@test "cola block: STOP manual mientras espera saca la PR de la cola sin fusionar" {
  queue_on
  mkpr 41 "scripts/a.sh"; review 41 APPROVE correctness
  echo wait > "$FAKE/41.queue_outcome"
  echo "bash '$SCRIPT_ABS' stop >/dev/null" > "$FAKE/41.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"STOP manual"* ]]
  grep -qx 41 "$FAKE/dequeued"
  [ ! -e "$FAKE/merged" ]
}

@test "cola boundary: la espera agotada saca la PR de la cola y la aparca como cola_agotada" {
  queue_on; export MERGE_SPRINT_QUEUE_POLLS=2
  mkpr 42 "scripts/a.sh"; review 42 APPROVE correctness
  echo wait > "$FAKE/42.queue_outcome"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 42 "$FAKE/dequeued"
  ledger_has PARK 42 cola_agotada
  [ ! -e "$FAKE/merged" ]
}

@test "cola boundary: max_merges=1 cuenta también las PR que esperan en la cola" {
  queue_on
  printf 'allowed_tiers=1,2,3\nttl_hours=12\nmax_merges=1\nmax_prs=50\n' > "$MERGE_SPRINT_POLICY"
  mkpr 43 "scripts/a.sh"; mkpr 44 "scripts/b.sh"
  review 43 APPROVE correctness; review 44 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$(paste -sd, "$FAKE/enqueued")" = "43" ]
  [ "$(paste -sd, "$FAKE/merged")" = "43" ]
}

@test "cola error: modo cola pedido pero la rama base no exige cola en GitHub; anomalía sin fusionar" {
  export MERGE_SPRINT_QUEUE=1   # sin $FAKE/queue_enabled
  mkpr 45 "scripts/a.sh"; review 45 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"cola_no_activa"* ]]
  run grep -c 'enqueuePullRequest' "$FAKE/calls"
  [ "$output" = 0 ]
}

@test "cola fail: main roja tras la fusión para el sprint y saca de la cola las que quedaban" {
  queue_on
  mkpr 46 "scripts/a.sh"; mkpr 47 "scripts/b.sh"
  review 46 APPROVE correctness; review 47 APPROVE correctness
  echo wait > "$FAKE/47.queue_outcome"; echo fail > "$FAKE/main_ci"
  plan_and_grant
  run bash "$SCRIPT" run
  [[ "$output" == *"STOP"* ]]
  grep -qx 46 "$FAKE/merged"
  run grep -cx 47 "$FAKE/merged"
  [ "$output" = 0 ]
  grep -qx 47 "$FAKE/dequeued"
}

@test "cola default: la política versionada deja el modo cola apagado (merge_queue=0)" {
  run awk -F'=' '$1=="merge_queue" {print $2}' config/merge-sprint-policy.conf
  [ "$output" = 0 ]
}

resv_of() { find "$MERGE_SPRINT_HOME/reservations" -name "pr.merge__$1.head"; }

@test "cola error: estado ilegible mientras espera es anomalía cola_ilegible y la PR se saca de la cola (no se olvida)" {
  queue_on
  mkpr 50 "scripts/a.sh"; review 50 APPROVE correctness
  echo wait > "$FAKE/50.queue_outcome"
  echo "touch '$FAKE/50.state_fail'" > "$FAKE/50.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"cola_ilegible"* ]]
  grep -qx 50 "$FAKE/dequeued"
  run ledger_has PARK 50 no_abierto
  [ "$status" -ne 0 ]
}

@test "cola fail: PR cerrada mientras espera se saca de la cola antes de aparcarla como no_abierto" {
  queue_on
  mkpr 51 "scripts/a.sh"; review 51 APPROVE correctness
  echo wait > "$FAKE/51.queue_outcome"
  echo "echo CLOSED > '$FAKE/51.state'" > "$FAKE/51.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 51 "$FAKE/dequeued"
  ledger_has DEQUEUE 51
  ledger_has PARK 51 no_abierto
}

@test "cola error: dequeue fallido con cabeza movida para con anomalía, sin aparcar ni liberar la reserva" {
  queue_on
  mkpr 52 "scripts/a.sh"; review 52 APPROVE correctness
  echo wait > "$FAKE/52.queue_outcome"; touch "$FAKE/dequeue_fail"
  echo "printf '%040d' 8 | tr 0 e > '$FAKE/52.head'" > "$FAKE/52.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"dequeue_fallo"* ]]
  ledger_has DEQUEUE_FALLO 52
  run ledger_has PARK 52 head_movido
  [ "$status" -ne 0 ]
  [ -n "$(resv_of 52)" ]
  [ "$(head -1 "$MERGE_SPRINT_HOME/STOP")" = dequeue_fallo ]
}

@test "cola error: STOP manual con dequeue fallido no sale con 0; reserva conservada y sprint parado" {
  queue_on
  mkpr 53 "scripts/a.sh"; review 53 APPROVE correctness
  echo wait > "$FAKE/53.queue_outcome"; touch "$FAKE/dequeue_fail"
  echo "bash '$SCRIPT_ABS' stop >/dev/null" > "$FAKE/53.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"SIGUE en la cola"* ]]
  ledger_has DEQUEUE_FALLO 53
  [ -n "$(resv_of 53)" ]
}

@test "cola boundary: una sola lectura «fuera de la cola» (desfase) no expulsa; la PR se fusiona" {
  queue_on
  mkpr 54 "scripts/a.sh"; review 54 APPROVE correctness
  touch "$FAKE/54.lag"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 54 "$FAKE/merged"
  run ledger_has PARK 54 cola_expulsada
  [ "$status" -ne 0 ]
}

@test "cola boundary: la espera por defecto (polls × poll_s) supera timeout de checks 120 min + espera de grupo 5 min" {
  polls=$(sed -n 's/.*MERGE_SPRINT_QUEUE_POLLS:-\([0-9]*\)}.*/\1/p' "$SCRIPT" | head -1)
  poll_s=$(sed -n 's/.*MERGE_SPRINT_POLL_S:-\([0-9]*\)}.*/\1/p' "$SCRIPT" | head -1)
  [ -n "$polls" ] && [ -n "$poll_s" ]
  [ $(( polls * poll_s )) -gt $(( 125 * 60 )) ]
}

# ── Revisión independiente 2026-11-20 (codex-refutacion y security, HOLD sobre 295b1c5) ──

@test "serie con la cola de GitHub activa: gh encola en vez de fusionar; se saca de la cola y el run para (exit 5)" {
  touch "$FAKE/queue_enabled"; export MERGE_SPRINT_RESYNC=0   # MERGE_SPRINT_QUEUE sin definir: modo serie
  mkpr 60 "scripts/a.sh"; review 60 APPROVE correctness
  echo wait > "$FAKE/60.queue_outcome"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"merge_no_inmediato"* ]]
  grep -qx 60 "$FAKE/enqueued"
  grep -qx 60 "$FAKE/dequeued"     # el trap la saca: no queda en la cola sin vigilancia
  [ ! -e "$FAKE/merged" ]
  run ledger_has MERGED 60
  [ "$status" -ne 0 ]
}

@test "cola: un auto-merge pendiente al encolar no cuenta como entrada; se desarma y se aparca" {
  queue_on
  mkpr 61 "scripts/a.sh"; review 61 APPROVE correctness
  touch "$FAKE/61.enqueue_auto"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 61 "$FAKE/automerge_disabled"
  [ ! -e "$FAKE/61.automerge" ]
  ledger_has PARK 61 auto_merge_pendiente
  run ledger_has QUEUED 61
  [ "$status" -ne 0 ]
}

@test "cola: auto-merge pendiente durante la espera no se toma por expulsión; se desarma" {
  queue_on
  mkpr 62 "scripts/a.sh"; review 62 APPROVE correctness
  echo wait > "$FAKE/62.queue_outcome"
  # Sale de la cola y queda con auto-merge pendiente (p. ej. falta una aprobación).
  echo "mv '$FAKE/62.inqueue' '$FAKE/62.left'; touch '$FAKE/62.automerge'" > "$FAKE/62.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 62 "$FAKE/automerge_disabled"
  ledger_has PARK 62 auto_merge_pendiente
  run ledger_has PARK 62 cola_expulsada
  [ "$status" -ne 0 ]
}

@test "cola: auto-merge que no se puede desarmar para con anomalía y conserva la reserva" {
  queue_on
  mkpr 63 "scripts/a.sh"; review 63 APPROVE correctness
  touch "$FAKE/63.enqueue_auto" "$FAKE/dequeue_fail"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"dequeue_fallo"* ]]
  [ -e "$FAKE/63.automerge" ]
  [ -n "$(resv_of 63)" ]
}

@test "cola: respuesta perdida tras encolar (la mutación falla pero la PR entró) se vigila y se fusiona" {
  queue_on
  mkpr 64 "scripts/a.sh"; review 64 APPROVE correctness
  touch "$FAKE/64.enqueue_lost"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 64 "$FAKE/merged"
  ledger_has QUEUED 64
  ledger_has MERGED 64
  run ledger_has PARK 64 cola_rechazada
  [ "$status" -ne 0 ]
}

@test "cola: respuesta perdida tras encolar y STOP después; la PR se saca de la cola (no queda sin vigilancia)" {
  queue_on
  mkpr 65 "scripts/a.sh"; review 65 APPROVE correctness
  touch "$FAKE/65.enqueue_lost"; echo wait > "$FAKE/65.queue_outcome"
  echo "bash '$SCRIPT_ABS' stop >/dev/null" > "$FAKE/65.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"STOP manual"* ]]
  grep -qx 65 "$FAKE/dequeued"
  [ ! -e "$FAKE/merged" ]
}

@test "cola: GitHub rechaza la entrada (expectedHeadOid no coincide); no entra, se libera la reserva y se aparca" {
  queue_on
  mkpr 66 "scripts/a.sh"; review 66 APPROVE correctness
  plan_and_grant
  # Push justo entre la comprobación del head y la entrada: GitHub ve otra cabeza y rechaza la mutación.
  echo "printf '%040d' 6 | tr 0 b > '$FAKE/66.head'" > "$FAKE/66.on_enqueue"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE/enqueued" ]
  ledger_has PARK 66 cola_rechazada
  [ -z "$(resv_of 66)" ]
}

@test "cola: STOP mientras otra PR espera su CI saca de la cola la ya encolada" {
  queue_on; export MERGE_SPRINT_CI_POLLS=3
  mkpr 67 "scripts/a.sh"; mkpr 68 "scripts/b.sh"
  review 67 APPROVE correctness; review 68 APPROVE correctness
  echo wait > "$FAKE/67.queue_outcome"; echo pending > "$FAKE/68.checks"
  plan_and_grant
  # La 67 ya está en la cola cuando empieza la espera de CI de la 68: el STOP llega en la primera consulta.
  sed -i 's|^  "pr checks")|  "pr checks") [[ "$3" == 68 ]] \&\& bash "$SCRIPT_ABS" stop >/dev/null;|' "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"STOP manual"* ]]
  grep -qx 67 "$FAKE/dequeued"
  # Paró tras la primera consulta de CI de la 68, no tras agotar la espera.
  [ "$(grep -c '^pr checks 68' "$FAKE/calls")" -eq 1 ]
  [ ! -e "$FAKE/merged" ]
}

@test "cola: grant revocado mientras main espera su CI tras fusionar una PR saca de la cola la siguiente" {
  queue_on; export MERGE_SPRINT_MAIN_POLLS=3
  mkpr 69 "scripts/a.sh"; mkpr 70 "scripts/b.sh"
  review 69 APPROVE correctness; review 70 APPROVE correctness
  echo wait > "$FAKE/70.queue_outcome"; echo pending > "$FAKE/main_ci"
  plan_and_grant
  sed -i 's|^      api\*check-runs\*)|      api*check-runs*) bash "$SCRIPT_ABS" revoke >/dev/null;|' "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"grant_revocado"* ]]
  grep -qx 69 "$FAKE/merged"
  grep -qx 70 "$FAKE/dequeued"
  run grep -cx 70 "$FAKE/merged"
  [ "$output" = 0 ]
}

@test "cola: método de la cola distinto de squash es anomalía sin encolar" {
  queue_on; echo MERGE > "$FAKE/queue_method"
  mkpr 71 "scripts/a.sh"; review 71 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"cola_metodo_no_squash"* ]]
  run grep -c 'enqueuePullRequest' "$FAKE/calls"
  [ "$output" = 0 ]
}

@test "cola: método de la cola ilegible (vacío con cola) es anomalía sin encolar" {
  queue_on; : > "$FAKE/queue_method"
  mkpr 72 "scripts/a.sh"; review 72 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  run grep -c 'enqueuePullRequest' "$FAKE/calls"
  [ "$output" = 0 ]
}

@test "cola: fusionada antes de la primera lectura cuenta contra max_merges, se registra y comprueba main; no pasa la segunda" {
  queue_on
  printf 'allowed_tiers=1,2,3\nttl_hours=12\nmax_merges=1\nmax_prs=50\n' > "$MERGE_SPRINT_POLICY"
  mkpr 73 "scripts/a.sh"; mkpr 74 "scripts/b.sh"
  review 73 APPROVE correctness; review 74 APPROVE correctness
  touch "$FAKE/73.merge_on_enqueue"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"máximo de merges"* ]]
  [ "$(paste -sd, "$FAKE/enqueued")" = "73" ]
  [ "$(paste -sd, "$FAKE/merged")" = "73" ]
  ledger_has MERGED 73
  grep -q 'check-runs' "$FAKE/calls"     # la CI de main tras la fusión se comprobó
  run ledger_has PARK 73 cola_rechazada
  [ "$status" -ne 0 ]
  [ ! -e "$FAKE/dequeued" ]
}

@test "serie con la cola de GitHub activa y respuesta perdida: la PR encolada se saca de la cola y el run para (exit 5)" {
  touch "$FAKE/queue_enabled"; export MERGE_SPRINT_RESYNC=0   # modo serie
  mkpr 75 "scripts/a.sh"; review 75 APPROVE correctness
  echo wait > "$FAKE/75.queue_outcome"; touch "$FAKE/75.enqueue_lost"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"merge_no_inmediato"* ]]
  grep -qx 75 "$FAKE/enqueued"
  grep -qx 75 "$FAKE/dequeued"
  [ ! -e "$FAKE/merged" ]
  run ledger_has PARK 75
  [ "$status" -ne 0 ]
}

@test "serie: gh pr merge sale con error pero la PR quedó fusionada; se registra MERGED, no se aparca" {
  export MERGE_SPRINT_RESYNC=0
  mkpr 76 "scripts/a.sh"; review 76 APPROVE correctness
  touch "$FAKE/76.merge_lost"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  ledger_has MERGED 76
  run ledger_has PARK 76
  [ "$status" -ne 0 ]
}

@test "cola: grant revocado durante la CI de la primera PR (cola vacía) es anomalía antes de encolar" {
  queue_on
  mkpr 77 "scripts/a.sh"; review 77 APPROVE correctness
  plan_and_grant
  sed -i 's|^  "pr checks")|  "pr checks") bash "$SCRIPT_ABS" revoke >/dev/null;|' "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"grant_revocado"* ]]
  run grep -c 'enqueuePullRequest' "$FAKE/calls"
  [ "$output" = 0 ]
  [ -z "$(resv_of 77)" ]
}

@test "serie: grant revocado durante la CI es anomalía antes de fusionar" {
  export MERGE_SPRINT_RESYNC=0
  mkpr 78 "scripts/a.sh"; review 78 APPROVE correctness
  plan_and_grant
  sed -i 's|^  "pr checks")|  "pr checks") bash "$SCRIPT_ABS" revoke >/dev/null;|' "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"grant_revocado"* ]]
  [ ! -e "$FAKE/merged" ]
}

@test "cola: método de la cola cambiado a MERGE durante el run es anomalía antes de encolar la PR" {
  queue_on
  mkpr 79 "scripts/a.sh"; review 79 APPROVE correctness
  plan_and_grant
  sed -i "s|^  \"pr checks\")|  \"pr checks\") echo MERGE > '$FAKE/queue_method';|" "$GH"
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [[ "$output" == *"cola_metodo_no_squash"* ]]
  run grep -c 'enqueuePullRequest' "$FAKE/calls"
  [ "$output" = 0 ]
}

@test "cola boundary: una lectura «fuera» justo tras encolar (desfase) no saca la PR; se confirma y se fusiona" {
  queue_on
  mkpr 80 "scripts/a.sh"; review 80 APPROVE correctness
  touch "$FAKE/80.fresh_lag"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ -e "$FAKE/80.fresh_lag.done" ]      # el desfase se produjo de verdad
  [ ! -e "$FAKE/dequeued" ]
  grep -qx 80 "$FAKE/merged"
  ledger_has MERGED 80
  run ledger_has PARK 80 cola_rechazada
  [ "$status" -ne 0 ]
}

@test "serie boundary: commit y estado de la fusión tardan una lectura en verse; se relee y se registra, sin anomalía" {
  export MERGE_SPRINT_RESYNC=0
  mkpr 81 "scripts/a.sh"; review 81 APPROVE correctness
  echo 2 > "$FAKE/81.lag_reads"     # la primera lectura de mergeCommit y la de state no ven la fusión
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE/81.lag_reads")" = 0 ]   # el desfase se consumió de verdad
  ledger_has MERGED 81
  [[ "$output" != *"merge_no_inmediato"* ]]
}

@test "cola boundary: fusionada durante la última espera; la retirada no la libera, se registra MERGED y cuenta" {
  queue_on; export MERGE_SPRINT_QUEUE_POLLS=1
  printf 'allowed_tiers=1,2,3\nttl_hours=12\nmax_merges=1\nmax_prs=50\n' > "$MERGE_SPRINT_POLICY"
  mkpr 90 "scripts/a.sh"; mkpr 91 "scripts/b.sh"
  review 90 APPROVE correctness; review 91 APPROVE correctness
  echo wait > "$FAKE/90.queue_outcome"; touch "$FAKE/90.merge_on_dequeue"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  ledger_has MERGED 90
  run ledger_has PARK 90 cola_agotada
  [ "$status" -ne 0 ]
  grep -q 'check-runs' "$FAKE/calls"      # CI de main comprobada tras la fusión
  [ "$(paste -sd, "$FAKE/enqueued")" = "90" ]   # max_merges=1: la 91 no entra
}

@test "cola fail: expulsión leída pero GitHub la fusiona antes de la retirada; se registra MERGED, no se aparca" {
  queue_on
  mkpr 92 "scripts/a.sh"; review 92 APPROVE correctness
  echo eject:ci_failed > "$FAKE/92.queue_outcome"; touch "$FAKE/92.merge_on_dequeue"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  ledger_has MERGED 92
  run ledger_has PARK 92 cola_expulsada
  [ "$status" -ne 0 ]
}

@test "cola: SIGTERM tras aceptar la entrada y antes de leer la respuesta; el trap saca la PR de la cola" {
  queue_on
  mkpr 93 "scripts/a.sh"; review 93 APPROVE correctness
  echo wait > "$FAKE/93.queue_outcome"; touch "$FAKE/93.term_after_enqueue"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -ne 0 ]
  [ ! -e "$FAKE/93.term_after_enqueue" ]   # la señal llegó de verdad
  grep -qx 93 "$FAKE/dequeued"
  [ ! -e "$FAKE/93.inqueue" ]
  [ ! -e "$FAKE/merged" ]
  [ -z "$(resv_of 93)" ]                     # retirada verificada: la reserva se libera
}

@test "cola error: limpieza con mutaciones fallidas y una lectura «fuera» desfasada; no se da por retirada (exit 5)" {
  queue_on
  mkpr 94 "scripts/a.sh"; review 94 APPROVE correctness
  echo wait > "$FAKE/94.queue_outcome"; touch "$FAKE/dequeue_fail" "$FAKE/94.stale_when_stopped"
  echo "bash '$SCRIPT_ABS' stop >/dev/null" > "$FAKE/94.on_poll"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ ! -e "$FAKE/94.stale_when_stopped" ]   # la lectura desfasada se produjo
  [[ "$output" == *"SIGUE en la cola"* ]]
  [[ "$output" != *"#94 sacada de la cola"* ]]
  ledger_has DEQUEUE_FALLO 94
  [ -n "$(resv_of 94)" ]
}

@test "serie boundary: gh pr merge sale con error y la fusión tarda en verse; se espera antes de releer y se registra" {
  export MERGE_SPRINT_RESYNC=0 MERGE_SPRINT_POLL_S=1
  mkpr 95 "scripts/a.sh"; review 95 APPROVE correctness
  touch "$FAKE/95.merge_lost"; echo 0.5 > "$FAKE/95.lag_secs"
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  ledger_has MERGED 95
  run ledger_has PARK 95
  [ "$status" -ne 0 ]
}
