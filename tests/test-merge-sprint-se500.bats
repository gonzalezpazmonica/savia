#!/usr/bin/env bats
# Ref: docs/specs/SE-500-merge-sprint-sin-realineacion.spec.md (S2, AC-9 a AC-16; S3, AC-17 a AC-20)
# Integración en línea dentro de run: resolutor congelado, equivalencia ampliada, métricas y plan ordenado. gh falso, nunca GitHub.
# El arnés (gh falso, repo con remoto bare) es el de tests/test-merge-sprint.bats; el temporal lo limpia bats.

SCRIPT="scripts/merge-sprint.sh"

setup() {
  TMPDIR_T="$BATS_TEST_TMPDIR"
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
  cp scripts/merge-sprint.sh scripts/risk-tier.py scripts/f5-state.sh scripts/merge-registry-resolve.py "$MERGE_SPRINT_GIT_ROOT/scripts/"
  echo base > "$MERGE_SPRINT_GIT_ROOT/a.txt"; G add a.txt scripts; G commit -qm base; G branch -M main; G push -q origin main
}

G() { git -C "$MERGE_SPRINT_GIT_ROOT" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }


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


# ── SE-500 S2: fixtures del registro de planificación (formato antiguo) en el main del repo temporal ──
RESOLVER_PY="scripts/merge-registry-resolve.py"

reg_main() {  # registro base, roadmap.sh falso (validate/render) y generadores falsos opcionales en main
  export MERGE_SPRINT_RESYNC=1
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/docs/propuestas"
  python3 - "$MERGE_SPRINT_GIT_ROOT/docs/propuestas" <<'PY'
import json, sys
d = {"version": 2, "initiatives": [{"id": "SE-900", "status": "APPROVED", "title": "base ñ"}], "route": {"wip": 1}}
open(sys.argv[1] + "/planning-state.json", "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
open(sys.argv[1] + "/LOG.md", "w").write("<!-- append-only -->\n# Log\n\n## 2026-11-01 SE-900 APPROVED\n\nbase\n")
PY
  cat > "$MERGE_SPRINT_GIT_ROOT/scripts/roadmap.sh" <<'EOF'
#!/usr/bin/env bash
R="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
case "$1" in
  validate) [[ -n "${MS_VALIDATE_HOOK:-}" ]] && bash "$MS_VALIDATE_HOOK"
            [[ -z "${MS_VALIDATE_FAIL:-}" ]] || exit 1
            python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); i=[x["id"] for x in d["initiatives"]]; sys.exit(len(i)!=len(set(i)))' "$R/docs/propuestas/planning-state.json" ;;
  current) python3 -c 'import json,sys; print("\n".join(x["id"]+" "+x["status"] for x in json.load(open(sys.argv[1]))["initiatives"]))' "$R/docs/propuestas/planning-state.json" ;;
  render) bash "${BASH_SOURCE[0]}" current > "$R/docs/propuestas/ROADMAP-CURRENT.md" ;;
esac
EOF
  G add docs scripts; G commit -qm "registro base"; G push -q origin main
}

