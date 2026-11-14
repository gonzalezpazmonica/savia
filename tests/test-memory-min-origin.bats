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

only_owner() {
  [[ "$output" == *"zebra-owner"* ]]
  local x; for x in agent untrusted system legacy; do [[ "$output" != *"zebra-$x"* ]]; done
}

@test "hybrid con --min-origin owner solo devuelve owner" {
  run bash "$S" search zebra --mode hybrid --min-origin owner
  [ "$status" -eq 0 ]
  only_owner
}

@test "auto con --min-origin agent devuelve owner+agent, no untrusted/system/legacy" {
  run bash "$S" search zebra --mode auto --min-origin agent
  [[ "$output" == *"zebra-owner"* && "$output" == *"zebra-agent"* ]]
  local x; for x in untrusted system legacy; do [[ "$output" != *"zebra-$x"* ]]; done
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

# stub del grafo: líneas de texto libre con los títulos de las cinco entradas
enable_graph_stub() {
  cat > "$T/scripts/memory-graph.py" <<'PY'
for n in ("owner", "agent", "untrusted", "system", "legacy"):
    print("- zebra-%s" % n)
PY
}

@test "grafo real de memory-hybrid: --min-origin owner descarta títulos untrusted" {
  enable_graph_stub
  run python3 "$T/scripts/memory-hybrid.py" search zebra --store "$STORE" --mode graph --min-origin owner
  [ "$status" -eq 0 ]
  [[ "$output" == *"zebra-owner"* ]]
  local x; for x in agent untrusted system legacy; do [[ "$output" != *"zebra-$x"* ]]; done
}

@test "grafo sin --min-origin devuelve todos (el filtro es lo que recorta)" {
  enable_graph_stub
  run python3 "$T/scripts/memory-hybrid.py" search zebra --store "$STORE" --mode graph
  local x; for x in owner agent untrusted system legacy; do [[ "$output" == *"zebra-$x"* ]]; done
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
    for x in owner agent untrusted legacy; do [[ "$output" == *"zebra-$x"* ]]; done
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
