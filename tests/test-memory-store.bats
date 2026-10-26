#!/usr/bin/env bats
# Ref: docs/memory-system.md
# Tests for memory-store.sh — JSONL persistent memory store

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/memory-store.sh"
  TMPDIR_MS=$(mktemp -d)
  export PROJECT_ROOT="$TMPDIR_MS"
  export SAVIA_TEST_MODE=true
  mkdir -p "$TMPDIR_MS/output"
}

teardown() {
  rm -rf "$TMPDIR_MS"
}

@test "help shows usage" {
  run bash "$SCRIPT" help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Commands:"* ]]
}

@test "unknown command fails" {
  run bash "$SCRIPT" bogus
  [[ "$status" -eq 1 ]]
}

@test "stats on empty store succeeds" {
  run bash "$SCRIPT" stats
  [[ "$status" -eq 0 ]]
}

@test "save requires type and title" {
  run bash "$SCRIPT" save
  [[ "$status" -ne 0 ]] || [[ "$output" == *"type"* ]] || [[ "$output" == *"title"* ]]
}

@test "save creates JSONL entry" {
  run bash "$SCRIPT" save --type decision --title "Test decision" --content "Test content" --source tool:Bats
  [[ "$status" -eq 0 ]]
  [[ -f "$TMPDIR_MS/output/.memory-store.jsonl" ]]
  grep -q "Test decision" "$TMPDIR_MS/output/.memory-store.jsonl"
}

@test "SE-072: save without --source rejected" {
  run bash "$SCRIPT" save --type decision --title "No source" --content "X"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--source"* ]] || [[ "$stderr" == *"--source"* ]]
}

@test "SE-072: --source speculation blacklisted" {
  run bash "$SCRIPT" save --type decision --title "Spec" --content "X" --source speculation
  [[ "$status" -ne 0 ]]
}

@test "SE-072: invalid --source format rejected" {
  run bash "$SCRIPT" save --type decision --title "Bad" --content "X" --source random-string
  [[ "$status" -ne 0 ]]
}

@test "SE-072: tool:Bash --source accepted" {
  run bash "$SCRIPT" save --type decision --title "OK1" --content "X" --source tool:Bash
  [[ "$status" -eq 0 ]]
}

@test "SE-072: file:path:line --source accepted" {
  run bash "$SCRIPT" save --type pattern --title "OK2" --content "X" --source file:scripts/foo.sh:42
  [[ "$status" -eq 0 ]]
}

@test "SE-072: user:explicit --source accepted" {
  run bash "$SCRIPT" save --type decision --title "OK3" --content "X" --source user:explicit
  [[ "$status" -eq 0 ]]
}

@test "SE-072: source field embedded in JSONL" {
  bash "$SCRIPT" save --type decision --title "WithSource" --content "X" --source tool:Bash
  grep -q '"source":"tool:Bash"' "$TMPDIR_MS/output/.memory-store.jsonl"
}

@test "SE-072: SAVIA_VERIFIED_MEMORY_DISABLED bypass works" {
  SAVIA_VERIFIED_MEMORY_DISABLED=true run bash "$SCRIPT" save --type decision --title "Bypass" --content "X"
  [[ "$status" -eq 0 ]]
}

@test "search on empty store handles gracefully" {
  run bash "$SCRIPT" search "nonexistent"
  # Search may return 0 (no results) or 1 (no store file) — both acceptable
  [[ "$status" -le 1 ]]
}

@test "suggest-topic generates slug" {
  run bash "$SCRIPT" suggest-topic decision "My Test Decision"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"decision/"* ]]
}

@test "suggest-topic without args shows usage" {
  run bash "$SCRIPT" suggest-topic
  [[ "$status" -ne 0 ]] || [[ "$output" == *"Uso"* ]]
}

@test "save then search finds entry" {
  bash "$SCRIPT" save --type bug --title "Login broken" --content "Session expired" --source tool:Bats
  run bash "$SCRIPT" search "Login"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Login"* ]] || [[ "$output" == *"login"* ]]
}

@test "multiple saves accumulate in JSONL" {
  bash "$SCRIPT" save --type decision --title "Decision A" --content "A" --source tool:Bats
  bash "$SCRIPT" save --type decision --title "Decision B" --content "B" --source tool:Bats
  local count
  count=$(wc -l < "$TMPDIR_MS/output/.memory-store.jsonl")
  [[ "$count" -ge 2 ]]
}

@test "script has safety flags" {
  head -10 "$SCRIPT" | grep -q "set -.*pipefail"
}

