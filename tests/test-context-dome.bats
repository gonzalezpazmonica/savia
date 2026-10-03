#!/usr/bin/env bats
# SE-376 — context-dome: CONTEXT_DOME.md se genera como dice la skill y no
# rompe confidencialidad (N4: nada de otro proyecto), idempotencia (no pisa
# ediciones manuales), frontmatter YAML válido, rutas con espacios/unicode ni
# exit codes. Fuentes sintéticas en mktemp; nunca vaults/ reales ni ~/.savia.
# Ref: .claude/skills/context-dome/SKILL.md · docs/propuestas/SE-252-bus-factor-shield.md
# Ref: docs/rules/domain/context-placement-confirmation.md (aislamiento N4)
set -uo pipefail

SCRIPT="scripts/context-dome-generate.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GEN="$REPO_ROOT/$SCRIPT"
  TMPDIR_T="$(mktemp -d)"
  export HOME="$TMPDIR_T/home"
  mkdir -p "$HOME"
  P="$TMPDIR_T/proj"
  OUT="$TMPDIR_T/bf-out"
  mkdir -p "$P" "$OUT"
  export BF_OUTPUT_DIR="$OUT"
  git -C "$P" init -q
  git -C "$P" config user.email alice@test.com
  git -C "$P" config user.name Alice
  git -C "$P" config commit.gpgsign false
}

teardown() { rm -rf "$TMPDIR_T"; }

# mod <dir>: crea el módulo con un fichero y un commit.
mod() {
  mkdir -p "$P/$1"
  echo "x" >> "$P/$1/a.py"
  git -C "$P" add -A
  git -C "$P" commit -qm "${2:-feat: $1}"
}

# scan <modules-json> [project-name] [file]: escribe el JSON de bus-factor-scan.
scan() {
  local name="${2:-proj}" file="${3:-$OUT/proj-20261003T000000Z.json}"
  printf '{"project": "%s", "modules": %s}' "$name" "$1" > "$file"
}

# m <path> [owner] [bf] [risk]: un módulo del scan, con owner en JSON.
m() {
  local owner="${2-alice@test.com}"
  python3 -c 'import json,sys; p,o,bf,r=sys.argv[1:5]
print(json.dumps({"name":p,"path":p,"bus_factor":json.loads(bf),"risk_level":r,
 "owners":[{"dev":o,"score":1.0,"files_owned":1}] if o else [],"warnings":[]}))' \
    "$1" "$owner" "${3:-1}" "${4:-CRITICAL}"
}