spec_pr() {  # spec_pr <n> <SE-id> [modo] [mensaje] : rama pr-<n> que registra la spec; modo altera el registro
  local n="$1" id="$2" mode="${3:-add}" msg="${4:-docs(spec): $2 alta}"
  G switch -q -c "pr-$n" main
  python3 - "$MERGE_SPRINT_GIT_ROOT/docs/propuestas" "$id" "$mode" <<'PY'
import json, sys
root, sid, mode = sys.argv[1:4]
p = root + "/planning-state.json"; d = json.load(open(p))
ini = d["initiatives"]
if mode.startswith("set900="):
    ini[0]["status"] = mode.split("=", 1)[1]
else:
    ini.append({"id": sid, "status": "PROPOSED", "title": "alta " + sid})
if mode == "route": d["route"] = {"wip": 9}
if mode == "newkey": d["colada"] = True
if mode == "other": ini[0]["status"] = "IMPLEMENTED"
if mode == "delete": del ini[0]
open(p, "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
lp = root + "/LOG.md"; log = open(lp).read()
head, sep, rest = log.partition("## ")
if mode == "logmod": rest = rest.replace("base\n", "base reescrita\n")
open(lp, "w").write(head + "## 2026-11-03 %s PROPOSED\n\nalta\n\n" % sid + sep + rest)
PY
  G add docs; G commit -qm "$msg"; G push -q origin "pr-$n"; G switch -q main
  echo "pr-$n" > "$FAKE/$n.branch"; echo x > "$FAKE/$n.head"
  printf 'docs/propuestas/planning-state.json\ndocs/propuestas/LOG.md\n' > "$FAKE/$n.files"
  register_head "$n"
}

register_head() {  # revisión APPROVE sobre el head actual de pr-<n>
  local s; s=$(git --git-dir="$BARE" rev-parse "refs/heads/pr-$1")
  echo "VERDICT: APPROVE pr=$1 sha=$s role=correctness tier=2 reviewer=rev-agent author=impl-agent p0=0 p1=0 p2=0 p2_blocking=0" > "$TMPDIR_T/r$1.md"
  bash "$SCRIPT" review-register "$1" "$TMPDIR_T/r$1.md" >/dev/null
}

squash_on_merge() {  # squash_on_merge <n> : el merge falso de GitHub integra de verdad pr-<n> en main (squash)
  cat > "$FAKE/$1.on_merge" <<EOF
d="$TMPDIR_T/sq$1"; git clone -q -b main "\$BARE" "\$d" && cd "\$d" && git merge --squash -q origin/pr-$1 >/dev/null \
  && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm "squash #$1" && git push -q origin main
EOF
}

ledger_has() { grep -q "$1" "$MERGE_SPRINT_HOME/ledger.jsonl"; }
merged_line() { grep '"event":"MERGED"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep "\"pr\":\"$1\""; }
branch_sha() { git --git-dir="$BARE" rev-parse "refs/heads/pr-$1"; }

assert_parked_registry() {  # assert_parked_registry <n> <fichero> : aparcada por conflicto_real con el fichero, sin juez ni push
  run grep '"event":"PARK"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  [[ "$output" == *"\"pr\":\"$1\""*"conflicto_real"* || "$output" == *"conflicto_real"*"\"pr\":\"$1\""* ]]
  [[ "$output" == *"$2"* ]]
  ! grep -qx "$1" "$FAKE/merged" 2>/dev/null || false
  ! ledger_has '"event":"JUDGE_REQUEST"' || false
}

two_spec_prs() {  # two_spec_prs <modo-121> [mensaje-121] : #120 registra SE-901 y se fusiona de verdad; #121 choca
  reg_main
  spec_pr 120 SE-901
  spec_pr 121 SE-902 "${1:-add}" "${2:-docs(spec): SE-902 alta}"
  squash_on_merge 120
}

@test "AC-9 positivo: dos PR de spec con registro en conflicto; run integra la segunda, la resuelve y la fusiona como registry_merge" {
  two_spec_prs
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(paste -sd, "$FAKE/merged")" = "120,121" ]
  merged_line 121 | grep -q '"equivalence":"registry_merge"'
  merged_line 121 | grep -q "\"resolver_blob\":\"$(git hash-object "$RESOLVER_PY")\""
  merged_line 121 | grep -q '"registry_hashes":"docs/propuestas/LOG.md:[0-9a-f]\{64\},docs/propuestas/planning-state.json:[0-9a-f]\{64\}"'
  ! ledger_has '"event":"JUDGE_REQUEST"' || false
  # El registro resuelto conserva las dos altas y las dos entradas, la nueva arriba.
  git --git-dir="$BARE" show refs/heads/pr-121:docs/propuestas/planning-state.json | jq -e '[.initiatives[].id] == ["SE-900","SE-901","SE-902"]'
  git --git-dir="$BARE" show refs/heads/pr-121:docs/propuestas/LOG.md | grep '^## ' | paste -sd'|' | grep -qx '## 2026-11-03 SE-902 PROPOSED|## 2026-11-03 SE-901 PROPOSED|## 2026-11-01 SE-900 APPROVED'
  # refs congeladas en el manifiesto desde los commits de H0
  jq -e '.prs[] | select(.pr==121) | .refs == ["SE-902"]' "$MERGE_SPRINT_HOME/manifest.json"
}

@test "AC-10 block: la PR cambia route junto a su alta → rechazo, conflicto_real con el fichero y sin juez" {
  two_spec_prs route; plan_and_grant
  local before; before=$(branch_sha 121)
  run bash "$SCRIPT" run
  assert_parked_registry 121 docs/propuestas/planning-state.json
  [ "$(branch_sha 121)" = "$before" ]
}

@test "AC-10 block: la PR añade una clave nueva al registro → rechazo" {
  two_spec_prs newkey; plan_and_grant
  run bash "$SCRIPT" run
  assert_parked_registry 121 docs/propuestas/planning-state.json
}

@test "AC-10 block: la PR cambia el estado de una iniciativa de una spec que no referencia → rechazo" {
  two_spec_prs other; plan_and_grant
  run bash "$SCRIPT" run
  assert_parked_registry 121 docs/propuestas/planning-state.json
}

@test "AC-10 block: la PR borra una iniciativa → rechazo" {
  two_spec_prs delete; plan_and_grant
  run bash "$SCRIPT" run
  assert_parked_registry 121 docs/propuestas/planning-state.json
}

@test "AC-10 block: main cambió desde el merge-base la misma iniciativa con otro valor → rechazo" {
  reg_main
  spec_pr 120 SE-900 set900=IMPLEMENTED "docs: SE-900 cierre"
  spec_pr 121 SE-900 set900=REJECTED "docs: SE-900 rechazo"
  squash_on_merge 120
  plan_and_grant
  run bash "$SCRIPT" run
  grep -qx 120 "$FAKE/merged"
  assert_parked_registry 121 docs/propuestas/planning-state.json
}

@test "AC-10 block: la PR modifica una entrada existente de LOG.md → rechazo de LOG.md" {
  two_spec_prs logmod; plan_and_grant
  run bash "$SCRIPT" run
  assert_parked_registry 121 docs/propuestas/LOG.md
}

@test "AC-10 block: cuerpo editado tras el grant para añadir SE-900; la rama cambia SE-900 y refs no la incluye → rechazo" {
  two_spec_prs other "docs(spec): SE-902 alta"; plan_and_grant
  echo "Registra SE-902 y cierra SE-900" > "$FAKE/121.body"   # el cuerpo editable nunca se consulta
  run bash "$SCRIPT" run
  assert_parked_registry 121 docs/propuestas/planning-state.json
  jq -e '.prs[] | select(.pr==121) | .refs == ["SE-902"]' "$MERGE_SPRINT_HOME/manifest.json"
  ! grep -q -- '--json body' "$FAKE/calls" || false
}

@test "AC-10 positivo: refs incluye las specs citadas en .pr-summary.md de H0 y en el nombre de la rama, no las del cuerpo" {
  reg_main
  G switch -q -c pr-130-SE-931 main; echo "Toca SE-932" > "$MERGE_SPRINT_GIT_ROOT/.pr-summary.md"
  G add .pr-summary.md; G commit -qm "docs: SE-930"; G push -q origin pr-130-SE-931; G switch -q main
  echo pr-130-SE-931 > "$FAKE/130.branch"; echo x > "$FAKE/130.head"; echo docs/x.md > "$FAKE/130.files"
  local s; s=$(git --git-dir="$BARE" rev-parse refs/heads/pr-130-SE-931)
  echo "VERDICT: APPROVE pr=130 sha=$s role=correctness tier=2 reviewer=rev-agent author=impl-agent p0=0 p1=0 p2=0 p2_blocking=0" > "$TMPDIR_T/r130.md"
  bash "$SCRIPT" review-register 130 "$TMPDIR_T/r130.md"
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  jq -e '.prs[] | select(.pr==130) | .refs == ["SE-930","SE-931","SE-932"]' "$MERGE_SPRINT_HOME/manifest.json"
}

@test "AC-10 block: el resultado que no pasa roadmap.sh validate de main se rechaza" {
  two_spec_prs; plan_and_grant
  export MS_VALIDATE_FAIL=1
  run bash "$SCRIPT" run
  grep -qx 120 "$FAKE/merged"
  assert_parked_registry 121 docs/propuestas/planning-state.json
}

integrate_by_hand() {  # integrate_by_hand <n> [byte] : integra main en pr-<n> con el resolutor; con byte, manipula un byte
  local h0 m mb
  h0=$(branch_sha "$1"); G fetch -q origin
  m=$(G rev-parse origin/main); mb=$(G merge-base "$h0" "$m")
  G switch -q --detach "$h0"
  G merge -q --no-edit origin/main >/dev/null 2>&1 || [ -n "$(G diff --name-only --diff-filter=U)" ]   # conflicto esperado
  for f in docs/propuestas/planning-state.json docs/propuestas/LOG.md; do
    python3 "$RESOLVER_PY" resolve --repo "$MERGE_SPRINT_GIT_ROOT" --base "$mb" --head "$h0" --main "$m" \
      --refs '["SE-902"]' --path "$f" --out "$MERGE_SPRINT_GIT_ROOT/$f" >/dev/null
  done
  [[ -z "${2:-}" ]] || sed -i 's/alta SE-902/alta SE-903/' "$MERGE_SPRINT_GIT_ROOT/docs/propuestas/planning-state.json"
  G add docs; G commit -qm "integración a mano" >/dev/null; G push -q origin "HEAD:pr-$1"; G switch -q main
}

@test "AC-11 positivo: integración hecha fuera con el resolutor coincide byte a byte con el recálculo → registry_merge" {
  two_spec_prs; rm -f "$FAKE/120.on_merge"
  G merge -q --squash origin/pr-120 >/dev/null; G commit -qm "squash 120"; G push -q origin main
  integrate_by_hand 121
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  merged_line 121 | grep -q '"equivalence":"registry_merge"'
}

@test "AC-11 block: registro manipulado tras resolver (un carácter) → no equivalente y sin merge" {
  two_spec_prs; rm -f "$FAKE/120.on_merge"
  G merge -q --squash origin/pr-120 >/dev/null; G commit -qm "squash 120"; G push -q origin main
  integrate_by_hand 121 manipula
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 121 "$FAKE/merged" 2>/dev/null || false
  ! ledger_has '"equivalence":"registry_merge"' || false
}

@test "AC-11b determinismo: el resolutor da la misma salida con relojes y locales distintos" {
  two_spec_prs; G merge -q --squash origin/pr-120 >/dev/null; G commit -qm "squash 120"
  local h0 m mb f
  h0=$(branch_sha 121); m=$(G rev-parse HEAD); mb=$(G merge-base "$h0" "$m")
  for f in docs/propuestas/planning-state.json docs/propuestas/LOG.md; do
    SOURCE_DATE_EPOCH=1 TZ=UTC LC_ALL=C python3 "$RESOLVER_PY" resolve --repo "$MERGE_SPRINT_GIT_ROOT" --base "$mb" --head "$h0" --main "$m" --refs '["SE-902"]' --path "$f" --out "$TMPDIR_T/a"
    SOURCE_DATE_EPOCH=2000000000 TZ=Asia/Tokyo LC_ALL=es_ES.UTF-8 python3 "$RESOLVER_PY" resolve --repo "$MERGE_SPRINT_GIT_ROOT" --base "$mb" --head "$h0" --main "$m" --refs '["SE-902"]' --path "$f" --out "$TMPDIR_T/b"
    cmp "$TMPDIR_T/a" "$TMPDIR_T/b"
    [ -s "$TMPDIR_T/a" ]
  done
  ! grep -qE 'time|datetime|random' "$RESOLVER_PY" || false
}

@test "AC-11b block: el resolutor rechaza refs inválidas, una ruta fuera de la lista cerrada y una ruta sin argumentos" {
  run python3 "$RESOLVER_PY" resolve --repo . --base HEAD --head HEAD --main HEAD --refs '["SE-1\n"]' --path docs/propuestas/LOG.md --out "$TMPDIR_T/x"
  [ "$status" -eq 2 ]; [[ "$output" == *"refs con ids inválidos"* ]]
  run python3 "$RESOLVER_PY" resolve --repo . --base HEAD --head HEAD --main HEAD --refs '[]' --path scripts/merge-sprint.sh --out "$TMPDIR_T/x"
  [ "$status" -eq 2 ]; [[ "$output" == *"scripts/merge-sprint.sh"* ]]
  run python3 "$RESOLVER_PY" resolve --repo .
  [ "$status" -eq 2 ]; [[ "$output" == *"merge-registry-resolve: "* ]]
}

# ── derivados: generadores falsos deterministas en main ──
fake_generators() {
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/docs/rules/domain"
  cat > "$MERGE_SPRINT_GIT_ROOT/scripts/rules-index-generate.sh" <<'EOF'
#!/usr/bin/env bash
P="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ls "$P/docs/rules/domain" | sort > "$P/docs/rules/INDEX.md"
EOF
  cat > "$MERGE_SPRINT_GIT_ROOT/scripts/generate-capability-map.py" <<'PY'
import os, sys
os.makedirs(".scm", exist_ok=True)
open(".scm/registry.json", "w").write(" ".join(sorted(f for f in os.listdir(".") if not f.startswith("."))))
PY
  cat > "$MERGE_SPRINT_GIT_ROOT/scripts/sam.py" <<'PY'
import os, sys
if sys.argv[1] == "generate": open(".scm/sam.json", "w").write("sam:" + open(".scm/registry.json").read())
else: print("SAM: FRESH" if open(".scm/sam.json").read() == "sam:" + open(".scm/registry.json").read() else "SAM: STALE")
PY
  echo r1 > "$MERGE_SPRINT_GIT_ROOT/docs/rules/domain/r1.md"
  bash "$MERGE_SPRINT_GIT_ROOT/scripts/rules-index-generate.sh"
  G add docs scripts; G commit -qm "generadores falsos"; G push -q origin main
}

derived_tamper() {  # derived_tamper <n> <ruta> : PR con un fichero; main avanza; se integra main y se manipula el derivado
  reg_main; fake_generators
  v2_pr "$1" "x$1.txt" "pr$1"
  main_moves "y$1.txt" main
  G switch -q --detach "$(branch_sha "$1")"; G merge -q --no-edit origin/main >/dev/null
  # SE-501: D no se regenera ni se versiona; solo la hoja de ruta (derivado restante) cuando es la ruta bajo prueba.
  # Solo el derivado bajo prueba difiere de main: así el test aísla su comparación (el resto coincide o no existe).
  [[ "$2" != docs/propuestas/ROADMAP-CURRENT.md ]] || (cd "$MERGE_SPRINT_GIT_ROOT" && bash scripts/roadmap.sh render)
  G add -A; G commit -q --allow-empty -m "integra main" >/dev/null
  mkdir -p "$(dirname "$MERGE_SPRINT_GIT_ROOT/$2")"; echo manipulado >> "$MERGE_SPRINT_GIT_ROOT/$2"
  G add -A; G commit -qm "derivado tocado" >/dev/null; G push -q origin "HEAD:pr-$1"; G switch -q main
}

@test "AC-12 control: derivados regenerados correctamente tras integrar main son equivalentes (main_merge) y se fusionan" {
  reg_main; fake_generators
  v2_pr 140 x140.txt pr140
  main_moves y140.txt main
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 140 "$FAKE/merged"
  merged_line 140 | grep -q '"equivalence":"main_merge"'
  git --git-dir="$BARE" cat-file -e refs/heads/pr-140:docs/propuestas/ROADMAP-CURRENT.md
  # SE-501 AC-13: resync ya no regenera .scm/ (D); la rama re-sincronizada no lo lleva.
  run git --git-dir="$BARE" cat-file -e refs/heads/pr-140:.scm/registry.json
  [ "$status" -ne 0 ]
}

@test "AC-12/SE-501 AC-13 block: ruta de D (.scm/) añadida en H1 antes del plan → no equivalente, sin merge" {
  derived_tamper 141 .scm/registry.json
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 141 "$FAKE/merged" 2>/dev/null || false
}

@test "AC-12/SE-501 AC-13 block: docs/rules/INDEX.md (D) modificado en H1 → no equivalente, sin merge" {
  derived_tamper 142 docs/rules/INDEX.md
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 142 "$FAKE/merged" 2>/dev/null || false
}

@test "AC-12 block: ROADMAP-CURRENT.md manipulado → no equivalente, sin merge" {
  derived_tamper 143 docs/propuestas/ROADMAP-CURRENT.md
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 143 "$FAKE/merged" 2>/dev/null || false
}

@test "AC-12 block: derivado sin generador en el código congelado solo vale si coincide con main o con H0" {
  reg_main; mkdir -p "$MERGE_SPRINT_GIT_ROOT/docs/rules"
  main_moves docs/rules/INDEX.md base-index
  v2_pr 144 x144.txt pr144
  main_moves y144.txt main
  G switch -q --detach "$(branch_sha 144)"; G merge -q --no-edit origin/main >/dev/null
  echo inventado > "$MERGE_SPRINT_GIT_ROOT/docs/rules/INDEX.md"; G commit -qam "índice inventado" >/dev/null
  G push -q origin HEAD:pr-144; G switch -q main
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 144 "$FAKE/merged" 2>/dev/null || false
}

canon_same() { python3 "$RESOLVER_PY" same "$1" "$TMPDIR_T/a" "$TMPDIR_T/b"; }

@test "AC-12b positivo: INDEX.md de propuestas con otra hora es equivalente" {
  printf '# Índice\n<!-- Last regenerated: 2026-11-03T10:00:00Z -->\n| SE-1 | APPROVED |\n' > "$TMPDIR_T/a"
  printf '# Índice\n<!-- Last regenerated: 2026-11-04T23:59:59Z -->\n| SE-1 | APPROVED |\n' > "$TMPDIR_T/b"
  run canon_same docs/propuestas/INDEX.md; [ "$status" -eq 0 ]
}

# SE-501 AC-13 (sustituye a las aserciones de rule-manifest.json en AC-12b y a «AC-5b block: generated de
# rule-manifest.json terminado en \n»): D no tiene fila en la tabla canónica; ni siquiera dos copias
# idénticas son comparables (fail-closed, código 2).
@test "SE-501 AC-13 block: rutas de D sin fila en la tabla canónica; dos copias idénticas dan 2" {
  local p
  echo '{"generated":"2026-11-03T10:00:00Z","rules":[]}' > "$TMPDIR_T/a"; cp "$TMPDIR_T/a" "$TMPDIR_T/b"
  for p in docs/rules/domain/rule-manifest.json docs/rules/INDEX.md .scm/registry.json .scm/views/x.json .confidentiality-signature; do
    run canon_same "$p"; [ "$status" -eq 2 ]
    run python3 "$RESOLVER_PY" kind "$p"; [ "$status" -eq 2 ]
  done
}

@test "AC-12b block: fila cambiada, texto extra en la fecha o dos fechas → no equivalente" {
  printf '<!-- Last regenerated: 2026-11-03T10:00:00Z -->\n| SE-1 | APPROVED |\n' > "$TMPDIR_T/a"
  printf '<!-- Last regenerated: 2026-11-03T10:00:00Z -->\n| SE-1 | REJECTED |\n' > "$TMPDIR_T/b"
  run canon_same docs/propuestas/INDEX.md; [ "$status" -eq 1 ]
  printf '<!-- Last regenerated: 2026-11-03T10:00:00Z --> colado\n| SE-1 | APPROVED |\n' > "$TMPDIR_T/b"
  run canon_same docs/propuestas/INDEX.md; [ "$status" -eq 2 ]; [[ "$output" == *"línea de fecha"* ]]
  printf '<!-- Last regenerated: 2026-11-03T10:00:00Z -->\n<!-- Last regenerated: 2026-11-03T10:00:01Z -->\n| SE-1 | APPROVED |\n' > "$TMPDIR_T/b"
  run canon_same docs/propuestas/INDEX.md; [ "$status" -eq 2 ]; [[ "$output" == *"línea de fecha"* ]]
}

fake_audit() {  # escáner que bloquea si el diff de la PR contiene SECRETO; firmador que deja una marca congelada
  printf '#!/usr/bin/env bash\n! git diff origin/main...HEAD | grep -q SECRETO\n' > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-scan.sh"
  printf '#!/usr/bin/env bash\necho "firma-congelada $(git rev-parse HEAD^{tree})" > .confidentiality-signature\n' > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-sign.sh"
  G add scripts; G commit -qm "auditoría falsa"; G push -q origin main
}

@test "AC-12c block: diff que la auditoría bloquea con una firma válida de otro diff → no equivalente" {
  reg_main; fake_audit
  v2_pr 150 x150.txt "SECRETO"
  main_moves y150.txt main
  G switch -q --detach "$(branch_sha 150)"; G merge -q --no-edit origin/main >/dev/null
  echo "firma-congelada de-otro-diff" > "$MERGE_SPRINT_GIT_ROOT/.confidentiality-signature"
  G add -A; G commit -qm "firma de otro diff" >/dev/null; G push -q origin HEAD:pr-150; G switch -q main
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 150 "$FAKE/merged" 2>/dev/null || false
}

# SE-501 AC-12/AC-13 (sustituye a «AC-12c positivo: … el ejecutor re-firma con el firmador congelado»): la
# auditoría se repite con el escáner congelado, pero nadie firma: ni el firmador de main ni el trampa de la rama.
@test "SE-501 AC-13 positivo: auditoría PASSED, el ejecutor no firma (ni el firmador congelado ni el de la rama) y la PR se fusiona" {
  reg_main; fake_audit
  G switch -q -c pr-151 main
  printf '#!/usr/bin/env bash\necho trampa > .confidentiality-signature\n' > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-sign.sh"
  G commit -qam "firmador trampa"; G push -q origin pr-151; G switch -q main
  echo pr-151 > "$FAKE/151.branch"; echo x > "$FAKE/151.head"; echo scripts/x151.sh > "$FAKE/151.files"; register_head 151
  main_moves y151.txt main
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 151 "$FAKE/merged"
  grep -q '"event":"RESYNC"' "$MERGE_SPRINT_HOME/ledger.jsonl"
  run git --git-dir="$BARE" cat-file -e refs/heads/pr-151:.confidentiality-signature
  [ "$status" -ne 0 ]
}

@test "AC-12d block: un derivado sin fila en la tabla canónica no es equivalente; toda alternativa de DERIVED_RE tiene fila" {
  run python3 "$RESOLVER_PY" kind docs/rules/domain/otro.json
  [ "$status" -eq 2 ]
  : > "$TMPDIR_T/a"; : > "$TMPDIR_T/b"
  run canon_same docs/rules/domain/otro.json
  [ "$status" -eq 2 ]
  run python3 "$RESOLVER_PY" kind $'.confidentiality-signature\n'
  [ "$status" -eq 2 ]
  local re p; re=$(sed -n "s/^DERIVED_RE='\(.*\)'$/\1/p" "$SCRIPT")
  [[ -n "$re" ]]
  for p in docs/propuestas/ROADMAP-CURRENT.md docs/propuestas/INDEX.md; do
    grep -qE "$re" <<<"$p"
    python3 "$RESOLVER_PY" kind "$p" >/dev/null
  done
  # SE-501 AC-13: D ya no es derivado regenerable; ninguna de sus rutas casa con DERIVED_RE.
  for p in .scm/INDEX.scm .scm/registry.json .confidentiality-signature docs/rules/INDEX.md docs/rules/domain/rule-manifest.json; do
    ! grep -qE "$re" <<<"$p" || false
  done
}

@test "AC-13 block: conflicto de código real se aparca con conflicto_real y el fichero, sin juez, y el sprint sigue" {
  export MERGE_SPRINT_RESYNC=1
  v2_pr 160 scripts/foo.sh "uno"
  v2_pr 161 scripts/foo.sh "dos"
  v2_pr 162 z162.txt "tres"
  squash_on_merge 160
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  # SE-500 S3: el orden congelado pone primero la independiente (#162) y luego el par que choca por número.
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["order"])' "$MERGE_SPRINT_HOME/manifest.json")" = "[162, 160, 161]" ]
  [ "$(paste -sd, "$FAKE/merged")" = "162,160" ]
  grep '"event":"PARK"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep '"pr":"161"' | grep '"reason":"conflicto_real"' | grep -q '"files":"scripts/foo.sh"'
  ! ledger_has '"event":"JUDGE_REQUEST"' || false
}

@test "AC-14 block: resolver_blob distinto del manifiesto para el sprint con anomalía y sin merge" {
  echo "# otra versión" >> "$MERGE_SPRINT_GIT_ROOT/scripts/merge-registry-resolve.py"; G commit -qam "resolutor cambiado"; G push -q origin main
  mkpr 170 "scripts/u.sh"; review 170 APPROVE correctness
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 5 ]
  [ ! -e "$FAKE/merged" ]
  ledger_has '"reason":"blob_resolutor"'
}

