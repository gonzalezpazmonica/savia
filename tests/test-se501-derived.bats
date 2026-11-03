#!/usr/bin/env bats
# Ref: docs/specs/SE-501-derivados-fuera-de-las-pr.spec.md (opción B)
# AC-1..AC-10, AC-12, AC-14, AC-15 con repos temporales, generadores espía y gh simulado. Nunca GitHub.
# AC-13 vive en tests/test-merge-sprint-se501.bats; AC-11 (inventario de lectores) al final de este fichero.

REPO="$BATS_TEST_DIRNAME/.."

setup() {
  T="$BATS_TEST_TMPDIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}

G() { git -C "$R" -c commit.gpgsign=false "$@"; }

# mkrepo: repo temporal con el código SE-501 copiado y un commit base en main (origin/main apunta a él).
mkrepo() {
  R="$T/r"; mkdir -p "$R/scripts/lib"
  git init -q -b main "$R"
  cp "$REPO/scripts/derived-paths.txt" "$REPO/scripts/derived-gate.sh" "$REPO/scripts/derived-drop.sh" \
     "$REPO/scripts/derived.sh" "$REPO/scripts/derived_canon.py" "$R/scripts/"
  cp "$REPO/scripts/lib/derived-paths.sh" "$R/scripts/lib/"
  echo base > "$R/a.txt"
  G add -A; G commit -qm base
  G update-ref refs/remotes/origin/main HEAD
}

# fake_gens: generadores espía deterministas (salvo la hora del manifiesto, que la forma canónica ignora).
fake_gens() {
  mkdir -p "$R/docs/rules/domain"
  printf -- '---\ncontext_tier: L1\n---\n# Regla uno\n' > "$R/docs/rules/domain/uno.md"
  cat > "$R/scripts/rule-manifest-generate.sh" <<'EOF'
#!/usr/bin/env bash
echo x >> "${SPY:-/dev/null}"
s=$(( $(date +%N | sed 's/^0*//;s/^$/0/') % 60 ))
printf '{"generated":"2026-01-01T00:00:%02dZ","total":1,"tier1_count":1,"tier2_count":0,"dormant_count":0,"rules":{"uno.md":{"tier":"tier1","consumers":""}}}\n' "$s" > docs/rules/domain/rule-manifest.json
EOF
  cat > "$R/scripts/rules-index-generate.sh" <<'EOF'
#!/usr/bin/env bash
printf '# Rules Index — auto-generated %s · 1 rules\n\n| context_tier | file | title | spec |\n|---|---|---|---|\n| L1 | [uno.md](domain/uno.md) | Regla uno | — |\n' "$(date +%Y-%m-%d)" > docs/rules/INDEX.md
EOF
  cat > "$R/scripts/generate-capability-map.py" <<'EOF'
import os
os.makedirs(".scm/views", exist_ok=True)
src = open("a.txt").read()
import json; open(".scm/registry.json", "w").write(json.dumps({"src": src.strip()}) + "\n")
open(".scm/INDEX.scm", "w").write("index " + src)
open(".scm/views/v.json", "w").write('{"v": 1}\n')
EOF
  cat > "$R/scripts/sam.py" <<'EOF'
import json, sys
reg = open(".scm/registry.json").read()
want = json.dumps({"from": reg.strip()}) + "\n"
if sys.argv[1] == "generate":
    open(".scm/sam.json", "w").write(want)
else:
    ok = open(".scm/sam.json").read() == want
    print("SAM: FRESH (1 nodes)" if ok else "SAM: STALE")
EOF
  cp "$REPO/.gitignore" "$R/.gitignore"
  G add -A; G commit -qm gens
  G update-ref refs/remotes/origin/main HEAD
}

# ── AC-1: G20 y «Derived paths absent» ──────────────────────────────────────

@test "AC-1 negativo: cada ruta de D añadida en la PR da FAIL y la nombra" {
  mkrepo
  local p
  for p in .scm/sam.json .confidentiality-signature docs/rules/INDEX.md docs/rules/domain/rule-manifest.json .scm/views/x.json; do
    G checkout -q -B "pr" main
    mkdir -p "$R/$(dirname "$p")"; echo x > "$R/$p"
    G add -f -- "$p"; G commit -qm "añade $p"
    run bash "$R/scripts/derived-gate.sh" --base origin/main
    [ "$status" -eq 1 ]
    [[ "$output" == *"$p"* ]]
    [[ "$output" == *"derived-drop.sh"* ]]
  done
}

@test "AC-1 positivo y límite: sin D, declaraciones de .scm y ruta parecida (INDEX.md.bak) dan PASS" {
  mkrepo
  G checkout -q -b pr
  mkdir -p "$R/.scm/runtime-surface" "$R/docs/rules"
  echo y > "$R/b.txt"; echo '{}' > "$R/.scm/sam-declarations.json"; echo '{}' > "$R/.scm/runtime-surface/x.json"
  echo bak > "$R/docs/rules/INDEX.md.bak"
  G add -A; G commit -qm cambios
  run bash "$R/scripts/derived-gate.sh" --base origin/main
  [ "$status" -eq 0 ]
  [[ "$output" == *"G20 PASS"* ]]
}

@test "AC-1 límite: borrar D (corte o derived-drop) pasa; sin la lista D falla cerrado" {
  mkrepo
  mkdir -p "$R/.scm"; echo old > "$R/.scm/sam.json"; G add -f .scm/sam.json; G commit -qm "D versionado (antes del corte)"
  G update-ref refs/remotes/origin/main HEAD
  G checkout -q -b pr; G rm -q --cached .scm/sam.json; G commit -qm corte
  run bash "$R/scripts/derived-gate.sh" --base origin/main
  [ "$status" -eq 0 ]
  mv "$R/scripts/derived-paths.txt" "$T/"
  run bash "$R/scripts/derived-gate.sh" --base origin/main
  [ "$status" -eq 2 ]
}

@test "AC-1 G20 en pr-plan: registrado en pr-plan.sh y su FAIL nombra la ruta" {
  grep -q 'gate "G20" "Derived paths absent"  g20_derived_absent' "$REPO/scripts/pr-plan.sh"
  mkrepo; G checkout -q -b pr
  mkdir -p "$R/.scm"; echo x > "$R/.scm/registry.json"; G add -f .scm/registry.json; G commit -qm d
  run bash -c "cd '$R' && source '$REPO/scripts/pr-plan-gates.sh' && g20_derived_absent"
  [[ "$output" == FAIL:*".scm/registry.json"* ]]
  G checkout -q main
  run bash -c "cd '$R' && source '$REPO/scripts/pr-plan-gates.sh' && g20_derived_absent"
  [ "$output" = PASS ]
}

@test "AC-1 CI: ci.yml ejecuta «Derived paths absent» con el gate y ya no exige la firma en la PR (AC-12)" {
  grep -q 'name: Derived paths absent' "$REPO/.github/workflows/ci.yml"
  grep -q 'bash scripts/derived-gate.sh --range "$BASE_SHA..HEAD"' "$REPO/.github/workflows/ci.yml"
  run grep -c 'confidentiality-signature' "$REPO/.github/workflows/ci.yml"
  [ "$output" = 0 ]
}

# ── AC-2: generación verificada, válida y determinista ──────────────────────

@test "AC-2 positivo: generadores espía válidos y deterministas (la hora del manifiesto no cuenta) dan PASS" {
  mkrepo; fake_gens
  run bash "$R/scripts/derived.sh" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS rules"* && "$output" == *"PASS scm"* ]]
}

@test "AC-2 negativo: un generador que termina con ≠ 0 da FAIL" {
  mkrepo; fake_gens
  echo 'exit 3' >> "$R/scripts/rules-index-generate.sh"
  run bash "$R/scripts/derived.sh" verify --only rules
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL rules"* ]]
}

@test "AC-2 negativo: dos ejecuciones con salida canónica distinta dan FAIL" {
  mkrepo; fake_gens
  echo 'import time; open(".scm/views/v.json", "w").write("%d\n" % time.time_ns())' >> "$R/scripts/generate-capability-map.py"
  run bash "$R/scripts/derived.sh" verify --only scm
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es determinista"* ]]
}

@test "AC-2 negativo: un generador ausente da FAIL (fail-closed)" {
  mkrepo; fake_gens
  mv "$R/scripts/sam.py" "$T/"
  run bash "$R/scripts/derived.sh" verify --only scm
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta el generador scripts/sam.py"* ]]
}

@test "AC-2 negativo: salida que no pasa su validación interna (INDEX.md con filas ≠ recuento) da FAIL" {
  mkrepo; fake_gens
  sed -i 's/· 1 rules/· 2 rules/' "$R/scripts/rules-index-generate.sh"
  run bash "$R/scripts/derived.sh" verify --only rules
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pasa su validación"* ]]
}

@test "AC-2 positivo: los cuatro generadores reales sobre el árbol actual dan PASS sin D commiteado" {
  run git -C "$REPO" ls-files -- .confidentiality-signature .scm/sam.json .scm/registry.json docs/rules/INDEX.md docs/rules/domain/rule-manifest.json
  [ -z "$output" ]
  run bash "$REPO/scripts/derived.sh" verify
  [ "$status" -eq 0 ]
}

# ── AC-3 y AC-4: escaneo de la PR con el escáner de la base ─────────────────

scan_repo() {  # repo cuya base tiene el escáner real y un generador de blocklist con el término vetado
  mkrepo
  mkdir -p "$R/.claude/hooks/lib" "$R/docs"
  cp "$REPO/scripts/confidentiality-scan.sh" "$REPO/scripts/confidentiality-pr-scan.sh" "$R/scripts/"
  cp "$REPO/.claude/hooks/lib/gate-result.sh" "$R/.claude/hooks/lib/"
  printf '#!/usr/bin/env bash\necho zorblaxcorp\n' > "$R/scripts/generate-blocklist.sh"
  G add -A; G commit -qm escaner
  BASE=$(G rev-parse HEAD); G update-ref refs/remotes/origin/main HEAD
  G checkout -q -b pr
}

@test "AC-3 negativo: la PR añade un dato vetado y vacía el escáner y la blocklist → BLOCKED con el de la base" {
  scan_repo
  echo "cliente zorblaxcorp" > "$R/docs/nota.md"
  printf '#!/usr/bin/env bash\necho "gate-result: {\\"result\\":\\"clean\\",\\"gaps\\":[]}"\n' > "$R/scripts/confidentiality-scan.sh"
  printf '#!/usr/bin/env bash\n:\n' > "$R/scripts/generate-blocklist.sh"
  G add -A; G commit -qm "dato y escáner vaciado"
  run bash "$R/scripts/confidentiality-pr-scan.sh" --repo "$R" --base "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Confidentiality scan (PR): FAIL"* ]]
  # Control: con el escáner de la PR pasa; el test puede fallar si el envoltorio usara el de la PR.
  run bash -c "cd '$R' && bash scripts/confidentiality-scan.sh --pr"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"result":"clean"'* ]]
}

