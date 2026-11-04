#!/usr/bin/env bats
# Ref: docs/specs/SE-501-derivados-fuera-de-las-pr.spec.md (opción B)
# AC-1..AC-10, AC-12, AC-14, AC-15 con repos temporales, generadores espía y gh simulado. Nunca GitHub.
# AC-13 vive en tests/test-merge-sprint.bats y tests/test-merge-sprint-se500.bats (casos «SE-501 AC-13»); AC-11 (inventario de lectores) al final de este fichero.

REPO="$BATS_TEST_DIRNAME/.."

setup() {
  T="$BATS_TEST_TMPDIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}

G() { git -C "$R" -c commit.gpgsign=false "$@"; }

# mkrepo: repo temporal con el código SE-501 copiado y un commit base en main (origin/main apunta a él).
mkrepo() {
  R="$T/r"; mkdir -p "$R/scripts"
  git init -q -b main "$R"
  cp "$REPO/scripts/derived-paths.txt" \
     "$REPO/scripts/derived.sh" "$REPO/scripts/derived_canon.py" "$R/scripts/"
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
    run bash "$R/scripts/derived.sh" gate --base origin/main
    [ "$status" -eq 1 ]
    [[ "$output" == *"$p"* ]]
    [[ "$output" == *"derived.sh drop"* ]]
  done
}

@test "AC-1 positivo y límite: sin D, declaraciones de .scm y ruta parecida (INDEX.md.bak) dan PASS" {
  mkrepo
  G checkout -q -b pr
  mkdir -p "$R/.scm/runtime-surface" "$R/docs/rules"
  echo y > "$R/b.txt"; echo '{}' > "$R/.scm/sam-declarations.json"; echo '{}' > "$R/.scm/runtime-surface/x.json"
  echo bak > "$R/docs/rules/INDEX.md.bak"
  G add -A; G commit -qm cambios
  run bash "$R/scripts/derived.sh" gate --base origin/main
  [ "$status" -eq 0 ]
  [[ "$output" == *"G20 PASS"* ]]
}

@test "AC-1 límite: borrar D (corte o derived.sh drop) pasa; sin la lista D falla cerrado" {
  mkrepo
  mkdir -p "$R/.scm"; echo old > "$R/.scm/sam.json"; G add -f .scm/sam.json; G commit -qm "D versionado (antes del corte)"
  G update-ref refs/remotes/origin/main HEAD
  G checkout -q -b pr; G rm -q --cached .scm/sam.json; G commit -qm corte
  run bash "$R/scripts/derived.sh" gate --base origin/main
  [ "$status" -eq 0 ]
  mv "$R/scripts/derived-paths.txt" "$T/"
  run bash "$R/scripts/derived.sh" gate --base origin/main
  [ "$status" -eq 2 ]
}

@test "rev-1472 S-P2-1: el gate con la lista de la base ignora una PR que vacía derived-paths.txt (--repo)" {
  mkrepo
  mkdir -p "$T/base/scripts"; cp "$R/scripts/derived.sh" "$R/scripts/derived-paths.txt" "$T/base/scripts/"
  G checkout -q -b pr
  printf '# vaciada\n' > "$R/scripts/derived-paths.txt"
  mkdir -p "$R/.scm"; echo x > "$R/.scm/sam.json"; G add -f -A; G commit -qm "lista vaciada y D añadido"
  # El de la PR, con su lista vaciada, no puede decidir (2); el de la base lo bloquea y lo nombra (1).
  run bash "$R/scripts/derived.sh" gate --base origin/main
  [ "$status" -eq 2 ]
  run bash "$T/base/scripts/derived.sh" gate --repo "$R" --base origin/main
  [ "$status" -eq 1 ]
  [[ "$output" == *".scm/sam.json"* ]]
}

@test "rev-1472: source scripts/derived.sh solo define la lista D y no toca ROOT ni las opciones del llamante" {
  run bash -c 'ROOT=/llamante; set +u; source "'"$REPO"'/scripts/derived.sh"; echo "ROOT=$ROOT"; [[ $- == *u* ]] && echo U
    derived_paths_load "'"$REPO"'" && is_derived_path .scm/sam.json && ! is_derived_path .scm/sam-declarations.json && echo LISTA'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ROOT=/llamante"* ]]
  [[ "$output" != *U* ]]
  [[ "$output" == *LISTA* ]]
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
  grep -q 'bash "$X/scripts/derived.sh" gate --repo "$PWD" --range "$BASE_SHA..HEAD"' "$REPO/.github/workflows/ci.yml"
  grep -q 'git show "$BASE_SHA:scripts/derived-paths.txt"' "$REPO/.github/workflows/ci.yml"
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

@test "rev-1472 P2-2: verify que falla en la 1.ª generación no pierde el .scm/sam.json local" {
  mkrepo; fake_gens
  mkdir -p "$R/.scm"; echo '{"previo": 1}' > "$R/.scm/sam.json"
  echo 'raise SystemExit(4)' >> "$R/scripts/generate-capability-map.py"
  run bash "$R/scripts/derived.sh" verify --only scm
  [ "$status" -eq 1 ]
  [ -f "$R/.scm/sam.json" ]
  [ "$(cat "$R/.scm/sam.json")" = '{"previo": 1}' ]
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

# pr_scan: el envoltorio de confianza (el del código bajo prueba, fuera del checkout, como la copia de la base
# en la CI) audita el repo de la PR. Nunca el confidentiality-scan.sh del checkout de la PR.
pr_scan() { bash "$REPO/scripts/confidentiality-scan.sh" --pr-base "$BASE" --repo "$R"; }

scan_repo() {  # base con el escáner y el generador reales; el término vetado está en la lista estática, como en el repo
  mkrepo
  mkdir -p "$R/.claude/hooks/lib" "$R/docs"
  cp "$REPO/scripts/confidentiality-scan.sh" "$REPO/scripts/generate-blocklist.sh" "$R/scripts/"
  cp "$REPO/.claude/hooks/lib/gate-result.sh" "$R/.claude/hooks/lib/"
  printf '# términos vetados\n%s\n' "${STATIC_TERM-zorblaxcorp}" > "$R/scripts/confidentiality-blocklist.txt"
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
  run pr_scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"Confidentiality scan (PR): FAIL"* ]]
  # Control: con el escáner de la PR pasa; el test puede fallar si el envoltorio usara el de la PR.
  run bash -c "cd '$R' && bash scripts/confidentiality-scan.sh --pr"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"result":"clean"'* ]]
}

@test "rev-1472 S-P1-1: el término de la lista estática de la base bloquea aunque la PR vacíe esa lista" {
  scan_repo
  echo "cliente zorblaxcorp" > "$R/docs/nota.md"
  printf '# vaciada\n' > "$R/scripts/confidentiality-blocklist.txt"
  G add -A; G commit -qm "dato y lista vaciada"
  run pr_scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  docs/nota.md"* || "$output" == *"Blocklist terms found"* ]]
}

@test "rev-1472 S-P1-1: base con la lista estática vacía → FAIL (el check 1 no evaluaría nada)" {
  STATIC_TERM="" scan_repo
  echo "texto neutro" > "$R/docs/nota.md"; G add -A; G commit -qm limpio
  run pr_scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocklist vacía"* ]]
}

@test "rev-1472 S-P2-1: un .gitattributes de la PR que marca *.md como binario no oculta las líneas añadidas" {
  scan_repo
  printf '*.md -diff\n' > "$R/.gitattributes"
  echo "cliente zorblaxcorp" > "$R/docs/nota.md"
  G add -A; G commit -qm "atributos y dato"
  # Precondición: dentro del repo, sin --text, git no muestra la línea.
  run bash -c "cd '$R' && git diff origin/main...HEAD -U0 -- docs/nota.md"
  [[ "$output" == *"Binary files"* ]]
  # --pr con el escáner bajo prueba (copiado en la base por scan_repo), ejecutado dentro del repo:
  # aquí sí rige el .gitattributes de la PR; falla si get_lines no usa --text.
  run bash -c "cd '$R' && SAVIA_GATE_UNKNOWN=block bash scripts/confidentiality-scan.sh --pr --blocklist scripts/confidentiality-blocklist.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Blocklist terms found"* ]]
  # --staged: mismo caso en el índice.
  echo "otra zorblaxcorp" >> "$R/docs/nota.md"; G add docs/nota.md
  run bash -c "cd '$R' && SAVIA_GATE_UNKNOWN=block bash scripts/confidentiality-scan.sh --staged --blocklist scripts/confidentiality-blocklist.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Blocklist terms found"* ]]
  # El envoltorio --pr-base también bloquea.
  G reset -q --hard
  run pr_scan
  [ "$status" -eq 1 ]
}