# section <fichero> <titulo>: cuerpo de una sección "## <titulo>".
section() { awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

gen() { run bash "$GEN" --project "$P" --min-risk LOW "$@"; }

# fm <fichero>: frontmatter como JSON (falla si el YAML no es válido).
fm() {
  python3 -c 'import sys,yaml,json
t=open(sys.argv[1],encoding="utf-8").read().split("---\n")
print(json.dumps(yaml.safe_load(t[1]),default=str,ensure_ascii=False))' "$1"
}

@test "safety: el script y el test declaran set -uo pipefail" {
  grep -q '^set -uo pipefail' "$GEN"
  grep -q '^set -uo pipefail' "$BATS_TEST_FILENAME"
}

@test "positive: genera CONTEXT_DOME.md con frontmatter YAML válido y las 7 secciones" {
  mod src/pay
  scan "[$(m src/pay)]"
  gen
  [ "$status" -eq 0 ]
  f="$P/src/pay/CONTEXT_DOME.md"
  [ -f "$f" ]
  run fm "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"module": "src/pay"'* ]]
  [[ "$output" == *'"knowledge_owners": ["alice@test.com"]'* ]]
  [[ "$output" == *'"bus_factor": 1'* ]]
  for s in Proposito "Decisiones no obvias" "Dependencias criticas" "Runbook minimo" \
           "Knowledge owners actuales" "Plan de distribucion sugerido" "Historial de cambios relevantes"; do
    [ "$(grep -c "^## $s\$" "$f")" -eq 1 ]
  done
}

@test "edge: ruta con espacios y unicode; owner con tilde; frontmatter sigue siendo válido" {
  mod "src/mi módulo ñ"
  scan "[$(m "src/mi módulo ñ" "José Núñez")]"
  gen
  [ "$status" -eq 0 ]
  run fm "$P/src/mi módulo ñ/CONTEXT_DOME.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"module": "src/mi módulo ñ"'* ]]
  [[ "$output" == *'"José Núñez"'* ]]
}

@test "invalid yaml: owner con ': ', '#' y '*' no rompe el frontmatter" {
  mod src/pay
  scan "[$(m src/pay '*alias: x #c')]"
  gen
  [ "$status" -eq 0 ]
  run fm "$P/src/pay/CONTEXT_DOME.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"knowledge_owners": ["*alias: x #c"]'* ]]
}

@test "edge: owner con apóstrofo (o'brien) genera la cúpula en vez de 'no hay modulos'" {
  mod src/pay
  scan "[$(m src/pay "o'brien@x.com")]"
  gen
  [ "$status" -eq 0 ]
  [ -f "$P/src/pay/CONTEXT_DOME.md" ]
  grep -qF "o'brien@x.com" "$P/src/pay/CONTEXT_DOME.md"
}

@test "error: JSON de scan corrupto falla con exit 2 (ilegible) y no escribe nada" {
  mod src/pay
  printf '{"project": "proj", "modules": [' > "$OUT/proj.json"
  gen
  [ "$status" -eq 2 ]
  [[ "$output" == *"ilegible"* ]]
  [[ "$output" == *"ERROR"* ]]
  [ ! -e "$P/src/pay/CONTEXT_DOME.md" ]
}

@test "reject: --min-risk desconocido se rechaza con exit 1 (antes generaba todo)" {
  mod src/pay
  scan "[$(m src/pay alice@test.com 5 LOW)]"
  run bash "$GEN" --project "$P" --min-risk BOGUS
  [ "$status" -eq 1 ]
  [[ "$output" == *"--min-risk"* ]]
  [ ! -e "$P/src/pay/CONTEXT_DOME.md" ]
}

@test "error: --project sin valor da uso y exit 1, sin 'variable sin asignar'" {
  run bash "$GEN" --project
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" != *"sin asignar"* && "$output" != *"unbound"* ]]
}

@test "error: --project inexistente falla con exit 1" {
  scan "[$(m src/pay)]" nope "$OUT/nope.json"
  run bash "$GEN" --project "$TMPDIR_T/nope" --min-risk LOW
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es un directorio"* ]]
}

@test "block N4: no usa el scan de OTRO proyecto aunque sea el único JSON del directorio" {
  mod src/pay
  scan "[$(m src/pay secreto@clienteA.com)]" clienteA "$OUT/clienteA-20261003T000000Z.json"
  gen
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se encontro JSON de scan"* ]]
  run grep -rF "secreto@clienteA.com" "$P"
  [ "$status" -ne 0 ]
}

@test "block N4: un scan de 'proj-legacy' no se toma por el de 'proj' (prefijo)" {
  mod src/pay
  scan "[$(m src/pay ajeno@legacy.com)]" proj-legacy "$OUT/proj-legacy-20261003T000000Z.json"
  gen
  [ "$status" -eq 1 ]
  run grep -rF "ajeno@legacy.com" "$P"
  [ "$status" -ne 0 ]
}

@test "block N4: un scan de otro proyecto con nombre <proj>-<texto>.json no vale" {
  mod src/pay
  scan "[$(m src/pay ajeno@x.com)]" proj "$OUT/proj-backup.json"
  gen
  [ "$status" -eq 1 ]
  run grep -rF "ajeno@x.com" "$P"
  [ "$status" -ne 0 ]
}

@test "block N4: un scan renombrado a proj.json pero con project ajeno se rechaza" {
  mod src/pay
  scan "[$(m src/pay ajeno@x.com)]" clienteA "$OUT/proj.json"
  gen
  [ "$status" -eq 1 ]
  [[ "$output" == *"es del proyecto 'clienteA'"* ]]
  run grep -rF "ajeno@x.com" "$P"
  [ "$status" -ne 0 ]
}

@test "positive: elige el scan con timestamp mas reciente del proyecto" {
  mod src/pay
  scan "[$(m src/pay viejo@x.com)]" proj "$OUT/proj-20260101T000000Z.json"
  touch -d '2026-01-01' "$OUT/proj-20260101T000000Z.json"
  scan "[$(m src/pay nuevo@x.com)]" proj "$OUT/proj-20261003T120000Z.json"
  gen
  [ "$status" -eq 0 ]
  grep -q "nuevo@x.com" "$P/src/pay/CONTEXT_DOME.md"
}

@test "block N4: las decisiones (why:) se extraen y solo de HEAD, no de ramas sin integrar" {
  mod src/pay "feat: base why: diseño publico"
  git -C "$P" checkout -qb privada
  echo y >> "$P/src/pay/a.py"
  git -C "$P" commit -qam "fix: why: dato-confidencial-de-rama"
  git -C "$P" checkout -q -
  scan "[$(m src/pay)]"
  gen
  [ "$status" -eq 0 ]
  run section "$P/src/pay/CONTEXT_DOME.md" "Decisiones no obvias"
  [[ "$output" == *"diseño publico"* ]]
  [[ "$output" != *"dato-confidencial-de-rama"* ]]
  run grep -F "dato-confidencial-de-rama" "$P/src/pay/CONTEXT_DOME.md"
  [ "$status" -ne 0 ]
}

@test "reject: --module con comillas no se ejecuta como código Python" {
  mod src/pay
  scan "[$(m src/pay)]"
  gen --module "x'+__import__('os').system('touch $TMPDIR_T/PWNED')+'"
  [ "$status" -eq 0 ]
  [ ! -e "$TMPDIR_T/PWNED" ]
  [ ! -e "$P/src/pay/CONTEXT_DOME.md" ]
}

@test "idempotencia: regenerar sin cambios deja el fichero byte a byte y sin secciones duplicadas" {
  mod src/pay
  scan "[$(m src/pay)]"
  gen
  [ "$status" -eq 0 ]
  f="$P/src/pay/CONTEXT_DOME.md"
  before=$(sha256sum "$f")
  gen
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCHANGED"* ]]
  [ "$(sha256sum "$f")" = "$before" ]
  [ "$(grep -c '^## Proposito$' "$f")" -eq 1 ]
  [ "$(grep -c '^---$' "$f")" -eq 2 ]
}

@test "idempotencia: si el scan cambia, se regenera con los datos nuevos" {
  mod src/pay
  scan "[$(m src/pay)]"
  gen
  scan "[$(m src/pay bob@test.com 2 HIGH)]"
  gen
  [ "$status" -eq 0 ]
  run fm "$P/src/pay/CONTEXT_DOME.md"
  [[ "$output" == *'"bus_factor": 2'* && "$output" == *"bob@test.com"* ]]
  [[ "$output" != *"alice@test.com"* ]]
}

@test "block: una cúpula editada a mano no se pisa al regenerar; --force sí la regenera" {
  mod src/pay
  scan "[$(m src/pay)]"
  gen
  f="$P/src/pay/CONTEXT_DOME.md"
  printf '\nNota manual del owner: arrancar con make dev.\n' >> "$f"
  scan "[$(m src/pay bob@test.com 2 HIGH)]"
  gen
  [ "$status" -eq 0 ]
  [[ "$output" == *"editada manualmente"* ]]
  grep -q "Nota manual del owner" "$f"
  gen --force
  [ "$status" -eq 0 ]
  run grep -c "Nota manual del owner" "$f"
  [ "$output" -eq 0 ]
  grep -q "bob@test.com" "$f"
}

@test "empty: scan sin módulos sale con 0 y no escribe nada" {
  mod src/pay
  scan "[]"
  gen
  [ "$status" -eq 0 ]
  [[ "$output" == *"no hay modulos"* ]]
  [ -z "$(find "$P" -name CONTEXT_DOME.md)" ]
}

@test "empty: módulo sin owners da knowledge_owners: [] válido" {
  mod src/pay
  scan "[$(m src/pay '')]"
  gen
  [ "$status" -eq 0 ]
  run fm "$P/src/pay/CONTEXT_DOME.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"knowledge_owners": []'* ]]
}

@test "boundary: bus_factor no entero (1.5) no rompe la aritmética y planifica como BF<=2" {
  mod src/pay
  scan "[$(m src/pay alice@test.com 1.5)]"
  gen
  [ "$status" -eq 0 ]
  [[ "$output" != *"error sintáctico"* && "$output" != *"syntax error"* ]]
  grep -q "pair-review" "$P/src/pay/CONTEXT_DOME.md"
}

@test "reject: path del scan con '..' o absoluto no escribe fuera del proyecto" {
  mod src/pay
  scan "[$(m ../fuera), $(m /tmp/abs-dome-$$)]"
  gen
  [ "$status" -eq 0 ]
  [[ "$output" == *"ruta insegura"* ]]
  [ ! -e "$TMPDIR_T/fuera/CONTEXT_DOME.md" ]
  [ ! -e "/tmp/abs-dome-$$/CONTEXT_DOME.md" ]
}

@test "positive: usa el path del módulo aunque el name sea distinto" {
  mod src/pay
  printf '{"project":"proj","modules":[{"name":"payments","path":"src/pay","bus_factor":1,"risk_level":"CRITICAL","owners":[],"warnings":[]}]}' > "$OUT/proj.json"
  gen
  [ "$status" -eq 0 ]
  [ -f "$P/src/pay/CONTEXT_DOME.md" ]
  for sel in payments src/pay; do
    gen --module "$sel"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UNCHANGED: $P/src/pay/CONTEXT_DOME.md"* ]]
  done
}

@test "confidencialidad: --redact-owners quita el dominio de los emails" {
  mod src/pay
  scan "[$(m src/pay alice@cliente-secreto.com)]"
  gen --redact-owners
  [ "$status" -eq 0 ]
  run grep -rF "cliente-secreto.com" "$P/src/pay/CONTEXT_DOME.md"
  [ "$status" -ne 0 ]
  grep -q "alice" "$P/src/pay/CONTEXT_DOME.md"
}

@test "boundary: --dry-run no escribe y sale con 0" {
  mod src/pay
  scan "[$(m src/pay)]"
  gen --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  [ ! -e "$P/src/pay/CONTEXT_DOME.md" ]
}

@test "block: no sigue un CONTEXT_DOME.md que sea symlink" {
  mod src/pay
  echo "victima" > "$TMPDIR_T/victima.txt"
  ln -s "$TMPDIR_T/victima.txt" "$P/src/pay/CONTEXT_DOME.md"
  scan "[$(m src/pay)]"
  gen --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"symlink"* ]]
  [ "$(cat "$TMPDIR_T/victima.txt")" = "victima" ]
}

