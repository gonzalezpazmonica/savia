#!/usr/bin/env bats
# BATS tests for hybrid-search.py (SE-342 S6 / Labs L22)
# Ref: SE-342 S6, hypothesis l22-vector-store-hybrid.md, CRIT-001
# Comportamiento: valores BM25, IDF, fusión alpha, ruta densa contra un
# servidor de embeddings falso local, códigos de salida y orden determinista.

SCRIPT="scripts/hybrid-search.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  IDXDIR="$(mktemp -d -t hs.XXXXXX)"
  IDX="$IDXDIR/index.json"
  mkdir -p "$IDXDIR/notes"
  cat > "$IDXDIR/notes/riego.md" <<'EOF'
---
title: Riego de precisión
---
El riego por goteo optimiza el agua del cultivo de tomate.
EOF
  cat > "$IDXDIR/notes/plagas.md" <<'EOF'
---
title: Plagas
---
Detección foliar de plagas con visión computacional en cultivos.
EOF
  cat > "$IDXDIR/notes/energia.md" <<'EOF'
---
title: Energía
---
Comunidades energéticas rurales y balance de red fotovoltaica.
EOF
  # embeddings inalcanzables por defecto -> ruta BM25 pura
  export SAVIA_EMBED_URL="http://127.0.0.1:1/nope"
  SRV_PID=""
}

teardown() {
  [[ -n "$SRV_PID" ]] && kill "$SRV_PID" 2>/dev/null
  rm -rf "$IDXDIR"
  cd /
}

# Servidor de embeddings falso: vector [1,0] si el texto contiene "riego", si no [0,1].
start_embed() {
  cat > "$IDXDIR/srv.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        t = json.loads(self.rfile.read(n))["text"].lower()
        v = [1.0, 0.0] if "riego" in t else [0.0, 1.0]
        b = json.dumps({"embedding": v}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers()
        self.wfile.write(b)
    def log_message(self, *a): pass
s = HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port))
s.serve_forever()
PY
  python3 "$IDXDIR/srv.py" "$IDXDIR/port" &
  SRV_PID=$!
  for _ in $(seq 1 50); do [[ -s "$IDXDIR/port" ]] && break; sleep 0.1; done
  export SAVIA_EMBED_URL="http://127.0.0.1:$(cat "$IDXDIR/port")/embed"
}

build() { python3 "$SCRIPT" index --dir "$IDXDIR/notes" --out "$IDX" >/dev/null; }

pyexpr() { python3 - "$@" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("hs", "scripts/hybrid-search.py")
hs = importlib.util.module_from_spec(spec); spec.loader.exec_module(hs)
print(eval(sys.argv[1]))
PY
}

@test "script exists and executable" {
  [[ -x "$SCRIPT" ]]
}

@test "py_compile OK" {
  run python3 -m py_compile "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "version flag prints the version and exits 0" {
  run python3 "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "hybrid-search.py 0.1.0"* ]]
}

@test "no subcommand is a usage error with exit 2" {
  run python3 "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "index builds over notes dir" {
  run python3 "$SCRIPT" index --dir "$IDXDIR/notes" --out "$IDX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"indexed 3 notes -> $IDX"* ]]
  [[ -f "$IDX" ]]
}

@test "index stores doc_count, avg_dl, relative paths and sorted idf" {
  build
  run python3 - "$IDX" <<'PY'
import json, sys
i = json.load(open(sys.argv[1]))
assert i["doc_count"] == 3
assert [n["path"] for n in i["notes"]] == ["energia.md", "plagas.md", "riego.md"], i["notes"]
assert i["avg_dl"] > 0
assert list(i["idf"]) == sorted(i["idf"])
assert "riego" in i["idf"] and "de" not in i["idf"]   # tokens < 3 chars fuera
PY
  [ "$status" -eq 0 ]
}

@test "index idf equals log((N-df+0.5)/(df+0.5)+1) from real document frequencies" {
  build
  run python3 - "$IDX" <<'PY'
import json, math, sys
idf = json.load(open(sys.argv[1]))["idf"]
assert abs(idf["riego"] - math.log((3 - 1 + 0.5) / (1 + 0.5) + 1)) < 1e-9, idf["riego"]
PY
  [ "$status" -eq 0 ]
}

