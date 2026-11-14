#!/usr/bin/env bats
# Fix SE-352: --min-origin debe aplicarse en TODAS las rutas de memory-store.sh search
# (hybrid, vector, graph, grep, auto), no solo en el fallback grep.
# Almacén sintético con una entrada de cada origen; scripts copiados a un tmp para poder
# sustituir memory-vector.py por un stub que "ve" las cinco entradas (índice disponible).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T=$(mktemp -d); export PROJECT_ROOT="$T"
  export SAVIA_TEST_MODE=true SAVIA_EMBED_AUTOSTART=false
  export SAVIA_MEMORY_PYTHON="$(command -v python3)"
  mkdir -p "$T/output" "$T/scripts"
  cp "$REPO_ROOT"/scripts/memory-store.sh "$REPO_ROOT"/scripts/memory-search.sh \
     "$REPO_ROOT"/scripts/memory-save.sh "$REPO_ROOT"/scripts/memory-hybrid.py "$REPO_ROOT"/scripts/memory-origin.py \
     "$REPO_ROOT"/scripts/memory-graph.py "$REPO_ROOT"/scripts/memory-domains.py "$T/scripts/"
  STORE="$T/output/.memory-store.jsonl"
  for o in owner agent untrusted system; do
    echo "{\"ts\":\"2026-11-01T00:00:00Z\",\"type\":\"decision\",\"title\":\"zebra-$o\",\"topic_key\":\"t/$o\",\"origin\":\"$o\",\"content\":\"zebra\",\"rev\":1}" >> "$STORE"
  done
  # entrada antigua sin campo origin: cuenta como untrusted
  echo '{"ts":"2026-11-01T00:00:00Z","type":"decision","title":"zebra-legacy","topic_key":"t/legacy","content":"zebra","rev":1}' >> "$STORE"
  S="$T/scripts/memory-store.sh"
}
teardown() { rm -rf "$T"; }

# stub del índice vectorial: devuelve las cinco entradas con score alto
enable_vector_stub() {
  cat > "$T/scripts/memory-vector.py" <<'PY'
import json
r = [{"title": "zebra-%s" % n, "topic_key": "t/%s" % n, "type": "decision", "ts": "2026-11-01T00:00:00Z", "score": 0.9}
     for n in ("owner", "agent", "untrusted", "system", "legacy")]
print(json.dumps({"results": r, "fallback": False}))
PY
  touch "$T/output/.memory-store-index.idx"
}

# `|| return 1` explícito: en bash 3.2 un [[ ]] fallido que no es el último no falla el test.
only_owner() {
  [[ "$output" == *"zebra-owner"* ]] || return 1
  local x; for x in agent untrusted system legacy; do [[ "$output" != *"zebra-$x"* ]] || return 1; done
}

@test "hybrid con --min-origin owner solo devuelve owner" {
  run bash "$S" search zebra --mode hybrid --min-origin owner
  [ "$status" -eq 0 ]
  only_owner
}

@test "auto con --min-origin agent devuelve owner+agent, no untrusted/system/legacy" {
  run bash "$S" search zebra --mode auto --min-origin agent
  [[ "$output" == *"zebra-owner"* && "$output" == *"zebra-agent"* ]]
  local x; for x in untrusted system legacy; do [[ "$output" != *"zebra-$x"* ]] || return 1; done
}

@test "hybrid con índice vectorial: el stub devuelve todo y el filtro lo recorta" {
  enable_vector_stub
  run bash "$S" search zebra --mode hybrid --min-origin owner
  only_owner
}

@test "vector con --min-origin owner filtra la ruta vectorial heredada" {
  enable_vector_stub
  run bash "$S" search zebra --mode vector --min-origin owner
  [ "$status" -eq 0 ]
  only_owner
}

@test "auto con índice vectorial y --min-origin owner solo devuelve owner" {
  enable_vector_stub
  run bash "$S" search zebra --mode auto --min-origin owner
  only_owner
}

