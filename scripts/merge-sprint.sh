#!/usr/bin/env bash
# merge-sprint.sh — SE-433 v1: merges en serie bajo autorización humana previa y acotada.
#
#   review-register <pr> <informe>   registra una revisión (primera línea VERDICT: …) en el registro encadenado
#   plan                             manifiesto: PRs abiertos con revisión APPROVE sobre su head actual
#   grant <manifest-digest>          emite el grant (regla «ask»: la operadora lo aprueba desde el frontend)
#   run                              ejecuta el sprint del grant vigente, en serie y ascendente
#   status | stop | revoke | report | verify-ledger
#
# Estado: ${MERGE_SPRINT_HOME:-$HOME/.savia/merge-sprint} (fuera del repo). Política: config/merge-sprint-policy.conf.
# Nunca: rebase, force-push, revert automático, tier 4, reintento de CI.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_MS="${MERGE_SPRINT_HOME:-$HOME/.savia/merge-sprint}"
POLICY="${MERGE_SPRINT_POLICY:-$ROOT/config/merge-sprint-policy.conf}"
REPO="${MERGE_SPRINT_REPO:-gonzalezpazmonica/savia}"
GH="${GH:-gh}"
ORCH="${MERGE_SPRINT_ORCHESTRATOR:-savia-orchestrator}"
REG="$HOME_MS/reviews.jsonl"; LEDGER="$HOME_MS/ledger.jsonl"; GRANT="$HOME_MS/grant.json"
STOPF="$HOME_MS/STOP"; MANIFEST="$HOME_MS/manifest.json"
GITROOT="${MERGE_SPRINT_GIT_ROOT:-$ROOT}"     # repo git sobre el que se re-sincronizan las ramas
RESYNC="${MERGE_SPRINT_RESYNC:-1}"           # v2: re-sync con main dentro de run (0 = solo v1)
BASE="${MERGE_SPRINT_BASE:-main}"

