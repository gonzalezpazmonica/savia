#!/usr/bin/env bash
# merge-sprint.sh — SE-433 v1: merges en serie bajo autorización humana previa y acotada.
#
#   review-register <pr> <informe>   registra una revisión (VERDICT: …) o un veredicto del juez (JUDGE: …, §2.7)
#   plan                             manifiesto: PRs abiertos con revisión APPROVE sobre su head actual
#   grant <manifest-digest>          emite el grant (regla «ask»: la operadora lo aprueba desde el frontend)
#   run                              ejecuta el sprint del grant vigente, en serie y ascendente
#   status | stop | revoke | report | verify-ledger
#
# Estado: ${MERGE_SPRINT_HOME:-$HOME/.savia/merge-sprint} (fuera del repo). Política: config/merge-sprint-policy.conf.
# Nunca: rebase, force-push, revert automático, tier 4, reintento de CI.
# Salida de run: 0 terminado o parado (STOP manual, TTL, máximo, main no verde) · 5 anomalía o sprint ya parado
# (hace falta un grant nuevo) · 6 en pausa, un PR espera al juez (§2.7) · 3/4 sin grant, cerrojo o datos manipulados.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_MS="${MERGE_SPRINT_HOME:-$HOME/.savia/merge-sprint}"
POLICY="${MERGE_SPRINT_POLICY:-$ROOT/config/merge-sprint-policy.conf}"
REPO="${MERGE_SPRINT_REPO:-gonzalezpazmonica/savia}"
GH="${GH:-gh}"
ORCH="${MERGE_SPRINT_ORCHESTRATOR:-savia-orchestrator savia-orquestadora}"   # ids del orquestador, separados por espacios
REG="$HOME_MS/reviews.jsonl"; JREG="$HOME_MS/judge.jsonl"; LEDGER="$HOME_MS/ledger.jsonl"; GRANT="$HOME_MS/grant.json"
STOPF="$HOME_MS/STOP"; MANIFEST="$HOME_MS/manifest.json"
GITROOT="${MERGE_SPRINT_GIT_ROOT:-$ROOT}"     # repo git sobre el que se re-sincronizan las ramas
RESYNC="${MERGE_SPRINT_RESYNC:-1}"           # v2: re-sync con main dentro de run (0 = solo v1)
BASE="${MERGE_SPRINT_BASE:-main}"

