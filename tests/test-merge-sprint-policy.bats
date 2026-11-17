#!/usr/bin/env bats
# Ref: docs/specs/SE-512-grant-de-politica-nocturno.spec.md (S1: AC-1, AC-8)
# policy-plan y policy-verify de scripts/merge-sprint.sh con un gh falso y un repo local: nunca toca GitHub.
# El recibo de SE-488 (AC-12b, AC-12c) se prueba en tests/python/test_merge_sprint_policy.py (git + gpg).

SCRIPT="scripts/merge-sprint.sh"

setup() {
  T="$(mktemp -d)"
  export MERGE_SPRINT_HOME="$T/state" TZ=UTC
  mkdir -p "$T/bin"
  cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  api*protection/required_status_checks*) cat "$FAKE_REQUIRED" 2>/dev/null; exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$T/bin/gh"; export GH="$T/bin/gh" FAKE_REQUIRED="$T/required"
  printf 'CI\nCodeQL\n' > "$FAKE_REQUIRED"
  # Repo con origin/main: ejecutor, clasificador, f5, resolutor y un workflow sin filtro en push a main.
  git init -q --bare "$T/origin.git"
  git init -q -b main "$T/repo"
  mkdir -p "$T/repo/scripts" "$T/repo/.github/workflows"
  for f in merge-sprint.sh risk-tier.py f5-state.sh merge-registry-resolve.py; do echo "# $f" > "$T/repo/scripts/$f"; done
  printf 'name: ci\non:\n  push:\n    branches: [main]\n  pull_request:\njobs: {}\n' > "$T/repo/.github/workflows/ci.yml"
  git -C "$T/repo" add -A
  git -C "$T/repo" -c user.name=t -c user.email=t@t.invalid commit -q -m init
  git -C "$T/repo" remote add origin "$T/origin.git"
  git -C "$T/repo" push -q origin main
  git -C "$T/repo" fetch -q origin
  export MERGE_SPRINT_GIT_ROOT="$T/repo"
  cat > "$T/base.json" <<'EOF'
{"repos":[{"repo":"org/savia","base":"main","include":["docs/**","CHANGELOG.d/*"],"exclude":[]}],
 "tiers":[1,2],"max_merges":12,"reviewers":["revisora-a","revisora-b"],"universe":"open"}
EOF
}

teardown() { rm -rf "$T"; }

# borrador <expresión python sobre d> → fichero de borrador derivado de base.json
borrador() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); exec(sys.argv[2]); json.dump(d,open(sys.argv[3],"w"))' \
    "$T/base.json" "$1" "$T/b.json"
  echo "$T/b.json"
}

plan_at() { run bash "$SCRIPT" policy-plan --borrador "$1" --ahora "$2"; }

sin_politica() { [ -z "$(ls -A "$MERGE_SPRINT_HOME/policy" 2>/dev/null)" ]; }

rechaza() {  # rechaza <expresión> [ahora]
  plan_at "$(borrador "$1")" "${2:-2026-11-10T22:00:00Z}"
  [ "$status" -eq 2 ] || { echo "esperaba rechazo de: $1 (status $status) $output"; return 1; }
  sin_politica || { echo "escribió la política pese al rechazo: $1"; return 1; }
}

@test "AC-1 positivo: emitida a las 22:00 sin not_after acaba a las 08:00; a las 18:00, a las 06:00 (12 h)" {
  plan_at "$T/base.json" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ventana": ["2026-11-10T22:00:00Z", "2026-11-11T08:00:00Z"]'* ]]
  plan_at "$T/base.json" 2026-11-10T18:00:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ventana": ["2026-11-10T18:00:00Z", "2026-11-11T06:00:00Z"]'* ]]
  [ "$(ls "$MERGE_SPRINT_HOME/policy" | wc -l)" -eq 2 ]
}

@test "AC-1 positivo: las 08:00 son locales (TZ Europe/Madrid, 22:00 locales = 21:00Z → 07:00Z)" {
  TZ=Europe/Madrid plan_at "$T/base.json" 2026-11-10T21:00:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *'"2026-11-11T07:00:00Z"'* ]]
}