@test "edge: save with empty title is handled" {
  run bash "$SCRIPT" save --type decision --title "" --content "X"
  [[ "$status" -ne 0 ]] || [[ "$output" == *"title"* ]]
}

@test "edge: suggest_topic_key function exists" {
  grep -q "suggest_topic_key()" "$SCRIPT"
}

@test "edge: redact_private function exists" {
  grep -q "redact_private()" "$SCRIPT"
}

@test "edge: hash_content function exists" {
  grep -q "hash_content()" "$SCRIPT"
}

# --- S03c: contenido del JSONL, upsert, procedencia y consolidación (SE-072, SE-352, SE-405) ---

sv() { bash "$SCRIPT" save --source tool:Bats "$@"; }
store() { echo "$TMPDIR_MS/output/.memory-store.jsonl"; }
field() { # field N CAMPO → valor del campo en la línea N del store
  sed -n "${1}p" "$(store)" | python3 -c "import json,sys; v=json.load(sys.stdin).get('$2'); print(v if not isinstance(v,(list,dict)) else json.dumps(v))"
}

@test "JSONL: cada línea es JSON válido con sector, tier y memory_type derivados del tipo" {
  sv --type decision --title "Uno" --content "c1" >/dev/null
  sv --type bug --title "Dos" --content "c2" >/dev/null
  sv --type pattern --title "Tres" --content "c3" >/dev/null
  [ "$(wc -l < "$(store)")" -eq 3 ]
  [ "$(field 1 sector)" = "semantic" ];   [ "$(field 1 importance_tier)" = "A" ]; [ "$(field 1 memory_type)" = "decision" ]
  [ "$(field 2 sector)" = "semantic" ];   [ "$(field 2 importance_tier)" = "B" ]; [ "$(field 2 memory_type)" = "error" ]
  [ "$(field 3 sector)" = "procedural" ]; [ "$(field 3 importance_tier)" = "B" ]; [ "$(field 3 memory_type)" = "learning" ]
}

@test "origin: tool:* → agent, user:explicit → owner, explícito se respeta" {
  sv --type decision --title "A" --content "a" >/dev/null
  bash "$SCRIPT" save --source user:explicit --type decision --title "B" --content "b" >/dev/null
  sv --type decision --title "C" --content "c" --origin system >/dev/null
  [ "$(field 1 origin)" = "agent" ]
  [ "$(field 2 origin)" = "owner" ]
  [ "$(field 3 origin)" = "system" ]
}

@test "origin: valor inválido → rechazo y nada se escribe" {
  run sv --type decision --title "X" --content "x" --origin root
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "inválido"
  [ ! -s "$(store)" ]
}

@test "origin: turno marcado como tainted degrada a untrusted aunque se pida owner" {
  export SESSION_ID="bats-s03c-$$"
  mkdir -p /tmp/savia-memory-taint
  date -u +%s > "/tmp/savia-memory-taint/$SESSION_ID"
  run sv --type decision --title "Tainted" --content "t" --origin owner
  unlink "/tmp/savia-memory-taint/$SESSION_ID"
  [ "$status" -eq 0 ]
  [ "$(field 1 origin)" = "untrusted" ]
}

@test "origin: marca de taint caducada (>30 min) no degrada" {
  export SESSION_ID="bats-s03c-old-$$"
  mkdir -p /tmp/savia-memory-taint
  echo $(( $(date -u +%s) - 4000 )) > "/tmp/savia-memory-taint/$SESSION_ID"
  run sv --type decision --title "Old taint" --content "t" --origin owner
  unlink "/tmp/savia-memory-taint/$SESSION_ID"
  [ "$(field 1 origin)" = "owner" ]
}

@test "privacidad: <private>…</private> se sustituye por [REDACTED] antes de guardar" {
  sv --type decision --title "Priv" --content "público <private>secreto-123</private> fin" >/dev/null
  grep -q "REDACTED" "$(store)"
  if grep -q "secreto-123" "$(store)"; then false; fi
}

@test "contenido: se trunca a 2000 caracteres (borde de tamaño)" {
  big=$(python3 -c "print('x' * 5000)")
  sv --type decision --title "Grande" --content "$big" >/dev/null
  [ "$(field 1 content | tr -d '\n' | wc -c)" -eq 2000 ]
}

@test "contenido: saltos de línea y tabuladores se escapan y la línea sigue siendo una" {
  sv --type decision --title "Multi" --content $'linea1\nlinea2\tTab' >/dev/null
  [ "$(wc -l < "$(store)")" -eq 1 ]
  [ "$(field 1 content)" = $'linea1\nlinea2\tTab' ]
}