@test "rev-1472 S-P1-2: un projects/ versionado por la PR con un nombre que rompe el regex no anula el check 1" {
  scan_repo
  mkdir -p "$R/projects/x(" ; echo n > "$R/projects/x(/f.md"
  echo "cliente zorblaxcorp" > "$R/docs/nota.md"
  G add -f -A; G commit -qm "proyecto inyectado y dato"
  run pr_scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"Blocklist terms found"* ]]
}

@test "rev-1472 S-P1-2: el escáner trata un regex inválido en la blocklist como gap (unknown), no como OK" {
  scan_repo
  echo "texto neutro" > "$R/docs/nota.md"; G add -A; G commit -qm limpio
  printf 'zorblaxcorp\nx(\n' > "$T/bl.txt"
  run bash -c "cd '$R' && SAVIA_GATE_UNKNOWN=block bash scripts/confidentiality-scan.sh --pr --blocklist '$T/bl.txt'"
  [ "$status" -eq 2 ]
  [[ "$output" == *'"result":"unknown"'* ]]
  [[ "$output" == *"regex inválido"* ]]
  # Control: la misma lista sin el patrón roto da clean.
  printf 'zorblaxcorp\n' > "$T/bl.txt"
  run bash -c "cd '$R' && SAVIA_GATE_UNKNOWN=block bash scripts/confidentiality-scan.sh --pr --blocklist '$T/bl.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"result":"clean"'* ]]
}

@test "AC-3 positivo: una PR limpia pasa con el escáner de la base" {
  scan_repo
  echo "texto neutro" > "$R/docs/nota.md"; G add -A; G commit -qm limpio
  run pr_scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"Confidentiality scan (PR): PASS"* ]]
}

fake_base_scanner() {  # fake_base_scanner <cuerpo> : la base trae un escáner falso; la PR, uno que siempre da clean
  mkrepo
  mkdir -p "$R/.claude/hooks/lib"; echo ':' > "$R/.claude/hooks/lib/gate-result.sh"
  cp "$REPO/scripts/generate-blocklist.sh" "$R/scripts/"
  echo zorblaxcorp > "$R/scripts/confidentiality-blocklist.txt"
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
    run pr_scan
    [ "$status" -eq 1 ]
  done
  rm -rf "$T/r"
  fake_base_scanner 'echo "gate-result: {\"result\":\"clean\",\"gaps\":[]}"; exit 0'
  run pr_scan
  [ "$status" -eq 0 ]
}

