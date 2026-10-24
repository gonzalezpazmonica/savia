#!/usr/bin/env bats
# BATS tests for scripts/forge-idea.sh (SE-269 S1)
# Ref: docs/specs/SE-269-bmad-patterns.spec.md

SCRIPT="scripts/forge-idea.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export RESIDUE_FILE="$BATS_TEST_TMPDIR/residue/forge-residue.jsonl"
}

# ── Structure / safety ────────────────────────────────────────────────────

@test "SE269-S1: script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "SE269-S1: script has valid bash syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── Input validation ──────────────────────────────────────────────────────

@test "SE269-S1: --idea is required" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "SE269-S1: --idea with empty string fails" {
  run bash "$SCRIPT" --idea ""
  [ "$status" -eq 1 ]
}

@test "SE269-S1: accepts --idea with valid text" {
  run bash "$SCRIPT" --idea "Crear un sistema de notificaciones"
  [ "$status" -eq 0 ]
}

# ── AC-1.3: linea_roja check ──────────────────────────────────────────────

@test "SE269-S1 AC-1.3: idea violating CRIT-023 produces MUERTA" {
  run bash "$SCRIPT" --idea "Propongo un bypass de seguridad fail.open sin verificacion ni control"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "MUERTA"'* ]]
}

@test "SE269-S1 AC-1.3: clean idea survives linea_roja check" {
  run bash "$SCRIPT" --idea "Mejorar la documentacion del proyecto"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"veredicto": "MUERTA"'* ]]
}

# ── Output structure ──────────────────────────────────────────────────────

@test "SE269-S1: output contains required fields" {
  run bash "$SCRIPT" --idea "test idea"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto"'* ]]
  [[ "$output" == *'"motivo"'* ]]
  [[ "$output" == *'"destilado"'* ]]
  [[ "$output" == *'"turnos"'* ]]
  [[ "$output" == *'"session_id"'* ]]
  [[ "$output" == *'"timestamp"'* ]]
  [[ "$output" == *'"kg_contrast"'* ]]
  [[ "$output" == *'"preguntas_abiertas"'* ]]
  [[ "$output" == *'"decisiones"'* ]]
  [[ "$output" == *'"max_turns"'* ]]
}

@test "SE269-S1: output is valid JSON" {
  run bash "$SCRIPT" --idea "test valid json"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool >/dev/null 2>&1
  [ "$?" -eq 0 ]
}

@test "SE269-S1: verdict is ENDURECIDA for clean ideas" {
  run bash "$SCRIPT" --idea "Una idea valida y no conflictiva"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "ENDURECIDA"'* ]]
}

# ── Adversarial mode ──────────────────────────────────────────────────────

@test "SE269-S1: --adversarial flag is accepted" {
  run bash "$SCRIPT" --idea "test" --adversarial
  [ "$status" -eq 0 ]
}

@test "SE269-S1: adversarial mode reflected in output" {
  run bash "$SCRIPT" --idea "test" --adversarial
  [ "$status" -eq 0 ]
  [[ "$output" == *'"adversarial": true'* ]]
}

@test "SE269-S1: default mode is not adversarial" {
  run bash "$SCRIPT" --idea "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"adversarial": false'* ]]
}

# ── AC-1.6: max turns ─────────────────────────────────────────────────────

@test "SE269-S1 AC-1.6: max_turns is in output" {
  run bash "$SCRIPT" --idea "test" --max-turns 15
  [ "$status" -eq 0 ]
  [[ "$output" == *'"max_turns": 15'* ]]
}

@test "SE269-S1 AC-1.6: default max_turns is 20" {
  run bash "$SCRIPT" --idea "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"max_turns": 20'* ]]
}

# ── Residue file ──────────────────────────────────────────────────────────

@test "SE269-S1 AC-1.5: residue file is created" {
  local tmp_dir; tmp_dir="$(mktemp -d)"
  local residue_file="$tmp_dir/forge-residue.jsonl"
  mkdir -p "$(dirname "$residue_file")"
  run env RESIDUE_FILE="$residue_file" bash "$SCRIPT" --idea "test residue write"
  [ "$status" -eq 0 ]
  [[ -f "$residue_file" ]]
  rm -rf "$tmp_dir"
}

# ── Destilado ─────────────────────────────────────────────────────────────