@test "AC-3 positivo: una PR limpia pasa con el escáner de la base" {
  scan_repo
  echo "texto neutro" > "$R/docs/nota.md"; G add -A; G commit -qm limpio
  run bash "$R/scripts/confidentiality-pr-scan.sh" --repo "$R" --base "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Confidentiality scan (PR): PASS"* ]]
}

fake_base_scanner() {  # fake_base_scanner <cuerpo> : la base trae un escáner falso; la PR, uno que siempre da clean
  mkrepo
  mkdir -p "$R/.claude/hooks/lib"; echo ':' > "$R/.claude/hooks/lib/gate-result.sh"
  cp "$REPO/scripts/confidentiality-pr-scan.sh" "$R/scripts/"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$R/scripts/confidentiality-scan.sh"
  G add -A; G commit -qm base; BASE=$(G rev-parse HEAD); G update-ref refs/remotes/origin/main HEAD
  G checkout -q -b pr; echo z > "$R/z.txt"; G add -A; G commit -qm pr
}

@test "AC-4 negativo: sin línea gate-result, con unknown, con findings o clean con ≠ 0 → FAIL; solo clean da PASS" {
  local body
  for body in 'echo hecho; exit 0' \
              'echo "gate-result: {\"result\":\"unknown\",\"gaps\":[{\"check\":\"x\",\"reason\":\"limit\"}]}"; exit 0' \
              'echo "gate-result: {\"result\":\"findings\",\"gaps\":[]}"; exit 1' \
              'echo "gate-result: {\"result\":\"clean\",\"gaps\":[]}"; exit 1' \
              'echo "gate-result: no-json"; exit 0'; do
    rm -rf "$T/r"
    fake_base_scanner "$body"
    run bash "$R/scripts/confidentiality-pr-scan.sh" --repo "$R" --base "$BASE"
    [ "$status" -eq 1 ]
  done
  rm -rf "$T/r"
  fake_base_scanner 'echo "gate-result: {\"result\":\"clean\",\"gaps\":[]}"; exit 0'
  run bash "$R/scripts/confidentiality-pr-scan.sh" --repo "$R" --base "$BASE"
  [ "$status" -eq 0 ]
}