@test "W/W/W/L: --what/--why/--where/--learned componen el contenido estructurado" {
  sv --type decision --title "WWWL" --what "A" --why "B" --where "C" --learned "D" >/dev/null
  [ "$(field 1 content)" = "What: A | Why: B | Where: C | Learned: D" ]
}

@test "falta contenido (ni --content ni --what) → error y exit ≠ 0" {
  run sv --type decision --title "Vacío"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "required"
}

@test "upsert: mismo topic reemplaza la línea, sube rev y guarda supersedes" {
  sv --type decision --title "T" --topic decision/mi-tema --content "version uno" >/dev/null
  sv --type decision --title "T" --topic decision/mi-tema --content "version dos" >/dev/null
  [ "$(wc -l < "$(store)")" -eq 1 ]
  [ "$(field 1 rev)" = "2" ]
  [ "$(field 1 content)" = "version dos" ]
  [ "$(field 1 supersedes)" = "version uno" ]
}

@test "upsert: contenido idéntico en el mismo topic sube rev pero no marca supersedes" {
  sv --type decision --title "T" --topic decision/igual --content "mismo" >/dev/null
  sv --type decision --title "T" --topic decision/igual --content "mismo" >/dev/null
  [ "$(field 1 rev)" = "2" ]
  if grep -q '"supersedes"' "$(store)"; then false; fi
}

@test "dedup: mismo contenido en topics distintos dentro de 15 min se omite" {
  sv --type decision --title "A" --topic decision/a --content "contenido repetido" >/dev/null
  run sv --type decision --title "B" --topic decision/b --content "contenido repetido"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Duplicado omitido"
  [ "$(wc -l < "$(store)")" -eq 1 ]
}

@test "dedup: tras 15 min el mismo contenido sí se guarda" {
  sv --type decision --title "A" --topic decision/a --content "contenido viejo" >/dev/null
  old=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)
  sed -i "s/\"ts\":\"[^\"]*\"/\"ts\":\"$old\"/" "$(store)"
  run sv --type decision --title "B" --topic decision/b --content "contenido viejo"
  echo "$output" | grep -q "Guardado"
  [ "$(wc -l < "$(store)")" -eq 2 ]
}

@test "episodio: TTL de 90 días por defecto y --pin lo elimina" {
  sv --type episode --title "Ep1" --content "e1" >/dev/null
  sv --type episode --title "Ep2" --content "e2" --pin >/dev/null
  exp=$(field 1 expires_at)
  [ "$exp" != "None" ]
  python3 - "$exp" <<'PY'
import datetime, sys
d = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
delta = (d - datetime.datetime.utcnow()).days
assert 88 <= delta <= 90, delta
PY
  [ "$(field 2 expires_at)" = "None" ]
}

@test "--expires N fija expires_at ≈ N días" {
  sv --type decision --title "Exp" --content "x" --expires 7 >/dev/null
  python3 - "$(field 1 expires_at)" <<'PY'
import datetime, sys
d = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
assert 5 <= (d - datetime.datetime.utcnow()).days <= 7
PY
}

@test "concepts: se normalizan a array JSON sin espacios" {
  sv --type decision --title "Cpt" --content "x" --concepts "uno, dos ,tres" >/dev/null
  [ "$(field 1 concepts)" = '["uno", "dos", "tres"]' ]
}

@test "entities: --entities se guarda como array (SE-076)" {
  sv --type episode --title "Ent" --content "x" --entities "a, b" >/dev/null
  [ "$(field 1 entities)" = '["a", "b"]' ]
}

@test "supersedes-key: la entrada antigua recibe valid_to y superseded_by" {
  sv --type decision --title "Vieja" --topic decision/vieja --content "v" >/dev/null
  sv --type decision --title "Nueva" --topic decision/nueva --content "n" --supersedes decision/vieja >/dev/null
  [ "$(field 1 superseded_by)" = "decision/nueva" ]
  [ "$(field 1 valid_to)" != "None" ]
  [ "$(field 2 supersedes_key)" = "decision/vieja" ]
}

@test "supersedes-key: '|' y '&' en la clave se tratan como literales" {
  sv --type decision --title "A" --topic 'decision/a|b' --content "x" >/dev/null
  sv --type decision --title "B" --topic 'decision/a' --content "y" >/dev/null
  sv --type decision --title "C" --topic 'decision/c&a' --content "z" --supersedes 'decision/a|b' >/dev/null
  # solo la entrada 1 (clave con '|') queda reemplazada; la 2 ('decision/a') no
  [ "$(field 1 superseded_by)" = 'decision/c&a' ]
  [ "$(field 2 superseded_by)" = "None" ]
}

