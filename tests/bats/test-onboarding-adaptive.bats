#!/usr/bin/env bats
# SE-484 — onboarding adaptativo: catálogo, plan determinista, simulación, reentrada y privacidad.
# Fixtures sintéticos en tests/fixtures/onboarding/ (personas ficticias, slug fx-*). Perfiles: SPEC-110.

SCRIPT="scripts/onboarding-plan.py"
ENGINE="$SCRIPT"
CATALOG="docs/onboarding/capabilities.yaml"
FX="tests/fixtures/onboarding"

setup() {
  # Los helpers encadenan el motor con python3: sin pipefail un fallo del motor quedaría oculto.
  set -o pipefail
  REPO="$(git rev-parse --show-toplevel)"
  cd "$REPO"
  TMP="$(mktemp -d)"
  # Repo de juguete con la misma regla de ignorado y la plantilla real: el onboarding simulado escribe aquí.
  SANDBOX="$TMP/repo"
  mkdir -p "$SANDBOX/.claude/profiles/users"
  cp -r .claude/profiles/users/template "$SANDBOX/.claude/profiles/users/template"
  printf '.claude/profiles/users/*\n!.claude/profiles/users/template/\n' > "$SANDBOX/.gitignore"
  git -C "$SANDBOX" init -q
  git -C "$SANDBOX" add -A
  git -C "$SANDBOX" -c user.email=t@example.com -c user.name=t commit -qm base
}

teardown() {
  rm -rf "$TMP"
}

plan_of() {
  python3 "$ENGINE" plan --input "$1"
}

# Comprueba un campo del plan con una expresión Python sobre `p`.
plan_check() {
  local fixture="$1" expr="$2"
  plan_of "$fixture" | python3 -c "import json,sys; p=json.load(sys.stdin); sys.exit(0 if ($expr) else 1)"
}

caps_of() {
  plan_of "$1" | python3 -c "import json,sys; print(','.join(sorted(c['id'] for c in json.load(sys.stdin)['capabilities'])))"
}

steps_of() {
  plan_of "$1" | python3 -c "import json,sys; print(' '.join(s['command'] for s in json.load(sys.stdin)['first_steps']))"
}

sandbox_apply() {
  python3 "$ENGINE" apply --root "$SANDBOX" --catalog "$REPO/$CATALOG" "$@"
}

# ── AC-1: esquema y referencias ─────────────────────────────────────────────
# cubre: main, validate_catalog, load_catalog, schema_errors, _resolve, semantic_errors, _configures_blocks,
#        reference_errors, template_keys, frontmatter

@test "AC-1: el catálogo valida contra su esquema" {
  run python3 "$ENGINE" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK catálogo válido"* ]]
}

@test "AC-1 negativo [invalid]: una recomendada que no es opción hace fallar la validación" {
  sed 's/recommended: internal/recommended: inventada/' "$CATALOG" > "$TMP/bad.yaml"
  run python3 "$ENGINE" validate --catalog "$TMP/bad.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"knowledge.confidentiality: la recomendada 'inventada' no es una opción"* ]]
}

@test "AC-1 negativo [invalid]: una clave fuera del esquema hace fallar la validación" {
  sed 's/^version: 1$/version: 1\nsorpresa: true/' "$CATALOG" > "$TMP/bad.yaml"
  run python3 "$ENGINE" validate --catalog "$TMP/bad.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"clave no permitida 'sorpresa'"* ]]
}

@test "AC-1 límite [boundary]: más de 4 opciones sin ninguna destacada falla" {
  sed 's/, featured: true//' "$CATALOG" > "$TMP/bad.yaml"
  run python3 "$ENGINE" validate --catalog "$TMP/bad.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sdd-development.languages: con más de 4 opciones hacen falta 1..4 'featured' (hay 0)"* ]]
}

@test "AC-1 negativo [reject]: /sprint-status no puede ser un primer paso" {
  sed 's/command: arch-detect/command: sprint-status/' "$CATALOG" > "$TMP/bad.yaml"
  run python3 "$ENGINE" validate --catalog "$TMP/bad.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"primer paso prohibido (genérico): /sprint-status"* ]]
}

@test "AC-1: cada configures apunta a ficheros, claves, packs, skills y comandos que existen" {
  run python3 "$ENGINE" refs
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK todas las referencias existen"* ]]
}