@test "AC-4 negativo: base sin escáner → FAIL (no se escanea con el de la PR)" {
  mkrepo; BASE=$(G rev-parse HEAD)
  cp "$REPO/scripts/confidentiality-pr-scan.sh" "$R/scripts/"
  G checkout -q -b pr; G add -A; G commit -qm pr
  run bash "$R/scripts/confidentiality-pr-scan.sh" --repo "$R" --base "$BASE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no hay escáner de confianza"* ]]
}

fake_gh() {  # fake_gh <fichero de respuesta | FAIL> : gh simulado para api y repo view
  mkdir -p "$T/bin"
  cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
[[ "\$1" == repo ]] && { echo o/r; exit 0; }
[[ "$1" == FAIL ]] && exit 1
cat "$1"
EOF
  chmod +x "$T/bin/gh"; export SAVIA_GH="$T/bin/gh" SAVIA_GH_REPO=o/r
}

@test "AC-4 migración: derived-migration-check da FAIL si el contexto no es requerido, PASS si lo es, 2 si la API cae" {
  echo '{"strict":true,"contexts":["Validate workspace","PR Guardian"]}' > "$T/prot.json"; fake_gh "$T/prot.json"
  run bash "$REPO/scripts/derived-migration-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no está entre los contextos requeridos"* ]]
  echo '{"strict":true,"contexts":["Validate workspace","Confidentiality scan (PR)"]}' > "$T/prot.json"
  run bash "$REPO/scripts/derived-migration-check.sh"
  [ "$status" -eq 0 ]
  fake_gh FAIL
  run bash "$REPO/scripts/derived-migration-check.sh"
  [ "$status" -eq 2 ]
}

