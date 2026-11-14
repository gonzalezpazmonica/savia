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

@test "graph con --min-origin owner solo devuelve owner" {
  run bash "$S" search zebra --mode graph --min-origin owner
  only_owner
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

@test "fail-closed: sin el módulo de filtro, hybrid con --min-origin no devuelve untrusted" {
  mv "$T/scripts/memory-origin.py" "$T/scripts/memory-origin.py.off"
  run bash "$S" search zebra --mode hybrid --min-origin owner
  [[ "$output" == *"zebra-owner"* ]]
  local x; for x in agent untrusted system legacy; do [[ "$output" != *"zebra-$x"* ]]; done
}