die() { echo "merge-sprint: $*" >&2; exit "${2:-1}"; }
is_orch() { [[ " $ORCH " == *" $1 "* ]]; }
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
  [[ "$pr" =~ ^[0-9]+$ ]] || die "pr inválido: $pr" 3
  if [[ "$(head -c 6 "$file")" == "JUDGE:" ]]; then
    # Veredicto del juez de cambios (§2.7): se registra tal cual; run lo valida y, si no es válido, para.
    local copy="$HOME_MS/judge/$pr-$(sha < "$file" | cut -c1-12).verdict.md"
    mkdir -p "$HOME_MS/judge"; cp "$file" "$copy"; chmod 600 "$copy"
    chain_append "$JREG" "$(python3 -c 'import json,sys,time; print(json.dumps({"ts":sys.argv[1],"ts_epoch":int(time.time()),"pr":int(sys.argv[2]),"file":sys.argv[3],"hash":sys.argv[4]}))' \
      "$(now)" "$pr" "$copy" "$(sha < "$copy")")"
    echo "veredicto de juez registrado: #$pr"; return 0
  fi
  local parsed; parsed=$(parse_verdict "$(head -1 "$file")") || die "primera línea sin gramática VERDICT válida" 3
  read -r v p s role tier rv au <<<"$parsed"
  [[ "$p" == "$pr" ]] || die "pr del veredicto ($p) ≠ $pr" 3
  [[ "$rv" != "$au" ]] && ! is_orch "$rv" || die "revisor no independiente ($rv)" 3
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
  # Fork borrado: GitHub devuelve owner y nombre vacíos ("/"); sin repo de head no hay metadatos fiables.
  r=$($GH pr view "$1" -R "$REPO" --json headRepository,headRepositoryOwner --jq '.headRepositoryOwner.login+"/"+.headRepository.name') && [[ "$r" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || return 1
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

clean_labels() {  # borra etiquetas merge-sprint:* de sprints muertos (kill -9 no ejecuta el trap); nunca con un run en curso
  ( flock -n 9 || exit 0
    local keep="" l
    [[ -f "$GRANT" ]] && keep="merge-sprint:$(grant_field digest | cut -c1-12)"
    # Una etiqueta por línea, sin partir en palabras ni expandir comodines: «merge-sprint:x bug» no borra «bug».
    while IFS= read -r l; do
      [[ "$l" =~ ^merge-sprint:[0-9a-f]{12}$ && "$l" != "$keep" ]] || continue
      $GH label delete "$l" -R "$REPO" --yes >/dev/null 2>&1 && ledger event=LABEL_CLEAN label="$l"
    done < <($GH label list -R "$REPO" --search merge-sprint: --limit 200 --json name --jq '.[].name' 2>/dev/null) ) 9>"$HOME_MS/run.lock"
}

pr_refs() {  # pr_refs <pr> <H0> → ids SE-NNN referenciados (JSON) desde H0: commits, .pr-summary.md y rama; [] si falla
  local br; br=$($GH pr view "$1" -R "$REPO" --json headRefName --jq .headRefName 2>/dev/null)
  python3 "$RESOLVER" refs --repo "$GITROOT" --head "$2" --base-ref "origin/$BASE" --branch "$br" 2>/dev/null || echo '[]'
}

cmd_plan() {
  verify_chain "$REG" || die "registro de revisiones manipulado" 4
  git -C "$GITROOT" fetch -q origin 2>/dev/null
  clean_labels
  local max_prs allowed; max_prs=$(policy max_prs) || exit 2; allowed=$(policy allowed_tiers) || exit 2
  # Código congelado (SE-500 S2): el commit de main y el blob del resolutor entran en el manifiesto y en el digest;
  # la equivalencia de este plan ya regenera derivados con ese mismo commit.
  local mc rsb
  mc=$(git -C "$GITROOT" rev-parse -q --verify "origin/$BASE^{commit}") || die "sin origin/$BASE" 4
  rsb=$(blob_on_main scripts/merge-registry-resolve.py) || die "sin scripts/merge-registry-resolve.py en origin/$BASE" 4
  frozen_extract "$mc" plan || die "código congelado ilegible ($mc)" 4
  # La equivalencia del plan usa el mismo resolutor que verificará run: el de main congelado, no la copia local.
  RESOLVER="$FROZEN_SRC/scripts/merge-registry-resolve.py"
  [[ "$(git hash-object "$RESOLVER" 2>/dev/null)" == "$rsb" ]] || die "resolutor congelado ilegible ($mc)" 4
  local out="[]" n head tier refs
  for n in $($GH pr list -R "$REPO" --state open --limit 200 --json number --jq '[.[].number]|sort|.[]'); do
    head=$($GH pr view "$n" -R "$REPO" --json headRefOid --jq .headRefOid)
    tier=$(pr_tier "$n")
    [[ ",$allowed," == *",$tier,"* ]] || continue
    # El workflow remoto integra main en las ramas tras cada merge: si el head actual no tiene revisión
    # propia, vale la revisión más reciente cuyo sha sea equivalente al head (§2.6). El manifiesto lleva
    # el sha revisado; run vuelve a exigir la equivalencia con el head de ese momento.
    if ! reviews_ok "$n" "$head" "$tier"; then
      local cand found="" rev=0
      for cand in $(reviewed_shas "$n"); do
        reviews_ok "$n" "$cand" "$tier" || continue
        rev=1
        head_equivalent "$cand" "$head" "$(pr_refs "$n" "$cand")" && { found="$cand"; break; }
      done
      if [[ -z "$found" ]]; then
        if (( rev )); then echo "excluida PR $n: la cabeza actual no es equivalente a ninguna revisión válida" >&2
        else echo "excluida PR $n: sin revisión válida" >&2; fi
        continue
      fi
      head="$found"
    fi
    local meta files; meta=$(pr_meta "$n") || continue
    # Los checks congelados son los de $BASE: un PR hacia otra rama no los tiene, no entra al manifiesto.
    [[ "${meta%% *}" == "$BASE" ]] || continue
    files=$($GH pr diff "$n" -R "$REPO" --name-only 2>/dev/null) && [[ -n "$files" ]] || continue
    refs=$(pr_refs "$n" "$head")
    out=$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); b,r,o=sys.argv[5].split(); a.append({"pr":int(sys.argv[2]),"head":sys.argv[3],"tier":int(sys.argv[4]),"base_ref":b,"head_repo":r,"reopens":int(o),"files":sorted(sys.argv[6].split()),"refs":json.loads(sys.argv[7])}); print(json.dumps(a))' "$out" "$n" "$head" "$tier" "$meta" "$files" "$refs")
  done
  # Blobs del ejecutor y del clasificador en origin/<base> y checks obligatorios de la protección (§2.2).
  local rb cb fb req
  rb=$(blob_on_main scripts/merge-sprint.sh) || die "sin scripts/merge-sprint.sh en origin/$BASE" 4
  cb=$(blob_on_main scripts/risk-tier.py) || die "sin scripts/risk-tier.py en origin/$BASE" 4
  fb=$(blob_on_main scripts/f5-state.sh) || die "sin scripts/f5-state.sh en origin/$BASE" 4   # decide reconciliar o merge_externo
  req=$(required_live)
  [[ -n "$req" ]] || die "la protección de $BASE no declara checks obligatorios" 4
  python3 -c 'import json,sys; a=json.loads(sys.argv[1])[:int(sys.argv[2])]
print(json.dumps({"repo":sys.argv[3],"base":sys.argv[4],"runner_blob":sys.argv[5],"classifier_blob":sys.argv[6],
 "f5_blob":sys.argv[8],"resolver_blob":sys.argv[9],"main_commit":sys.argv[10],"required_checks":sys.argv[7].splitlines(),"prs":a},sort_keys=True,separators=(",",":")))' \
    "$out" "$max_prs" "$REPO" "$BASE" "$rb" "$cb" "$req" "$fb" "$rsb" "$mc" > "$MANIFEST"
  chmod 600 "$MANIFEST"
  echo "manifiesto: $(python3 -c 'import json,sys; print(" ".join("#%d(t%d)"%(p["pr"],p["tier"]) for p in json.load(open(sys.argv[1]))["prs"]))' "$MANIFEST")"
  # refs sale de la rama (commits, .pr-summary.md, nombre): quien concede el grant ve qué iniciativas habilita.
  python3 -c 'import json,sys
for p in json.load(open(sys.argv[1]))["prs"]:
    if p.get("refs"): print("refs #%d: %s" % (p["pr"], " ".join(p["refs"])))' "$MANIFEST"
  echo "digest: $(sha < "$MANIFEST")"
}

cmd_grant() {
  local digest="$1"
  [[ -f "$MANIFEST" && "$(sha < "$MANIFEST")" == "$digest" ]] || die "el digest no coincide con el manifiesto vigente" 3
  local ttl max; ttl=$(policy ttl_hours) || exit 2; max=$(policy max_merges) || exit 2
  printf '{"digest":"%s","id":"%s","issued_at":"%s","expires_epoch":%s,"max_merges":%s,"merged":0}\n' \
    "$digest" "$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')" "$(now)" "$(( $(date +%s) + ttl*3600 ))" "$max" > "$GRANT"; chmod 600 "$GRANT"
  rm -f "$STOPF"
  ledger event=GRANT digest="$digest" ttl_h="$ttl" max="$max"
  echo "grant emitido: ${digest:0:12} (TTL ${ttl} h, máx. $max merges)"
}

grant_field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$GRANT" "$1"; }
grant_set_merged() {  # el contador se actualiza solo si el grant sigue vigente; revocado, el siguiente paso para
  # Bajo el mismo cerrojo que revoke: sin él, un revoke entre la lectura y la escritura recrearía grant.json.
  ( flock -x 7 || exit 1
    [[ -f "$GRANT" ]] || exit 0
    python3 -c 'import json,os,sys; d=json.load(open(sys.argv[1])); d["merged"]=int(sys.argv[2]); t=sys.argv[1]+".tmp"; json.dump(d,os.fdopen(os.open(t,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600),"w")); os.replace(t,sys.argv[1])' "$GRANT" "$1"
  ) 7>"$GRANT.lock"
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

# Derivados regenerables (SE-500 S2): conflictos admisibles; al comparar heads se regeneran con el código
# congelado y se comparan en su forma canónica (tabla de merge-registry-resolve.py), nunca se ignoran.
# SE-501: la firma, el .scm generado, rules/INDEX.md y rule-manifest.json (D) ya no son derivados admitidos:
# no se versionan. Quedan ROADMAP-CURRENT.md e INDEX.md de propuestas.
DERIVED_RE='^(docs/propuestas/ROADMAP-CURRENT\.md$|docs/propuestas/INDEX\.md$)'
is_derived() { grep -qE "$DERIVED_RE" <<<"$1"; }
# D (SE-501): lista cerrada de scripts/derived-paths.txt, comparación exacta o por prefijo. Sin ella, fail-closed.
# shellcheck source=derived.sh
source "$ROOT/scripts/derived.sh"
derived_paths_load "$ROOT" || die "falta scripts/derived-paths.txt (SE-501)" 2
is_d() { is_derived_path "$1"; }
# Registros (lista cerrada): se integran con el resolutor determinista y se recalculan al comparar heads.
REGISTRY_RE='^docs/propuestas/(planning-state\.json|LOG\.md)$'
is_registry() { grep -qE "$REGISTRY_RE" <<<"$1"; }
# Directorios que contienen derivados o registros: el ejecutor y los generadores escriben bajo ellos.
WRITE_DIRS_RE='^(\.scm|docs|docs/rules|docs/rules/domain|docs/propuestas)$'
no_write_links() {  # no_write_links <commit> → 0 si ningún derivado, registro ni directorio que los contiene es un
  # enlace simbólico en el árbol del commit; 1 si lo es o si git falla (fail-closed). Un enlace de la rama en esas
  # rutas haría que una escritura del ejecutor, del resolutor o de un generador acabase fuera del worktree.
  python3 - "$GITROOT" "$1" "$DERIVED_RE" "$REGISTRY_RE" "$WRITE_DIRS_RE" <<'PY'
import re, subprocess, sys
root, commit, *rx = sys.argv[1:]
out = subprocess.run(["git", "-C", root, "ls-tree", "-r", "-z", commit], capture_output=True, check=True).stdout
bad = []
for e in out.split(b"\0"):
    if not e:
        continue
    meta, path = e.split(b"\t", 1)
    p = path.decode("utf-8", "surrogateescape")
    if meta.startswith(b"120000 ") and any(re.search(r, p) for r in rx):
        bad.append(p)
if bad:
    print("enlaces en rutas de escritura: " + ",".join(bad), file=sys.stderr)
    sys.exit(1)
PY
}
safe_target() {  # safe_target <raíz> <ruta> → 0 si ningún directorio entre <raíz> y la hoja es un enlace (retira la
  # hoja si es un enlace, para que la escritura cree un fichero nuevo en vez de seguirlo); 1 si hay un enlace intermedio.
  local d="$1" c parts=()
  IFS=/ read -ra parts <<<"$2"
  for c in "${parts[@]:0:${#parts[@]}-1}"; do d="$d/$c"; [[ ! -L "$d" ]] || return 1; done
  [[ ! -L "$1/$2" ]] || rm -f -- "$1/$2"
}

# ── Código congelado (SE-500 S2): generadores del commit de main del manifiesto y resolutor con blob propio ──
RESOLVER="$ROOT/scripts/merge-registry-resolve.py"   # en run, copia verificada contra resolver_blob
FROZEN_SRC=""   # worktree del commit de main congelado: solo se leen sus scripts, nunca los de la rama de la PR
# Rutas fijas en el directorio de estado, reutilizadas: los worktrees los crea y retira git, nada se borra a mano.
wt_reset() { git -C "$GITROOT" worktree remove --force "$1" >/dev/null 2>&1; git -C "$GITROOT" worktree prune >/dev/null 2>&1; [[ ! -e "$1" ]]; }
frozen_extract() {  # frozen_extract <commit> <nombre> → FROZEN_SRC = worktree desacoplado en ese commit
  git -C "$GITROOT" cat-file -e "${1:-x}^{commit}" 2>/dev/null || return 1
  FROZEN_SRC="$HOME_MS/frozen-$2"
  if [[ -e "$FROZEN_SRC/.git" ]]; then git -C "$FROZEN_SRC" checkout -q --detach --force "$1" >/dev/null 2>&1 || return 1
  else wt_reset "$FROZEN_SRC" && git -C "$GITROOT" worktree add -q --detach "$FROZEN_SRC" "$1" >/dev/null 2>&1 || return 1; fi
  [[ "$(git -C "$FROZEN_SRC" rev-parse HEAD)" == "$(git -C "$GITROOT" rev-parse "$1^{commit}")" ]] && git -C "$FROZEN_SRC" diff --quiet HEAD
}
# Código que ejecutan los generadores (lo que ellos mismos cargan desde su ruta): siempre del commit de main
# congelado, nunca de la rama. confidentiality-scan.sh carga .claude/hooks/lib/gate-result.sh por ruta relativa.
FROZEN_CODE=(scripts .claude/hooks/lib)
frozen_overlay() {  # frozen_overlay <destino> <dir del árbol> <ruta relativa> → enlaces al árbol salvo el código congelado
  local e n p fc pre
  for e in "$2"/* "$2"/.[!.]* "$2"/..?*; do
    [[ -e "$e" || -L "$e" ]] || continue
    n="${e##*/}"; p="${3:+$3/}$n"; pre=0
    for fc in "${FROZEN_CODE[@]}"; do
      [[ "$p" == "$fc" ]] && continue 2
      [[ "$fc" == "$p/"* ]] && pre=1
    done
    if (( pre )); then
      # Un prefijo del código congelado que en la rama es enlace o no es directorio: estado inesperado, fail-closed.
      [[ -d "$e" && ! -L "$e" ]] || return 1
      mkdir "$1/$n" && frozen_overlay "$1/$n" "$e" "$p" || return 1
    else
      ln -s "$e" "$1/$n" || return 1
    fi
  done
}
frozen_root() {  # frozen_root <árbol> <nombre> → raíz nueva con el código congelado y el resto enlazado a <árbol>:
  # los generadores calculan su raíz desde su ruta (lógica), así que leen y escriben en <árbol> con el código de main.
  # Cada llamada crea su raíz: un resto de una llamada anterior no bloquea las siguientes. Liberar con froot_release.
  local f fc
  f=$(mktemp -d "$HOME_MS/froot-$2.XXXXXX") || return 1
  # Un fallo a medio montar deja solo enlaces y directorios propios: se retiran para no acumular raíces.
  frozen_overlay "$f" "$1" "" || { froot_release "$f" >/dev/null 2>&1; return 1; }
  for fc in "${FROZEN_CODE[@]}"; do
    [[ -e "$FROZEN_SRC/$fc" ]] || continue
    mkdir -p "$f/$(dirname "$fc")" && ln -s "$FROZEN_SRC/$fc" "$f/$fc" || { froot_release "$f" >/dev/null 2>&1; return 1; }
  done
  echo "$f"
}
froot_release() {  # froot_release <raíz> → 0 si solo quedaban enlaces y directorios propios (los retira); 1 si un
  # generador escribió en la raíz en vez de en el árbol (p. ej. tmp+mv sobre un enlace): resultado no fiable.
  [[ -n "$1" && -d "$1" ]] || return 1
  [[ -z "$(find "$1" -mindepth 1 ! -type l ! -type d -print -quit)" ]] || return 1
  find "$1" -type l -delete && find "$1" -depth -type d -empty -delete && [[ ! -e "$1" ]]
}
gen_propuestas() {  # INDEX.md de propuestas (solo si su forma canónica cambió) y ROADMAP-CURRENT.md
  [[ -d "$1/docs/propuestas" ]] || return 0
  if [[ -f "$2/scripts/propuestas-index-gen.sh" ]]; then
    (cd "$1" && { bash "$2/scripts/propuestas-index-gen.sh" --check >/dev/null 2>&1 || bash "$2/scripts/propuestas-index-gen.sh" >/dev/null 2>&1; }) || return 1
  fi
  if [[ -f "$2/scripts/roadmap.sh" && -f "$1/docs/propuestas/planning-state.json" ]]; then
    (cd "$1" && REPO_ROOT="$1" bash "$2/scripts/roadmap.sh" render >/dev/null 2>&1) || return 1
  fi
}
# 0 = CLEAN o PASSED. Un escaneo incompleto (unknown) bloquea: sin él, el escáner sale con 0 sin haber escaneado.
audit() { (cd "$1" && SAVIA_GATE_UNKNOWN=block bash "$2/scripts/confidentiality-scan.sh" --pr >/dev/null 2>&1); }

equiv_tree() {  # equiv_tree <sha_revisado> <sha_actual> → árbol T = merge(revisado, main integrado en el actual)
  git -C "$GITROOT" cat-file -e "$1^{commit}" 2>/dev/null && git -C "$GITROOT" cat-file -e "$2^{commit}" 2>/dev/null || return 1
  local m tree
  m=$(git -C "$GITROOT" merge-base "$2" "origin/$BASE" 2>/dev/null) || return 1
  # Conflictos solo admisibles en derivados: merge-tree escribe el árbol aunque haya conflictos.
  tree=$(git -C "$GITROOT" merge-tree --write-tree --name-only "$1" "$m" 2>/dev/null | head -1)
  [[ -n "$tree" ]] && echo "$tree"
}

head_equivalent() {  # head_equivalent <H0> <H1> [refs] → 0 si H1 == merge(H0, main) salvo registros recalculados y
  # derivados regenerados (SE-500 S2). Deja EQK = identical | main_merge | registry_merge y REG_HASHES.
  EQK=identical; REG_HASHES=""
  [[ "$1" == "$2" ]] && return 0
  EQK=main_merge
  local tree changed m f st reg=() der=()
  tree=$(equiv_tree "$1" "$2") || return 1
  changed=$(git -C "$GITROOT" diff --name-status --no-renames "$tree" "$2" 2>/dev/null) || return 1
  while IFS=$'\t' read -r st f; do
    [[ -z "$f" ]] && continue
    # SE-501 AC-13: una ruta de D solo es admisible si H1 la borra (commit de derived-drop.sh o resync);
    # añadirla o modificarla hace el head no equivalente (fail-closed). Borrar cualquier otra ruta, también.
    if is_d "$f"; then [[ "$st" == D ]] || return 1; continue; fi
    if is_registry "$f"; then reg+=("$f"); elif is_derived "$f"; then der+=("$f"); else return 1; fi
  done <<<"$changed"
  (( ${#reg[@]} + ${#der[@]} )) || return 0
  m=$(git -C "$GITROOT" merge-base "$2" "origin/$BASE" 2>/dev/null) || return 1
  for f in "${reg[@]}"; do registry_equivalent "$1" "$2" "$m" "$f" "${3:-[]}" || return 1; EQK=registry_merge; done
  (( ${#der[@]} == 0 )) || derived_equivalent "$1" "$2" "$m" "$tree" "${der[@]}"
}

registry_equivalent() {  # registry_equivalent <H0> <H1> <M> <ruta> <refs> → 0 si H1 == resolver(merge-base, H0, M) byte a byte
  local mb out="$HOME_MS/registry.resolved-${FROZEN_SRC##*-}" rc=1
  mb=$(git -C "$GITROOT" merge-base "$1" "$3" 2>/dev/null) || return 1
  rm -f "$out"
  if python3 "$RESOLVER" resolve --repo "$GITROOT" --base "$mb" --head "$1" --main "$3" --refs "$5" --path "$4" --out "$out" >/dev/null 2>&1 \
     && git -C "$GITROOT" show "$2:$4" 2>/dev/null | cmp -s - "$out"; then
    rc=0; REG_HASHES="${REG_HASHES:+$REG_HASHES,}$4:$(sha < "$out")"
  fi
  rm -f "$out"; return $rc
}

derived_equivalent() {  # derived_equivalent <H0> <H1> <M> <T> <rutas…> → 0 si cada derivado de H1 coincide con su
  # regeneración con el código congelado, en la forma canónica de su fila; la firma exige repetir la auditoría.
  # Antes de regenerar, cada derivado del worktree toma su contenido de T = merge(H0, main): lo que ningún generador
  # reescribe tiene que coincidir con T, no consigo mismo (un fichero añadido tras la revisión no es equivalente).
  local h0="$1" h1="$2" m="$3" t="$4"; shift 4
  # Rutas por modo (plan | run): un plan concurrente con un run no comparte worktree ni temporales.
  local mode="${FROZEN_SRC##*-}"; local tw="$HOME_MS/eqwt-$mode" fr="" p k gens g have rc=0 b="$HOME_MS/derived.blob-$mode"
  # H1 no está revisado: un derivado (o su directorio) convertido en enlace no es equivalente y no se toca nada.
  no_write_links "$h1" 2>/dev/null || return 1
  wt_reset "$tw" && git -C "$GITROOT" worktree add -q --detach "$tw" "$h1" >/dev/null 2>&1 || return 1
  for p in "$@"; do
    safe_target "$tw" "$p" || { rc=1; break; }
    if git -C "$GITROOT" cat-file -e "$t:$p" 2>/dev/null; then
      mkdir -p "$(dirname "$tw/$p")" && git -C "$GITROOT" show "$t:$p" > "$tw/$p" 2>/dev/null || { rc=1; break; }
    else
      rm -f "$tw/$p" || { rc=1; break; }
    fi
  done
  (( rc == 0 )) && { fr=$(frozen_root "$tw" "eq-$mode") || rc=1; }
  if (( rc == 0 )); then
    # SE-501: solo quedan derivados de propuestas; reglas y .scm no se versionan ni se regeneran aquí.
    gen_propuestas "$tw" "$fr" || rc=1
  fi
  for p in "$@"; do
    (( rc == 0 )) || break
    k=""; read -r k gens <<<"$(python3 "$RESOLVER" kind "$p" 2>/dev/null)"
    [[ -n "$k" ]] || { rc=1; break; }   # derivado sin fila en la tabla canónica: no equivalente (fail-closed)
    have=1; for g in $gens; do [[ -f "$fr/$g" ]] || have=0; done
    if [[ "$k" == audit ]]; then
      (( have )) && audit "$tw" "$fr" || rc=1
    elif (( have )); then
      rm -f "$b"; git -C "$GITROOT" show "$h1:$p" > "$b" 2>/dev/null || rm -f "$b"
      python3 "$RESOLVER" same "$p" "$b" "$tw/$p" >/dev/null 2>&1 || rc=1
    else
      # Sin generador congelado no hay regeneración posible: solo vale un contenido ya revisado (H0) o ya en main.
      g=$(git -C "$GITROOT" rev-parse -q --verify "$h1:$p" 2>/dev/null)
      [[ "$g" == "$(git -C "$GITROOT" rev-parse -q --verify "$m:$p" 2>/dev/null)" \
         || "$g" == "$(git -C "$GITROOT" rev-parse -q --verify "$h0:$p" 2>/dev/null)" ]] || rc=1
    fi
  done
  [[ -z "$fr" ]] || froot_release "$fr" || rc=1
  rm -f "$b"; wt_reset "$tw" || rc=1
  return $rc
}

resync() {  # resync <pr> <H0> <refs> → 0 al día (sincronizado y empujado) · 2 conflicto real (CONFLICT_FILES) ·
  # 3 confidencialidad · 5 fallo. Registros con el resolutor y derivados con los generadores congelados (SE-500 S2).
  local pr="$1" h0="$2" refs="${3:-[]}" br wt c f fr rc reg=() der=() other=() dd=()
  CONFLICT_FILES=""; RESOLVED=""
  br=$($GH pr view "$pr" -R "$REPO" --json headRefName --jq .headRefName) || return 5
  git -C "$GITROOT" fetch -q origin "$br" main || return 5
  # Antes de tocar el worktree: el head actual no está revisado y el resolutor y los generadores escriben en él.
  if ! no_write_links "origin/$br" 2>/dev/null; then ledger event=ENLACE_RECHAZADO pr="$pr"; return 5; fi
  wt="$HOME_MS/wt/$pr"
  if [[ -d "$wt" ]]; then git -C "$wt" switch -q --detach "origin/$br" || return 5
  else mkdir -p "$HOME_MS/wt"; git -C "$GITROOT" worktree add -q --detach "$wt" "origin/$br" || return 5; fi
  git -C "$wt" merge-base --is-ancestor origin/main HEAD && return 0
  if ! git -C "$wt" merge -q --no-edit origin/main >/dev/null 2>&1; then
    c=$(git -C "$wt" diff --name-only --diff-filter=U)
    [[ -n "$c" ]] || { git -C "$wt" merge --abort 2>/dev/null; return 5; }   # fallo sin conflicto (identidad, hooks…)
    while IFS= read -r f; do
      if is_d "$f"; then dd+=("$f")
      elif is_registry "$f"; then reg+=("$f"); elif is_derived "$f"; then der+=("$f"); else other+=("$f"); fi
    done <<<"$c"
    if (( ${#other[@]} )); then
      CONFLICT_FILES=$(IFS=,; echo "${other[*]}"); git -C "$wt" merge --abort; return 2
    fi
    # SE-501: un conflicto en D (la rama lo cambió antes del corte; main ya no lo versiona) se resuelve
    # sacándolo del índice, igual que derived-drop.sh. Mecánico: no ejecuta generadores ni firma.
    if (( ${#dd[@]} )); then git -C "$wt" rm -q --cached -- "${dd[@]}" >/dev/null || return 5; fi
    if (( ${#der[@]} )); then git -C "$wt" restore -q --theirs -- "${der[@]}" && git -C "$wt" add -- "${der[@]}" || return 5; fi
    if (( ${#reg[@]} )); then resolve_registries "$wt" "$h0" "$refs" "${reg[@]}" || { git -C "$wt" merge --abort; return 2; }; fi
    git -C "$wt" commit -q --no-edit || return 5
  fi
  drop_d "$wt" || return 5
  fr=$(frozen_root "$wt" resync) || return 5
  regen_derived "$wt" "$fr"; rc=$?
  froot_release "$fr" || { (( rc )) || rc=5; }   # un generador que escribió fuera del árbol: resultado no fiable
  (( rc == 0 )) || return $rc
  # Sin forzar: si la rama se movió desde el fetch, el push falla y la PR se aparca.
  git -C "$wt" push -q origin "HEAD:$br" 2>/dev/null || return 5
  ledger event=RESYNC pr="$pr" head="$(git -C "$wt" rev-parse HEAD)" ${RESOLVED:+resolved="$RESOLVED"}
}

drop_d() {  # drop_d <wt> → 0 si la rama ya no difiere de origin/main en D (commit de derived-drop si hacía falta)
  # SE-501 migración §4: equivalente mecánico de derived-drop.sh. Cada ruta de D distinta de main vuelve a su
  # estado en main: restaurada si main la tiene, fuera del índice si no. Nada fuera de D.
  local p todo=()
  while IFS= read -r p; do [[ -n "$p" ]] && is_d "$p" && todo+=("$p"); done \
    < <(git -C "$1" diff --name-only --no-renames origin/main HEAD 2>/dev/null)
  (( ${#todo[@]} )) || return 0
  for p in "${todo[@]}"; do
    if git -C "$1" cat-file -e "origin/main:$p" 2>/dev/null; then git -C "$1" checkout -q origin/main -- "$p" || return 1
    else git -C "$1" rm -q --cached -- "$p" >/dev/null || return 1; fi
  done
  git -C "$1" diff --cached --quiet || git -C "$1" commit -q -m "chore(derived): saca los derivados del diff de la PR (SE-501, merge-sprint)"
}

regen_derived() {  # regen_derived <wt> <raíz congelada> → 0 derivados regenerados y commiteados · 3 confidencialidad · 5 fallo
  # SE-501: D (reglas, .scm, firma) no se versiona: ni se regenera ni se firma. Quedan los derivados de propuestas
  # y el escaneo --pr, que solo lee.
  local f
  gen_propuestas "$1" "$2" || return 5
  for f in docs/propuestas/INDEX.md docs/propuestas/ROADMAP-CURRENT.md; do [[ ! -e "$1/$f" ]] || git -C "$1" add -- "$f"; done
  git -C "$1" diff --cached --quiet || git -C "$1" commit -q -m "chore(propuestas): índice y hoja de ruta regenerados (merge-sprint)"
  if [[ -f "$2/scripts/confidentiality-scan.sh" ]]; then
    # Veredicto por código de salida: 0 = CLEAN o PASSED con avisos; ≠0 = BLOCKED. Nunca por el texto.
    audit "$1" "$2" || return 3
  fi
  return 0
}

resolve_registries() {  # resolve_registries <wt> <H0> <refs> <registros…> → 0 resueltos, validados y añadidos
  # El delta sale siempre de H0 (revisado) frente al merge-base, nunca del head actual; refs, del manifiesto.
  local wt="$1" h0="$2" refs="$3" m mb f fr rej=() rc
  shift 3
  CONFLICT_FILES=$(IFS=,; echo "$*")
  m=$(git -C "$wt" rev-parse -q --verify MERGE_HEAD) && mb=$(git -C "$GITROOT" merge-base "$h0" "$m" 2>/dev/null) || return 1
  for f in "$@"; do
    safe_target "$wt" "$f" || { rej+=("$f"); continue; }
    python3 "$RESOLVER" resolve --repo "$GITROOT" --base "$mb" --head "$h0" --main "$m" --refs "$refs" --path "$f" --out "$wt/$f" >/dev/null 2>&1 || rej+=("$f")
  done
  if (( ${#rej[@]} )); then CONFLICT_FILES=$(IFS=,; echo "${rej[*]}"); return 1; fi
  git -C "$wt" add -- "$@" || return 1
  # El resultado debe pasar roadmap.sh validate con el código congelado de main; sin validador, rechazo.
  fr=$(frozen_root "$wt" resync) || return 1
  rc=1
  [[ ! -f "$fr/scripts/roadmap.sh" ]] || { (cd "$wt" && REPO_ROOT="$wt" bash "$fr/scripts/roadmap.sh" validate >/dev/null 2>&1); rc=$?; }
  froot_release "$fr" || rc=1
  (( rc == 0 )) || return 1
  RESOLVED=$(IFS=,; echo "$*"); CONFLICT_FILES=""
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
  ledger event=PARK pr="$1" reason="$2" ${3:+files="$3"}; echo "  aparcado #$1: $2${3:+ ($3)}"
}

halt() {  # halt <motivo> → el sprint queda parado: el fichero STOP con el motivo solo lo borra un grant nuevo
  printf '%s\n' "$1" > "$STOPF"
}

anomaly() {  # anomaly <motivo> [pr] → STOP del sprint, sin merge ni revert
  halt "$1"; ledger event=STOP reason="$1" ${2:+pr="$2"}; echo "STOP: $1${2:+ #$2}"; exit 5
}

stop_gate() {  # fichero STOP: vacío = STOP manual (exit 0); con motivo = sprint ya parado, no se reanuda (exit 5)
  [[ -e "$STOPF" ]] || return 0
  local r; r=$(head -1 "$STOPF")
  [[ -z "$r" ]] && { ledger event=STOP reason=manual; echo "STOP manual"; exit 0; }
  ledger event=STOP reason=parado cause="$r"; echo "STOP: sprint parado ($r); hace falta un grant nuevo"; exit 5
}

# Reservas F5 (SE-387) pr.merge/<N> por manifiesto (digest), compartidas por los grants del mismo manifiesto:
# un merge reservado bajo un grant anterior del mismo manifiesto también es propio. Distinguen un merge propio sin registrar de uno externo.
f5() { (cd "$GITROOT" && SAVIA_GH_REPO="$REPO" SAVIA_RESERVATIONS="$HOME_MS/reservations/${DIGEST:0:12}" bash "$ROOT/scripts/f5-state.sh" "$@"); }
resv_head() { mkdir -p "$HOME_MS/reservations/${DIGEST:0:12}"; echo "$HOME_MS/reservations/${DIGEST:0:12}/pr.merge__$1.head"; }
reconcilable() {  # reconcilable <pr> → imprime el SHA reservado si el merge real es de ese SHA y lo hizo la cuenta del ejecutor
  local s real by me
  s=$(cat "$(resv_head "$1")" 2>/dev/null) && [[ -n "$s" ]] || return 1
  real=$($GH pr view "$1" -R "$REPO" --json headRefOid --jq .headRefOid 2>/dev/null) && [[ "$real" == "$s" ]] || return 1
  by=$($GH pr view "$1" -R "$REPO" --json mergedBy --jq .mergedBy.login 2>/dev/null) && [[ -n "$by" ]] || return 1
  me=$($GH api user --jq .login 2>/dev/null) && [[ "$by" == "$me" ]] || return 1
  echo "$s"
}

mf() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print("\n".join(v) if isinstance(v,list) else v)' "$MANIFEST" "$1"; }
mf_entry() { python3 -c 'import json,sys; print(json.dumps(next(p for p in json.load(open(sys.argv[1]))["prs"] if p["pr"]==int(sys.argv[2]))))' "$MANIFEST" "$1"; }

check_required() {  # checks obligatorios vivos ⊇ los del manifiesto y no vacíos (AC-16)
  local live; live=$(required_live)
  [[ -n "$live" ]] || anomaly checks_obligatorios_vacios
  [[ -z "$(comm -23 <(mf required_checks | sort -u) <(echo "$live"))" ]] || anomaly checks_obligatorios_reducidos
}

sprint_gate() {  # paso 1 de cada entrada: STOP, grant vigente, TTL, contador y checks obligatorios
  stop_gate
  [[ -f "$GRANT" && "$(grant_field digest)" == "$DIGEST" ]] || anomaly grant_revocado   # §2.5: anomalía, exit ≠ 0
  (( $(date +%s) < $(grant_field expires_epoch) )) || { ledger event=STOP reason=ttl; echo "STOP: grant caducado"; exit 0; }
  (( MERGED < $(grant_field max_merges) )) || { ledger event=STOP reason=max; echo "STOP: máximo de merges"; exit 0; }
  check_required
}

main_ci_gate() {  # main_ci_gate <pr> <merge_commit> → vuelve solo si main queda en verde; si no, STOP sin revert
  local st
  for _ in $(seq 1 "${MERGE_SPRINT_MAIN_POLLS:-40}"); do st=$(main_ci "$2"); [[ "$st" != pending ]] && break; sleep "${MERGE_SPRINT_POLL_S:-30}"; done
  [[ "$st" == pass ]] || { halt "main_$st"; ledger event=STOP reason="main_$st" pr="$1"; echo "STOP: main '$st' tras #$1 (sin revert)"; exit 0; }
}

merge_at() {  # merge_at <pr> <S> → 0 mergeado; 1 con FAIL=<motivo>. Pasos 7–8 de §2.5 sobre el SHA S
  local pr="$1" s="$2"
  case "$(wait_ci "$pr")" in
    pass) ;;
    fail) FAIL=ci_roja; return 1 ;;
    *) FAIL=ci_pendiente; return 1 ;;
  esac
  [[ "$($GH pr view "$pr" -R "$REPO" --json headRefOid --jq .headRefOid)" == "$s" ]] || { FAIL=head_movido; return 1; }
  [[ -e "$STOPF" ]] && { park "$pr" stop_antes_de_merge; ledger event=STOP reason=manual; echo "STOP manual"; exit 0; }
  # Entre la comprobación del bucle y aquí pasan la espera de CI y, en la cola, la del juez: base, repo de
  # head y reaperturas se revalidan contra el manifiesto (AC-18); --match-head-commit solo fija el head.
  [[ "$($GH pr view "$pr" -R "$REPO" --json state --jq .state)" == OPEN ]] || { FAIL=no_abierto; return 1; }
  local meta; meta=$(pr_meta "$pr") || anomaly pr_ilegible "$pr"
  [[ "$meta" == "$(python3 -c 'import json,sys; p=json.loads(sys.argv[1]); print(p["base_ref"],p["head_repo"],p["reopens"])' "$(mf_entry "$pr")")" ]] || anomaly pr_alterado "$pr"
  # Solo vuelve a Draft al aparcarse lo que este run sacó de Draft (gh pr ready sale con 0 aunque no lo fuera).
  if [[ "$($GH pr view "$pr" -R "$REPO" --json isDraft --jq .isDraft 2>/dev/null)" == true ]]; then
    $GH pr ready "$pr" -R "$REPO" >/dev/null 2>&1 && READIED="$READIED $pr"
  fi
  # La reserva lleva el SHA solicitado: la reconciliación solo acepta un merge de ese SHA (AC-26).
  echo "$s" > "$(resv_head "$pr")" && f5 reserve pr.merge "$pr" >/dev/null && f5 mark_submitted pr.merge "$pr" >/dev/null || anomaly f5_reserva "$pr"
  $GH pr merge "$pr" -R "$REPO" --squash --match-head-commit "$s" >/dev/null 2>&1 && return 0
  FAIL="merge_rechazado:$($GH pr view "$pr" -R "$REPO" --json mergeStateStatus --jq .mergeStateStatus 2>/dev/null)"
  # Merge rechazado: la reserva no queda submitted, o un merge ajeno posterior pasaría por propio.
  if f5 release pr.merge "$pr" >/dev/null; then rm -f "$(resv_head "$pr")"; else ledger event=F5_RELEASE_FALLO pr="$pr"; fi
  return 1
}

ledger_merged() {  # ledger_merged <pr> → 0 si el ledger ya tiene el MERGED de ese PR para este manifiesto
  [[ -s "$LEDGER" ]] || return 1
  python3 -c 'import json,sys
sys.exit(0 if any(d.get("event")=="MERGED" and d.get("pr")==sys.argv[2] and d.get("digest")==sys.argv[3]
                  for d in map(json.loads, open(sys.argv[1]))) else 1)' "$LEDGER" "$1" "$DIGEST"
}
merged_count() {  # merges registrados en el ledger bajo el grant vigente: el contador sale del ledger, no de la memoria
  [[ -s "$LEDGER" ]] || { echo 0; return; }
  python3 -c 'import json,sys; print(sum(1 for d in map(json.loads, open(sys.argv[1])) if d.get("event")=="MERGED" and d.get("grant")==sys.argv[2]))' "$LEDGER" "$GRANT_ID"
}

record_merge() {  # record_merge <pr> <tier> <S> <equivalencia> [judge_ref] → ledger, contador, reserva cerrada y CI de main
  # La reserva sigue submitted hasta que el MERGED está en el ledger: una caída en cualquier punto anterior
  # la deja reconciliable, y al reconciliar no se repite un MERGED ya escrito (idempotente por PR y manifiesto).
  local mc; mc=$($GH pr view "$1" -R "$REPO" --json mergeCommit --jq .mergeCommit.oid) && [[ "$mc" =~ ^[0-9a-f]{40}$ ]] \
    || anomaly merge_commit_ilegible "$1"
  # Registros recalculados (registry_merge, o judge_safe con registros): blob del resolutor congelado y hashes.
  local rx=()
  [[ "$4" == registry_merge || -n "${REG_HASHES:-}" ]] && rx=(resolver_blob="$(git hash-object "$RESOLVER")" registry_hashes="${REG_HASHES:-}")
  ledger_merged "$1" || ledger event=MERGED pr="$1" digest="$DIGEST" grant="$GRANT_ID" tier="$2" head="$3" merge_commit="$mc" equivalence="$4" ${5:+judge_ref="$5"} "${rx[@]}"
  MERGED=$(merged_count); grant_set_merged "$MERGED"
  f5 close pr.merge "$1" >/dev/null || anomaly f5_close "$1"
  echo "  MERGED #$1 → ${mc:0:8}"
  main_ci_gate "$1" "$mc"
}

# ── Juez de cambios posteriores al grant (§2.7): el ejecutor no usa LLM; solo pide, filtra y verifica ──
judge_prefilter() {  # judge_prefilter <T> <H1> <tier> <entrada-json> → vacío si pasa; si no, el motivo
  python3 - "$GITROOT" "$1" "$2" "$3" "$4" "$DERIVED_RE" "$ROOT/scripts/risk-tier.py" <<'PY'
import json, re, subprocess, sys
root, t, h1, tier, entry, derived, classifier = sys.argv[1:8]
g = lambda *a: subprocess.run(["git", "-C", root, *a], capture_output=True, text=True, check=True).stdout
keep = lambda p: not re.search(derived, p)
raw = [l.split("\t") for l in g("diff", "--raw", "--no-renames", t, h1).splitlines() if l]
raw = [(m.lstrip(":").split(), p) for m, p in raw if keep(p)]
paths = [p for _, p in raw]
# Solo difieren derivados o registros y no son equivalentes: el juez no vería diff alguno, no se le pregunta.
if not paths: print("prefiltro_solo_derivados"); sys.exit(0)
out = subprocess.run(["python3", classifier, "--diff", " ".join(paths), "--json"], capture_output=True, text=True).stdout
dt = json.loads(out).get("tier", 4) if out else 4
if dt >= 3 or dt > int(tier): print("prefiltro_tier"); sys.exit(0)
if any(m[4] in ("A", "D") for m, _ in raw): print("prefiltro_alta_baja"); sys.exit(0)
num = [l.split("\t") for l in g("diff", "--numstat", "--no-renames", t, h1, "--", *paths).splitlines() if l]
if any(m[0] != m[1] for m, _ in raw) or any(a == "-" for a, _, _ in num): print("prefiltro_binario_modo"); sys.exit(0)
if set(paths) - set(json.loads(entry)["files"]): print("prefiltro_fuera_de_files"); sys.exit(0)
patch, cur, hunk = g("diff", "-U0", "--no-renames", t, h1, "--", *paths), "", False
is_test = lambda p: p.endswith(".bats") or re.search(r"(^|/)(tests?/|test_[^/]*\.py$|[^/]*_test\.py$|[^/]*\.(test|spec)\.[jt]sx?$)", p)
weak = re.compile(r"\bskip\b|\|\|\s*true\b|\bxfail\b|pytest\.mark\.skip|\.skip\(|\bxit\(|\bxdescribe\(")
for l in patch.splitlines():
    # Las cabeceras ---/+++ solo van antes del primer @@ de cada fichero: dentro de un hunk,
    # una línea borrada «-- x» se ve como «--- x» y sigue siendo contenido.
    if l.startswith("diff --git "): hunk = False; continue
    if not hunk:
        if l.startswith("+++ "): cur = l[6:]
        hunk = l.startswith("@@"); continue
    body = l[1:].strip()
    if l.startswith("-"):
        if ("@test" in body or re.search(r"\bassert|\bexpect\(", body) or (is_test(cur) and re.search(r"\bshould\b", body))
                or (cur.endswith(".bats") and (body.startswith("[") or body.startswith("run ")))):
            print("prefiltro_tests_eliminados"); sys.exit(0)
    elif l.startswith("+") and is_test(cur) and weak.search(body):
        print("prefiltro_tests_debilitados"); sys.exit(0)
if sum(int(a) + int(d) for a, d, _ in num) > 200: print("prefiltro_tamano"); sys.exit(0)
PY
}

judge_request_body() {  # judge_request_body <pr> <H0> <H1> <T> <tier> <epoch> → JSON de la solicitud · 1 fallo · 3 sin autor del arreglo
  local fixers
  # fix_author: identidades sin espacios (email del autor y trailer Fix-Author), una por línea. Si git falla o no
  # hay ningún autor (delta solo en commits de merge), la independencia del juez no es comprobable: fail-closed.
  fixers=$(git -C "$GITROOT" log --no-merges --format='%ae%n%(trailers:key=Fix-Author,valueonly)' "$3" "^$2" "^origin/$BASE") || return 1
  fixers=$(sed 's/^ *//;s/ *$//;/^$/d' <<<"$fixers" | sort -u)
  [[ -n "$fixers" ]] || return 3
  # El diff lo calcula python sin los derivados (§2.7): nunca viaja por argv (E2BIG por encima de 128 KB).
  python3 - "$GITROOT" "$REG" "$1" "$2" "$3" "$4" "$5" "$(mf_entry "$1")" "$fixers" "$DERIVED_RE" "$6" <<'PY'
import json, re, subprocess, sys
root, reg, pr, h0, h1, t, tier, entry, fixers, derived, epoch = sys.argv[1:12]
g = lambda *a: subprocess.run(["git", "-C", root, *a], capture_output=True, text=True, check=True).stdout
paths = [p for p in g("diff", "--name-only", "--no-renames", t, h1).splitlines() if p and not re.search(derived, p)]
diff = "".join(l + "\n" for l in g("diff", "--no-renames", t, h1, "--", *paths).splitlines() if not l.startswith("index ")) if paths else ""
revs = [json.loads(l) for l in open(reg)] if reg else []
revs = [r for r in revs if r["pr"] == int(pr) and r["sha"] == h0]
print(json.dumps({"pr": int(pr), "from": h0, "to": h1, "tier": int(tier), "entry": json.loads(entry),
  "review_sha256": [r["hash"] for r in revs], "authors": sorted({r["author"] for r in revs}),
  "fix_author": [x for x in fixers.splitlines() if x], "diff": diff, "requested_epoch": int(epoch)}, sort_keys=True, indent=1))
PY
}

judge_request() {  # judge_request <pr> <H0> <H1> <T> <tier> → escribe la solicitud y la registra; ≠0 si no pudo
  local f="$JDIR/$1-$3.request.json" body rc
  mkdir -p "$JDIR"
  body=$(judge_request_body "$1" "$2" "$3" "$4" "$5" "$(date +%s)"); rc=$?
  (( rc == 3 )) && anomaly judge_fix_author_vacio "$1"
  (( rc == 0 )) || return 1
  printf '%s\n' "$body" > "$f.tmp" && chmod 600 "$f.tmp" && mv "$f.tmp" "$f" || { rm -f "$f.tmp"; return 1; }
  ledger event=JUDGE_REQUEST pr="$1" from="$2" to="$3" request="$f"
  echo "  #$1 awaiting_judge (${3:0:8})"
}

judge_verdict() {  # judge_verdict <request> → SAFE:<hash> | PENDING | STOP:<motivo>
  python3 - "$JREG" "$1" "$ORCH" "${MERGE_SPRINT_JUDGE_MIN:-60}" <<'PY'
import hashlib, json, os, re, sys, time
jreg, reqf, orch, minutes = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
q = json.load(open(reqf)); deadline = q["requested_epoch"] + minutes * 60
try: recs = [json.loads(l) for l in open(jreg)]
except FileNotFoundError: recs = []
recs = [r for r in recs if r["pr"] == q["pr"] and r["ts_epoch"] >= q["requested_epoch"]]
G = re.compile(r"JUDGE: (SAFE|STOP) pr=(\d+) from=([0-9a-f]{40}) to=([0-9a-f]{40}) judge=(\S+) fix_author=(\S+) "
               r"scope=(unchanged|changed) security=(unchanged|changed) reason=([a-z0-9_-]+)")
def stop(m): print("STOP:" + m); sys.exit(0)
parsed = []
for r in recs:
    data = open(r["file"], "rb").read()
    if hashlib.sha256(data).hexdigest() != r["hash"]: stop("judge_alterado")
    m = G.fullmatch(data.decode("utf-8", "replace").split("\n", 1)[0])
    if not m: stop("judge_formato")
    # Veredicto tardío de una solicitud obsoleta de este grant (mismo from, otro to con solicitud propia):
    # nunca autoriza el head actual, así que se ignora en vez de parar el sprint por un juez lento.
    _, vpr, vfr, vto = m.groups()[:4]
    if (int(vpr) == q["pr"] and vfr == q["from"] and vto != q["to"]
            and os.path.exists(os.path.join(os.path.dirname(reqf), "%s-%s.request.json" % (vpr, vto)))): continue
    parsed.append((r, m.groups()))
for r, (v, pr, fr, to, judge, fixer, scope, sec, _) in parsed:
    if int(pr) != q["pr"] or fr != q["from"] or to != q["to"]: stop("judge_from_to")
    if judge in {*orch.split(), fixer, *q["fix_author"], *q["authors"]}: stop("judge_no_independiente")
    if q["fix_author"] and fixer not in q["fix_author"]: stop("judge_fix_author")
    if r["ts_epoch"] > deadline: stop("judge_plazo")
if len(parsed) > 1: stop("judge_duplicado")
if not parsed: stop("judge_plazo") if time.time() > deadline else print("PENDING"); sys.exit(0)
r, (v, *_, scope, sec, _) = parsed[0]
stop("judge_stop") if v != "SAFE" or scope != "unchanged" or sec != "unchanged" else print("SAFE:" + r["hash"])
PY
}

LABELED=""
unlabel() {  # al terminar, el auto-rebase vuelve a ver los PRs no mergeados (D6 solo pausa el manifiesto vigente)
  local n
  for n in $LABELED; do
    [[ "$($GH pr view "$n" -R "$REPO" --json state --jq .state 2>/dev/null)" == OPEN ]] || continue
    $GH api -X DELETE "repos/$REPO/issues/$n/labels/merge-sprint:${DIGEST:0:12}" >/dev/null 2>&1
  done
}
keep_label() { LABELED=$(tr ' ' '\n' <<<"$LABELED" | grep -vx "$1" | paste -sd' ' -); }   # PR que espera al juez (D6)

try_merge() {  # try_merge <pr> <head> <tier> [to] → RESULT=merged|awaiting_judge|<motivo>; CUR, EQ, AWAIT_TO
  # <head>: sha revisado del manifiesto. <to>: head con veredicto SAFE (§2.7); tras él solo cabe un merge de main (§2.6).
  # Si main avanza durante la espera de CI (otro merge), GitHub rechaza el merge por desfase:
  # se re-sincroniza y se vuelve a esperar, hasta MERGE_SPRINT_TRIES intentos.
  local pr="$1" head="$2" tier="$3" to="${4:-}" try rs cur tt pf refs
  RESULT=""; CONFLICT_FILES=""; REG_HASHES=""
  # refs: lista congelada en el manifiesto (cubierta por el digest); nunca el título ni el cuerpo de la PR.
  refs=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]).get("refs",[]),separators=(",",":")))' "$(mf_entry "$pr")") || anomaly manifiesto_ilegible "$pr"
  for try in $(seq 1 "${MERGE_SPRINT_TRIES:-3}"); do
    if [[ "$RESYNC" == 1 ]]; then
      # En la cola del juez la rama ya está en <to> (SAFE): el delta de registros sale de <to>, no de H0.
      resync "$pr" "${to:-$head}" "$refs"; rs=$?
      case $rs in 0) ;; 2) RESULT=conflicto_real; return ;; 3) RESULT=confidencialidad; return ;; *) RESULT=resync_fallo; return ;; esac
      sleep "${MERGE_SPRINT_CI_SETTLE_S:-60}"
    fi
    cur=$($GH pr view "$pr" -R "$REPO" --json headRefOid --jq .headRefOid)
    git -C "$GITROOT" fetch -q origin 2>/dev/null
    if head_equivalent "$head" "$cur" "$refs"; then
      EQ=$EQK
    elif [[ -n "$to" ]] && head_equivalent "$to" "$cur" "$refs"; then
      EQ=judge_safe
    else
      tt=$(equiv_tree "$head" "$cur") || { RESULT=equivalencia_ilegible; return; }
      pf=$(judge_prefilter "$tt" "$cur" "$tier" "$(mf_entry "$pr")") || anomaly judge_prefiltro_fallo "$pr"
      # Derivados o registros manipulados tras la revisión: la PR se aparca; el resto del sprint sigue.
      [[ "$pf" != prefiltro_solo_derivados ]] || { RESULT=derivados_no_equivalentes; return; }
      [[ -z "$pf" ]] || anomaly "judge_$pf" "$pr"    # el prefiltro para sin consultar al juez (AC-11)
      judge_request "$pr" "$head" "$cur" "$tt" "$tier" || anomaly judge_solicitud_fallo "$pr"
      AWAIT_TO="$cur"; RESULT=awaiting_judge; return
    fi
    if merge_at "$pr" "$cur"; then CUR="$cur"; RESULT=merged; return; fi
    RESULT=$FAIL
    if [[ "$RESYNC" == 1 && ( "$FAIL" == *:DIRTY || "$FAIL" == *:BEHIND ) ]]; then
      ledger event=RETRY pr="$pr" try="$try" reason=main_movido; RESULT=main_movido_sin_converger; continue
    fi
    return
  done
}

cmd_run() {
  [[ -f "$GRANT" ]] || die "sin grant" 3
  exec 9>"$HOME_MS/run.lock"; flock -n 9 || die "otro sprint en curso" 3
  verify_chain "$LEDGER" || die "ledger manipulado" 4
  verify_chain "$REG" || die "registro de revisiones manipulado" 4
  verify_chain "$JREG" || die "registro de veredictos del juez manipulado" 4
  DIGEST=$(sha < "$MANIFEST")
  [[ "$DIGEST" == "$(grant_field digest)" ]] || die "manifiesto alterado tras el grant" 4
  # Solicitudes al juez acotadas a este grant (§2.7): las de grants anteriores nunca se reutilizan.
  GRANT_ID=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("id") or d["digest"][:12])' "$GRANT")
  JDIR="$HOME_MS/judge/$GRANT_ID"
  local allowed; allowed=$(policy allowed_tiers) || exit 2
  stop_gate   # un sprint parado (anomalía o main no verde) no se reanuda con el mismo grant
  MERGED=$(merged_count)
  ledger event=RUN digest="$DIGEST" candidates="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["prs"]))' "$MANIFEST")"
  # La base de la equivalencia y del juez es la congelada en el manifiesto, no la del entorno.
  [[ "$(mf base)" == "$BASE" ]] || anomaly base_distinta
  # El ejecutor, el clasificador y las reservas F5 que corren deben ser los blobs congelados en el manifiesto (AC-17).
  [[ "$(git hash-object "$ROOT/scripts/merge-sprint.sh")" == "$(mf runner_blob)" ]] || anomaly blob_ejecutor
  [[ "$(git hash-object "$ROOT/scripts/risk-tier.py")" == "$(mf classifier_blob)" ]] || anomaly blob_clasificador
  [[ "$(git hash-object "$ROOT/scripts/f5-state.sh")" == "$(mf f5_blob 2>/dev/null)" ]] || anomaly blob_f5
  # SE-500 S2: el resolutor que corre es una copia del del ejecutor con el blob del manifiesto; el de la rama de
  # la PR nunca se ejecuta. Los generadores salen del commit de main congelado, en un worktree propio.
  mkdir -p "$HOME_MS/frozen-bin" && cp "$ROOT/scripts/merge-registry-resolve.py" "$HOME_MS/frozen-bin/resolver.py" || anomaly blob_resolutor
  RESOLVER="$HOME_MS/frozen-bin/resolver.py"
  [[ "$(git hash-object "$RESOLVER")" == "$(mf resolver_blob 2>/dev/null)" ]] || anomaly blob_resolutor
  frozen_extract "$(mf main_commit 2>/dev/null)" run || anomaly codigo_congelado_ilegible
  check_required
  local entries; entries=$(python3 -c 'import json,sys
for p in sorted(json.load(open(sys.argv[1]))["prs"],key=lambda p:p["pr"]): print(p["pr"],p["head"],p["tier"],p["base_ref"],p["head_repo"],p["reopens"])' "$MANIFEST") \
    || anomaly manifiesto_ilegible
  # D6: la etiqueta merge-sprint:<id> pausa el auto-rebase de los PRs del manifiesto mientras dura el run.
  local label="merge-sprint:${DIGEST:0:12}" pr head tier base hrepo reopens st
  $GH label create "$label" -R "$REPO" --force --description "SE-433: auto-rebase en pausa" >/dev/null 2>&1 || anomaly etiqueta_fallida
  trap unlabel EXIT
  while read -r pr _; do
    [[ -n "$pr" ]] || continue
    # Sin estado legible no se sabe si hay que pausar su auto-rebase: para, no lo deja sin etiqueta.
    st=$($GH pr view "$pr" -R "$REPO" --json state --jq .state) && [[ -n "$st" ]] || anomaly etiqueta_fallida "$pr"
    [[ "$st" == OPEN ]] || continue
    # API REST de etiquetas: `gh pr edit` falla desde la deprecación de Projects (classic) en GraphQL.
    $GH api -X POST "repos/$REPO/issues/$pr/labels" -f "labels[]=$label" >/dev/null 2>&1 || anomaly etiqueta_fallida "$pr"
    LABELED="$LABELED $pr"
  done <<<"$entries"
  local awaiting=""   # PRs en awaiting_judge: vuelven al final de la cola (§2.7)
  while read -r pr head tier base hrepo reopens; do
    [[ -z "$pr" ]] && continue
    sprint_gate
    local state; state=$($GH pr view "$pr" -R "$REPO" --json state --jq .state)
    if [[ "$state" == MERGED ]]; then
      # Reconciliación tras una caída (AC-25/26): solo una reserva submitted de este grant lo hace propio.
      # Además, el merge real debe ser del SHA reservado y de la cuenta del ejecutor; si no, es ajeno.
      local rs_sha
      case "$(f5 status pr.merge "$pr")" in
        closed) continue ;;   # ya mergeado y registrado (close va después del ledger)
        submitted) rs_sha=$(reconcilable "$pr") || anomaly merge_externo "$pr"
                   echo "  #$pr mergeado sin registrar: reconciliado con la reserva F5"
                   record_merge "$pr" "$tier" "$rs_sha" reconciled; continue ;;
        *) anomaly merge_externo "$pr" ;;
      esac
    fi
    # Cerrado: se aparca sin leer metadatos (un fork borrado no los tiene y no debe parar el sprint).
    [[ "$state" == OPEN ]] || { park "$pr" no_abierto; continue; }
    local meta; meta=$(pr_meta "$pr") || anomaly pr_ilegible "$pr"
    [[ "$meta" == "$base $hrepo $reopens" ]] || anomaly "pr_alterado" "$pr"   # base, repo de head o reabierto (AC-18)
    local t; t=$(pr_tier "$pr")
    (( t <= tier )) && [[ ",$allowed," == *",$t,"* ]] || { park "$pr" "tier_$t"; continue; }
    reviews_ok "$pr" "$head" "$tier" || { park "$pr" revision; continue; }
    # Solicitud al juez de este grant para el head actual: se espera su veredicto, sin re-sincronizar.
    # Si el head se movió después, la solicitud es obsoleta y el head nuevo se evalúa de cero (§2.7).
    local h_now; h_now=$($GH pr view "$pr" -R "$REPO" --json headRefOid --jq .headRefOid)
    [[ -f "$JDIR/$pr-$h_now.request.json" ]] && { awaiting="$awaiting $pr:$tier:$h_now"; continue; }
    try_merge "$pr" "$head" "$tier"
    case "$RESULT" in
      awaiting_judge) awaiting="$awaiting $pr:$tier:$AWAIT_TO" ;;
      merged) record_merge "$pr" "$t" "$CUR" "$EQ" ;;
      *) park "$pr" "${RESULT%%:*}" "$CONFLICT_FILES" ;;
    esac
  done <<<"$entries"
  # Cola del juez: SAFE → re-sync con main si hace falta (sin código nuevo sobre `to`), CI nueva y merge;
  # cualquier otra cosa para el sprint.
  local item req v to h0 tt pf qft done_q="" again=""
  for item in $awaiting; do
    IFS=: read -r pr tier to <<<"$item"
    req="$JDIR/$pr-$to.request.json"
    h0=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["head"])' "$(mf_entry "$pr")") || anomaly manifiesto_ilegible "$pr"
    qft=$(python3 -c 'import json,sys; q=json.load(open(sys.argv[1])); print(q["pr"], q["from"], q["to"], q["tier"], q["requested_epoch"])' "$req") || anomaly judge_solicitud_ilegible "$pr"
    [[ "${qft% *}" == "$pr $h0 $to $tier" ]] || anomaly judge_from_to "$pr"
    # La solicitud vive en el directorio de estado: se recalcula entera (prefiltro, diff, autores, revisiones)
    # y debe coincidir con la guardada; si no, alguien la cambió después de emitirla.
    git -C "$GITROOT" fetch -q origin 2>/dev/null
    tt=$(equiv_tree "$h0" "$to") || anomaly judge_solicitud_alterada "$pr"
    pf=$(judge_prefilter "$tt" "$to" "$tier" "$(mf_entry "$pr")") || anomaly judge_prefiltro_fallo "$pr"
    [[ -z "$pf" ]] || anomaly "judge_$pf" "$pr"
    [[ "$(judge_request_body "$pr" "$h0" "$to" "$tt" "$tier" "${qft##* }")" == "$(cat "$req")" ]] || anomaly judge_solicitud_alterada "$pr"
    for _ in $(seq 1 "${MERGE_SPRINT_JUDGE_POLLS:-120}"); do
      v=$(judge_verdict "$req") || anomaly judge_verificacion_fallo "$pr"
      [[ "$v" != PENDING ]] && break; sleep "${MERGE_SPRINT_POLL_S:-30}"
    done
    ledger event=JUDGE_VERDICT pr="$pr" verdict="$v" request="$req"
    if [[ "$v" == PENDING ]]; then
      # Los PRs que siguen esperando al juez conservan la etiqueta: el auto-rebase no debe mover su head (D6).
      local w; for w in $awaiting; do [[ " $done_q " == *" ${w%%:*} "* ]] || keep_label "${w%%:*}"; done
      for w in $again; do keep_label "$w"; done
      ledger event=PAUSE reason=awaiting_judge pr="$pr"; echo "sprint en pausa: #$pr espera al juez"; exit 6
    fi
    done_q="$done_q $pr"
    [[ "$v" == SAFE:* ]] || anomaly "${v#STOP:}" "$pr"
    sprint_gate
    try_merge "$pr" "$h0" "$tier" "$to"
    case "$RESULT" in
      merged) record_merge "$pr" "$tier" "$CUR" "$EQ" "${v#SAFE:}" ;;
      awaiting_judge) again="$again $pr" ;;   # código nuevo tras el SAFE: solicitud nueva, se evalúa de cero
      *) park "$pr" "${RESULT%%:*}" "$CONFLICT_FILES" ;;
    esac
  done
  if [[ -n "$again" ]]; then
    local w; for w in $again; do keep_label "$w"; done
    ledger event=PAUSE reason=awaiting_judge pr="${again# }"; echo "sprint en pausa:$again espera al juez"; exit 6
  fi
  ledger event=END merged="$MERGED"; echo "sprint terminado: $MERGED merges"
}

cmd_report() {
  [[ -s "$LEDGER" ]] || { echo "sin actividad"; return 0; }
  python3 - "$LEDGER" <<'PY'
import json, sys
from datetime import datetime
ev = [json.loads(l) for l in open(sys.argv[1])]
m = [e for e in ev if e.get("event") == "MERGED"]; p = [e for e in ev if e.get("event") == "PARK"]
s = [e for e in ev if e.get("event") in ("STOP", "END")]
print(f"merges: {len(m)} · aparcados: {len(p)}")
for e in m: print(f"  MERGED #{e['pr']} tier {e['tier']} → {e['merge_commit'][:8]}")
for e in p: print(f"  aparcado #{e['pr']}: {e['reason']}" + (f" ({e['files']})" if e.get("files") else ""))
if s: print(f"fin: {s[-1].get('reason', 'completo')}")
# SE-500: métricas por tanda (manifiesto = digest). M1 merges frente a candidatas que llegaron a decidirse,
# sin contar CI roja; M2 integraciones administrativas sin revisión nueva (registry_merge); M3 grants y minutos
# desde el primer grant hasta el último merge.
t = lambda e: datetime.strptime(e["ts"], "%Y-%m-%dT%H:%M:%SZ")
digests = []
for e in ev:
    if e.get("event") == "GRANT" and e.get("digest") and e["digest"] not in digests: digests.append(e["digest"])
tm = tc = 0
for d in digests:
    md = [e for e in m if e.get("digest") == d]
    first_run = next((i for i, e in enumerate(ev) if e.get("event") == "RUN" and e.get("digest") == d), None)
    merged_prs = {e["pr"] for e in md}
    parked = {e["pr"] for i, e in enumerate(ev) if first_run is not None and i > first_run and e.get("event") == "PARK"
              and e.get("reason") != "ci_roja" and e["pr"] not in merged_prs
              and all(x.get("digest") in (None, d) for x in ev[first_run:i] if x.get("event") == "RUN")}
    cand = len(merged_prs | parked)
    tm += len(md); tc += cand
    g = [e for e in ev if e.get("event") == "GRANT" and e.get("digest") == d]
    mins = f"{(t(md[-1]) - t(g[0])).total_seconds() / 60:.0f} min" if md else "sin merges"
    print(f"tanda {d[:12]}: M1 {len(md)}/{cand} · M2 {sum(e.get('equivalence') == 'registry_merge' for e in md)} "
          f"registry_merge · M3 {len(g)} grant(s), {mins}")
print(f"M1 total: {tm}/{tc}" + (f" ({tm / tc:.2f})" if tc else "") + " sin contar CI roja")
print(f"M2 total: {sum(e.get('equivalence') == 'registry_merge' for e in m)} integraciones registry_merge sin revisión nueva")
print(f"M3 total: {sum(1 for e in ev if e.get('event') == 'GRANT')} grant(s) para {len(m)} merge(s)")
PY
}

case "${1:-}" in
  review-register) shift; [[ $# -eq 2 ]] || die "uso: review-register <pr> <informe>"; cmd_review_register "$@" ;;
  plan) cmd_plan ;;
  grant) [[ $# -eq 2 ]] || die "uso: grant <manifest-digest>"; cmd_grant "$2" ;;
  run) cmd_run ;;
  status) [[ -f "$GRANT" ]] && cat "$GRANT" || echo "sin grant"; [[ -e "$STOPF" ]] && echo "STOP activo" ;;
  stop) touch "$STOPF"; ledger event=STOP_REQUEST; echo "STOP solicitado" ;;
  revoke) ( flock -x 7 && mv "$GRANT" "$HOME_MS/grant.revoked.$(date +%s)" 2>/dev/null ) 7>"$GRANT.lock"; ledger event=REVOKE; echo "grant revocado" ;;
  report) cmd_report ;;
  verify-ledger) verify_chain "$LEDGER" && verify_chain "$REG" && verify_chain "$JREG" && echo "íntegro" || die "cadena rota" 4 ;;
  *) die "uso: merge-sprint.sh review-register|plan|grant|run|status|stop|revoke|report|verify-ledger" ;;
esac