@test "AC-4 negativo: base sin escáner → FAIL (no se escanea con el de la PR)" {
  mkrepo; BASE=$(G rev-parse HEAD)
  G checkout -q -b pr; echo z > "$R/z.txt"; G add -A; G commit -qm pr
  run pr_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *"no hay escáner de confianza"* ]]
}

@test "consolidación: la CI toma el envoltorio --pr-base de la base cuando la base lo tiene; si no, solo en el arranque" {
  local wf="$REPO/.github/workflows/confidentiality-gate.yml" sel
  # El selector del workflow, tal cual: lo que decide si se ejecuta la copia de la base o la de la PR.
  sel=$(grep -oE "grep -q -- '[^']+'" "$wf" | head -1 | sed "s/^grep -q -- '//; s/'\$//")
  [ -n "$sel" ]
  grep -q "bash \"\$RUNNER_TEMP/pr-scan.sh\" --pr-base \"\$BASE_SHA\" --repo \"\$GITHUB_WORKSPACE\"" "$wf"
  # Positivo: el escáner actual (la base tras el merge) cumple el selector → la CI usa siempre el de la base.
  grep -qF -- "$sel" "$REPO/scripts/confidentiality-scan.sh"
  # Negativo: un escáner sin el modo (main antes de SE-501) no lo cumple → solo entonces cae al de la PR.
  printf '#!/usr/bin/env bash\ncase "$1" in --pr) : ;; esac\n' > "$T/old.sh"
  run grep -qF -- "$sel" "$T/old.sh"
  [ "$status" -eq 1 ]
}

@test "consolidación: las subórdenes fallan cerrado ante uso incorrecto (drop, migration-check, --pr-base, verify-main)" {
  mkrepo
  run bash "$R/scripts/derived.sh" drop --nada; [ "$status" -eq 2 ]
  run bash "$R/scripts/derived.sh" drop --base no-existe; [ "$status" -eq 2 ]
  echo y > "$R/b.txt"; G add b.txt
  run bash "$R/scripts/derived.sh" drop
  [ "$status" -eq 1 ]
  [[ "$output" == *"el índice tiene cambios"* ]]
  run bash "$REPO/scripts/derived.sh" migration-check --nada; [ "$status" -eq 2 ]
  run bash "$REPO/scripts/confidentiality-scan.sh" --pr-base; [ "$status" -eq 2 ]
  run bash "$REPO/scripts/confidentiality-scan.sh" --pr-base HEAD --nada; [ "$status" -eq 2 ]
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main; [ "$status" -eq 2 ]
  [[ "$output" == *"uso: confidentiality-sign.sh verify-main"* ]]
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

@test "AC-4 migración: derived.sh migration-check da FAIL si el contexto no es requerido, PASS si lo es, 2 si la API cae" {
  echo '{"strict":true,"contexts":["Validate workspace","PR Guardian"]}' > "$T/prot.json"; fake_gh "$T/prot.json"
  run bash "$REPO/scripts/derived.sh" migration-check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no está entre los contextos requeridos"* ]]
  echo '{"strict":true,"contexts":["Validate workspace","Confidentiality scan (PR)"]}' > "$T/prot.json"
  run bash "$REPO/scripts/derived.sh" migration-check
  [ "$status" -eq 0 ]
  # rev-1472 P2: un check retirado que sigue requerido bloquearía todas las PR → FAIL y lo nombra.
  for old in "Verify Audit Signature" "PII & Confidentiality Scan (PR)"; do
    printf '{"strict":true,"checks":[{"context":"Confidentiality scan (PR)"},{"context":"%s"}]}\n' "$old" > "$T/prot.json"
    run bash "$REPO/scripts/derived.sh" migration-check
    [ "$status" -eq 1 ]
    [[ "$output" == *"«$old» sigue entre los contextos requeridos"* ]]
  done
  fake_gh FAIL
  run bash "$REPO/scripts/derived.sh" migration-check
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

@test "AC-14: PR con D en su diff, tras derived.sh drop, se fusiona con el main posterior al corte sin conflictos" {
  mkrepo
  mkdir -p "$R/.scm"; echo v1 > "$R/.scm/sam.json"; G add -f .scm/sam.json; G commit -qm "D versionado"
  G update-ref refs/remotes/origin/main HEAD
  G checkout -q -b pr; echo pr > "$R/p.txt"; echo v-pr > "$R/.scm/sam.json"; G add -f -A; G commit -qm "pr reescribe D"
  G checkout -q main; G rm -q --cached .scm/sam.json; cp "$REPO/.gitignore" "$R/.gitignore"; G add .gitignore; G commit -qm corte
  echo m > "$R/m.txt"; G add m.txt; G commit -qm "main avanza"
  G update-ref refs/remotes/origin/main HEAD
  # Sin drop: choque modify/delete (el problema).
  G checkout -q pr; run G merge -q --no-edit main; [ "$status" -ne 0 ]; G merge --abort
  run bash "$R/scripts/derived.sh" drop
  [ "$status" -eq 0 ]
  # El commit de drop solo borra rutas de D.
  run G diff --name-status HEAD~1 HEAD
  [ "$output" = $'D\t.scm/sam.json' ]
  run G merge -q --no-edit main
  [ "$status" -eq 0 ]
  run bash "$R/scripts/derived.sh" gate --base main
  [ "$status" -eq 0 ]
}

# ── AC-6 y AC-15: workflows ─────────────────────────────────────────────────

W="$BATS_TEST_DIRNAME/../scripts/workflow-hmac-check.py"

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

@test "AC-15 (#1472 P2-3): toJSON(secrets), secrets: inherit o workflow_run con la clave dan FAIL; sin ellos, PASS" {
  printf 'on:\n  pull_request:\njobs:\n  a:\n    runs-on: x\n    env:\n      S: ${{ toJSON(secrets) }}\n    steps:\n      - run: echo\n' > "$T/w.yml"
  run python3 "$W" pr-secrets "$T/w.yml"; [ "$status" -eq 1 ]
  printf 'on:\n  pull_request:\njobs:\n  a:\n    uses: ./.github/workflows/x.yml\n    secrets: inherit\n' > "$T/w.yml"
  run python3 "$W" pr-secrets "$T/w.yml"; [ "$status" -eq 1 ]
  printf 'on:\n  workflow_run:\n    workflows: [CI]\njobs:\n  a:\n    runs-on: x\n    env:\n      K: ${{ secrets.CONFIDENTIALITY_HMAC_KEY }}\n    steps:\n      - run: echo\n' > "$T/w.yml"
  run python3 "$W" pr-secrets "$T/w.yml"; [ "$status" -eq 1 ]
  # Control: el mismo job reutilizable sin heredar secretos, PASS.
  printf 'on:\n  pull_request:\njobs:\n  a:\n    uses: ./.github/workflows/x.yml\n' > "$T/w.yml"
  run python3 "$W" pr-secrets "$T/w.yml"; [ "$status" -eq 0 ]
}

@test "AC-15 negativo: un YAML inválido falla cerrado sin volcar su contenido en el diagnóstico" {
  printf 'on: [pull_request]\njobs: [\n  private_fixture_marker: [\n' > "$T/invalid.yml"
  run python3 "$W" pr-secrets "$T/invalid.yml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$T/invalid.yml"* ]]
  [[ "$output" == *"YAML inválido o fichero ilegible"* ]]
  [[ "$output" != *"private_fixture_marker"* ]]
}