@test "index recurses into subdirectories and ignores non-md files" {
  mkdir -p "$IDXDIR/notes/sub"
  echo "nota anidada sobre riego" > "$IDXDIR/notes/sub/anidada.md"
  echo "no soy markdown" > "$IDXDIR/notes/leeme.txt"
  run python3 "$SCRIPT" index --dir "$IDXDIR/notes" --out "$IDX"
  [[ "$output" == *"indexed 4 notes"* ]]
  grep -q '"sub/anidada.md"' "$IDX"
  ! grep -q 'leeme.txt' "$IDX"
}

@test "index on a missing directory exits 2" {
  run python3 "$SCRIPT" index --dir "$IDXDIR/no-existe" --out "$IDX"
  [ "$status" -eq 2 ]
  [[ "$output" == *"dir not found"* ]]
  [[ ! -f "$IDX" ]]
}

@test "index on a directory without notes exits 1 and writes nothing" {
  mkdir "$IDXDIR/vacio"
  run python3 "$SCRIPT" index --dir "$IDXDIR/vacio" --out "$IDX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no .md notes found"* ]]
  [[ ! -f "$IDX" ]]
}

@test "index without --out writes hybrid-index.json in the current directory" {
  cd "$IDXDIR"
  run python3 "$BATS_TEST_DIRNAME/../$SCRIPT" index --dir "$IDXDIR/notes"
  [ "$status" -eq 0 ]
  [[ -f "$IDXDIR/hybrid-index.json" ]]
}

@test "bm25 of a term absent from the document is exactly 0" {
  run pyexpr 'hs.bm25_score(["zzz"], "riego agua", {"zzz": 2.0})'
  [ "$output" = "0.0" ]
}

@test "bm25 matches the closed-form value for a single known term" {
  # tf=1, dl=3 (tokens: riego agua cultivo), avg_dl=3 -> den = 1 + 1.5 = 2.5 ; num = 2.5 ; score = idf
  run pyexpr 'round(hs.bm25_score(["riego"], "riego agua cultivo", {"riego": 1.7}, avg_dl=3.0), 6)'
  [ "$output" = "1.7" ]
}

@test "bm25 saturates term frequency and penalises longer documents" {
  run pyexpr 'hs.bm25_score(["riego"], "riego riego riego", {"riego": 1.0}, avg_dl=3.0) > hs.bm25_score(["riego"], "riego agua cultivo", {"riego": 1.0}, avg_dl=3.0)'
  [ "$output" = "True" ]
  run pyexpr 'hs.bm25_score(["riego"], "riego " + "relleno " * 30, {"riego": 1.0}, avg_dl=5.0) < hs.bm25_score(["riego"], "riego agua", {"riego": 1.0}, avg_dl=5.0)'
  [ "$output" = "True" ]
}

@test "bm25 uses the default idf log(1.5) for terms missing from the idf map" {
  run pyexpr 'round(hs.bm25_score(["riego"], "riego agua cultivo", {}, avg_dl=3.0) - __import__("math").log(1.5), 9)'
  [ "$output" = "0.0" ]
}

@test "idf is higher for rarer terms" {
  run pyexpr 'hs._idf("x", 10, 1) > hs._idf("x", 10, 9)'
  [ "$output" = "True" ]
}

@test "tokenizer lowercases and drops tokens shorter than 3 characters" {
  run pyexpr 'hs._tokenize("El RIEGO de AB x1 ok_go ab-cd")'
  [ "$output" = "['riego', 'ok_go', 'ab-cd']" ]
}

@test "cosine of identical vectors is 1, orthogonal is 0, zero vector is 0" {
  run pyexpr '[round(hs._cosine([1,2],[1,2]),6), hs._cosine([1,0],[0,1]), hs._cosine([0,0],[1,1])]'
  [ "$output" = "[1.0, 0.0, 0.0]" ]
}

@test "query returns riego note for 'riego agua tomate'" {
  build
  run python3 "$SCRIPT" query "riego agua tomate" --index "$IDX" --top 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"riego.md"* ]]
}

@test "query ranks best match first and orders by fused score descending" {
  build
  run python3 "$SCRIPT" query "plagas cultivos vision" --index "$IDX" --top 3
  [ "$status" -eq 0 ]
  first="$(echo "$output" | head -1 | cut -f1)"
  [[ "$first" == "plagas.md" ]]
  scores="$(echo "$output" | sed -E 's/.*fused=([0-9.]+).*/\1/')"
  [ "$scores" = "$(echo "$scores" | sort -rn)" ]
}