@test "SE269-S1 AC-1.4: destilado contains the idea content" {
  run bash "$SCRIPT" --idea "Crear un dashboard de metricas"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Crear un dashboard de metricas"* ]]
}

# ── Session ID ────────────────────────────────────────────────────────────

@test "SE269-S1: each run produces unique session_id" {
  run bash "$SCRIPT" --idea "test1"
  local sid1; sid1=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])" 2>/dev/null)
  run bash "$SCRIPT" --idea "test2"
  local sid2; sid2=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])" 2>/dev/null)
  [[ "$sid1" != "$sid2" ]]
}

# ── Decisiones ────────────────────────────────────────────────────────────

@test "SE269-S1: decisiones array is populated" {
  run bash "$SCRIPT" --idea "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decisiones"'* ]]
  local count; count=$(echo "$output" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['decisiones']))" 2>/dev/null)
  [[ "$count" -ge 1 ]]
}

# ── kg_contrast field ─────────────────────────────────────────────────────

@test "SE269-S1: kg_contrast field is present" {
  run bash "$SCRIPT" --idea "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kg_contrast"'* ]]
}

# ── Comportamiento: lineas rojas, residuo, valores especiales y rama del KG ──────────

# jf <expresion-python-sobre-d>: evalua sobre el JSON de la salida de la ultima ejecucion
jf() { python3 -c "import json,sys;d=json.loads(sys.argv[1]);assert $1, d" "$output"; }

@test "cada linea roja produce MUERTA con su codigo CRIT" {
  declare -A casos=(
    ["Quiero un bypass del control"]="CRIT-023"
    ["Publicar metricas internas del equipo"]="CRIT-013"
    ["Vamos a privatizar el repositorio"]="CRIT-010"
    ["Hay que subir los datos a un servicio cloud"]="CRIT-001"
  )
  for idea in "${!casos[@]}"; do
    run bash "$SCRIPT" --idea "$idea"
    [ "$status" -eq 0 ]
    jf "d['veredicto']=='MUERTA' and '${casos[$idea]}' in d['motivo'] and d['turnos']==0 and d['destilado']==''" || { echo "$idea"; return 1; }
  done
}

@test "cada formulacion de cada linea roja se detecta con el codigo que le corresponde" {
  while IFS='|' read -r crit idea; do
    run bash "$SCRIPT" --idea "$idea"
    [ "$status" -eq 0 ]
    jf "d['veredicto']=='MUERTA' and d['motivo'].endswith('$crit')" || { echo "$crit: $idea"; return 1; }
  done <<'EOT'
CRIT-023|Hacerlo fail-open por defecto
CRIT-023|Desplegar sin verificación previa
CRIT-023|Dejarlo sin control humano
CRIT-023|Ejecutarlo sin supervisión
CRIT-023|Un bypass para ir mas rapido
CRIT-023|Podemos saltar el gate de calidad
CRIT-013|Compartir las metricas internas con clientes
CRIT-013|Datos internos sin publicar en la web
CRIT-013|Dejar datos internos fuera del repositorio publico
CRIT-010|Cerrar el proyecto a la comunidad
CRIT-010|Hay que privatizar el codigo
CRIT-010|Excluir a los colaboradores externos
CRIT-010|Restringir acceso al repositorio
CRIT-001|Subir los ficheros a la cloud
CRIT-001|Usar un proveedor externo para el analisis
CRIT-001|Contratar un servicio cloud para guardar datos
CRIT-001|Compartir con terceros los datos del equipo
EOT
}

@test "una idea parecida pero sin ninguna formulacion de linea roja sobrevive" {
  for idea in "Verificar los datos con el equipo" "Mejorar el control de versiones" "Publicar las metricas del sprint" "Abrir el proyecto a mas gente" "Guardar datos en local"; do
    run bash "$SCRIPT" --idea "$idea"
    [ "$status" -eq 0 ]
    jf "d['veredicto']=='ENDURECIDA'" || { echo "$idea"; return 1; }
  done
}

@test "--max-turns vacio se rechaza como no entero" {
  run bash "$SCRIPT" --idea "algo" --max-turns ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"--max-turns debe ser un entero"* ]]
}