@test "AC-14 boundary: un resolutor trampa en la rama de la PR nunca se ejecuta; resuelve el congelado" {
  two_spec_prs
  G switch -q pr-121
  printf 'import pathlib\npathlib.Path("%s").write_text("x")\n' "$TMPDIR_T/trampa" > "$MERGE_SPRINT_GIT_ROOT/scripts/merge-registry-resolve.py"
  G commit -qam "docs(spec): SE-902 resolutor trampa"; G push -q origin pr-121; G switch -q main
  register_head 121
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ ! -e "$TMPDIR_T/trampa" ]
  merged_line 121 | grep -q '"equivalence":"registry_merge"'
}

@test "AC-15 block: la rama se mueve durante la integración; el push sin forzar falla y la PR se aparca sin pisarla" {
  two_spec_prs; plan_and_grant
  cat > "$TMPDIR_T/mover.sh" <<EOF
[[ -e "$TMPDIR_T/movida" ]] && exit 0; touch "$TMPDIR_T/movida"
git clone -q -b main "\$BARE" "$TMPDIR_T/mv" && cd "$TMPDIR_T/mv" && git switch -q pr-121 && echo otro > movido.txt && git add movido.txt \
  && git -c user.email=o@o -c user.name=o -c commit.gpgsign=false commit -qm movida && git push -q origin pr-121
EOF
  export MS_VALIDATE_HOOK="$TMPDIR_T/mover.sh"
  run bash "$SCRIPT" run
  grep -qx 120 "$FAKE/merged"
  ! grep -qx 121 "$FAKE/merged" || false
  ledger_has '"reason":"resync_fallo"'
  [ "$(git --git-dir="$BARE" log -1 --format=%s refs/heads/pr-121)" = "movida" ]
}