@test "AC-15 negativo: las referencias HMAC en minúsculas, mixtas y por índice también se rechazan" {
  for expression in 'secrets.confidentiality_hmac_key' 'secrets.Confidentiality_Hmac_Key' "secrets['confidentiality_hmac_key']"; do
    printf 'on: [pull_request]\njobs:\n  a:\n    env:\n      K: ${{ %s }}\n' "$expression" > "$T/case.yml"
    run python3 "$W" pr-secrets "$T/case.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"referencia CONFIDENTIALITY_HMAC_KEY"* ]]
  done
}

# ── AC-7: prueba de main por ejecución ──────────────────────────────────────

S=0123456789abcdef0123456789abcdef01234567
run_json() {  # run_json <path> <event> <branch> <sha> <conclusion>
  printf '{"workflow_runs":[{"id":1,"path":"%s","event":"%s","head_branch":"%s","head_sha":"%s","conclusion":"%s"}]}\n' "$@" > "$T/runs.json"
}

@test "AC-7 positivo: ejecución push en main con éxito para el sha → 0" {
  run_json .github/workflows/confidentiality-main.yml push main "$S" success; fake_gh "$T/runs.json"
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"
  [ "$status" -eq 0 ]
}

@test "AC-7 negativo: pull_request, otro sha, failure, otra ruta, solo status, API caída o no JSON → ≠ 0" {
  run_json .github/workflows/confidentiality-main.yml pull_request main "$S" success; fake_gh "$T/runs.json"
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"; [ "$status" -ne 0 ]
  run_json .github/workflows/confidentiality-main.yml push main "${S%1234567}7654321" success
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"; [ "$status" -ne 0 ]
  run_json .github/workflows/confidentiality-main.yml push main "$S" failure
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"; [ "$status" -ne 0 ]
  run_json .github/workflows/otro.yml push main "$S" success
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"; [ "$status" -ne 0 ]
  run_json .github/workflows/confidentiality-main.yml push feature "$S" success
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"; [ "$status" -ne 0 ]
  printf '{"workflow_runs":[],"statuses":[{"state":"success","sha":"%s"}]}\n' "$S" > "$T/runs.json"
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"; [ "$status" -ne 0 ]
  echo '<html>' > "$T/runs.json"
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"; [ "$status" -eq 2 ]
  fake_gh FAIL
  run bash "$REPO/scripts/confidentiality-sign.sh" verify-main "$S"; [ "$status" -eq 2 ]
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

@test "rev-1472 P1-1: todo script que citan la migración y esta suite está versionado (ningún .gitignore lo oculta)" {
  local f missing=0 n=0
  while read -r f; do
    n=$((n+1))
    if ! git -C "$REPO" ls-files --error-unmatch "$f" >/dev/null 2>&1; then echo "sin versionar: $f"; missing=1; fi
  done < <(grep -ohE 'scripts/[A-Za-z0-9_./-]+\.(sh|py)' "$REPO/scripts/derived.sh" \
             "$BATS_TEST_FILENAME" | sort -u)
  [ "$n" -ge 5 ]
  [ "$missing" -eq 0 ]
}

# ── AC-11: inventario de lectores de D ──────────────────────────────────────
# Lista declarada: cada fichero que nombra una ruta de D, con su clase.
#   gen      genera D o es la herramienta de D (lista, canon, SAM)
#   ref      solo nombra la ruta (filtros, exclusiones, texto); no lee el contenido de D
#   ensure   llama a «derived.sh ensure» antes de leer D (el test lo comprueba)
#   session  arranque: regenera en segundo plano y no espera (arranque blindado)
#   ensure   (Python) derived_canon.ensure; (solo lectura) error DERIVED_MISSING que nombra la orden
#   via      lee D solo a través de otro lector de clase ensure (ablation_kernel._optional)
AC11_DECLARED='
gen scripts/derived.sh
gen scripts/derived-paths.txt
gen scripts/derived_canon.py
gen scripts/generate-capability-map.py
gen scripts/rule-manifest-generate.sh
gen scripts/rules-index-generate.sh
gen scripts/sam.py
gen scripts/sam_model.py
gen scripts/sam_surface.py
gen scripts/sam_trace.py
ref .claude/hooks/scope-guard.sh
ref .claude/hooks/stop-dod-gate.sh
ref config/ablation-contract.json
ref config/edit-ledger-exclusions.txt
ref config/kernel-candidate.json
ref scripts/ablation_consumers.py
ref scripts/llms-txt-generate.sh
ref scripts/merge-registry-resolve.py
ref scripts/merge-sprint.sh
ref scripts/plan-diff-check.sh
ref scripts/pr-plan-gates.sh
ref scripts/push-pr.sh
ref scripts/receipt-v2.sh
ref scripts/resolve-pr-conflicts.sh
ref scripts/risk-tier.py
ref scripts/scope-creep-check.sh
ref scripts/scope-trace-gate.sh
ref scripts/setup-merge-drivers.sh
ensure .github/workflows/ci.yml
ensure scripts/ci-extended-checks.sh
ensure scripts/readiness-check.sh
ensure scripts/rule-manifest-integrity.sh
ensure scripts/validate-ci-local.sh
session .claude/hooks/session-init.sh
session scripts/session-init-bootstrap.sh
ensure scripts/ablation_inventory.py
ensure scripts/ablation_kernel.py
via scripts/ablation_units.py
ensure scripts/capability-entropy.py
ensure scripts/dual-cli/audit.py
ensure scripts/dual-cli/config.py
ensure scripts/eval-coverage-matrix.py
ensure scripts/release-invariants.sh
ensure scripts/se397-f4-corpus.sh
'
AC11_SCOPE=(scripts .claude/hooks config .github/workflows)

# ac11_diff <repo>: diferencias entre el inventario real (grep de la spec) y la lista declarada.
ac11_diff() {
  diff <(cd "$1" && grep -rlE --exclude-dir=__pycache__ '\.scm/|rule-manifest\.json|rules/INDEX\.md' -- "${AC11_SCOPE[@]}" 2>/dev/null | sort) \
       <(awk 'NF==2{print $2}' <<<"$AC11_DECLARED" | sort)
}

@test "AC-11: el inventario de lectores de D coincide con la lista declarada; los de clase ensure llaman a ensure" {
  run ac11_diff "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local c f
  while read -r c f; do
    case "$c" in
      ensure) grep -qE 'derived\.sh.{0,2} ensure|derived_canon\.ensure\(' "$REPO/$f" || { echo "sin ensure: $f"; return 1; } ;;
      via)    # cada línea que nombra D pasa por _optional (que llama a ensure)
              if grep -E '\.scm/|rule-manifest\.json|rules/INDEX\.md' "$REPO/$f" | grep -qv '_optional('; then
                echo "lee D sin _optional: $f"; return 1
              fi ;;
    esac
  done <<<"$AC11_DECLARED"
}