@test "query output has path, fused, bm25 and cos columns with rounded numbers" {
  build
  run python3 "$SCRIPT" query "riego" --index "$IDX" --top 1
  [[ "$output" =~ ^riego\.md$'\t'fused=[0-9.]+$'\t'bm25=[0-9.]+$'\t'cos=0\.0$ ]]
}

@test "query --top limits the number of rows" {
  build
  run python3 "$SCRIPT" query "riego plagas energia cultivo" --index "$IDX" --top 2
  [ "${#lines[@]}" -eq 2 ]
  run python3 "$SCRIPT" query "riego plagas energia cultivo" --index "$IDX"
  [ "${#lines[@]}" -eq 3 ]
}

@test "query --top 0 prints 'no results' and exits 1" {
  build
  run python3 "$SCRIPT" query "riego" --index "$IDX" --top 0
  [ "$status" -eq 1 ]
  [ "$output" = "no results" ]
}

@test "query is deterministic across runs" {
  build
  a="$(python3 "$SCRIPT" query "agua cultivo red" --index "$IDX")"
  b="$(python3 "$SCRIPT" query "agua cultivo red" --index "$IDX")"
  [ "$a" = "$b" ]
}

@test "query without index returns error" {
  run python3 "$SCRIPT" query "x" --index "$IDXDIR/missing.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"index not found"* ]]
}

@test "query made only of short tokens is an empty query with exit 1" {
  build
  run python3 "$SCRIPT" query "a el de" --index "$IDX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty query"* ]]
}

@test "query with unreachable embeddings degrades to BM25 with cos=0 on every row" {
  build
  run python3 "$SCRIPT" query "energia fotovoltaica red" --index "$IDX" --top 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"energia.md"* ]]
  [ "$(echo "$output" | grep -c 'cos=0.0$')" -eq 3 ]
}

@test "query with no matching term still lists every note with fused 0.0" {
  build
  run python3 "$SCRIPT" query "zzzzzz" --index "$IDX" --top 3
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'fused=0.0')" -eq 3 ]
}

@test "dense path: cosine from the embedding server appears and boosts the matching note" {
  start_embed
  build
  run python3 "$SCRIPT" query "riego" --index "$IDX" --top 3 --alpha 1.0
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == riego.md*"cos=1.0" ]]
  [ "$(echo "$output" | grep -c 'cos=0.0')" -eq 2 ]
}

@test "dense path: alpha 1 ranks by cosine alone, alpha 0 by BM25 alone" {
  start_embed
  # nota "decoy" sin la palabra riego en BM25 pero con embedding de riego
  echo "riego riego riego riego" > "$IDXDIR/notes/zz-riego-extra.md"
  echo "tomate tomate tomate agua" > "$IDXDIR/notes/aa-tomate.md"
  build
  top_dense="$(python3 "$SCRIPT" query "tomate" --index "$IDX" --top 1 --alpha 1.0 | cut -f1)"
  top_bm25="$(python3 "$SCRIPT" query "tomate" --index "$IDX" --top 1 --alpha 0.0 | cut -f1)"
  # con alpha=1 y consulta sin "riego", la consulta tiene vector [0,1]: gana una nota sin "riego" (cos 1)
  [[ "$top_dense" != "zz-riego-extra.md" ]]
  [[ "$top_bm25" == "aa-tomate.md" ]]
}

@test "dense path: fused score is the alpha-weighted blend of cosine and bm25" {
  start_embed
  build
  line="$(python3 "$SCRIPT" query "riego" --index "$IDX" --top 1 --alpha 0.25)"
  run python3 - "$line" <<'PY'
import re, sys
f = float(re.search(r"fused=([\d.]+)", sys.argv[1]).group(1))
b = float(re.search(r"bm25=([\d.]+)", sys.argv[1]).group(1))
c = float(re.search(r"cos=([\d.]+)", sys.argv[1]).group(1))
assert abs(f - (0.25 * c + 0.75 * b)) < 1e-3, (f, b, c)
PY
  [ "$status" -eq 0 ]
}