die() { echo "merge-sprint: $*" >&2; exit "${2:-1}"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
sha() { sha256sum | cut -d' ' -f1; }
mkdir -p "$HOME_MS" && chmod 700 "$HOME_MS"

policy() {  # policy <clave> → valor; fail-closed si falta el fichero o la clave
  [[ -f "$POLICY" ]] || die "política ausente: $POLICY" 2
  local v; v=$(awk -F'=' -v k="$1" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$POLICY")
  [[ -n "$v" ]] || die "política sin '$1'" 2
  echo "$v"
}

chain_append() {  # chain_append <fichero> <json-sin-prev> → añade {"prev":…} encadenado, bajo cerrojo exclusivo
  local f="$1" body="$2"
  (
    flock -x 8 || exit 1   # sin cerrojo, dos escritores concurrentes rompen la cadena (prev duplicado)
    local prev="genesis"
    [[ -s "$f" ]] && prev=$(tail -1 "$f" | sha)
    python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["prev"]=sys.argv[2]; print(json.dumps(d,sort_keys=True,separators=(",",":")))' "$body" "$prev" >> "$f"
  ) 8>"$f.lock"
}

verify_chain() {  # verify_chain <fichero> → 0 íntegro
  local f="$1" prev="genesis" line
  [[ -s "$f" ]] || return 0
  while IFS= read -r line; do
    [[ "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("prev",""))' "$line")" == "$prev" ]] || return 1
    prev=$(printf '%s\n' "$line" | sha)
  done < "$f"
}

ledger() { chain_append "$LEDGER" "$(python3 -c 'import json,sys; print(json.dumps(dict(a.split("=",1) for a in sys.argv[1:])))' "ts=$(now)" "$@")"; }

parse_verdict() {  # parse_verdict <primera línea> → imprime "verdict pr sha role tier reviewer author" o falla
  python3 - "$1" <<'PY'
import re, sys
m = re.fullmatch(r"VERDICT: (APPROVE|HOLD) pr=(\d+) sha=([0-9a-f]{40}) role=(correctness|security) tier=([1-4]) "
                 r"reviewer=(\S+) author=(\S+) p0=(\d+) p1=(\d+) p2=(\d+) p2_blocking=(\d+)", sys.argv[1])
if not m: sys.exit(1)
v, pr, sha, role, tier, rv, au, p0, p1, p2, p2b = m.groups()
if v == "APPROVE" and (int(p0) or int(p1) or int(p2b)): v = "HOLD"
print(v, pr, sha, role, tier, rv, au)
PY
}

cmd_review_register() {
  local pr="$1" file="$2"
  [[ -f "$file" ]] || die "informe inexistente: $file"
  local parsed; parsed=$(parse_verdict "$(head -1 "$file")") || die "primera línea sin gramática VERDICT válida" 3
  read -r v p s role tier rv au <<<"$parsed"
  [[ "$p" == "$pr" ]] || die "pr del veredicto ($p) ≠ $pr" 3
  [[ "$rv" != "$au" && "$rv" != "$ORCH" ]] || die "revisor no independiente ($rv)" 3
  local copy="$HOME_MS/reviews/$pr-$s-$role-$(sha < "$file" | cut -c1-12).md"
  mkdir -p "$HOME_MS/reviews"; cp "$file" "$copy"; chmod 600 "$copy"
  chain_append "$REG" "$(printf '{"ts":"%s","pr":%s,"sha":"%s","role":"%s","tier":%s,"verdict":"%s","reviewer":"%s","author":"%s","file":"%s","hash":"%s"}' \
    "$(now)" "$pr" "$s" "$role" "$tier" "$v" "$rv" "$au" "$copy" "$(sha < "$copy")")"
  echo "registrada: #$pr $role $v sobre ${s:0:8}"
}

reviews_ok() {  # reviews_ok <pr> <sha> <tier> → 0 si hay APPROVE suficientes y ningún HOLD para (pr,sha), con hashes intactos
  python3 - "$REG" "$1" "$2" "$3" <<'PY'
import hashlib, json, sys
reg, pr, sha, tier = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
roles, hold = set(), False
try: lines = open(reg).read().splitlines()
except FileNotFoundError: sys.exit(1)
for l in lines:
    d = json.loads(l)
    if d["pr"] != pr or d["sha"] != sha: continue
    try: h = hashlib.sha256(open(d["file"], "rb").read()).hexdigest()
    except OSError: sys.exit(1)
    if h != d["hash"]: sys.exit(1)
    if d["verdict"] != "APPROVE": hold = True
    else: roles.add(d["role"])
need = {"correctness"} | ({"security"} if tier >= 3 else set())
sys.exit(0 if not hold and need <= roles else 1)
PY
}

pr_tier() {  # tier calculado por risk-tier.py sobre los ficheros del PR
  local files; files=$($GH pr diff "$1" -R "$REPO" --name-only 2>/dev/null | tr '\n' ' ')
  [[ -n "$files" ]] || { echo 4; return; }
  python3 "$ROOT/scripts/risk-tier.py" --diff "$files" --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tier",4))' 2>/dev/null || echo 4
}

blob_on_main() { git -C "$GITROOT" rev-parse -q --verify "origin/$BASE:$1" 2>/dev/null; }

required_live() {  # checks obligatorios vivos de la protección de base, uno por línea, ordenados
  $GH api "repos/$REPO/branches/$BASE/protection/required_status_checks" --jq '.contexts[]' 2>/dev/null | sort -u
}

pr_meta() {  # pr_meta <pr> → "base_ref head_repo reopens" o falla (fail-closed)
  local b r o
  b=$($GH pr view "$1" -R "$REPO" --json baseRefName --jq .baseRefName) && [[ -n "$b" ]] || return 1
  r=$($GH pr view "$1" -R "$REPO" --json headRepository,headRepositoryOwner --jq '.headRepositoryOwner.login+"/"+.headRepository.name') && [[ -n "$r" ]] || return 1
  o=$($GH api --paginate "repos/$REPO/issues/$1/events?per_page=100" --jq '[.[]|select(.event=="reopened")]|length') || return 1
  echo "$b $r $(awk '{s+=$1} END {print s+0}' <<<"$o")"
}

reviewed_shas() {  # reviewed_shas <pr> → shas con revisión registrada, del más reciente al más antiguo
  [[ -f "$REG" ]] || return 0
  python3 -c 'import json,sys
seen=[]
for l in reversed(open(sys.argv[1]).read().splitlines()):
    d=json.loads(l)
    if d["pr"]==int(sys.argv[2]) and d["sha"] not in seen: seen.append(d["sha"])
print(" ".join(seen))' "$REG" "$1"
}

cmd_plan() {
  verify_chain "$REG" || die "registro de revisiones manipulado" 4
  git -C "$GITROOT" fetch -q origin 2>/dev/null
  local max_prs allowed; max_prs=$(policy max_prs) || exit 2; allowed=$(policy allowed_tiers) || exit 2
  local out="[]" n head tier
  for n in $($GH pr list -R "$REPO" --state open --limit 200 --json number --jq '[.[].number]|sort|.[]'); do
    head=$($GH pr view "$n" -R "$REPO" --json headRefOid --jq .headRefOid)
    tier=$(pr_tier "$n")
    [[ ",$allowed," == *",$tier,"* ]] || continue
    # El workflow remoto integra main en las ramas tras cada merge: si el head actual no tiene revisión
    # propia, vale la revisión más reciente cuyo sha sea equivalente al head (§2.6). El manifiesto lleva
    # el sha revisado; run vuelve a exigir la equivalencia con el head de ese momento.
    if ! reviews_ok "$n" "$head" "$tier"; then
      local cand found=""
      for cand in $(reviewed_shas "$n"); do
        reviews_ok "$n" "$cand" "$tier" && head_equivalent "$cand" "$head" && { found="$cand"; break; }
      done
      [[ -n "$found" ]] || continue
      head="$found"
    fi
    local meta; meta=$(pr_meta "$n") || continue
    out=$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); b,r,o=sys.argv[5].split(); a.append({"pr":int(sys.argv[2]),"head":sys.argv[3],"tier":int(sys.argv[4]),"base_ref":b,"head_repo":r,"reopens":int(o)}); print(json.dumps(a))' "$out" "$n" "$head" "$tier" "$meta")
  done
  # Blobs del ejecutor y del clasificador en origin/<base> y checks obligatorios de la protección (§2.2).
  local rb cb req
  rb=$(blob_on_main scripts/merge-sprint.sh) || die "sin scripts/merge-sprint.sh en origin/$BASE" 4
  cb=$(blob_on_main scripts/risk-tier.py) || die "sin scripts/risk-tier.py en origin/$BASE" 4
  req=$(required_live)
  [[ -n "$req" ]] || die "la protección de $BASE no declara checks obligatorios" 4
  python3 -c 'import json,sys; a=json.loads(sys.argv[1])[:int(sys.argv[2])]
print(json.dumps({"repo":sys.argv[3],"base":sys.argv[4],"runner_blob":sys.argv[5],"classifier_blob":sys.argv[6],
 "required_checks":sys.argv[7].splitlines(),"prs":a},sort_keys=True,separators=(",",":")))' \
    "$out" "$max_prs" "$REPO" "$BASE" "$rb" "$cb" "$req" > "$MANIFEST"
  chmod 600 "$MANIFEST"
  echo "manifiesto: $(python3 -c 'import json,sys; print(" ".join("#%d(t%d)"%(p["pr"],p["tier"]) for p in json.load(open(sys.argv[1]))["prs"]))' "$MANIFEST")"
  echo "digest: $(sha < "$MANIFEST")"
}

cmd_grant() {
  local digest="$1"
  [[ -f "$MANIFEST" && "$(sha < "$MANIFEST")" == "$digest" ]] || die "el digest no coincide con el manifiesto vigente" 3
  local ttl max; ttl=$(policy ttl_hours) || exit 2; max=$(policy max_merges) || exit 2
  printf '{"digest":"%s","issued_at":"%s","expires_epoch":%s,"max_merges":%s,"merged":0}\n' \
    "$digest" "$(now)" "$(( $(date +%s) + ttl*3600 ))" "$max" > "$GRANT"; chmod 600 "$GRANT"
  rm -f "$STOPF"
  ledger event=GRANT digest="$digest" ttl_h="$ttl" max="$max"
  echo "grant emitido: ${digest:0:12} (TTL ${ttl} h, máx. $max merges)"
}

grant_field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$GRANT" "$1"; }
grant_set_merged() {  # el contador se actualiza solo si el grant sigue vigente; revocado, el siguiente paso para
  [[ -f "$GRANT" ]] || return 0
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["merged"]=int(sys.argv[2]); json.dump(d,open(sys.argv[1],"w"))' "$GRANT" "$1"
}

main_ci() {  # pass | fail | pending sobre un SHA de main
  $GH api "repos/$REPO/commits/$1/check-runs?per_page=100" --jq '[.check_runs[] | .conclusion // "pending"] | if length==0 then "pending" elif any(.=="pending") then "pending" elif any(.=="failure" or .=="timed_out" or .=="cancelled") then "fail" else "pass" end' 2>/dev/null || echo pending
}

required_ok() {  # checks obligatorios del PR: pass | fail | pending
  local b; b=$($GH pr checks "$1" -R "$REPO" --required 2>/dev/null | awk -F'\t' '{print $2}' | sort -u | paste -sd, -)
  [[ -z "$b" ]] && { echo pending; return; }
  [[ "$b" == *fail* ]] && { echo fail; return; }
  [[ "$b" == *pending* ]] && { echo pending; return; }
  echo pass
}

# Derivados regenerables: conflictos admisibles y diferencias ignoradas al comparar heads.
DERIVED_RE='^(\.scm/|\.confidentiality-signature$|docs/rules/INDEX\.md$|docs/rules/domain/rule-manifest\.json$)'
is_derived() { grep -qE "$DERIVED_RE" <<<"$1"; }

head_equivalent() {  # head_equivalent <sha_revisado> <sha_actual> → 0 si el actual == merge(revisado, main) salvo derivados
  [[ "$1" == "$2" ]] && return 0
  git -C "$GITROOT" cat-file -e "$1^{commit}" 2>/dev/null && git -C "$GITROOT" cat-file -e "$2^{commit}" 2>/dev/null || return 1
  local m tree changed f
  m=$(git -C "$GITROOT" merge-base "$2" origin/main 2>/dev/null) || return 1
  # Árbol resultante de mergear la versión revisada con ese main (conflictos solo admisibles en derivados).
  tree=$(git -C "$GITROOT" merge-tree --write-tree --name-only "$1" "$m" 2>/dev/null | head -1)
  [[ -n "$tree" ]] || return 1
  changed=$(git -C "$GITROOT" diff --name-only "$tree" "$2" 2>/dev/null) || return 1
  while IFS= read -r f; do
    { [[ -z "$f" ]] || is_derived "$f"; } && continue
    return 1
  done <<<"$changed"
}

resync() {  # resync <pr> → 0 al día (sincronizado y empujado) · 2 conflicto real · 3 confidencialidad · 5 fallo
  local pr="$1" br wt c
  br=$($GH pr view "$pr" -R "$REPO" --json headRefName --jq .headRefName) || return 5
  git -C "$GITROOT" fetch -q origin "$br" main || return 5
  wt="$HOME_MS/wt/$pr"
  if [[ -d "$wt" ]]; then git -C "$wt" switch -q --detach "origin/$br" || return 5
  else mkdir -p "$HOME_MS/wt"; git -C "$GITROOT" worktree add -q --detach "$wt" "origin/$br" || return 5; fi
  git -C "$wt" merge-base --is-ancestor origin/main HEAD && return 0
  if ! git -C "$wt" merge -q --no-edit origin/main >/dev/null 2>&1; then
    c=$(git -C "$wt" diff --name-only --diff-filter=U)
    [[ -n "$c" ]] || { git -C "$wt" merge --abort 2>/dev/null; return 5; }   # fallo sin conflicto (identidad, hooks…)
    if grep -qvE "$DERIVED_RE" <<<"$c"; then git -C "$wt" merge --abort; return 2; fi
    git -C "$wt" restore -q --theirs -- $c && git -C "$wt" add -- $c && git -C "$wt" commit -q --no-edit || return 5
  fi
  if [[ -f "$wt/scripts/rules-index-generate.sh" ]]; then
    (cd "$wt" && { [[ ! -f scripts/rule-manifest-generate.sh ]] || bash scripts/rule-manifest-generate.sh >/dev/null 2>&1; } && bash scripts/rules-index-generate.sh >/dev/null 2>&1) || return 5
    git -C "$wt" add docs/rules && { git -C "$wt" diff --cached --quiet || git -C "$wt" commit -q -m "chore(rules): índice y manifiesto regenerados (merge-sprint)"; }
  fi
  if [[ -f "$wt/scripts/sam.py" ]]; then
    (cd "$wt" && { [[ ! -f scripts/generate-capability-map.py ]] || python3 scripts/generate-capability-map.py >/dev/null 2>&1; }) || return 5
    # El SAM registra el último commit de cada fuente, .scm/registry.json incluido: si el mapa cambió en
    # este mismo commit, el SAM nace STALE. Se regenera y commitea hasta que check dé FRESH.
    local _i fresh=0
    for _i in 1 2 3; do
      (cd "$wt" && python3 scripts/sam.py generate >/dev/null 2>&1) || return 5
      git -C "$wt" add .scm && { git -C "$wt" diff --cached --quiet || git -C "$wt" commit -q -m "chore(scm): SAM regenerado (merge-sprint)"; }
      (cd "$wt" && python3 scripts/sam.py check 2>/dev/null | grep -q FRESH) && { fresh=1; break; }
    done
    (( fresh )) || return 5
  fi
  if [[ -f "$wt/scripts/confidentiality-scan.sh" ]]; then
    # Veredicto por código de salida: 0 = CLEAN o PASSED con avisos; ≠0 = BLOCKED. Nunca por el texto.
    (cd "$wt" && bash scripts/confidentiality-scan.sh --pr >/dev/null 2>&1) || return 3
    (cd "$wt" && bash scripts/confidentiality-sign.sh sign >/dev/null 2>&1) || return 3
    git -C "$wt" add .confidentiality-signature && { git -C "$wt" diff --cached --quiet || git -C "$wt" commit -q -m "chore: sign confidentiality audit (merge-sprint)"; }
  fi
  git -C "$wt" push -q origin "HEAD:$br" 2>/dev/null || return 5
  ledger event=RESYNC pr="$pr" head="$(git -C "$wt" rev-parse HEAD)"
}

wait_ci() {  # wait_ci <pr> → pass | fail | pending (agotado el plazo)
  local st i
  for _ in $(seq 1 "${MERGE_SPRINT_CI_POLLS:-60}"); do st=$(required_ok "$1"); [[ "$st" != pending ]] && break; sleep "${MERGE_SPRINT_POLL_S:-30}"; done
  echo "$st"
}

READIED=""   # PRs sacados de Draft en este run: si se aparcan, vuelven a Draft (§2.5)
park() {
  if [[ " $READIED " == *" $1 "* ]]; then
    $GH pr ready "$1" -R "$REPO" --undo >/dev/null 2>&1 || ledger event=DRAFT_FALLO pr="$1"
  fi
  ledger event=PARK pr="$1" reason="$2"; echo "  aparcado #$1: $2"
}

anomaly() {  # anomaly <motivo> [pr] → STOP del sprint, sin merge ni revert
  ledger event=STOP reason="$1" ${2:+pr="$2"}; echo "STOP (anomalía): $1${2:+ #$2}"; exit 5
}

# Reservas F5 (SE-387) pr.merge/<N> de este grant: distinguen un merge propio sin registrar de uno externo.
f5() { (cd "$GITROOT" && SAVIA_RESERVATIONS="$HOME_MS/reservations/${DIGEST:0:12}" bash "$ROOT/scripts/f5-state.sh" "$@"); }

mf() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print("\n".join(v) if isinstance(v,list) else v)' "$MANIFEST" "$1"; }

check_required() {  # checks obligatorios vivos ⊇ los del manifiesto y no vacíos (AC-16)
  local live; live=$(required_live)
  [[ -n "$live" ]] || anomaly checks_obligatorios_vacios
  [[ -z "$(comm -23 <(mf required_checks | sort -u) <(echo "$live"))" ]] || anomaly checks_obligatorios_reducidos
}

main_ci_gate() {  # main_ci_gate <pr> <merge_commit> → vuelve solo si main queda en verde; si no, STOP sin revert
  local st
  for _ in $(seq 1 "${MERGE_SPRINT_MAIN_POLLS:-40}"); do st=$(main_ci "$2"); [[ "$st" != pending ]] && break; sleep "${MERGE_SPRINT_POLL_S:-30}"; done
  [[ "$st" == pass ]] || { ledger event=STOP reason="main_$st" pr="$1"; echo "STOP: main '$st' tras #$1 (sin revert)"; exit 0; }
}

LABELED=""
unlabel() {  # al terminar, el auto-rebase vuelve a ver los PRs no mergeados (D6 solo pausa el manifiesto vigente)
  local n
  for n in $LABELED; do
    [[ "$($GH pr view "$n" -R "$REPO" --json state --jq .state 2>/dev/null)" == OPEN ]] || continue
    $GH pr edit "$n" -R "$REPO" --remove-label "merge-sprint:${DIGEST:0:12}" >/dev/null 2>&1
  done
}

cmd_run() {
  [[ -f "$GRANT" ]] || die "sin grant" 3
  exec 9>"$HOME_MS/run.lock"; flock -n 9 || die "otro sprint en curso" 3
  verify_chain "$LEDGER" || die "ledger manipulado" 4
  verify_chain "$REG" || die "registro de revisiones manipulado" 4
  DIGEST=$(sha < "$MANIFEST")
  [[ "$DIGEST" == "$(grant_field digest)" ]] || die "manifiesto alterado tras el grant" 4
  local allowed; allowed=$(policy allowed_tiers) || exit 2
  local merged; merged=$(grant_field merged)
  ledger event=RUN digest="$DIGEST"
  # El ejecutor y el clasificador que corren deben ser los blobs congelados en el manifiesto (AC-17).
  [[ "$(git hash-object "$ROOT/scripts/merge-sprint.sh")" == "$(mf runner_blob)" ]] || anomaly blob_ejecutor
  [[ "$(git hash-object "$ROOT/scripts/risk-tier.py")" == "$(mf classifier_blob)" ]] || anomaly blob_clasificador
  check_required
  local entries; entries=$(python3 -c 'import json,sys
for p in sorted(json.load(open(sys.argv[1]))["prs"],key=lambda p:p["pr"]): print(p["pr"],p["head"],p["tier"],p["base_ref"],p["head_repo"],p["reopens"])' "$MANIFEST") \
    || anomaly manifiesto_ilegible
  # D6: la etiqueta merge-sprint:<id> pausa el auto-rebase de los PRs del manifiesto mientras dura el run.
  local label="merge-sprint:${DIGEST:0:12}" pr head tier base hrepo reopens
  $GH label create "$label" -R "$REPO" --force --description "SE-433: auto-rebase en pausa" >/dev/null 2>&1 || anomaly etiqueta_fallida
  trap unlabel EXIT
  while read -r pr _; do
    [[ -n "$pr" && "$($GH pr view "$pr" -R "$REPO" --json state --jq .state)" == OPEN ]] || continue
    $GH pr edit "$pr" -R "$REPO" --add-label "$label" >/dev/null 2>&1 || anomaly etiqueta_fallida "$pr"
    LABELED="$LABELED $pr"
  done <<<"$entries"
  while read -r pr head tier base hrepo reopens; do
    [[ -z "$pr" ]] && continue
    [[ -e "$STOPF" ]] && { ledger event=STOP reason=manual; echo "STOP manual"; return 0; }
    [[ -f "$GRANT" && "$(grant_field digest)" == "$DIGEST" ]] || { ledger event=STOP reason=grant_revocado; echo "STOP: grant revocado"; return 0; }
    (( $(date +%s) < $(grant_field expires_epoch) )) || { ledger event=STOP reason=ttl; echo "STOP: grant caducado"; return 0; }
    (( merged < $(grant_field max_merges) )) || { ledger event=STOP reason=max; echo "STOP: máximo de merges"; return 0; }
    check_required
    local state; state=$($GH pr view "$pr" -R "$REPO" --json state --jq .state)
    if [[ "$state" == MERGED ]]; then
      # Reconciliación tras una caída (AC-25/26): solo una reserva submitted de este grant lo hace propio.
      case "$(f5 status pr.merge "$pr")" in
        closed) continue ;;   # ya mergeado y registrado por este grant
        submitted)
          local mc; mc=$($GH pr view "$pr" -R "$REPO" --json mergeCommit --jq .mergeCommit.oid)
          merged=$((merged+1)); grant_set_merged "$merged"
          ledger event=MERGED pr="$pr" tier="$tier" head="$head" merge_commit="$mc" reconciled=1
          f5 close pr.merge "$pr" >/dev/null || anomaly f5_close "$pr"
          echo "  MERGED #$pr (reconciliado) → ${mc:0:8}"
          main_ci_gate "$pr" "$mc"; continue ;;
        *) anomaly merge_externo "$pr" ;;
      esac
    fi
    local meta; meta=$(pr_meta "$pr") || anomaly pr_ilegible "$pr"
    [[ "$meta" == "$base $hrepo $reopens" ]] || anomaly "pr_alterado" "$pr"   # base, repo de head o reabierto (AC-18)
    [[ "$state" == OPEN ]] || { park "$pr" no_abierto; continue; }
    local t; t=$(pr_tier "$pr")
    (( t <= tier )) && [[ ",$allowed," == *",$t,"* ]] || { park "$pr" "tier_$t"; continue; }
    reviews_ok "$pr" "$head" "$tier" || { park "$pr" revision; continue; }
    # Si main avanza durante la espera de CI (otro merge), GitHub rechaza el merge por desfase:
    # se re-sincroniza y se vuelve a esperar, hasta MERGE_SPRINT_TRIES intentos.
    local try reason="" cur="" ok=0 ms rs
    for try in $(seq 1 "${MERGE_SPRINT_TRIES:-3}"); do
      if [[ "$RESYNC" == 1 ]]; then
        resync "$pr"; rs=$?
        case $rs in 0) ;; 2) reason=conflicto_real; break ;; 3) reason=confidencialidad; break ;; *) reason=resync_fallo; break ;; esac
        sleep "${MERGE_SPRINT_CI_SETTLE_S:-60}"
      fi
      cur=$($GH pr view "$pr" -R "$REPO" --json headRefOid --jq .headRefOid)
      git -C "$GITROOT" fetch -q origin 2>/dev/null
      head_equivalent "$head" "$cur" || { reason=head_cambiado_requiere_juez; break; }
      case "$(wait_ci "$pr")" in
        pass) ;;
        fail) reason=ci_roja; break ;;
        *) reason=ci_pendiente; break ;;
      esac
      [[ -e "$STOPF" ]] && { park "$pr" stop_antes_de_merge; ledger event=STOP reason=manual; echo "STOP manual"; return 0; }
      $GH pr ready "$pr" -R "$REPO" >/dev/null 2>&1 && READIED="$READIED $pr"
      f5 reserve pr.merge "$pr" >/dev/null && f5 mark_submitted pr.merge "$pr" >/dev/null || anomaly f5_reserva "$pr"
      if $GH pr merge "$pr" -R "$REPO" --squash --match-head-commit "$cur" >/dev/null 2>&1; then ok=1; break; fi
      ms=$($GH pr view "$pr" -R "$REPO" --json mergeStateStatus --jq .mergeStateStatus 2>/dev/null)
      if [[ "$RESYNC" == 1 && ( "$ms" == DIRTY || "$ms" == BEHIND ) ]]; then
        ledger event=RETRY pr="$pr" try="$try" reason=main_movido; reason=main_movido_sin_converger; continue
      fi
      reason=merge_rechazado; break
    done
    (( ok )) || { park "$pr" "$reason"; continue; }
    merged=$((merged+1)); grant_set_merged "$merged"
    local mc; mc=$($GH pr view "$pr" -R "$REPO" --json mergeCommit --jq .mergeCommit.oid)
    ledger event=MERGED pr="$pr" tier="$t" head="$cur" merge_commit="$mc"
    f5 close pr.merge "$pr" >/dev/null || anomaly f5_close "$pr"
    echo "  MERGED #$pr → ${mc:0:8}"
    main_ci_gate "$pr" "$mc"
  done <<<"$entries"
  ledger event=END merged="$merged"; echo "sprint terminado: $merged merges"
}