@test "suggest-topic: slug en minúsculas, sin símbolos y recortado a 40 caracteres" {
  run bash "$SCRIPT" suggest-topic decision "Usar Cache!! para API/v2 con un título larguísimo que excede cuarenta caracteres"
  [ "$status" -eq 0 ]
  slug="${output#decision/}"
  [ "${#slug}" -ge 30 ]
  [[ "$output" == decision/usar-cache-para-apiv2-con-un-t* ]]
  [ "${#slug}" -le 40 ]
  [[ "$slug" =~ ^[a-z0-9-]+$ ]]
}

@test "suggest-topic: tipo no mapeado usa el propio tipo como prefijo" {
  run bash "$SCRIPT" suggest-topic rareza "Hola Mundo"
  [ "$output" = "rareza/hola-mundo" ]
}

@test "session-summary: sin --accomplished falla; con él guarda topic session/<fecha>" {
  run bash "$SCRIPT" session-summary --goal g
  [ "$status" -ne 0 ]
  run env SAVIA_VERIFIED_MEMORY_DISABLED=true bash "$SCRIPT" session-summary --goal g --accomplished hecho --files f.sh
  [ "$status" -eq 0 ]
  [ "$(field 1 topic_key)" = "session/$(date +%Y-%m-%d)" ]
  [ "$(field 1 importance_tier)" = "C" ]
  field 1 content | grep -q "Goal: g | Accomplished: hecho | Files: f.sh"
}

@test "audit-origins: cuenta por origen con porcentajes y trata la falta de origen como untrusted" {
  sv --type decision --title "A" --content "a" >/dev/null
  sv --type decision --title "B" --content "b" --origin owner >/dev/null
  printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","type":"x","title":"viejo","topic_key":"x/viejo","hash":"h"}' >> "$(store)"
  run bash "$SCRIPT" audit-origins
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Total: 3 entradas"
  echo "$output" | grep -q "owner:      1 (33.3%)"
  echo "$output" | grep -q "agent:      1 (33.3%)"
  echo "$output" | grep -q "untrusted:  1 (33.3%)"
  echo "$output" | grep -q "sin src:    1"
}

@test "consolidate --dry-run informa exclusiones sin tocar el store" {
  sv --type decision --title "A" --content "a" --origin owner >/dev/null
  sv --type decision --title "B" --content "b" --origin untrusted >/dev/null
  before=$(sha256sum "$(store)" | cut -d' ' -f1)
  run bash "$SCRIPT" consolidate --dry-run
  echo "$output" | grep -q "excluidas 1 entradas untrusted/system, mantenidas 1"
  [ "$(sha256sum "$(store)" | cut -d' ' -f1)" = "$before" ]
}

@test "consolidate: elimina untrusted/system y conserva owner/agent" {
  sv --type decision --title "A" --content "a" --origin owner >/dev/null
  sv --type decision --title "B" --content "b" --origin untrusted >/dev/null
  sv --type decision --title "C" --content "c" --origin system >/dev/null
  sv --type decision --title "D" --content "d" >/dev/null
  run bash "$SCRIPT" consolidate
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$(store)")" -eq 2 ]
  if grep -q '"origin":"untrusted"\|"origin":"system"' "$(store)"; then false; fi
}

@test "timeline: ventana alrededor del ancla marca la entrada con ▶" {
  for i in 1 2 3 4 5; do
    sv --type decision --title "E$i" --topic "decision/e$i" --content "c$i" >/dev/null
    sed -i "${i}s/\"ts\":\"[^\"]*\"/\"ts\":\"2026-01-0${i}T10:00:00Z\"/" "$(store)"
  done
  run bash "$SCRIPT" timeline decision/e3 --window 1
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  echo "${lines[1]}" | grep -q "^▶ 2026-01-03T10:00  \[decision\] E3"
  echo "$output" | grep -q "E2"
  if echo "$output" | grep -q "E1\|E5"; then false; fi
}

@test "timeline: errores — ancla inexistente (1), sin ancla o ventana inválida (2), store vacío (1)" {
  run bash "$SCRIPT" timeline x
  [ "$status" -eq 1 ]
  sv --type decision --title "E" --topic decision/e --content c >/dev/null
  run bash "$SCRIPT" timeline decision/no-esta
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" timeline
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" timeline decision/e --window abc
  [ "$status" -eq 2 ]
}