@test "idempotencia: generar, commitear la cúpula y regenerar da UNCHANGED (3 ciclos)" {
  mod src/pay
  scan "[$(m src/pay)]"
  for i in 1 2 3; do
    gen
    [ "$status" -eq 0 ]
    if [ "$i" -gt 1 ]; then [[ "$output" == *"UNCHANGED"* ]]; fi
    git -C "$P" add -A
    git -C "$P" commit -qm "docs: why: cúpula ciclo $i" || true
  done
  run section "$P/src/pay/CONTEXT_DOME.md" "Historial de cambios relevantes"
  [[ "$output" != *"cúpula ciclo"* ]]
  run section "$P/src/pay/CONTEXT_DOME.md" "Decisiones no obvias"
  [[ "$output" != *"cúpula ciclo"* ]]
}

@test "boundary: historial excluye commits chore/format/typo/style" {
  mod src/pay "feat: real"
  mod src/pay "chore: ruido"
  mod src/pay "style: espacios"
  scan "[$(m src/pay)]"
  gen
  run section "$P/src/pay/CONTEXT_DOME.md" "Historial de cambios relevantes"
  [[ "$output" == *"feat: real"* ]]
  [[ "$output" != *"chore: ruido"* && "$output" != *"style: espacios"* ]]
}