@test "AC-1 negativo [nonexistent]: comando, skill, pack y clave inexistentes se detectan" {
  sed -e 's/commands: \[vault-init, vault-status\]/commands: [vault-init, comando-fantasma]/' \
      -e 's/skills: \[savia-vaults\]/skills: [skill-fantasma]/' \
      -e 's#packs: \[docs/rules/domain/language-packs.md\]#packs: [docs/no-existe.md]#' \
      -e 's/alert_style: direct}/clave_fantasma: direct}/' "$CATALOG" > "$TMP/bad.yaml"
  run python3 "$ENGINE" refs --catalog "$TMP/bad.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no existe el comando /comando-fantasma"* ]]
  [[ "$output" == *"no existe la skill skill-fantasma"* ]]
  [[ "$output" == *"no existe el pack docs/no-existe.md"* ]]
  [[ "$output" == *"la clave tone.md:clave_fantasma no está en la plantilla"* ]]
}

# ── AC-2: mapeo determinista con capacidades propuestas fijas ───────────────
# cubre: build_plan, _match_option, _merge_set, slugify, pick_first_steps, diff_writes

@test "AC-2 investigadora: investigación + conocimiento + desarrollo, prerregistro obligatorio" {
  [ "$(caps_of "$FX/investigadora.json")" = "knowledge,research,sdd-development,tone" ]
  plan_check "$FX/investigadora.json" "p['status']=='ready' and {'file':'preferences.md','key':'research_preregistration','value':'required','action':'create'} in p['writes']"
  [ "$(steps_of "$FX/investigadora.json")" = "biblio-search vault-init arch-detect" ]
}

@test "AC-2 PM: gestión de proyectos con Savia Flow y cadencia de dos semanas" {
  [ "$(caps_of "$FX/pm.json")" = "project-management,tone" ]
  plan_check "$FX/pm.json" "'flow-setup' in p['commands'] and {'file':'workflow.md','key':'planning_cadence','value':'2w','action':'create'} in p['writes']"
  [ "$(steps_of "$FX/pm.json")" = "flow-setup flow-backlog-groom sprint-plan" ]
}

@test "AC-2 programador: dos lenguajes activan sus dos packs y Codex exige su cliente" {
  [ "$(caps_of "$FX/programador.json")" = "harness-orchestration,sdd-development,tone" ]
  plan_check "$FX/programador.json" "'docs/rules/languages/go-rules.md' in p['packs'] and 'docs/rules/languages/typescript-rules.md' in p['packs'] and [r['id'] for r in p['requires']]==['codex-cli']"
  plan_check "$FX/programador.json" "{'file':'preferences.md','key':'harness_providers','value':['claude','codex'],'action':'create'} in p['writes']"
}

@test "AC-2 profesor: Savia School como docente y vertical de educación" {
  [ "$(caps_of "$FX/profesor.json")" = "teaching-learning,tone,vertical" ]
  plan_check "$FX/profesor.json" "p['vertical']=={'status':'selected','id':'education'} and 'school-setup' in p['commands']"
}

@test "AC-2 alumna: Savia School como alumna, sin vertical" {
  [ "$(caps_of "$FX/alumna.json")" = "sdd-development,teaching-learning,tone" ]
  plan_check "$FX/alumna.json" "'my-learning' in p['commands'] and 'school-setup' not in p['commands'] and p['vertical']['status']=='none'"
}

@test "AC-2 médica: vertical de salud marcada como categoría especial y confidencialidad máxima" {
  [ "$(caps_of "$FX/medica.json")" = "knowledge,research,tone,vertical" ]
  plan_check "$FX/medica.json" "p['vertical']['id']=='healthcare' and [s['capability'] for s in p['sensitivity']['special_categories']]==['vertical']"
  plan_check "$FX/medica.json" "{'file':'preferences.md','key':'knowledge_confidentiality','value':'confidential','action':'create'} in p['writes']"
}

@test "AC-2 científico: investigación con Python y Rust" {
  [ "$(caps_of "$FX/cientifico.json")" = "knowledge,research,sdd-development,tone" ]
  plan_check "$FX/cientifico.json" "{'file':'workflow.md','key':'sdd_languages','value':['python','rust'],'action':'create'} in p['writes']"
}