@test "AC-11 negativo: un script nuevo que lee .scm/registry.json sin estar en la lista hace fallar el inventario" {
  mkdir -p "$T/inv"
  (cd "$REPO" && git ls-files -z -- "${AC11_SCOPE[@]}" | xargs -0 tar cf -) | tar xf - -C "$T/inv"
  run ac11_diff "$T/inv"
  [ "$status" -eq 0 ]
  local n=nuevo-lector   # variable: el test rev-1472 P1-1 no debe tomarlo por un script del repo
  echo 'json.load(open(".scm/registry.json"))' > "$T/inv/scripts/$n.py"
  run ac11_diff "$T/inv"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/$n.py"* ]]
}

@test "AC-11: rule-manifest-integrity sin D genera con ensure; si ensure falla, el hallazgo nombra derived.sh ensure" {
  mkrepo; fake_gens
  cp "$REPO/scripts/rule-manifest-integrity.sh" "$R/scripts/"
  G add -A; G commit -qm gens
  [ ! -e "$R/docs/rules/domain/rule-manifest.json" ]
  run bash "$R/scripts/rule-manifest-integrity.sh"
  [ -f "$R/docs/rules/domain/rule-manifest.json" ]
  [[ "$output" != *"rule-manifest.json not found"* ]]
  # Negativo: sin generadores ensure falla; el script termina con ≠ 0 y nombra la orden.
  mkdir -p "$T/apartado"
  mv "$R/docs/rules/domain/rule-manifest.json" "$R/scripts/rule-manifest-generate.sh" "$R/scripts/rules-index-generate.sh" "$T/apartado/"
  run bash "$R/scripts/rule-manifest-integrity.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"derived.sh ensure"* ]]
}