# ── AC-5 y AC-14: ramas sin conflictos ──────────────────────────────────────

@test "AC-5: dos ramas con código distinto y D regenerado en local se fusionan en cualquier orden; con D versionado chocan" {
  mkrepo; cp "$REPO/.gitignore" "$R/.gitignore"; G add -A; G commit -qm ignore
  local o
  for o in ab ba; do
    G checkout -q -B x main; echo x > "$R/x.txt"; mkdir -p "$R/.scm"; echo X > "$R/.scm/sam.json"; G add -A; G commit -qm x
    G checkout -q -B y main; echo y > "$R/y.txt"; echo Y > "$R/.scm/sam.json"; G add -A; G commit -qm y
    if [[ $o == ab ]]; then G checkout -q x; run G merge -q --no-edit y; else run G merge -q --no-edit x; fi
    [ "$status" -eq 0 ]
  done
  # Reproducción del problema: con D versionado, la misma pareja de ramas choca.
  G checkout -q -B x2 main; echo X > "$R/.scm/sam.json"; G add -f .scm/sam.json; G commit -qm x2
  G checkout -q -B y2 main; mkdir -p "$R/.scm"; echo Y > "$R/.scm/sam.json"; G add -f .scm/sam.json; G commit -qm y2
  run G merge -q --no-edit x2
  [ "$status" -ne 0 ]
}