@test "varias lineas rojas se acumulan en el motivo" {
  run bash "$SCRIPT" --idea "bypass y privatizar todo"
  [ "$status" -eq 0 ]
  jf "'CRIT-023' in d['motivo'] and 'CRIT-010' in d['motivo']"
  jf "d['decisiones'][0]['decision']=='muerte por linea_roja' and 'CRIT-010' in d['decisiones'][0]['crits']"
}

@test "la deteccion de lineas rojas no distingue mayusculas" {
  run bash "$SCRIPT" --idea "BYPASS del Control"
  [ "$status" -eq 0 ]
  jf "d['veredicto']=='MUERTA'"
}

@test "una idea MUERTA no escribe residuo" {
  run bash "$SCRIPT" --idea "bypass del control"
  [ "$status" -eq 0 ]
  [ ! -e "$RESIDUE_FILE" ]
}

@test "una idea limpia escribe una linea de residuo con sesion, veredicto y longitud" {
  run bash "$SCRIPT" --idea "Mejorar la documentacion" --session-id sesion-xyz
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$RESIDUE_FILE")" -eq 1 ]
  python3 -c 'import json,sys;d=json.loads(open(sys.argv[1]).read());assert d["session_id"]=="sesion-xyz" and d["veredicto"]=="ENDURECIDA" and d["idea_len"]==len("Mejorar la documentacion") and d["adversarial"] is False and d["kg_contrast"]=="kg_vacio_o_escaso",d' "$RESIDUE_FILE"
}

@test "el residuo se anade, no se sobrescribe, y crea la carpeta si falta" {
  bash "$SCRIPT" --idea "uno" >/dev/null
  run bash "$SCRIPT" --idea "dos" --adversarial
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$RESIDUE_FILE")" -eq 2 ]
  [ "$(sed -n 2p "$RESIDUE_FILE" | python3 -c 'import json,sys;print(json.load(sys.stdin)["adversarial"])')" = "True" ]
}

@test "--session-id fija el session_id de la salida" {
  run bash "$SCRIPT" --idea "algo" --session-id fijo-123
  [ "$status" -eq 0 ]
  jf "d['session_id']=='fijo-123'"
}

@test "una comilla simple en la idea no rompe la salida ni se interpreta como codigo" {
  run bash "$SCRIPT" --idea "it's a plan'); import os; os.system('touch $BATS_TEST_TMPDIR/pwned'); ('"
  [ "$status" -eq 0 ]
  jf "d['veredicto']=='ENDURECIDA' and d['destilado'].startswith(\"it's a plan\")"
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "comillas dobles, barras y saltos de linea en la idea sobreviven como texto" {
  idea=$'dice "hola" \\ y\nsegunda linea'
  run bash "$SCRIPT" --idea "$idea"
  [ "$status" -eq 0 ]
  IDEA_ESPERADA="$idea" python3 -c 'import json,os,sys;d=json.loads(sys.argv[1]);assert d["destilado"]==os.environ["IDEA_ESPERADA"],d' "$output"
}

@test "la idea se trunca a 800 caracteres en el destilado" {
  idea=$(printf 'x%.0s' $(seq 1 1000))
  run bash "$SCRIPT" --idea "$idea"
  [ "$status" -eq 0 ]
  jf "len(d['destilado'])==800"
}

@test "--file lee la idea del fichero" {
  printf 'idea desde fichero' > "$BATS_TEST_TMPDIR/idea.txt"
  run bash "$SCRIPT" --file "$BATS_TEST_TMPDIR/idea.txt"
  [ "$status" -eq 0 ]
  jf "d['destilado']=='idea desde fichero'"
}

@test "--file con un fichero inexistente equivale a idea vacia: error" {
  run bash "$SCRIPT" --file "$BATS_TEST_TMPDIR/no-existe.txt"
  [ "$status" -eq 1 ]
}

@test "idea vacia: error JSON en stderr y sin salida" {
  run bash -c "bash '$SCRIPT' --idea '' 2>&1 >/dev/null"
  [[ "$output" == *'{"error":"--idea obligatorio"}'* ]]
}

@test "--max-turns no entero se rechaza con exit 1" {
  run bash "$SCRIPT" --idea "algo" --max-turns "abc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--max-turns debe ser un entero"* ]]
  run bash "$SCRIPT" --idea "algo" --max-turns "5; import os"
  [ "$status" -eq 1 ]
}