@test "índice: SAVIA_MEMORY_INDEX_FILE se actualiza en sitio (reemplazo, no duplicado)" {
  idx="$TMPDIR_MS/MEMORY.md"
  printf '# Índice\n<!-- ENTRIES_START -->\n<!-- ENTRIES_END -->\n' > "$idx"
  export SAVIA_MEMORY_INDEX_FILE="$idx"
  sv --type decision --title "Primero" --topic decision/uno --content "a" >/dev/null
  sv --type decision --title "Cambiado" --topic decision/uno --content "b" >/dev/null
  sv --type decision --title "Otro" --topic decision/dos --content "c" >/dev/null
  [ "$(grep -c '^- ' "$idx")" -eq 2 ]
  grep -q '^- decision: Otro \[decision/dos\] · src:agent$' "$idx"
  grep -q '^- decision: Cambiado \[decision/uno\]' "$idx"
  if grep -q "Primero" "$idx"; then false; fi
  # lo más nuevo arriba
  [ "$(grep -n '^- ' "$idx" | head -1 | cut -d: -f2-)" = "- decision: Otro [decision/dos] · src:agent" ]
}

@test "índice: el tope blando recorta las entradas más antiguas" {
  idx="$TMPDIR_MS/MEMORY.md"
  printf '<!-- ENTRIES_START -->\n<!-- ENTRIES_END -->\n' > "$idx"
  export SAVIA_MEMORY_INDEX_FILE="$idx" MEMORY_INDEX_SOFT_CAP=3
  for i in 1 2 3 4 5; do sv --type decision --title "N$i" --topic "decision/n$i" --content "c$i" >/dev/null; done
  [ "$(grep -c '^- ' "$idx")" -eq 3 ]
  grep -q "N5" "$idx"; grep -q "N3" "$idx"
  if grep -q "N1" "$idx"; then false; fi
}

@test "índice: sin fichero de índice la grabación sigue funcionando (exit 0)" {
  export SAVIA_MEMORY_INDEX_FILE="$TMPDIR_MS/no-existe.md"
  run sv --type decision --title "Sin idx" --topic decision/x --content "x"
  [ "$status" -eq 0 ]
  [ ! -e "$SAVIA_MEMORY_INDEX_FILE" ]
}

@test "entity list/find: lista por proyecto y busca por nombre" {
  sv --type entity --title "Alice" --content "dev backend" --concepts "persona" --project alfa >/dev/null
  sv --type entity --title "Bob" --content "qa" --concepts "persona" --project beta >/dev/null
  run bash "$SCRIPT" entity list --project alfa
  echo "$output" | grep -q "Alice (persona) — proyecto: alfa"
  if echo "$output" | grep -q "Bob"; then false; fi
  run bash "$SCRIPT" entity find bob
  echo "$output" | grep -q "^Bob — "
  run bash "$SCRIPT" entity find
  echo "$output" | grep -q "Uso: entity find"
}

@test "HOME vacío → exit 1 con mensaje (no escribe en /tmp)" {
  run env -u HOME bash "$SCRIPT" stats
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "HOME no definido"
}

# Rutas Windows y comillas: cada línea del JSONL debe seguir siendo JSON válido.
# La ruta va por argv (MSYS la traduce para el python nativo de Windows).
jsonl_valid() {
  python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]' "$1"
}

@test "save con ruta Windows y comillas escribe JSON válido" {
  run bash "$SCRIPT" save --type discovery --title 'ruta C:\Users\x "citada"' \
    --content 'ver C:\Users\x\proyecto y "comillas"' --source 'file:C:\a.sh:1' --entities 'a"b,C:\x'
  [[ "$status" -eq 0 ]]
  run jsonl_valid "$TMPDIR_MS/output/.memory-store.jsonl"
  [[ "$status" -eq 0 ]]
  grep -qF '"title":"ruta C:\Users\x \"citada\""' "$TMPDIR_MS/output/.memory-store.jsonl"
}

@test "upsert sobre contenido con comillas escapadas mantiene supersedes válido" {
  bash "$SCRIPT" save --type discovery --title 'mismo tema' --content 'v1 "citada" C:\a' --source user:explicit
  bash "$SCRIPT" save --type discovery --title 'mismo tema' --content 'v2 distinta' --source user:explicit
  run jsonl_valid "$TMPDIR_MS/output/.memory-store.jsonl"
  [[ "$status" -eq 0 ]]
  grep -qF '"supersedes":"v1 \"citada\" C:\a"' "$TMPDIR_MS/output/.memory-store.jsonl"
}