@test "AC-14: PR con D en su diff, tras derived-drop.sh, se fusiona con el main posterior al corte sin conflictos" {
  mkrepo
  mkdir -p "$R/.scm"; echo v1 > "$R/.scm/sam.json"; G add -f .scm/sam.json; G commit -qm "D versionado"
  G update-ref refs/remotes/origin/main HEAD
  G checkout -q -b pr; echo pr > "$R/p.txt"; echo v-pr > "$R/.scm/sam.json"; G add -f -A; G commit -qm "pr reescribe D"
  G checkout -q main; G rm -q --cached .scm/sam.json; cp "$REPO/.gitignore" "$R/.gitignore"; G add .gitignore; G commit -qm corte
  echo m > "$R/m.txt"; G add m.txt; G commit -qm "main avanza"
  G update-ref refs/remotes/origin/main HEAD
  # Sin drop: choque modify/delete (el problema).
  G checkout -q pr; run G merge -q --no-edit main; [ "$status" -ne 0 ]; G merge --abort
  run bash "$R/scripts/derived-drop.sh"
  [ "$status" -eq 0 ]
  # El commit de drop solo borra rutas de D.
  run G diff --name-status HEAD~1 HEAD
  [ "$output" = $'D\t.scm/sam.json' ]
  run G merge -q --no-edit main
  [ "$status" -eq 0 ]
  run bash "$R/scripts/derived-gate.sh" --base main
  [ "$status" -eq 0 ]
}

# ── AC-6 y AC-15: workflows ─────────────────────────────────────────────────

W="$BATS_TEST_DIRNAME/../scripts/workflow-secrets-check.py"

@test "AC-6 positivo: confidentiality-main.yml solo push a main, contents: read, sin secretos, acciones por SHA" {
  run python3 "$W" main-audit "$REPO/.github/workflows/confidentiality-main.yml"
  [ "$status" -eq 0 ]
  grep -q 'confidentiality-scan.sh --full-repo' "$REPO/.github/workflows/confidentiality-main.yml"
  grep -q 'SAVIA_GATE_UNKNOWN: block' "$REPO/.github/workflows/confidentiality-main.yml"
}

@test "AC-6 negativo: contents: write, statuses: write, un secreto, pull_request_target o acción sin fijar dan FAIL" {
  local src="$REPO/.github/workflows/confidentiality-main.yml" f="$T/w.yml"
  sed 's/^  contents: read$/  contents: write/' "$src" > "$f"
  run python3 "$W" main-audit "$f"; [ "$status" -eq 1 ]
  sed 's/^  contents: read$/  contents: read\n  statuses: write/' "$src" > "$f"
  run python3 "$W" main-audit "$f"; [ "$status" -eq 1 ]
  sed 's/SAVIA_GATE_UNKNOWN: block/SAVIA_GATE_UNKNOWN: ${{ secrets.X }}/' "$src" > "$f"
  run python3 "$W" main-audit "$f"; [ "$status" -eq 1 ]
  sed 's/^  push:$/  pull_request_target:\n  push:/' "$src" > "$f"
  run python3 "$W" main-audit "$f"; [ "$status" -eq 1 ]
  sed 's/@3d3c42e5aac5ba805825da76410c181273ba90b1/@v7/' "$src" > "$f"
  run python3 "$W" main-audit "$f"; [ "$status" -eq 1 ]
  printf 'on: [pull_request_target]\njobs:\n  a:\n    runs-on: x\n    steps:\n      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n' > "$f"
  run python3 "$W" pr-secrets "$f"; [ "$status" -eq 1 ]
}