# ── AC-11: los lectores que estaban pendientes (rev-1472, tercera pasada) ──────
# fake_derived <modo>: derived.sh espía en $R/scripts. ok escribe el .scm mínimo; fail no escribe y sale 1.
fake_derived() {
  cat > "$R/scripts/derived.sh" <<EOF2
#!/usr/bin/env bash
echo "\$*" >> "$T/derived.spy"
[[ "$1" == ok ]] || exit 1
cd "\$(dirname "\$0")/.."
mkdir -p .scm/categories
printf '{"capabilities": []}\n' > .scm/registry.json
printf 'index\n' > .scm/INDEX.scm
printf '{"model_revision": "rev-x", "edges": []}\n' > .scm/sam.json
printf '{"hash": "h", "resources": []}\n' > .scm/resources.json
EOF2
}

# set_aside_scm: aparta el .scm generado (sin borrar) para volver a empezar sin D.
set_aside_scm() { mv "$R/.scm" "$(mktemp -d "$T/scm.XXXX")/"; }

@test "AC-11: derived_canon.ensure verifica frescura en su propio repo; nunca ejecuta una raíz ajena" {
  mkrepo; fake_derived ok
  run python3 -c 'import sys; sys.path.insert(0, sys.argv[1] + "/scripts"); import derived_canon as d; print(d.ensure(sys.argv[1], [".scm/registry.json"]))' "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[]"* ]]
  [ -f "$R/.scm/registry.json" ]
  [ "$(wc -l < "$T/derived.spy")" -eq 1 ]
  grep -qx 'ensure --only scm' "$T/derived.spy"
  # Ya presente: delega de nuevo la frescura en derived.sh (que conserva su caché).
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1] + "/scripts"); import derived_canon as d; assert d.ensure(sys.argv[1], [".scm/registry.json"]) == []' "$R"
  [ "$(wc -l < "$T/derived.spy")" -eq 2 ]
  # Negativo: raíz ajena (otro árbol) sin D → devuelve lo que falta y no ejecuta nada.
  mkdir -p "$T/ajena/scripts"; cp "$R/scripts/derived.sh" "$T/ajena/scripts/"
  run python3 -c 'import sys; sys.path.insert(0, sys.argv[1] + "/scripts"); import derived_canon as d; print(d.ensure(sys.argv[2], [".scm/registry.json"]))' "$R" "$T/ajena"
  [[ "$output" == *"['.scm/registry.json']"* ]]
  [ "$(wc -l < "$T/derived.spy")" -eq 2 ]
  [ ! -e "$T/ajena/.scm" ]
}

@test "AC-11 negativo: si derived.sh ensure falla, ensure devuelve lo que sigue faltando" {
  mkrepo; fake_derived fail
  run python3 -c 'import sys; sys.path.insert(0, sys.argv[1] + "/scripts"); import derived_canon as d; print(d.ensure(sys.argv[1], [".scm/sam.json"]))' "$R"
  [[ "$output" == *"['.scm/sam.json']"* ]]
  [ "$(wc -l < "$T/derived.spy")" -eq 1 ]
}

@test "AC-11 negativo: el lector rechaza una entropía nueva sobre el límite aunque D ya exista" {
  mkrepo
  cp "$REPO/scripts/capability-entropy.py" "$R/scripts/"
  mkdir -p "$R/tests/baselines"
  printf '{"entropy":1}\n' > "$R/tests/baselines/capability-entropy.json"
  printf '{"capabilities":[]}\n' > "$R/source-registry.json"
  cat > "$R/scripts/derived.sh" <<'EOF2'
#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p .scm
cp source-registry.json .scm/registry.json
printf 'index\n' > .scm/INDEX.scm
EOF2
  run python3 "$R/scripts/capability-entropy.py" --root "$R" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: entropía 1"* ]]
  printf '{"capabilities":[{"id":"script:a","source":"scripts/%s.py","kind":"script"},{"id":"script:b","source":"scripts/%s.py","kind":"script"}]}\n' a b > "$R/source-registry.json"
  run python3 "$R/scripts/capability-entropy.py" --root "$R" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: entropía 3"* ]]
  # Si la comprobación de frescura falla, los derivados viejos presentes no bastan.
  fake_derived fail
  run python3 "$R/scripts/capability-entropy.py" --root "$R" --check
  [ "$status" -eq 2 ]
  [[ "$output" == *"derived.sh ensure"* ]]
}

@test "AC-11: capability-entropy y eval-coverage-matrix sin D generan con ensure; si falla, nombran la orden" {
  mkrepo
  cp "$REPO/scripts/capability-entropy.py" "$REPO/scripts/eval-coverage-matrix.py" "$R/scripts/"
  mkdir -p "$R/tests/baselines"; echo '{"entropy": 100}' > "$R/tests/baselines/capability-entropy.json"
  fake_derived ok
  run python3 "$R/scripts/capability-entropy.py" --root "$R" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: entropía 1 <= baseline 100"* ]]
  [ -f "$R/.scm/registry.json" ]
  [ "$(wc -l < "$T/derived.spy")" -eq 1 ]
  set_aside_scm
  run python3 "$R/scripts/eval-coverage-matrix.py" --root "$R"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$T/derived.spy")" -eq 2 ]
  # Negativo: ensure falla.
  set_aside_scm; fake_derived fail
  run python3 "$R/scripts/capability-entropy.py" --root "$R" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"derived.sh ensure"* ]]
  run python3 "$R/scripts/eval-coverage-matrix.py" --root "$R"
  [ "$status" -ne 0 ]
  [[ "$output" == *"derived.sh ensure"* ]]
  # Solo falta INDEX.scm en el propio repo y ensure falla: FAIL (sin él la entropía baja 1 y el ratchet
  # daría PASS en falso).
  fake_derived ok
  run python3 "$R/scripts/capability-entropy.py" --root "$R" --check
  [ "$status" -eq 0 ]
  mv "$R/.scm/INDEX.scm" "$T/index.apartado"; fake_derived fail
  run python3 "$R/scripts/capability-entropy.py" --root "$R" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *".scm/INDEX.scm"*"derived.sh ensure"* ]]
}