@test "AC-15 block: tier 4 entre los ficheros de la PR al integrar se aparca sin resolver ni empujar" {
  two_spec_prs; plan_and_grant
  local before; before=$(branch_sha 121)
  printf 'docs/propuestas/planning-state.json\ndocs/propuestas/LOG.md\nconfig/merge-sprint-policy.conf\n' > "$FAKE/121.files"
  run bash "$SCRIPT" run
  grep -qx 120 "$FAKE/merged"
  ledger_has '"reason":"tier_4"'
  [ "$(branch_sha 121)" = "$before" ]
}

@test "AC-15 block: STOP durante la integración impide el merge de la PR integrada" {
  two_spec_prs; plan_and_grant
  echo "touch '$MERGE_SPRINT_HOME/STOP'" > "$TMPDIR_T/stop.sh"; export MS_VALIDATE_HOOK="$TMPDIR_T/stop.sh"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(paste -sd, "$FAKE/merged")" = "120" ]
  ledger_has '"reason":"stop_antes_de_merge"'
}

@test "AC-16 positivo: report imprime M1, M2 y M3 desde el ledger" {
  two_spec_prs
  v2_pr 122 scripts/bar.sh uno; echo fail > "$FAKE/122.checks"
  plan_and_grant
  bash "$SCRIPT" run >/dev/null
  run bash "$SCRIPT" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"M1 total: 2/2 (1.00) sin contar CI roja"* ]]
  [[ "$output" == *"M2 total: 1 integraciones registry_merge"* ]]
  [[ "$output" == *"M3 total: 1 grant(s) para 2 merge(s)"* ]]
  [[ "$output" =~ M3\ 1\ grant\(s\),\ [0-9]+\ min ]]
}