@test "AC-1 la política guardada es JSON canónico con los campos de R1 y digest = sha256 del fichero" {
  plan_at "$T/base.json" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
  f=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["politica"])' "$output")
  d=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["digest"])' "$output")
  [ "$(head -c -1 "$f" | sha256sum | cut -d' ' -f1)" = "$d" ]
  python3 - "$f" <<'EOF'
import json, sys
raw = open(sys.argv[1]).read().rstrip("\n"); p = json.loads(raw)
assert raw == json.dumps(p, sort_keys=True, separators=(",", ":")), "no canónico"
assert p["repos"][0]["required_checks"] == ["CI", "CodeQL"], p["repos"]
assert p["kind"] == "policy" and len(p["id"]) == 16 and p["max_parks_in_row"] == 3
assert p["max_reviews_per_pr"] == 4 and p["main_pending_timeout"] == 20 and p["frozen_prs"] == []
assert "approval" not in p
EOF
}

@test "AC-1 tiers vacío o con 3 o 4 → rechazada" {
  rechaza 'd["tiers"]=[]'
  rechaza 'd["tiers"]=[1,3]'
  rechaza 'd["tiers"]=[4]'
}

@test "AC-1 ventana explícita: 12 h exactas se aceptan; 12 h y 1 s y 18 h se rechazan" {
  rechaza 'd["not_after"]="2026-11-11T10:00:01Z"'
  rechaza 'd["not_after"]="2026-11-11T16:00:00Z"'
  plan_at "$(borrador 'd["not_after"]="2026-11-11T10:00:00Z"')" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
}

@test "AC-1 not_before explícito: 1 h exacta se acepta; 1 h y 1 s y una semana se rechazan" {
  rechaza 'd["not_before"]="2026-11-10T23:00:01Z"'
  rechaza 'd["not_before"]="2026-11-17T22:00:00Z"'
  plan_at "$(borrador 'd["not_before"]="2026-11-10T23:00:00Z"')" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *'"2026-11-10T23:00:00Z", "2026-11-11T08:00:00Z"'* ]]
}

@test "AC-1 max_merges ausente, > 40 o < 1 → rechazada; 40 se acepta" {
  rechaza 'del d["max_merges"]'
  rechaza 'd["max_merges"]=41'
  rechaza 'd["max_merges"]=0'
  plan_at "$(borrador 'd["max_merges"]=40')" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
}

@test "AC-1 max_parks_in_row > 3 y max_reviews_per_pr > 4 → rechazada" {
  rechaza 'd["max_parks_in_row"]=4'
  rechaza 'd["max_reviews_per_pr"]=5'
}

@test "AC-1 reviewers: menos de dos distintos o con el orquestador → rechazada" {
  rechaza 'd["reviewers"]=["revisora-a"]'
  rechaza 'd["reviewers"]=["revisora-a","revisora-a"]'
  rechaza 'd["reviewers"]=["revisora-a","savia-orchestrator"]'
  MERGE_SPRINT_ORCHESTRATOR="orq-x" rechaza 'd["reviewers"]=["orq-x","revisora-a"]'
}

@test "AC-1 universe frozen sin lista → rechazada; con lista se acepta" {
  rechaza 'd["universe"]="frozen"'
  plan_at "$(borrador 'd["universe"]="frozen"; d["frozen_prs"]=[10,11]')" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
}

@test "AC-1 required_checks vacío en la protección viva → rechazada" {
  : > "$FAKE_REQUIRED"
  rechaza 'pass'
}

@test "AC-1 main_pending_timeout < 5 o > 60 → rechazada; 5 y 60 se aceptan" {
  rechaza 'd["main_pending_timeout"]=4'
  rechaza 'd["main_pending_timeout"]=61'
  plan_at "$(borrador 'd["main_pending_timeout"]=5')" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
  plan_at "$(borrador 'd["main_pending_timeout"]=60')" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
}