@test "rev-1472 r4: capability-entropy con --root ajeno sin INDEX.scm sigue midiendo (INDEX opcional fuera del repo)" {
  mkdir -p "$T/fx/.scm" "$T/fx/tests/baselines"
  echo '{"capabilities": [{"id": "script:fx/a", "kind": "script", "source": "fx/a.sh"}]}' > "$T/fx/.scm/registry.json"
  echo '{"entropy": 1}' > "$T/fx/tests/baselines/capability-entropy.json"
  run python3 "$REPO/scripts/capability-entropy.py" --root "$T/fx" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: entropía 1 <= baseline 1"* ]]
  # Negativo: sin registry, falla nombrando la orden.
  mv "$T/fx/.scm/registry.json" "$T/registry.apartado"
  run python3 "$REPO/scripts/capability-entropy.py" --root "$T/fx" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"derived.sh ensure"* ]]
}

@test "AC-11: ablation sin D en raíz ajena: el inventario falla nombrando ensure; la procedencia opcional queda UNKNOWN" {
  mkdir -p "$T/fx"
  run python3 -c '
import sys; sys.path.insert(0, sys.argv[1] + "/scripts")
from pathlib import Path
import ablation_inventory as inv, ablation_kernel as k
try:
    inv._sam_index(Path(sys.argv[2])); print("SIN ERROR")
except inv.InventoryError as e:
    print("ERR", e)
print("OPT", k._optional(Path(sys.argv[2]), ".scm/sam.json", "model_revision"))
' "$REPO" "$T/fx"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ERR SAM_MISSING: .scm/sam.json (ejecutar: bash scripts/derived.sh ensure)"* ]]
  [[ "$output" == *"OPT UNKNOWN"* ]]
  [ ! -e "$T/fx/.scm" ]
}

# dc_build <config.py> <raíz>: imprime «ERR <código>» o «SIN ERROR» de build_manifest.
dc_build() {
  python3 -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("c", sys.argv[1]); c = importlib.util.module_from_spec(s); s.loader.exec_module(c)
try:
    c.build_manifest(sys.argv[2]); print("SIN ERROR")
except c.ConfigError as e:
    print("ERR", e)
' "$1" "$2"
}

@test "AC-11: dual-cli audit y config sin .scm fallan con DERIVED_MISSING; un enlace roto sigue siendo UNTRUSTED_SOURCE" {
  mkdir -p "$T/dc/.claude"; echo '{"hooks": {}}' > "$T/dc/.claude/settings.json"
  run python3 "$REPO/scripts/dual-cli/audit.py" --root "$T/dc"
  [ "$status" -eq 2 ]
  [[ "$output" == *"DERIVED_MISSING: bash scripts/derived.sh ensure"* ]]
  run dc_build "$REPO/scripts/dual-cli/config.py" "$T/dc"
  [[ "$output" == *"ERR DERIVED_MISSING: bash scripts/derived.sh ensure"* ]]
  # Negativo: un enlace que apunta fuera (roto) no se confunde con D ausente.
  mkdir -p "$T/dc/.scm/categories"; ln -s /nonexistent/x "$T/dc/.scm/resources.json"
  : > "$T/dc/.scm/INDEX.scm"; : > "$T/dc/.scm/categories/quality.scm"
  run dc_build "$REPO/scripts/dual-cli/config.py" "$T/dc"
  [[ "$output" == *"ERR UNTRUSTED_SOURCE"* ]]
}

@test "AC-11: release-invariants en su repo sin D: ensure; si falla, FAIL que nombra la orden; raíz ajena sin D sigue en SKIP" {
  mkrepo
  cp "$REPO/scripts/release-invariants.sh" "$R/scripts/"
  printf 'import os\nos.makedirs(".scm", exist_ok=True)\nopen(".scm/INDEX.scm","w").write("index\\n")\nopen(".scm/registry.json","w").write("{\\"capabilities\\": []}\\n")\n' > "$R/scripts/generate-capability-map.py"
  chmod +x "$R/scripts/generate-capability-map.py"
  fake_derived ok
  run bash "$R/scripts/release-invariants.sh" --root "$R"
  [[ "$output" == *"PASS: GENERATED_VIEW_DRIFT"* ]]
  [ "$(wc -l < "$T/derived.spy")" -eq 1 ]
  set_aside_scm; fake_derived fail
  run bash "$R/scripts/release-invariants.sh" --root "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: GENERATED_VIEW_DRIFT: falta .scm/INDEX.scm — ejecutar: bash scripts/derived.sh ensure"* ]]
  [[ "$output" != *"SKIP: GENERATED_VIEW_DRIFT"* ]]
  mkdir -p "$T/ajena"
  run bash "$R/scripts/release-invariants.sh" --root "$T/ajena"
  [[ "$output" == *"SKIP: GENERATED_VIEW_DRIFT"* ]]
  [ "$(wc -l < "$T/derived.spy")" -eq 2 ]
}

@test "AC-11: se397-f4-corpus sin .scm/sam.json llama a ensure y, si falla, termina 1 nombrando la orden" {
  mkrepo
  cp "$REPO/scripts/se397-f4-corpus.sh" "$R/scripts/"
  fake_derived fail
  run bash -c 'cd "$1" && bash scripts/se397-f4-corpus.sh --events "$2"' _ "$R" "$T/events.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta .scm/sam.json — ejecutar: bash scripts/derived.sh ensure"* ]]
  grep -qx 'ensure --only scm' "$T/derived.spy"
}