@test "vector sin índice disponible: error y no devuelve resultados" {
  run bash "$S" search zebra --mode vector --min-origin owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"Vector index not available"* ]]
  [[ "$output" != *"zebra-untrusted"* ]]
}

@test "graph (grep de bash) con --min-origin owner solo devuelve owner" {
  run bash "$S" search zebra --mode graph --min-origin owner
  only_owner
}

# stub del grafo: líneas «- título», el contrato que parsea _run_graph. Ojo: el
# memory-graph.py real imprime JSON (indent=2) que _run_graph no parsea (previo a esta PR);
# estos tests cubren el filtro sobre resultados de grafo, no el parseo del grafo real.
enable_graph_stub() {
  cat > "$T/scripts/memory-graph.py" <<'PY'
for n in ("owner", "agent", "untrusted", "system", "legacy"):
    print("- zebra-%s" % n)
PY
}

@test "resultados de grafo (stub de líneas) en memory-hybrid: --min-origin owner descarta untrusted" {
  enable_graph_stub
  run python3 "$T/scripts/memory-hybrid.py" search zebra --store "$STORE" --mode graph --min-origin owner
  [ "$status" -eq 0 ]
  [[ "$output" == *"zebra-owner"* ]]
  local x; for x in agent untrusted system legacy; do [[ "$output" != *"zebra-$x"* ]] || return 1; done
}

@test "grafo sin --min-origin devuelve todos (el filtro es lo que recorta)" {
  enable_graph_stub
  run python3 "$T/scripts/memory-hybrid.py" search zebra --store "$STORE" --mode graph
  local x; for x in owner agent untrusted system legacy; do [[ "$output" == *"zebra-$x"* ]] || return 1; done
}

@test "grafo con --min-origin untrusted: pasan untrusted y legacy, no system" {
  enable_graph_stub
  run python3 "$T/scripts/memory-hybrid.py" search zebra --store "$STORE" --mode graph --min-origin untrusted
  [[ "$output" == *"zebra-untrusted"* && "$output" == *"zebra-legacy"* && "$output" == *"zebra-owner"* ]]
  [[ "$output" != *"zebra-system"* ]]
}

@test "título ambiguo: untrusted y owner posterior con el mismo título no se promueve a owner" {
  echo '{"ts":"2026-11-02T00:00:00Z","type":"decision","title":"zebra-untrusted","topic_key":"t/otro","origin":"owner","content":"zebra","rev":1}' >> "$STORE"
  run bash -c "echo '{\"results\":[{\"title\":\"zebra-untrusted\",\"topic_key\":\"\"}]}' | python3 '$T/scripts/memory-origin.py' filter --store '$STORE' --min-origin owner"
  [[ "$output" == *'"results": []'* ]]
}

@test "entrada superseded (valid_to) no cuenta para resolver el origen" {
  echo '{"ts":"2026-11-02T00:00:00Z","type":"decision","title":"zebra-viejo","topic_key":"t/v","origin":"owner","valid_to":"2026-11-03T00:00:00Z","content":"zebra","rev":1}' >> "$STORE"
  run bash -c "echo '{\"results\":[{\"title\":\"zebra-viejo\",\"topic_key\":\"t/v\"}]}' | python3 '$T/scripts/memory-origin.py' filter --store '$STORE' --min-origin owner"
  [[ "$output" == *'"results": []'* ]]
}

@test "--min-origin vacío falla (no desactiva el filtro)" {
  run bash "$S" search zebra --mode hybrid --min-origin ""
  [ "$status" -eq 1 ]
  [[ "$output" != *"zebra-untrusted"* ]]
}

@test "--min-origin sin valor al final falla sin bucle infinito" {
  run timeout 10 bash "$S" search zebra --min-origin
  [ "$status" -eq 1 ]
  [[ "$output" == *"requiere un valor"* ]]
}