@test "AC-1 repo sin workflow sin filtro de rutas en push a main → rechazada" {
  printf 'on:\n  push:\n    branches: [main]\n    paths: ["scripts/**"]\n  pull_request:\njobs: {}\n' > "$T/repo/.github/workflows/ci.yml"
  printf 'on: [pull_request]\njobs: {}\n' > "$T/repo/.github/workflows/pr.yml"
  printf 'on:\n  push:\n    branches: [develop]\njobs: {}\n' > "$T/repo/.github/workflows/dev.yml"
  git -C "$T/repo" add -A && git -C "$T/repo" -c user.name=t -c user.email=t@t.invalid commit -q -m filtro
  git -C "$T/repo" push -q origin main && git -C "$T/repo" fetch -q origin
  rechaza 'pass'
  # Con un workflow sin filtro (`on: push`) vuelve a aceptarse.
  printf 'on: push\njobs: {}\n' > "$T/repo/.github/workflows/all.yml"
  git -C "$T/repo" add -A && git -C "$T/repo" -c user.name=t -c user.email=t@t.invalid commit -q -m todo
  git -C "$T/repo" push -q origin main && git -C "$T/repo" fetch -q origin
  plan_at "$T/base.json" 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
}

@test "AC-1 claves desconocidas o include vacío → rechazada" {
  rechaza 'd["extend"]=True'
  rechaza 'd["repos"][0]["include"]=[]'
}

@test "AC-8 editar cualquier campo del fichero de política → policy-verify da anomalía por digest (5)" {
  plan_at "$T/base.json" 2026-11-10T22:00:00Z
  f=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["politica"])' "$output")
  id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "$output")
  echo '{"genesis":"0000000000000000000000000000000000000000","autor":{"email":"x@x.invalid"},"clave_webflow":"/nonexistent","huella_webflow":"0000000000000000000000000000000000000000","tipos":["savia-politica"],"libro":"'"$T"'/libro","espejo":"'"$T"'/esp","repo_aprobaciones":"org/aprob"}' > "$T/cfg.json"
  run bash "$SCRIPT" policy-request --politica "$f" --aprobacion "$T/cfg.json" --ahora 2026-11-10T22:00:00Z
  [ "$status" -eq 0 ]
  [ -f "$MERGE_SPRINT_HOME/policy/$id.request.json" ]
  cp "$f" "$T/orig.json"
  for e in 'p["not_after"]="2026-11-11T09:00:00Z"' 'p["max_merges"]=20' 'p["tiers"]=[1]' \
           'p["repos"][0]["include"].append("scripts/**")' 'p["repos"][0]["repo"]="org/otro"'; do
    python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); exec(sys.argv[2]); open(sys.argv[3],"w").write(json.dumps(p,sort_keys=True,separators=(",",":"))+"\n")' \
      "$T/orig.json" "$e" "$f"
    run bash "$SCRIPT" policy-verify --politica "$f" --aprobacion "$T/cfg.json" --ahora 2026-11-10T23:00:00Z
    [ "$status" -eq 5 ] || { echo "campo $e: status $status $output"; return 1; }
    [[ "$output" == *ANOMALIA*digest* ]]
  done
}

@test "AC-8 no existe subcomando para ampliar la política" {
  for s in policy-extend policy-prorrogar policy-edit policy-grant; do
    run bash "$SCRIPT" "$s"
    [ "$status" -ne 0 ]
  done
}

@test "policy-verify sin registro de petición ni recibo → sin grant (3), fail-closed" {
  plan_at "$T/base.json" 2026-11-10T22:00:00Z
  f=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["politica"])' "$output")
  echo '{}' > "$T/cfg.json"
  run bash "$SCRIPT" policy-verify --politica "$f" --aprobacion "$T/cfg.json" --ahora 2026-11-10T23:00:00Z
  [ "$status" -eq 3 ]
  [[ "$output" == *SIN_GRANT* ]]
}