@test "--max-turns 0 y valores grandes son enteros validos" {
  run bash "$SCRIPT" --idea "algo" --max-turns 0
  [ "$status" -eq 0 ]
  jf "d['max_turns']==0"
  run bash "$SCRIPT" --idea "algo" --max-turns 500
  [ "$status" -eq 0 ]
  jf "d['max_turns']==500"
}

@test "--help imprime el uso y sale con 0 sin ejecutar" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == "Uso: forge-idea.sh --idea"* ]]
  [ ! -e "$RESIDUE_FILE" ]
}

@test "argumentos desconocidos se ignoran" {
  run bash "$SCRIPT" --idea "algo" --desconocido
  [ "$status" -eq 0 ]
  jf "d['veredicto']=='ENDURECIDA'"
}

@test "la salida limpia declara 3 turnos, motivo de cold-start y engram almacenado" {
  run bash "$SCRIPT" --idea "algo limpio"
  [ "$status" -eq 0 ]
  jf "d['turnos']==3 and d['engram_stored'] is True and 'cold-start' in d['motivo'] and d['preguntas_abiertas']==[] and len(d['decisiones'])==2"
}

# kgroot <salida-del-kg>: copia el script a un arbol con un knowledge-graph.sh simulado
kgroot() {
  K="$BATS_TEST_TMPDIR/kgroot"; mkdir -p "$K/scripts"
  cp "$SCRIPT" "$K/scripts/forge-idea.sh"
  printf '#!/usr/bin/env bash\necho '"'"'%s'"'"'\n' "$1" > "$K/scripts/knowledge-graph.sh"
  chmod +x "$K/scripts/knowledge-graph.sh"
}

@test "KG con entidades: kg_contrast_disponible y el recuento en el motivo" {
  kgroot '[{"id":"a"},{"id":"b"},{"id":"c"}]'
  run bash "$K/scripts/forge-idea.sh" --idea "notificaciones"
  [ "$status" -eq 0 ]
  jf "d['kg_contrast']=='kg_contrast_disponible' and '3 entidades en KG' in d['motivo']"
  jf "any('3 entidades en KG' in x['motivo'] for x in d['decisiones'])"
}

@test "KG que devuelve lista vacia o null se trata como cold-start" {
  for out in '[]' 'null'; do
    kgroot "$out"
    run bash "$K/scripts/forge-idea.sh" --idea "notificaciones"
    [ "$status" -eq 0 ]
    jf "d['kg_contrast']=='kg_vacio_o_escaso'"
  done
}

@test "KG que devuelve algo que no es una lista cuenta cero y no marca contraste" {
  kgroot '{"a":1}'
  run bash "$K/scripts/forge-idea.sh" --idea "notificaciones"
  [ "$status" -eq 0 ]
  jf "d['kg_contrast']=='kg_vacio_o_escaso'"
}

@test "KG que falla se trata como cold-start sin romper la salida" {
  K="$BATS_TEST_TMPDIR/kgroot"; mkdir -p "$K/scripts"; cp "$SCRIPT" "$K/scripts/forge-idea.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$K/scripts/knowledge-graph.sh"; chmod +x "$K/scripts/knowledge-graph.sh"
  run bash "$K/scripts/forge-idea.sh" --idea "notificaciones"
  [ "$status" -eq 0 ]
  jf "d['kg_contrast']=='kg_vacio_o_escaso'"
}

@test "el contraste KG se registra tambien en el residuo" {
  kgroot '[{"id":"a"}]'
  run bash "$K/scripts/forge-idea.sh" --idea "notificaciones"
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys;d=json.loads(open(sys.argv[1]).read());assert d["kg_contrast"]=="kg_contrast_disponible",d' "$RESIDUE_FILE"
}

@test "la consulta al KG recibe los terminos de la idea en minusculas y sin signos" {
  kgroot '[]'
  printf '#!/usr/bin/env bash\necho "$@" > "%s"\necho "[]"\n' "$BATS_TEST_TMPDIR/kgargs" > "$K/scripts/knowledge-graph.sh"
  run bash "$K/scripts/forge-idea.sh" --idea "Crear DASHBOARD, ya!"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/kgargs")" = "query --terms crear dashboard ya " ]
}