@test "vector con índice y filtro que deja 0 resultados: no dice índice ausente" {
  enable_vector_stub
  run bash -c "sed -i 's/\"origin\":\"owner\"/\"origin\":\"agent\"/' '$STORE'; bash '$S' search zebra --mode vector --min-origin owner"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No se encontraron resultados"* ]]
  [[ "$output" != *"Vector index not available"* ]]
}

@test "grep con --min-origin owner solo devuelve owner" {
  run bash "$S" search zebra --mode grep --min-origin owner
  only_owner
}

@test "negativo: sin --min-origin no se filtra en ningún modo" {
  enable_vector_stub
  local m x
  for m in hybrid auto vector grep; do
    run bash "$S" search zebra --mode "$m"
    for x in owner agent untrusted legacy; do [[ "$output" == *"zebra-$x"* ]] || return 1; done
  done
}

@test "límite: --min-origin untrusted deja pasar untrusted y legacy, no system" {
  run bash "$S" search zebra --mode hybrid --min-origin untrusted
  [[ "$output" == *"zebra-untrusted"* && "$output" == *"zebra-legacy"* ]]
  [[ "$output" != *"zebra-system"* ]]
}

@test "fail-closed: valor inválido de --min-origin falla y no devuelve resultados" {
  run bash "$S" search zebra --mode hybrid --min-origin root
  [ "$status" -eq 1 ]
  [[ "$output" == *"inválido"* ]]
  [[ "$output" != *"zebra-untrusted"* ]]
}

@test "filtro hybrid: resultado no resoluble contra el almacén cuenta como untrusted" {
  run bash -c "echo '{\"results\":[{\"title\":\"fantasma\",\"topic_key\":\"x/y\"}]}' | python3 '$T/scripts/memory-origin.py' filter --store '$STORE' --min-origin agent"
  [[ "$output" == *'"results": []'* ]]
}

@test "fail-closed: sin el módulo de filtro, memory-hybrid.py falla y no imprime resultados" {
  mv "$T/scripts/memory-origin.py" "$T/scripts/memory-origin.py.off"
  run python3 "$T/scripts/memory-hybrid.py" search zebra --store "$STORE" --mode naive --min-origin owner
  [ "$status" -ne 0 ]
  [[ "$output" != *"zebra-"* ]]
}

@test "fail-closed: sin el módulo de filtro, la ruta completa solo devuelve owner (grep nativo)" {
  mv "$T/scripts/memory-origin.py" "$T/scripts/memory-origin.py.off"
  run bash "$S" search zebra --mode hybrid --min-origin owner
  [ "$status" -eq 0 ]
  only_owner
}

# --- Correcciones tras revisión (P1 seguridad y P2) ---

# stub vectorial con el contrato actual: cada resultado lleva origin y valid_to de su línea
enable_vector_stub_superseded() {
  echo '{"ts":"2026-11-01T00:00:00Z","type":"decision","title":"zebra-viejo-untrusted","topic_key":"t/k","origin":"untrusted","valid_to":"2026-11-02T00:00:00Z","content":"zebra","rev":1}' >> "$STORE"
  echo '{"ts":"2026-11-02T00:00:00Z","type":"decision","title":"zebra-nuevo-owner","topic_key":"t/k","origin":"owner","content":"zebra","rev":2}' >> "$STORE"
  cat > "$T/scripts/memory-vector.py" <<'PY'
import json
r = [{"title": "zebra-viejo-untrusted", "topic_key": "t/k", "type": "decision", "ts": "2026-11-01T00:00:00Z",
      "score": 0.95, "origin": "untrusted", "valid_to": "2026-11-02T00:00:00Z"},
     {"title": "zebra-nuevo-owner", "topic_key": "t/k", "type": "decision", "ts": "2026-11-02T00:00:00Z",
      "score": 0.9, "origin": "owner", "valid_to": None}]
print(json.dumps({"results": r, "fallback": False}))
PY
  touch "$T/output/.memory-store-index.idx"
}