@test "AC-2 ambigua [empty]: «hago de todo» pide aclaración en vez de configurar de más" {
  plan_check "$FX/ambigua.json" "p['status']=='needs_clarification' and [c['id'] for c in p['capabilities']]==['tone'] and p['clarify']['interview_skill']=='context-interview-conductor'"
  run python3 "$ENGINE" apply --root "$SANDBOX" --catalog "$REPO/$CATALOG" --input "$FX/ambigua.json" --profile-dir "$SANDBOX/.claude/profiles/users/fx-ambigua" --confirm
  [ "$status" -eq 5 ]
  [ ! -e "$SANDBOX/.claude/profiles/users/fx-ambigua" ]
}

@test "AC-2: todos los perfiles dan tres primeros pasos distintos, existentes y nunca /sprint-status" {
  for f in "$FX"/*.json; do
    steps="$(steps_of "$f")"
    [ "$(wc -w <<<"$steps")" -eq 3 ]
    [ "$(tr ' ' '\n' <<<"$steps" | sort -u | wc -l)" -eq 3 ]
    for c in $steps; do
      [ -f ".claude/commands/$c.md" ]
      [ "$c" != "sprint-status" ]
    done
  done
}

# ── AC-3: sin vertical no se inventa ninguna ────────────────────────────────

@test "AC-3 astronauta: capacidades generales y declaración explícita de que no hay vertical" {
  [ "$(caps_of "$FX/astronauta.json")" = "accessibility,knowledge,project-management,tone" ]
  plan_check "$FX/astronauta.json" "p['vertical']['status']=='none' and '/vertical-propose' in p['vertical']['message'] and not any(c.startswith('vertical-') for c in p['commands'])"
}

@test "AC-3 negativo [reject]: una capacidad o una opción inventadas se rechazan, no se configuran" {
  python3 -c "
import json; d=json.load(open('$FX/astronauta.json'))
d['proposed'].append({'id':'vertical-espacial','reason':'inventada'})
d['proposed'].append({'id':'vertical','reason':'sector'}); d['answers']['vertical']={'which':'espacial'}
json.dump(d, open('$TMP/in.json','w'))"
  plan_check "$TMP/in.json" "p['rejected']==[{'id':'vertical-espacial','reason':'no existe en el catálogo; no se inventa'}] and p['status']=='invalid_answers'"
  plan_check "$TMP/in.json" "\"vertical.which: opción desconocida 'espacial'\" in p['invalid_answers'] and p['vertical']['status']=='none'"
}

# ── AC-4: sin confirmación no se escribe nada ───────────────────────────────
# cubre: apply, write_keys, _yaml_scalar, run_checks, fail

@test "AC-4: apply sin --confirm es una simulación y no crea nada" {
  run sandbox_apply --input "$FX/pm.json" --profile-dir "$SANDBOX/.claude/profiles/users/fx-pm"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"applied": false'* ]]
  [ ! -e "$SANDBOX/.claude/profiles/users/fx-pm" ]
}

@test "AC-4: con --confirm escribe las claves del plan sobre la plantilla" {
  run sandbox_apply --input "$FX/pm.json" --profile-dir "$SANDBOX/.claude/profiles/users/fx-pm" --confirm
  [ "$status" -eq 0 ]
  grep -qx 'tracking_extra: "savia-flow"' "$SANDBOX/.claude/profiles/users/fx-pm/tools.md"
  grep -qx 'alert_style: "direct"' "$SANDBOX/.claude/profiles/users/fx-pm/tone.md"
  grep -qx 'name: "Gestora Ficticia"' "$SANDBOX/.claude/profiles/users/fx-pm/identity.md"
  grep -qx 'azure_devops: false' "$SANDBOX/.claude/profiles/users/fx-pm/tools.md"
}

@test "AC-4 negativo [block]: respuestas inválidas bloquean la aplicación aunque se confirme" {
  python3 -c "
import json; d=json.load(open('$FX/pm.json')); d['answers']['project-management']['tracker']=['jira','savia-flow']
json.dump(d, open('$TMP/in.json','w'))"
  run sandbox_apply --input "$TMP/in.json" --profile-dir "$SANDBOX/.claude/profiles/users/fx-pm" --confirm
  [ "$status" -eq 5 ]
  [[ "$output" == *"project-management.tracker: admite una sola opción"* ]]
  [ ! -e "$SANDBOX/.claude/profiles/users/fx-pm" ]
}

@test "AC-4 [missing]: los requisitos externos que faltan se diagnostican sin bloquear el resto" {
  python3 -c "
import json; d=json.load(open('$FX/pm.json')); d['answers']['project-management']['tracker']='azure-devops'
json.dump(d, open('$TMP/in.json','w'))"
  HOME="$TMP/home" run sandbox_apply --input "$TMP/in.json" --profile-dir "$SANDBOX/.claude/profiles/users/fx-pm" --confirm
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; p=json.load(sys.stdin); sys.exit(0 if p['applied'] and p['diagnostics']==[{'id':'azure-pat','ok':False,'description':'Token de Azure DevOps en ~/.azure/devops-pat'}] else 1)"
}

# ── AC-5: reentrada, solo cambios propuestos ────────────────────────────────

@test "AC-5: un perfil existente solo recibe cambios y no se sobrescribe sin confirmar la clave" {
  dir="$SANDBOX/.claude/profiles/users/fx-pm"
  sandbox_apply --input "$FX/pm.json" --profile-dir "$dir" --confirm >/dev/null
  sed -i 's/^alert_style: .*/alert_style: "diplomatic"/' "$dir/tone.md"
  printf 'Nota propia de la persona.\n' >> "$dir/tone.md"
  run sandbox_apply --input "$FX/pm.json" --profile-dir "$dir" --confirm
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; p=json.load(sys.stdin); sys.exit(0 if [w['action'] for w in p['writes']]==['overwrite'] and p['writes'][0]['before']=='diplomatic' and p['skipped_overwrites']==['tone.md:alert_style'] and p['unchanged']>0 else 1)"
  grep -qx 'alert_style: "diplomatic"' "$dir/tone.md"
  grep -qx 'Nota propia de la persona.' "$dir/tone.md"
}