@test "AC-16 boundary: un aparcamiento por conflicto_real cuenta en M1 y nada cuenta como registry_merge" {
  export MERGE_SPRINT_RESYNC=1
  v2_pr 163 scripts/foo.sh uno; v2_pr 164 scripts/foo.sh dos
  squash_on_merge 163
  plan_and_grant
  bash "$SCRIPT" run >/dev/null
  run bash "$SCRIPT" report
  [[ "$output" == *"M1 total: 1/2 (0.50)"* ]]
  [[ "$output" == *"M2 total: 0 integraciones"* ]]
  [[ "$output" == *"aparcado #164: conflicto_real (scripts/foo.sh)"* ]]
}

# ── Revisión independiente de la PR #1469: arreglos con test que falla sin ellos ──
plan_excludes() {  # plan_excludes <n> : plan deja fuera la PR por cabeza no equivalente y lo dice
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"excluida PR $1: la cabeza actual no es equivalente a ninguna revisión válida"* ]]
}

@test "rev-1469 P1-1 block: fichero nuevo en .scm/ que ningún generador produce, añadido tras la revisión → no equivalente" {
  derived_tamper 171 .scm/notes.md
  plan_excludes 171
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 171 "$FAKE/merged" 2>/dev/null || false
}

@test "rev-1469 P1-1 control: la misma integración sin el fichero añadido sí es equivalente (el plan no la excluye)" {
  reg_main; fake_generators
  v2_pr 172 x172.txt pr172
  main_moves y172.txt main
  G switch -q --detach "$(branch_sha 172)"; G merge -q --no-edit origin/main >/dev/null
  G add -A; G commit -q --allow-empty -m "integra main (SE-501: sin regenerar D)" >/dev/null; G push -q origin HEAD:pr-172; G switch -q main
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [[ "$output" != *"excluida PR 172"* ]]
  [[ "$output" == *"#172(t2)"* ]]
}

@test "rev-1469 AC-12 block con motivo: .scm/ y ROADMAP-CURRENT.md manipulados se excluyen en plan por no equivalentes" {
  derived_tamper 173 .scm/registry.json
  plan_excludes 173
  G switch -q main
  v2_pr 174 x174.txt pr174
  G switch -q --detach "$(branch_sha 174)"; G merge -q --no-edit origin/main >/dev/null
  (cd "$MERGE_SPRINT_GIT_ROOT" && bash scripts/rules-index-generate.sh && python3 scripts/generate-capability-map.py && python3 scripts/sam.py generate && bash scripts/roadmap.sh render)
  echo manipulado >> "$MERGE_SPRINT_GIT_ROOT/docs/propuestas/ROADMAP-CURRENT.md"
  G add -A; G commit -qm "hoja de ruta tocada" >/dev/null; G push -q origin HEAD:pr-174; G switch -q main
  plan_excludes 174
}

gate_lib_audit() {  # escáner congelado que carga .claude/hooks/lib/gate-result.sh desde ROOT_DIR = cd lógico de scripts/..
  # (la forma de los generadores reales). `source "$SCRIPT_DIR/../x"` lo resuelve el núcleo tras el enlace y ya
  # caía en main; ROOT_DIR lógico apunta a la raíz congelada, cuyo .claude antes era el de la rama.
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/.claude/hooks/lib"
  echo 'gate_ok() { return 0; }' > "$MERGE_SPRINT_GIT_ROOT/.claude/hooks/lib/gate-result.sh"
  cat > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-scan.sh" <<'SH'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/.claude/hooks/lib/gate-result.sh" || exit 2
gate_ok && ! git diff origin/main...HEAD | grep -q SECRETO
SH
  printf '#!/usr/bin/env bash\necho "firma-congelada $(git rev-parse HEAD^{tree})" > .confidentiality-signature\n' > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-sign.sh"
  G add .claude scripts; G commit -qm "auditoría con librería"; G push -q origin main
}

@test "rev-1469 P1-2 block: la librería .claude/hooks/lib de la rama nunca se ejecuta; el escáner carga la de main" {
  reg_main; gate_lib_audit
  G switch -q -c pr-175 main
  printf 'touch "%s"\ngate_ok() { return 0; }\n' "$TMPDIR_T/trampa-lib" > "$MERGE_SPRINT_GIT_ROOT/.claude/hooks/lib/gate-result.sh"
  G commit -qam "lib trampa"; G push -q origin pr-175; G switch -q main
  echo pr-175 > "$FAKE/175.branch"; echo x > "$FAKE/175.head"; echo .claude/hooks/lib/gate-result.sh > "$FAKE/175.files"; register_head 175
  main_moves y175.txt main
  plan_and_grant
  run bash "$SCRIPT" run
  [ ! -e "$TMPDIR_T/trampa-lib" ]
  [ "$status" -eq 0 ]
  grep -qx 175 "$FAKE/merged"
}

@test "rev-1469 P2-2 boundary: restos de raíces congeladas de un run anterior no bloquean la integración" {
  reg_main; fake_generators
  local d; for d in froot-resync froot-eq-plan froot-eq-run; do mkdir -p "$MERGE_SPRINT_HOME/$d"; echo resto > "$MERGE_SPRINT_HOME/$d/basura"; done
  v2_pr 176 x176.txt pr176
  main_moves y176.txt main
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 176 "$FAKE/merged"
}

@test "rev-1469 P2-2 block: un generador que escribe en la raíz congelada en vez de en el árbol → resync_fallo, sin merge" {
  # SE-501: resync ya no ejecuta los generadores de D; el generador que queda es el de la hoja de ruta.
  reg_main
  printf '[[ "$1" != render ]] || echo fuera > "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fuera.txt"\n' >> "$MERGE_SPRINT_GIT_ROOT/scripts/roadmap.sh"
  G commit -qam "generador que escribe fuera"; G push -q origin main
  v2_pr 177 x177.txt pr177
  main_moves y177.txt main
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 177 "$FAKE/merged" 2>/dev/null || false
  ledger_has '"reason":"resync_fallo"'
}