@test "P1: vector devuelve revisión untrusted superseded con la topic_key de una owner vigente: no pasa" {
  enable_vector_stub_superseded
  run bash "$S" search zebra --mode vector --min-origin owner
  [ "$status" -eq 0 ]
  [[ "$output" == *"zebra-nuevo-owner"* ]]
  [[ "$output" != *"zebra-viejo-untrusted"* ]]
}

@test "P1: mismo caso por memory-hybrid.py (ruta hybrid/auto)" {
  enable_vector_stub_superseded
  run python3 "$T/scripts/memory-hybrid.py" search zebra --store "$STORE" --mode vector --min-origin owner
  [ "$status" -eq 0 ]
  [[ "$output" == *"zebra-nuevo-owner"* ]]
  [[ "$output" != *"zebra-viejo-untrusted"* ]]
}

@test "P1: memory-vector.py emite el origin y valid_to de la propia línea (untrusted si falta)" {
  cp "$REPO_ROOT/scripts/memory-vector.py" "$T/scripts/"
  run python3 -c "
import importlib.util, json
sp = importlib.util.spec_from_file_location('mv', '$T/scripts/memory-vector.py')
m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
a = m._result(0, {'title': 'x', 'origin': 'untrusted', 'valid_to': '2026-11-02'}, 0.9)
b = m._result(1, {'title': 'y'}, 0.8)
print(json.dumps([a['origin'], a['valid_to'], b['origin'], b['valid_to']]))"
  [ "$status" -eq 0 ]
  [[ "$output" == *'["untrusted", "2026-11-02", "untrusted", null]'* ]]
}

@test "origen propio del resultado manda: una untrusted con el mismo título no oculta a la owner" {
  echo '{"ts":"2026-11-02T00:00:00Z","type":"decision","title":"zebra-owner","topic_key":"t/spam","origin":"untrusted","content":"zebra","rev":1}' >> "$STORE"
  run bash -c "echo '{\"results\":[{\"title\":\"zebra-owner\",\"topic_key\":\"t/owner\",\"origin\":\"owner\"}]}' | python3 '$T/scripts/memory-origin.py' filter --store '$STORE' --min-origin owner"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"zebra-owner"'* ]]
}

@test "grep de memory-hybrid filtra antes del top: 12 untrusted recientes no tapan la owner antigua" {
  local i; for i in $(seq 1 12); do
    echo "{\"ts\":\"2026-11-05T00:00:00Z\",\"type\":\"decision\",\"title\":\"zebra-spam-$i\",\"topic_key\":\"t/s$i\",\"origin\":\"untrusted\",\"content\":\"zebra\",\"rev\":1}" >> "$STORE"
  done
  run python3 "$T/scripts/memory-hybrid.py" search zebra --store "$STORE" --mode naive --top 10 --min-origin owner
  [ "$status" -eq 0 ]
  [[ "$output" == *"zebra-owner"* ]]
  [[ "$output" != *"zebra-spam"* ]]
}

@test "grep de bash: --min-origin system deja pasar system (coherente con Python)" {
  run bash "$S" search zebra --mode grep --min-origin system
  [[ "$output" == *"zebra-system"* && "$output" == *"zebra-owner"* ]]
}

@test "vector: si el filtro falla, error y exit 1 (no «0 resultados»)" {
  enable_vector_stub
  printf 'import sys\nsys.exit(3)\n' > "$T/scripts/memory-origin.py"
  run bash "$S" search zebra --mode vector --min-origin owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se pudo aplicar --min-origin"* ]]
  [[ "$output" != *"zebra-"* ]]
}

@test "vector: índice que responde fallback con --min-origin sigue siendo «índice no disponible»" {
  printf 'import json\nprint(json.dumps({"results": [], "fallback": True}))\n' > "$T/scripts/memory-vector.py"
  touch "$T/output/.memory-store-index.idx"
  run bash "$S" search zebra --mode vector --min-origin owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"Vector index not available"* ]]
}