@test "AC-5: con --overwrite de la clave concreta sí se cambia, y la nota propia se conserva" {
  dir="$SANDBOX/.claude/profiles/users/fx-pm"
  sandbox_apply --input "$FX/pm.json" --profile-dir "$dir" --confirm >/dev/null
  sed -i 's/^alert_style: .*/alert_style: "diplomatic"/' "$dir/tone.md"
  printf 'Nota propia de la persona.\n' >> "$dir/tone.md"
  run sandbox_apply --input "$FX/pm.json" --profile-dir "$dir" --confirm --overwrite tone.md:alert_style
  [ "$status" -eq 0 ]
  grep -qx 'alert_style: "direct"' "$dir/tone.md"
  grep -qx 'Nota propia de la persona.' "$dir/tone.md"
}

@test "AC-5 límite [zero]: repetir el mismo onboarding no propone ningún cambio" {
  dir="$SANDBOX/.claude/profiles/users/fx-medica"
  sandbox_apply --input "$FX/medica.json" --profile-dir "$dir" --confirm >/dev/null
  run sandbox_apply --input "$FX/medica.json" --profile-dir "$dir"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; p=json.load(sys.stdin); sys.exit(0 if p['writes']==[] and p['unchanged']>=8 else 1)"
}

# ── AC-6: ningún dato sale del directorio de perfiles ignorado ──────────────
# cubre: check_destination