cmd_report() {
  [[ -s "$LEDGER" ]] || { echo "sin actividad"; return 0; }
  python3 - "$LEDGER" <<'PY'
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1])]
m = [e for e in ev if e.get("event") == "MERGED"]; p = [e for e in ev if e.get("event") == "PARK"]
s = [e for e in ev if e.get("event") in ("STOP", "END")]
print(f"merges: {len(m)} · aparcados: {len(p)}")
for e in m: print(f"  MERGED #{e['pr']} tier {e['tier']} → {e['merge_commit'][:8]}")
for e in p: print(f"  aparcado #{e['pr']}: {e['reason']}")
if s: print(f"fin: {s[-1].get('reason', 'completo')}")
PY
}

case "${1:-}" in
  review-register) shift; [[ $# -eq 2 ]] || die "uso: review-register <pr> <informe>"; cmd_review_register "$@" ;;
  plan) cmd_plan ;;
  grant) [[ $# -eq 2 ]] || die "uso: grant <manifest-digest>"; cmd_grant "$2" ;;
  run) cmd_run ;;
  status) [[ -f "$GRANT" ]] && cat "$GRANT" || echo "sin grant"; [[ -e "$STOPF" ]] && echo "STOP activo" ;;
  stop) touch "$STOPF"; ledger event=STOP_REQUEST; echo "STOP solicitado" ;;
  revoke) mv "$GRANT" "$HOME_MS/grant.revoked.$(date +%s)" 2>/dev/null; ledger event=REVOKE; echo "grant revocado" ;;
  report) cmd_report ;;
  verify-ledger) verify_chain "$LEDGER" && verify_chain "$REG" && echo "íntegro" || die "cadena rota" 4 ;;
  *) die "uso: merge-sprint.sh review-register|plan|grant|run|status|stop|revoke|report|verify-ledger" ;;
esac