@test "portabilidad: sin sha256sum ni sed -i GNU (como macOS) la huella sigue funcionando" {
  shim="$TMPDIR_T/shim"; mkdir -p "$shim"
  printf '#!/bin/sh\necho "sha256sum: no existe" >&2; exit 127\n' > "$shim/sha256sum"
  printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "-i" ] && { echo "sed BSD: -i exige sufijo" >&2; exit 1; }; done\nexec %s "$@"\n' "$(command -v sed)" > "$shim/sed"
  chmod +x "$shim/sha256sum" "$shim/sed"
  mod src/pay
  scan "[$(m src/pay)]"
  PATH="$shim:$PATH" gen
  [ "$status" -eq 0 ]
  f="$P/src/pay/CONTEXT_DOME.md"
  grep -qE '^dome_hash: [0-9a-f]{16}$' "$f"
  printf '\nNota manual\n' >> "$f"
  PATH="$shim:$PATH" gen
  [[ "$output" == *"editada manualmente"* ]]
  grep -q "Nota manual" "$f"
}

@test "reject: módulo que es un directorio symlink hacia fuera del proyecto" {
  mkdir -p "$TMPDIR_T/externo" "$P/src"
  ln -s "$TMPDIR_T/externo" "$P/src/pay"
  scan "[$(m src/pay)]"
  gen
  [ "$status" -eq 0 ]
  [[ "$output" == *"fuera del proyecto"* ]]
  [ ! -e "$TMPDIR_T/externo/CONTEXT_DOME.md" ]
}