@test "rev-1469 P2-3: plan ejecuta el resolutor del commit de main congelado, no la copia local" {
  reg_main
  python3 - "$MERGE_SPRINT_GIT_ROOT/scripts/merge-registry-resolve.py" "$TMPDIR_T/marca-main" <<'PY'
import sys
p, mark = sys.argv[1:3]; s = open(p).read()
s = s.replace("import sys\n", "import sys\nopen(%r, 'a').write('main\\n')\n" % mark, 1)
open(p, "w").write(s)
PY
  G commit -qam "resolutor de main distinto de la copia local"; G push -q origin main
  v2_pr 178 x178.txt pr178
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [ -s "$TMPDIR_T/marca-main" ]
}

@test "rev-1469 P2-3 (seguridad): report no se rompe con un GRANT sin digest" {
  mkdir -p "$MERGE_SPRINT_HOME"
  printf '%s\n' '{"event":"GRANT","ts":"2026-11-03T10:00:00Z"}' \
    '{"event":"GRANT","ts":"2026-11-03T10:00:00Z","digest":"d1"}' \
    '{"event":"RUN","ts":"2026-11-03T10:01:00Z","digest":"d1"}' \
    '{"event":"MERGED","ts":"2026-11-03T10:05:00Z","digest":"d1","pr":"9","tier":"2","merge_commit":"cccccccc","equivalence":"identical"}' \
    > "$MERGE_SPRINT_HOME/ledger.jsonl"
  run bash "$SCRIPT" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"M1 total: 1/1"* ]]
  [[ "$output" == *"M3 total: 2 grant(s) para 1 merge(s)"* ]]
}

@test "rev-1469 P2-1: en la cola del juez los registros se integran desde <to> (SAFE) y el arreglo juzgado no se pierde" {
  export MERGE_SPRINT_JUDGE_POLLS=1
  reg_main
  spec_pr 180 SE-910
  plan_and_grant
  local h0 to f v
  h0=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["prs"][0]["head"])' "$MERGE_SPRINT_HOME/manifest.json")
  # Arreglo tras el grant (otra autora): cambia el título de SE-910 en el registro
  G switch -q pr-180
  sed -i 's/"alta SE-910"/"alta SE-910 corregida"/' "$MERGE_SPRINT_GIT_ROOT/docs/propuestas/planning-state.json"
  G add -A; git -C "$MERGE_SPRINT_GIT_ROOT" -c user.email=f@f -c user.name=fixer -c commit.gpgsign=false commit -qm "fix: SE-910 título"
  G push -q origin pr-180; G switch -q main
  run bash "$SCRIPT" run
  [ "$status" -eq 6 ]
  f=$(ls "$MERGE_SPRINT_HOME"/judge/*/180-*.request.json); to=${f##*/180-}; to=${to%.request.json}
  # main avanza con otra alta en el registro: la cola del juez tiene que integrar registros en conflicto
  spec_pr 181 SE-911; G merge -q --no-edit origin/pr-181 >/dev/null; G push -q origin main; echo MERGED > "$FAKE/181.state"
  squash_on_merge 180
  v=$(mktemp "$TMPDIR_T/v.XXXX")
  echo "JUDGE: SAFE pr=180 from=$h0 to=$to judge=judge-agent fix_author=f@f scope=unchanged security=unchanged reason=titulo" > "$v"
  bash "$SCRIPT" review-register 180 "$v"
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 180 "$FAKE/merged"
  merged_line 180 | grep -q '"equivalence":"judge_safe"'
  merged_line 180 | grep -q '"registry_hashes":"docs/propuestas/'
  git --git-dir="$BARE" show main:docs/propuestas/planning-state.json | grep -q '"alta SE-910 corregida"'
  git --git-dir="$BARE" show main:docs/propuestas/planning-state.json | grep -q '"SE-911"'
}

# ── Revisión independiente de la PR #1469 (segunda ronda, sha c36bed5) ──
link_head() {  # link_head <n> <ruta> : sobre el head de pr-<n>, <ruta> pasa a ser un enlace a $TMPDIR_T/victima
  echo intacta > "$TMPDIR_T/victima"
  G switch -q --detach "$(branch_sha "$1")"
  rm -f "$MERGE_SPRINT_GIT_ROOT/$2"; mkdir -p "$(dirname "$MERGE_SPRINT_GIT_ROOT/$2")"
  ln -s "$TMPDIR_T/victima" "$MERGE_SPRINT_GIT_ROOT/$2"
  G add -A; G commit -qm "enlace en $2" >/dev/null; G push -q origin "HEAD:pr-$1"; G switch -q main
}

@test "rev2-1469 P1-1 block (plan): derivado convertido en enlace tras la revisión → no equivalente y no escribe fuera del worktree" {
  reg_main; fake_generators
  v2_pr 190 x190.txt pr190
  main_moves y190.txt main
  G switch -q --detach "$(branch_sha 190)"; G merge -q --no-edit origin/main >/dev/null
  G push -q origin HEAD:pr-190; G switch -q main
  link_head 190 docs/rules/INDEX.md   # existe en main: sin el guard, la siembra desde T y el generador lo siguen
  run bash "$SCRIPT" plan
  [ "$(cat "$TMPDIR_T/victima")" = intacta ]
  [[ "$output" == *"excluida PR 190: la cabeza actual no es equivalente"* ]]
}

@test "rev2-1469 P1-1 block (run): derivado enlazado en la rama tras el grant → resync_fallo sin escribir fuera ni merge" {
  reg_main
  v2_pr 191 x191.txt pr191
  plan_and_grant
  link_head 191 docs/propuestas/ROADMAP-CURRENT.md   # roadmap.sh render escribiría a través del enlace
  main_moves y191.txt main
  run bash "$SCRIPT" run
  [ "$(cat "$TMPDIR_T/victima")" = intacta ]
  ! grep -qx 191 "$FAKE/merged" 2>/dev/null || false
  ledger_has '"event":"ENLACE_RECHAZADO"'
  ledger_has '"reason":"resync_fallo"'
}

@test "rev2-1469 P1-1 control (run): sin el enlace la misma PR se integra y se fusiona" {
  reg_main
  v2_pr 192 x192.txt pr192
  plan_and_grant
  main_moves y192.txt main
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 192 "$FAKE/merged"
  ! ledger_has '"event":"ENLACE_RECHAZADO"' || false
}

@test "rev2-1469 P1-1 block: el resolutor no escribe a través de un --out que es un enlace; con fichero normal sí" {
  reg_main; spec_pr 193 SE-930
  local m h; m=$(git -C "$MERGE_SPRINT_GIT_ROOT" rev-parse origin/main); h=$(branch_sha 193)
  echo intacta > "$TMPDIR_T/victima"; ln -s "$TMPDIR_T/victima" "$TMPDIR_T/out-enlace"
  run python3 "$RESOLVER_PY" resolve --repo "$MERGE_SPRINT_GIT_ROOT" --base "$m" --head "$h" --main "$m" --refs '["SE-930"]' --path docs/propuestas/LOG.md --out "$TMPDIR_T/out-enlace"
  [ "$status" -eq 2 ]
  [ "$(cat "$TMPDIR_T/victima")" = intacta ]
  run python3 "$RESOLVER_PY" resolve --repo "$MERGE_SPRINT_GIT_ROOT" --base "$m" --head "$h" --main "$m" --refs '["SE-930"]' --path docs/propuestas/LOG.md --out "$TMPDIR_T/out-normal"
  [ "$status" -eq 0 ]
  grep -q 'SE-930 PROPOSED' "$TMPDIR_T/out-normal"
}