@test "AC-15: ningún workflow de PR referencia la clave HMAC; un YAML de prueba que lo hace da FAIL" {
  run python3 "$W" pr-secrets "$REPO"/.github/workflows/*.yml
  [ "$status" -eq 0 ]
  printf 'on:\n  pull_request:\njobs:\n  a:\n    runs-on: x\n    env:\n      K: ${{ secrets.CONFIDENTIALITY_HMAC_KEY }}\n    steps:\n      - run: echo\n' > "$T/w.yml"
  run python3 "$W" pr-secrets "$T/w.yml"
  [ "$status" -eq 1 ]
  # Un comentario que nombra la clave no es una referencia.
  printf '# CONFIDENTIALITY_HMAC_KEY\non:\n  pull_request:\njobs:\n  a:\n    runs-on: x\n    steps:\n      - run: echo\n' > "$T/w.yml"
  run python3 "$W" pr-secrets "$T/w.yml"
  [ "$status" -eq 0 ]
}

# ── AC-7: prueba de main por ejecución ──────────────────────────────────────

S=0123456789abcdef0123456789abcdef01234567
run_json() {  # run_json <path> <event> <branch> <sha> <conclusion>
  printf '{"workflow_runs":[{"id":1,"path":"%s","event":"%s","head_branch":"%s","head_sha":"%s","conclusion":"%s"}]}\n' "$@" > "$T/runs.json"
}

@test "AC-7 positivo: ejecución push en main con éxito para el sha → 0" {
  run_json .github/workflows/confidentiality-main.yml push main "$S" success; fake_gh "$T/runs.json"
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"
  [ "$status" -eq 0 ]
}

@test "AC-7 negativo: pull_request, otro sha, failure, otra ruta, solo status, API caída o no JSON → ≠ 0" {
  run_json .github/workflows/confidentiality-main.yml pull_request main "$S" success; fake_gh "$T/runs.json"
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"; [ "$status" -ne 0 ]
  run_json .github/workflows/confidentiality-main.yml push main "${S%1234567}7654321" success
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"; [ "$status" -ne 0 ]
  run_json .github/workflows/confidentiality-main.yml push main "$S" failure
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"; [ "$status" -ne 0 ]
  run_json .github/workflows/otro.yml push main "$S" success
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"; [ "$status" -ne 0 ]
  run_json .github/workflows/confidentiality-main.yml push feature "$S" success
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"; [ "$status" -ne 0 ]
  printf '{"workflow_runs":[],"statuses":[{"state":"success","sha":"%s"}]}\n' "$S" > "$T/runs.json"
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"; [ "$status" -ne 0 ]
  echo '<html>' > "$T/runs.json"
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"; [ "$status" -eq 2 ]
  fake_gh FAIL
  run bash "$REPO/scripts/confidentiality-main-verify.sh" "$S"; [ "$status" -eq 2 ]
}

# ── AC-8: escaneo completo ──────────────────────────────────────────────────

@test "AC-8 negativo: árbol con un dato vetado → el escaneo completo termina con ≠ 0; limpio → 0" {
  scan_repo
  run bash -c "cd '$R' && SAVIA_GATE_UNKNOWN=block bash scripts/confidentiality-scan.sh --full-repo"
  [ "$status" -eq 0 ]
  echo "cliente zorblaxcorp" > "$R/docs/nota.md"; G add -A; G commit -qm dato
  run bash -c "cd '$R' && SAVIA_GATE_UNKNOWN=block bash scripts/confidentiality-scan.sh --full-repo"
  [ "$status" -ne 0 ]
}

# ── AC-9 y AC-10: ensure ────────────────────────────────────────────────────

@test "AC-9: ensure genera; la 2.ª llamada no ejecuta generadores y tarda < 1 s; tras editar, regenera" {
  mkrepo; fake_gens
  export SPY="$T/spy"
  run bash "$R/scripts/derived.sh" ensure
  [ "$status" -eq 0 ]
  [ -f "$R/.scm/sam.json" ] && [ -f "$R/docs/rules/INDEX.md" ] && [ -f "$R/docs/rules/domain/rule-manifest.json" ]
  [ "$(wc -l < "$SPY")" -eq 1 ]
  local t0 t1; t0=$(date +%s%N)
  run bash "$R/scripts/derived.sh" ensure
  t1=$(date +%s%N)
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$SPY")" -eq 1 ]
  (( (t1 - t0) < 1000000000 ))
  echo editado > "$R/a.txt"
  run bash "$R/scripts/derived.sh" ensure
  [ "$(wc -l < "$SPY")" -eq 2 ]
  grep -q editado "$R/.scm/registry.json"
}

@test "AC-9: la salida de ensure es igual, en forma canónica, a la de los generadores a mano" {
  mkrepo; fake_gens
  bash "$R/scripts/derived.sh" ensure
  mkdir -p "$T/e"; cp "$R/.scm/sam.json" "$R/docs/rules/domain/rule-manifest.json" "$R/docs/rules/INDEX.md" "$T/e/"
  (cd "$R" && bash scripts/rule-manifest-generate.sh && bash scripts/rules-index-generate.sh && python3 scripts/generate-capability-map.py && python3 scripts/sam.py generate)
  python3 "$R/scripts/derived_canon.py" same .scm/sam.json "$T/e/sam.json" "$R/.scm/sam.json"
  python3 "$R/scripts/derived_canon.py" same docs/rules/domain/rule-manifest.json "$T/e/rule-manifest.json" "$R/docs/rules/domain/rule-manifest.json"
  python3 "$R/scripts/derived_canon.py" same docs/rules/INDEX.md "$T/e/INDEX.md" "$R/docs/rules/INDEX.md"
  # Control: dos manifiestos con reglas distintas no son iguales en forma canónica.
  sed 's/"total":1/"total":2/' "$T/e/rule-manifest.json" > "$T/e/m2.json"
  run python3 "$R/scripts/derived_canon.py" same docs/rules/domain/rule-manifest.json "$T/e/rule-manifest.json" "$T/e/m2.json"
  [ "$status" -eq 1 ]
}

@test "AC-10: tras ensure, git status --porcelain está vacío; con D versionado no lo estaría" {
  mkrepo; fake_gens
  bash "$R/scripts/derived.sh" ensure
  run G status --porcelain
  [ -z "$output" ]
  # Control: con D versionado (antes del corte) la regeneración ensucia el árbol.
  G add -f .scm/sam.json; G commit -qm "D versionado"; echo cambio > "$R/a.txt"; G commit -qam a
  bash "$R/scripts/derived.sh" ensure
  run G status --porcelain
  [ -n "$output" ]
}

@test "AC-10 real: el repo no versiona D y .gitignore lo cubre" {
  local p
  for p in .confidentiality-signature .scm/sam.json .scm/registry.json .scm/resources.json .scm/INDEX.scm .scm/views/x.json .scm/reports/x.json .scm/categories/x.scm docs/rules/INDEX.md docs/rules/domain/rule-manifest.json .scm/.derived-stamp; do
    git -C "$REPO" check-ignore -q --no-index -- "$p"
  done
  run git -C "$REPO" check-ignore -q --no-index -- .scm/sam-declarations.json
  [ "$status" -eq 1 ]
}

# ── AC-12: la firma fuera del flujo ─────────────────────────────────────────

@test "AC-12: ningún script ni workflow escribe la firma; G4 sin _resolve_signature_conflict; sign retirado" {
  run grep -rnE 'confidentiality-sign\.sh"? +(sign|resign)|(git add|>) *"?[^ ]*\.confidentiality-signature' "$REPO/scripts" "$REPO/.github/workflows"
  [ "$status" -eq 1 ]
  run grep -c '_resolve_signature_conflict' "$REPO/scripts/pr-plan-gates.sh"
  [ "$output" = 0 ]
  run bash "$REPO/scripts/confidentiality-sign.sh" sign
  [ "$status" -eq 2 ]
  [[ "$output" == *"retirado (SE-501)"* ]]
}

@test "AC-12 risk-tier lee los derivados de .scm de derived-paths.txt (fuente única)" {
  run python3 - "$REPO/scripts/risk-tier.py" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("rt", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
assert ".scm/sam.json" in m.SCM_GENERATED_FILES and ".scm/views/" in m.SCM_GENERATED_DIRS, (m.SCM_GENERATED_FILES, m.SCM_GENERATED_DIRS)
assert ".scm/sam-declarations.json" not in m.SCM_GENERATED_FILES
PY
  [ "$status" -eq 0 ]
}