@test "AC-11: session-init con D ausente no espera a la generación (la lanza en segundo plano)" {
  mkdir -p "$T/ws/scripts" "$T/ws/docs/learning-proposals" "$T/home"
  # El hook sale por su trap ERR si no hay ninguna LP activa (grep sin coincidencias): fixture con una.
  echo 'lifecycle: active' > "$T/ws/docs/learning-proposals/lp.md"
  # Generador lento: si el arranque lo esperase, tardaría ≥ 6 s.
  printf 'import os, time\ntime.sleep(6)\nos.makedirs(".scm", exist_ok=True)\nopen(".scm/INDEX.scm", "w").write("x")\n' > "$T/ws/scripts/generate-capability-map.py"
  local port s e ms i rc
  port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
  s=$(date +%s%N)
  (cd "$T/ws" && HOME="$T/home" TMPDIR="$T" CLAUDE_PROJECT_DIR="$T/ws" SAVIA_PROBE_STATE="$T/probes.state" \
     OLLAMA_URL="http://127.0.0.1:$port" SAVIA_SHIELD_PORT="$port" SAVIA_SHIELD_PROXY_PORT="$port" \
     bash "$REPO/.claude/hooks/session-init.sh" </dev/null >/dev/null 2>&1) && rc=0 || rc=$?
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  [ "$rc" -eq 0 ]
  echo "session-init: ${ms} ms"
  [ ! -e "$T/ws/.scm/INDEX.scm" ]
  [ "$ms" -lt 6000 ]
  # La generación sí se lanzó: aparece después, sin el arranque.
  for i in $(seq 1 100); do [ -f "$T/ws/.scm/INDEX.scm" ] && break; sleep 0.1; done
  [ -f "$T/ws/.scm/INDEX.scm" ]
}

# ── rev-1472 P2-4: clave con rutas raras y salidas parciales ───────────────────
@test "rev-1472 P2-4: ensure regenera si falta una salida de views/ aunque las requeridas estén; sin cambios no" {
  mkrepo; fake_gens
  export SPY="$T/spy"
  bash "$R/scripts/derived.sh" ensure
  [ -f "$R/.scm/views/v.json" ]
  mv "$R/.scm/views/v.json" "$T/v.apartado"
  run bash "$R/scripts/derived.sh" ensure --only scm
  [ "$status" -eq 0 ]
  [[ "$output" == *"derived: scm generado"* ]]
  [ -f "$R/.scm/views/v.json" ]
  # Control: con todo presente y sin cambios, no genera.
  run bash "$R/scripts/derived.sh" ensure --only scm
  [ "$status" -eq 0 ]
  [[ "$output" != *"generado"* ]]
  # Una salida editada a mano también invalida el sello.
  echo '{"v": 2}' > "$R/.scm/views/v.json"
  run bash "$R/scripts/derived.sh" ensure --only scm
  [[ "$output" == *"derived: scm generado"* ]]
  grep -q '"v": 1' "$R/.scm/views/v.json"
}

@test "rev-1472 P2-4: la clave cambia con el contenido de una ruta con salto de línea y de un renombrado" {
  mkrepo; fake_gens
  local nl=$'n\nl.txt' k1 k2 k3 k4
  echo uno > "$R/$nl"
  k1=$(bash "$R/scripts/derived.sh" key --only scm)
  echo dos > "$R/$nl"
  k2=$(bash "$R/scripts/derived.sh" key --only scm)
  [ "$k1" != "$k2" ]
  G add -A; G commit -qm nl
  G mv a.txt "ren ombrado.txt"
  k3=$(bash "$R/scripts/derived.sh" key --only scm)
  echo cambiado > "$R/ren ombrado.txt"
  k4=$(bash "$R/scripts/derived.sh" key --only scm)
  [ "$k3" != "$k4" ]
}

@test "rev-1472 S-P2-2: una derived-paths.txt de la PR que cubra .scm/ no rebaja el tier de ficheros de .scm editados a mano" {
  mkdir -p "$T/rt/scripts" "$T/rt0/scripts"
  cp "$REPO/scripts/risk-tier.py" "$T/rt/scripts/"; cp "$REPO/scripts/risk-tier.py" "$T/rt0/scripts/"
  printf '.scm/\n.scm/views/\n.scm/sam-declarations.json\n.scm/runtime-surface/\n' > "$T/rt/scripts/derived-paths.txt"
  run python3 - "$T/rt/scripts/risk-tier.py" "$T/rt0/scripts/risk-tier.py" <<'PY'
import importlib.util, sys
def load(p):
    s = importlib.util.spec_from_file_location("rt", p); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
m, m0 = load(sys.argv[1]), load(sys.argv[2])   # m0: sin lista (no exime nada)
assert m.SCM_GENERATED_DIRS == (".scm/views/",), m.SCM_GENERATED_DIRS
assert m.SCM_GENERATED_FILES == (), m.SCM_GENERATED_FILES
for f in (".scm/sam-declarations.json", ".scm/runtime-surface/effects/auth-secret.json", ".scm/sam.schema.json"):
    assert m.classify([f]) == m0.classify([f]), (f, m.classify([f]), m0.classify([f]))
# Control: lo que sí es D sigue exento (views/authority.json no eleva por «auth»).
assert m.classify([".scm/views/authority.json"]) != m0.classify([".scm/views/authority.json"])
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}