# SE-501: .scm/ deja de ser derivado; el caso pasa al derivado restante sin generador en el código congelado
# (docs/propuestas/INDEX.md: reg_main no trae propuestas-index-gen.sh).
@test "rev2-1469 P2-1 (corrección) block en run: derivado de propuestas colado tras el plan → aparcada como derivados_no_equivalentes, sin juez" {
  reg_main
  v2_pr 194 x194.txt pr194
  main_moves y194.txt main
  G switch -q --detach "$(branch_sha 194)"; G merge -q --no-edit origin/main >/dev/null; G push -q origin HEAD:pr-194; G switch -q main
  plan_and_grant   # la cabeza honesta entra al manifiesto
  G switch -q --detach "$(branch_sha 194)"; echo colado > "$MERGE_SPRINT_GIT_ROOT/docs/propuestas/INDEX.md"
  G add -A; G commit -qm "índice colado" >/dev/null; G push -q origin HEAD:pr-194; G switch -q main
  run bash "$SCRIPT" run
  ! grep -qx 194 "$FAKE/merged" 2>/dev/null || false
  grep '"event":"PARK"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep '"pr":"194"' | grep -q '"reason":"derivados_no_equivalentes"'
  ! ledger_has '"event":"JUDGE_REQUEST"' || false
}

# SE-501 AC-13: una ruta de D colada tras el plan no llega a main. resync la saca (drop_d, como derived.sh drop);
# la cabeza resultante es T más ese borrado y es equivalente. Nada de D en la rama fusionada.
@test "SE-501 AC-13 run: ruta de D colada tras el plan → resync la saca del diff y la PR se fusiona sin D" {
  reg_main
  v2_pr 195 x195.txt pr195
  main_moves y195.txt main
  plan_and_grant
  G switch -q --detach "$(branch_sha 195)"; mkdir -p "$MERGE_SPRINT_GIT_ROOT/.scm"; echo colado > "$MERGE_SPRINT_GIT_ROOT/.scm/registry.json"
  G add -A; G commit -qm "D colado" >/dev/null; G push -q origin HEAD:pr-195; G switch -q main
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -qx 195 "$FAKE/merged"
  run git --git-dir="$BARE" cat-file -e refs/heads/pr-195:.scm/registry.json
  [ "$status" -ne 0 ]
  git --git-dir="$BARE" log --format=%s refs/heads/main..refs/heads/pr-195 | grep -q 'saca los derivados del diff de la PR (SE-501, merge-sprint)'
}

@test "rev2-1469 P2-1 (seguridad) block: un escaneo de confidencialidad incompleto (unknown) bloquea la integración" {
  reg_main
  printf '#!/usr/bin/env bash\n[ "${SAVIA_GATE_UNKNOWN:-warn}" = block ] && exit 2\nexit 0\n' > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-scan.sh"
  printf '#!/usr/bin/env bash\necho firma > .confidentiality-signature\n' > "$MERGE_SPRINT_GIT_ROOT/scripts/confidentiality-sign.sh"
  G add scripts; G commit -qm "escáner que no puede escanear"; G push -q origin main
  v2_pr 195 x195.txt pr195
  main_moves y195.txt main
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 195 "$FAKE/merged" 2>/dev/null || false
  ledger_has '"reason":"confidencialidad"'
}

@test "rev2-1469 P2-4: plan distingue la PR sin revisión de la PR con cabeza no equivalente" {
  mkpr 196 "scripts/u.sh"
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  grep -qx "excluida PR 196: sin revisión válida" <<<"$output"
}

@test "rev2-1469 P2-3 (seguridad): plan muestra los refs de cada PR antes del grant" {
  reg_main; spec_pr 197 SE-931
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"refs #197: SE-931"* ]]
}

@test "rev2-1469 P2-3 (corrección): un fallo al montar la raíz congelada no deja raíces froot-* atrás" {
  reg_main; fake_generators
  # .claude/hooks es prefijo del código congelado: en la rama como fichero, el montaje falla (fail-closed).
  G switch -q -c pr-198 main; mkdir -p "$MERGE_SPRINT_GIT_ROOT/.claude"; echo x > "$MERGE_SPRINT_GIT_ROOT/.claude/hooks"
  G add -A; G commit -qm "hooks como fichero"; G push -q origin pr-198; G switch -q main
  echo pr-198 > "$FAKE/198.branch"; echo x > "$FAKE/198.head"; echo scripts/x198.sh > "$FAKE/198.files"; register_head 198
  main_moves y198.txt main
  plan_and_grant
  run bash "$SCRIPT" run
  ! grep -qx 198 "$FAKE/merged" 2>/dev/null || false
  ledger_has '"reason":"resync_fallo"'
  [ -z "$(ls -d "$MERGE_SPRINT_HOME"/froot-* 2>/dev/null)" ]
}

# ── SE-500 S3: plan ordenado (AC-17 a AC-20) ──────────────────────────────────────────────────────────────
# Cada PR es una rama real pr-<n> sobre main, con sus ficheros en $FAKE/<n>.files: plan predice los choques
# con git merge-tree entre los heads revisados.

s3_pr() {  # s3_pr <n> <fichero>=<contenido>… : rama pr-<n> con esos cambios, ficheros declarados y revisión
  local n="$1" kv f; shift
  G switch -q -c "pr-$n" main
  : > "$FAKE/$n.files"
  for kv in "$@"; do
    f="${kv%%=*}"; mkdir -p "$(dirname "$MERGE_SPRINT_GIT_ROOT/$f")"
    printf '%b\n' "${kv#*=}" > "$MERGE_SPRINT_GIT_ROOT/$f"; G add "$f"; echo "$f" >> "$FAKE/$n.files"
  done
  G commit -qm "pr $n"; G push -q origin "pr-$n"; G switch -q main
  echo "pr-$n" > "$FAKE/$n.branch"; echo x > "$FAKE/$n.head"
  register_head "$n"
}

mf_get() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]],separators=(",",":")))' "$MERGE_SPRINT_HOME/manifest.json" "$1"; }

s3_three() {  # AC-17: #10 (A) y #11 (B) cambian docs/f.md de forma distinta; #12 (C) es independiente
  s3_pr 10 "docs/f.md=a"; s3_pr 11 "docs/f.md=b"; s3_pr 12 "docs/g.md=c"
}
s3_star() {   # AC-17b: #10 (B) choca con #11 (A) en docs/f.md y con #12 (C) en docs/g.md; A y C independientes
  s3_pr 10 "docs/f.md=b" "docs/g.md=b"; s3_pr 11 "docs/f.md=a"; s3_pr 12 "docs/g.md=c"
}
s3_chain() {  # control de AC-17b: cadena #10–#11–#12 (choques 10–11 en docs/f.md y 11–12 en docs/g.md)
  s3_pr 10 "docs/f.md=a"; s3_pr 11 "docs/f.md=b" "docs/g.md=b"; s3_pr 12 "docs/g.md=c"
}

fresh_env() {  # fresh_env <etiqueta> : repo, remoto, estado y gh falso nuevos (otro escenario en el mismo test)
  local t="$TMPDIR_T/$1"
  export MERGE_SPRINT_HOME="$t/state" FAKE="$t/fake" BARE="$t/origin.git" MERGE_SPRINT_GIT_ROOT="$t/clone"
  mkdir -p "$FAKE"; echo CI > "$FAKE/required"
  git init -q --bare "$BARE"; git clone -q "$BARE" "$MERGE_SPRINT_GIT_ROOT" 2>/dev/null
  # Identidad en el clon: los worktrees de resync la heredan para su commit de merge.
  G config user.email t@t; G config user.name t; G config commit.gpgsign false
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/scripts"
  cp scripts/merge-sprint.sh scripts/risk-tier.py scripts/f5-state.sh scripts/merge-registry-resolve.py "$MERGE_SPRINT_GIT_ROOT/scripts/"
  echo base > "$MERGE_SPRINT_GIT_ROOT/a.txt"; G add a.txt scripts; G commit -qm base; G branch -M main; G push -q origin main
}