@test "AC-6: tras un onboarding simulado el árbol versionado no tiene rastros" {
  for f in "$FX"/*.json; do
    slug="fx-$(basename "$f" .json)"
    [ "$slug" = "fx-ambigua" ] && continue
    sandbox_apply --input "$f" --profile-dir "$SANDBOX/.claude/profiles/users/$slug" --confirm >/dev/null
  done
  [ -f "$SANDBOX/.claude/profiles/users/fx-astronauta/identity.md" ]
  [ -z "$(git -C "$SANDBOX" status --porcelain)" ]
  run git -C "$SANDBOX" grep -n "Ficticia" HEAD
  [ "$status" -eq 1 ]
  [ "$(find "$SANDBOX" -path "$SANDBOX/.git" -prune -o -newer "$SANDBOX/.gitignore" -type f -print | grep -vc '/.claude/profiles/users/fx-')" -eq 0 ]
}

@test "AC-6 negativo [reject]: un destino fuera de profiles/users se rechaza y no se escribe" {
  run sandbox_apply --input "$FX/pm.json" --profile-dir "$SANDBOX/docs/fx-pm" --confirm
  [ "$status" -eq 4 ]
  [[ "$output" == *"destino no permitido"* ]]
  [ ! -e "$SANDBOX/docs/fx-pm" ]
}

@test "AC-6 negativo [block]: si git no ignora el directorio de perfiles, no se escribe" {
  printf '# sin regla\n' > "$SANDBOX/.gitignore"
  run sandbox_apply --input "$FX/pm.json" --profile-dir "$SANDBOX/.claude/profiles/users/fx-pm" --confirm
  [ "$status" -eq 4 ]
  [[ "$output" == *"destino no ignorado por git"* ]]
  [ ! -e "$SANDBOX/.claude/profiles/users/fx-pm" ]
}

@test "AC-6 negativo [reject]: el slug del plan debe coincidir con el directorio" {
  run sandbox_apply --input "$FX/pm.json" --profile-dir "$SANDBOX/.claude/profiles/users/fx-otra" --confirm
  [ "$status" -eq 4 ]
  [ ! -e "$SANDBOX/.claude/profiles/users/fx-otra" ]
}

# ── AC-7: presentación sin emojis con la frase de la fuente única ───────────
# cubre: identity_short

@test "AC-7: la presentación usa la frase corta de la fuente única y la pregunta abierta" {
  printf '# Savia\n\n## Identidad canónica\n\n<!-- identity:short -->\n> Frase corta de prueba.\n\nResto.\n' > "$TMP/savia.md"
  run python3 "$ENGINE" present --source "$TMP/savia.md"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Frase corta de prueba." ]
  [ "${lines[1]}" = "¿A qué te dedicas y qué quieres conseguir con Savia?" ]
}

@test "AC-7 negativo [missing]: sin marcador en la fuente o con emojis, la presentación falla cerrada" {
  printf '# Savia\n\nSin marcador.\n' > "$TMP/savia.md"
  run python3 "$ENGINE" present --source "$TMP/savia.md"
  [ "$status" -eq 3 ]
  printf '<!-- identity:short -->\nFrase con buho \xf0\x9f\xa6\x89\n' > "$TMP/savia.md"
  run python3 "$ENGINE" present --source "$TMP/savia.md"
  [ "$status" -eq 3 ]
  [[ "$output" == *"contiene emojis"* ]]
}

@test "AC-7: las superficies del onboarding no tienen emojis ni copia propia de la identidad" {
  for f in .claude/commands/profile-setup.md .claude/commands/onboard.md docs/rules/domain/profile-onboarding.md; do
    run grep -nP '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}]' "$f"
    [ "$status" -eq 1 ]
    run grep -n "metaorquestadora" "$f"
    [ "$status" -eq 1 ]
  done
  grep -q 'identity:short' .claude/commands/profile-setup.md
}

# ── AC-8: smoke dual Claude Code / OpenCode ─────────────────────────────────
# cubre: questions, render

@test "AC-8: OpenCode y Claude Code leen el mismo comando, que delega en el motor" {
  cmp -s .claude/commands/profile-setup.md .opencode/commands/profile-setup.md
  cmp -s .claude/commands/onboard.md .opencode/commands/onboard.md
  for f in .claude/commands/profile-setup.md .opencode/commands/profile-setup.md; do
    grep -q "scripts/onboarding-plan.py" "$f"
    grep -q "docs/onboarding/capabilities.yaml" "$f"
  done
  grep -q "profile-setup" .claude/commands/onboard.md
}

@test "AC-8: las mismas preguntas con botones (≤4 opciones) y en texto numerado" {
  python3 -c "
import json; d=json.load(open('$FX/programador.json')); d['answers']={}
json.dump(d, open('$TMP/in.json','w'))"
  run python3 "$ENGINE" questions --input "$TMP/in.json" --render askuser
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys; q=json.load(sys.stdin)['questions']
assert [x['ask'] for x in q]==['languages','review','providers','alert_style','formality'], q
assert all(1 <= len(x['options']) <= 4 and len(x['header']) <= 12 for x in q)
assert q[0]['options'][0]['label']=='Python (recomendada)' and q[0]['multiSelect'] is True"
  run python3 "$ENGINE" questions --input "$TMP/in.json" --render text
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^[0-9]+\. ' <<<"$output")" -eq 5 ]
  [[ "$output" == *"   p) COBOL: Convenciones de COBOL."* ]]
}

@test "AC-8: una respuesta con la etiqueta del botón se reconoce igual que el id" {
  python3 -c "
import json; d=json.load(open('$FX/pm.json')); d['answers']['project-management']['tracker']='Savia Flow (recomendada)'
json.dump(d, open('$TMP/in.json','w'))"
  plan_check "$TMP/in.json" "p['status']=='ready' and 'flow-setup' in p['commands']"
}