sprint_with() {  # sprint_with <escenario> <voraz|ascendente> → S3_RES=«fusionadas aparcadas» de un run con re-sync; sin
  # subshell: el entorno nuevo (FAKE, MERGE_SPRINT_HOME) queda para las aserciones del test
  fresh_env "$1-$2"; export MERGE_SPRINT_RESYNC=1
  "s3_$1"; squash_on_merge 10; squash_on_merge 11; squash_on_merge 12
  bash "$SCRIPT" plan >/dev/null 2>&1 || return 1
  if [[ "$2" == ascendente ]]; then
    # El orden ascendente de SE-433 §2.5: la operadora concede un manifiesto con ese orden (digest nuevo).
    python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["order"]=sorted(d["order"]); open(p,"w").write(json.dumps(d,sort_keys=True,separators=(",",":")))' "$MERGE_SPRINT_HOME/manifest.json"
  fi
  regrant
  bash "$SCRIPT" run >"$TMPDIR_T/run-$1-$2.log" 2>&1
  S3_RES="$(cat "$FAKE/merged" 2>/dev/null | grep -c .) $(grep -c '"event":"PARK"' "$MERGE_SPRINT_HOME/ledger.jsonl")"
}

@test "AC-17: A y B chocan en docs/f.md, C independiente → order [12,10,11] y aviso «#10 chocará con #11 en docs/f.md»" {
  s3_three
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [ "$(mf_get order)" = "[12,10,11]" ]
  [ "$(mf_get collisions)" = '[{"files":["docs/f.md"],"pr":10,"with":11}]' ]
  [[ "$output" == *"#10 chocará con #11 en docs/f.md"* ]]
  [[ "$output" == *"orden: #12 #10 #11"* ]]
  [[ "$output" != *"#12 chocará"* ]]
}

@test "AC-17b plan: estrella con B=#10 → order exactamente [11,12,10]" {
  s3_star
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [ "$(mf_get order)" = "[11,12,10]" ]
  [[ "$output" == *"#10 chocará con #11 en docs/f.md"* ]]
  [[ "$output" == *"#10 chocará con #12 en docs/g.md"* ]]
}

@test "AC-17b run: estrella; el orden voraz fusiona 2 y aparca 1, el ascendente fusiona 1 y aparca 2" {
  sprint_with star voraz
  [ "$S3_RES" = "2 1" ]
  [ "$(paste -sd, "$FAKE/merged")" = "11,12" ]
  grep '"event":"PARK"' "$MERGE_SPRINT_HOME/ledger.jsonl" | grep '"pr":"10"' | grep -q conflicto_real
  sprint_with star ascendente
  [ "$S3_RES" = "1 2" ]
  [ "$(paste -sd, "$FAKE/merged")" = "10" ]
}

@test "AC-17b control negativo: en la cadena 10–11–12 voraz y ascendente dan ambos 2 fusionadas y 1 aparcada" {
  sprint_with chain voraz
  [ "$S3_RES" = "2 1" ]
  [ "$(mf_get order)" = "[10,12,11]" ]
  local voraz="$S3_RES"
  sprint_with chain ascendente
  [ "$S3_RES" = "2 1" ]
  [ "$(mf_get order)" = "[10,11,12]" ]
  [ "$S3_RES" = "$voraz" ]
}

@test "AC-18: mismas entradas, mismo order y mismo digest (también con otro locale)" {
  s3_three
  run bash "$SCRIPT" plan; [ "$status" -eq 0 ]
  local d1 o1; d1=$(sed -n 's/^digest: //p' <<<"$output"); o1=$(mf_get order)
  LC_ALL=C run bash "$SCRIPT" plan; [ "$status" -eq 0 ]
  [ "$(sed -n 's/^digest: //p' <<<"$output")" = "$d1" ]
  [ "$(mf_get order)" = "$o1" ]
  [ "$o1" = "[12,10,11]" ]
}

@test "AC-19 block: choques solo en registros, derivados de propuestas o D no generan aviso ni alteran el orden" {
  s3_pr 10 "docs/propuestas/LOG.md=uno" "docs/propuestas/ROADMAP-CURRENT.md=uno" ".scm/sam.json=uno" "docs/x10.md=a"
  s3_pr 11 "docs/propuestas/LOG.md=dos" "docs/propuestas/ROADMAP-CURRENT.md=dos" ".scm/sam.json=dos" "docs/x11.md=b"
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [ "$(mf_get collisions)" = "[]" ]
  [ "$(mf_get order)" = "[10,11]" ]
  [[ "$output" != *"chocará"* ]]
  [[ "$output" != *"solapa"* ]]
}

@test "S3 aviso: solapamiento sin conflicto en el mismo fichero se avisa pero no es colisión ni cambia el orden" {
  mkdir -p "$MERGE_SPRINT_GIT_ROOT/docs"; printf 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\n' > "$MERGE_SPRINT_GIT_ROOT/docs/h.md"; G add docs/h.md; G commit -qm h; G push -q origin main
  s3_pr 10 "docs/h.md=L1\nl2\nl3\nl4\nl5\nl6\nl7\nl8"
  s3_pr 11 "docs/h.md=l1\nl2\nl3\nl4\nl5\nl6\nl7\nL8"
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [ "$(mf_get collisions)" = "[]" ]
  [ "$(mf_get order)" = "[10,11]" ]
  [[ "$output" == *"#10 solapa con #11 en docs/h.md"* ]]
  [[ "$output" != *"chocará"* ]]
}

@test "S3 boundary: un head que no está en el repo no se da por independiente en silencio: aviso de colisión no calculable" {
  s3_pr 10 "docs/f.md=a"
  mkpr 11 "scripts/z.sh"; review 11 APPROVE correctness
  run bash "$SCRIPT" plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"#10 y #11: colisión no calculable"* ]]
  [ "$(mf_get order)" = "[10,11]" ]
}

@test "AC-20 block: order editado tras el grant → el digest no coincide y run no arranca" {
  s3_three
  plan_and_grant
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["order"]=[10,11,12]; open(p,"w").write(json.dumps(d,sort_keys=True,separators=(",",":")))' "$MERGE_SPRINT_HOME/manifest.json"
  run bash "$SCRIPT" run
  [ "$status" -eq 4 ]
  [[ "$output" == *"manifiesto alterado"* ]]
  [ ! -s "$FAKE/merged" ]
}

@test "AC-20: run sigue order y no reordena (sin re-sync, las tres se fusionan en el orden congelado)" {
  s3_three
  plan_and_grant
  run bash "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(paste -sd, "$FAKE/merged")" = "12,10,11" ]
}

@test "AC-20 block: order que no es permutación de las PR del manifiesto → anomalía, sin merge (fail-closed)" {
  local bad
  for bad in '[12,10]' '[12,10,10]' '[12,10,11,99]' '"12,10,11"'; do
    fresh_env "perm-$RANDOM"; s3_three
    bash "$SCRIPT" plan >/dev/null 2>&1
    python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["order"]=json.loads(sys.argv[2]); open(p,"w").write(json.dumps(d,sort_keys=True,separators=(",",":")))' "$MERGE_SPRINT_HOME/manifest.json" "$bad"
    regrant
    run bash "$SCRIPT" run
    [ "$status" -eq 5 ]
    [[ "$output" == *"manifiesto_ilegible"* ]]
    [ ! -s "$FAKE/merged" ]
  done
}
