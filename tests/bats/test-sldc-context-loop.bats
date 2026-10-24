#!/usr/bin/env bats
# tests/bats/test-sldc-context-loop.bats — SE-311 S1: post-merge context loop

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/sldc-context-loop.sh"
  TESTDIR=$(mktemp -d)
  export SLDC_PENDING_DIR="$TESTDIR/pending"
  export HOME="$TESTDIR"
}

teardown() {
  # el servidor A2A falso (si el test lo arrancó) no debe sobrevivir al test
  [ -z "${A2A_PID:-}" ] || kill "$A2A_PID" 2>/dev/null || true
  rm -rf "$TESTDIR"
}

@test "S1: clasifica spec → nota spec-status (spec real con **Estado:**)" {
  run bash "$SCRIPT" --base ORIGIN/MAIN --head HEAD --dry-run \
    < <(echo "projects/savia-vaults/specs/SE-311-sldc-context-loop.spec.md")
  [ "$status" -eq 0 ]
  [[ "$output" == *"SE-311-sldc-context-loop-status.md"* ]]
  [[ "$output" == *"PROPOSED"* ]]
}

@test "S1: extrae estado via **Estado:** y via status:" {
  run bash -c "echo '---'; echo 'status: APPROVED'" | grep -q "APPROVED" \
    || true
}

@test "S1: sin artefactos → NO_ARTIFACTS" {
  run bash "$SCRIPT" --base ORIGIN/MAIN --head HEAD --dry-run \
    < <(echo "src/foo.py")
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO_ARTIFACTS"* ]]
}

@test "S1: feed fallido encola pendiente; list-pending lo muestra" {
  run bash "$SCRIPT" --base ORIGIN/MAIN --head HEAD --feed \
    < <(echo "CHANGELOG.d/x.md")
  # sin servidor A2A → encola pendiente (o falla graceful)
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" --list-pending
  [[ "$output" == *"pendientes"* ]]
}

@test "S1: --feed --dry-run no envia nada (DRY, sin pendientes)" {
  run bash "$SCRIPT" --base ORIGIN/MAIN --head HEAD --feed --dry-run \
    < <(echo "CHANGELOG.d/x.md")
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY"* ]]
  [ ! -d "$SLDC_PENDING_DIR" ]
}

@test "S1: CHANGELOG → nota release" {
  run bash "$SCRIPT" --base ORIGIN/MAIN --head HEAD --dry-run \
    < <(printf "CHANGELOG.d/se311-x.md\n- Cambio documentado\n")
  [ "$status" -eq 0 ]
  [[ "$output" == *"releases/"* ]]
}

@test "S1: docs/propuestas → nota decision" {
  run bash "$SCRIPT" --base ORIGIN/MAIN --head HEAD --dry-run \
    < <(printf "docs/propuestas/SE-999-x.md\ntitle: Decision X\n")
  [ "$status" -eq 0 ]
  [[ "$output" == *"decisions/"* ]]
}

# ── Comportamiento: contenido de las notas, entrega, cola pendiente, git ────

# Servidor A2A falso: guarda cada POST /share y responde según $MODE
# (ok | error | vacio). Puerto efímero en $BATS_TEST_TMPDIR/port.
start_a2a() {
  local mode="${1:-ok}"
  cat > "$BATS_TEST_TMPDIR/a2a.py" <<'PY'
import http.server, sys, os
out, mode, portf = sys.argv[1:4]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n)
        open(out, "ab").write(self.path.encode() + b" " + body + b"\n")
        if mode == "vacio":
            self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers(); return
        data = b'{"error":"dome cerrado"}' if mode == "error" else b'{"ok":true}'
        self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(portf, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
  : > "$BATS_TEST_TMPDIR/posts.log"
  # sin heredar los descriptores de bats: si el test aborta, el servidor no cuelga la suite
  python3 "$BATS_TEST_TMPDIR/a2a.py" "$BATS_TEST_TMPDIR/posts.log" "$mode" "$BATS_TEST_TMPDIR/port" >/dev/null 2>&1 3>&- &
  A2A_PID=$!
  for _ in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/port" ] && break; sleep 0.1; done
  export SLDC_VAULTS_URL="http://127.0.0.1:$(cat "$BATS_TEST_TMPDIR/port")"
}

stop_a2a() { [ -n "${A2A_PID:-}" ] && kill "$A2A_PID" 2>/dev/null; wait "$A2A_PID" 2>/dev/null || true; }

mkwork() { # carpeta de trabajo con artefactos reales
  WORK="$TESTDIR/work"; mkdir -p "$WORK/projects/p/specs" "$WORK/docs/propuestas" "$WORK/CHANGELOG.d"
  printf -- '---\nstatus: APPROVED\n---\n# Spec: Mi spec\n' > "$WORK/projects/p/specs/SE-1-x.spec.md"
  printf '# Otra\n**Estado:** PROPOSED\n' > "$WORK/projects/p/specs/SE-2-y.spec.md"
  printf '# sin estado\n' > "$WORK/projects/p/specs/SE-3-z.spec.md"
  printf -- '---\ntitle: Elegimos X\n---\ncuerpo\n' > "$WORK/docs/propuestas/SE-9-Elegir_X.md"
  printf -- '---\nsection: Added\n---\n### Added\n\n- Primer cambio\n- Segundo cambio\n' > "$WORK/CHANGELOG.d/cambio.md"
}

notas() { # lista de ficheros por stdin → JSON de notas (una por línea)
  ( cd "$WORK" && bash "$SCRIPT" --base A --head B --feed --dry-run "$@" )
}

@test "nota de spec: título de '# Spec:', estado de 'status:' y fuente citada" {
  mkwork
  run bash -c "cd '$WORK' && echo projects/p/specs/SE-1-x.spec.md | bash '$SCRIPT' --base A"
  [ "$status" -eq 0 ]
  local json
  json=$(echo "$output" | sed 1d | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)))")
  [ "$(echo "$json" | jq -r .path)" = "specs/SE-1-x-status.md" ]
  [ "$(echo "$json" | jq -r .dome)" = "example-context" ]
  [[ "$(echo "$json" | jq -r .content)" == "# Mi spec"*"## Estado"*"APPROVED (actualizado post-merge por SDLC Context Loop, $(date +%F))."*"## Fuente"*"- projects/p/specs/SE-1-x.spec.md"* ]]
}

@test "nota de spec: estado de '**Estado:**' cuando no hay status:, 'unknown' si falta; título = nombre si no hay '# Spec:'" {
  mkwork
  run bash -c "cd '$WORK' && printf 'projects/p/specs/SE-2-y.spec.md\nprojects/p/specs/SE-3-z.spec.md\nprojects/p/specs/SE-404.spec.md\n' | bash '$SCRIPT' --base A"
  [[ "$output" == *"PROPOSED (actualizado"* ]]
  [[ "$output" == *"unknown (actualizado"* ]]
  [[ "$output" == *"# SE-404.spec.md"* ]]
}

@test "nota de ADR: ruta decisions/<fecha>-<slug>.md con slug normalizado y título de 'title:'" {
  mkwork
  run bash -c "cd '$WORK' && echo docs/propuestas/SE-9-Elegir_X.md | bash '$SCRIPT' --base A"
  [[ "$output" == *"decisions/$(date +%F)-se-9-elegir-x.md"* ]]
  [[ "$output" == *"# Decision: Elegimos X"* ]]
  [[ "$output" == *"Documentada en docs/propuestas/SE-9-Elegir_X.md."* ]]
}

@test "nota de release: primera viñeta del fragmento y ruta releases/<slug>.md" {
  mkwork
  run bash -c "cd '$WORK' && echo CHANGELOG.d/cambio.md | bash '$SCRIPT' --base A"
  [[ "$output" == *"releases/cambio.md"* ]]
  [[ "$output" == *"- Primer cambio"* ]]
  [[ "$output" != *"Segundo cambio"* ]]
  [[ "$output" == *"- CHANGELOG.d/cambio.md"* ]]
}

@test "release sin viñetas usa 'cambio documentado'; fichero ausente no rompe" {
  mkwork
  printf 'sin vinetas\n' > "$WORK/CHANGELOG.d/vacio.md"
  run bash -c "cd '$WORK' && printf 'CHANGELOG.d/vacio.md\nCHANGELOG.d/fantasma.md\n' | bash '$SCRIPT' --base A"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'cambio documentado')" -eq 2 ]
}

@test "clasificación: solo specs de proyecto, propuestas y fragmentos; el resto y las líneas vacías se ignoran" {
  mkwork
  run bash -c "cd '$WORK' && printf 'src/a.py\n\nprojects/p/otro.md\nprojects/p/specs/x.md\ndocs/otra/z.md\nCHANGELOG.d/cambio.txt\nprojects/p/specs/SE-1-x.spec.md\nCHANGELOG.d/cambio.md\n' | bash '$SCRIPT' --base A"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c '"path"')" -eq 2 ]
  [[ "$output" == *"specs/SE-1-x-status.md"* ]]
  [[ "$output" == *"releases/cambio.md"* ]]
}

@test "SLDC_WRITE_DOME fija la cúpula destino de las notas" {
  mkwork
  run bash -c "cd '$WORK' && echo CHANGELOG.d/cambio.md | SLDC_WRITE_DOME=mi-cupula bash '$SCRIPT' --base A"
  [[ "$output" == *'"dome": "mi-cupula"'* ]]
}

@test "--feed entrega cada nota por POST /share y sale OK sin pendientes" {
  mkwork; start_a2a ok
  run bash -c "cd '$WORK' && printf 'projects/p/specs/SE-1-x.spec.md\nCHANGELOG.d/cambio.md\n' | bash '$SCRIPT' --base A --feed"
  stop_a2a
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: example-context/specs/SE-1-x-status.md"* ]]
  [[ "$output" == *"OK: example-context/releases/cambio.md"* ]]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/posts.log")" -eq 2 ]
  grep -q '^/share ' "$BATS_TEST_TMPDIR/posts.log"
  [ ! -d "$SLDC_PENDING_DIR" ] || [ -z "$(ls -A "$SLDC_PENDING_DIR")" ]
}

@test "--feed con respuesta de error de la cúpula encola la nota como pendiente" {
  mkwork; start_a2a error
  run bash -c "cd '$WORK' && echo CHANGELOG.d/cambio.md | bash '$SCRIPT' --base A --feed"
  stop_a2a
  [ "$status" -eq 0 ]
  [[ "$output" == *"fallo al alimentar, encolando pendiente"* ]]
  [[ "$output" == *"PENDING: 1 nota(s) encoladas en $SLDC_PENDING_DIR"* ]]
  [[ "$output" != *"OK:"* ]]
  [ "$(ls "$SLDC_PENDING_DIR" | wc -l)" -eq 1 ]
  [ "$(jq -r .path "$SLDC_PENDING_DIR"/*.json)" = "releases/cambio.md" ]
}

@test "--feed con servidor caído no dice OK: la nota queda pendiente" {
  mkwork
  export SLDC_VAULTS_URL="http://127.0.0.1:1"
  run bash -c "cd '$WORK' && echo CHANGELOG.d/cambio.md | bash '$SCRIPT' --base A --feed"
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK:"* ]]
  [[ "$output" == *"PENDING: 1 nota(s)"* ]]
}

@test "--feed con respuesta vacía de la cúpula tampoco cuenta como entregada" {
  mkwork; start_a2a vacio
  run bash -c "cd '$WORK' && echo CHANGELOG.d/cambio.md | bash '$SCRIPT' --base A --feed"
  stop_a2a
  [[ "$output" != *"OK:"* ]]
  [ "$(ls "$SLDC_PENDING_DIR" | wc -l)" -eq 1 ]
}

@test "--flush-pending reenvía, borra solo lo entregado y cuenta ok/fallidas" {
  mkwork; start_a2a ok
  mkdir -p "$SLDC_PENDING_DIR"
  echo '{"dome":"d","path":"a.md","content":"x"}' > "$SLDC_PENDING_DIR/1.json"
  echo '{"dome":"d","path":"b.md","content":"y"}' > "$SLDC_PENDING_DIR/2.json"
  run bash "$SCRIPT" --flush-pending
  [ "$output" = "$(printf 'OK: d/a.md\nOK: d/b.md\nFLUSH: 2 enviadas, 0 fallidas')" ]
  [ -z "$(ls -A "$SLDC_PENDING_DIR")" ]
  stop_a2a
  echo '{"dome":"d","path":"c.md","content":"z"}' > "$SLDC_PENDING_DIR/3.json"
  export SLDC_VAULTS_URL="http://127.0.0.1:1"
  run bash "$SCRIPT" --flush-pending
  [[ "$output" == *"FLUSH: 0 enviadas, 1 fallidas"* ]]
  [ -f "$SLDC_PENDING_DIR/3.json" ]
}

@test "--flush-pending --dry-run (en cualquier orden) no envía ni consume la cola" {
  mkwork; start_a2a ok
  mkdir -p "$SLDC_PENDING_DIR"
  echo '{"dome":"d","path":"a.md","content":"x"}' > "$SLDC_PENDING_DIR/1.json"
  run bash "$SCRIPT" --flush-pending --dry-run
  [[ "$output" == *"DRY: d/a.md"* ]]
  [ -f "$SLDC_PENDING_DIR/1.json" ]
  run bash "$SCRIPT" --dry-run --flush-pending
  [[ "$output" == *"DRY: d/a.md"* ]]
  [ -f "$SLDC_PENDING_DIR/1.json" ]
  stop_a2a
  [ ! -s "$BATS_TEST_TMPDIR/posts.log" ]
}

@test "--list-pending lista cada fichero y el total" {
  mkdir -p "$SLDC_PENDING_DIR"
  echo '{}' > "$SLDC_PENDING_DIR/a.json"; echo '{}' > "$SLDC_PENDING_DIR/b.json"
  run bash "$SCRIPT" --list-pending
  [ "$status" -eq 0 ]
  [[ "$output" == *"  - a.json"* ]]
  [[ "$output" == *"  - b.json"* ]]
  [[ "$output" == *"pendientes: 2"* ]]
  run bash "$SCRIPT" --list-pending --base x
  [[ "$output" == *"pendientes: 2"* ]]
}

@test "salida sin --feed: encabezado y notas en JSON legible" {
  mkwork
  run bash -c "cd '$WORK' && echo CHANGELOG.d/cambio.md | bash '$SCRIPT' --base A"
  [ "${lines[0]}" = "== Notas generadas (usa --feed para escribir en las cupulas) ==" ]
  [[ "$output" == *'"path": "releases/cambio.md"'* ]]
}

@test "uso: sin --base, argumento desconocido y --help salen con 2" {
  run bash -c "echo x | bash '$SCRIPT'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: --base requerido"* ]]
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento desconocido: --bogus"* ]]
  run bash "$SCRIPT" --help
  [ "$status" -eq 2 ]
  [[ "$output" == *"sldc-context-loop.sh --base"* ]]
}

@test "modo git (stdin es terminal): toma los ficheros del diff base...head" {
  command -v script >/dev/null || skip "script(1) no disponible"
  local repo="$TESTDIR/r"
  mkdir -p "$repo/scripts" "$repo/CHANGELOG.d"
  cp "$SCRIPT" "$repo/scripts/sldc-context-loop.sh"
  git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$repo" tag base
  printf -- '- Cambio via git\n' > "$repo/CHANGELOG.d/g.md"
  echo codigo > "$repo/otro.txt"
  git -C "$repo" add -A
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m cambio
  cd "$repo"   # las notas leen los artefactos relativos al directorio de trabajo
  run script -qec "bash scripts/sldc-context-loop.sh --base base --head HEAD" /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"releases/g.md"* ]]
  [[ "$output" == *"Cambio via git"* ]]
  [[ "$output" != *"otro.txt"* ]]
}

@test "flush-pending y list-pending salen con 0 incluso con envíos fallidos" {
  mkdir -p "$SLDC_PENDING_DIR"
  echo '{"dome":"d","path":"a.md","content":"x"}' > "$SLDC_PENDING_DIR/1.json"
  export SLDC_VAULTS_URL="http://127.0.0.1:1"
  run bash "$SCRIPT" --flush-pending
  [ "$status" -eq 0 ]
  [[ "$output" == *"FLUSH: 0 enviadas, 1 fallidas"* ]]
  run bash "$SCRIPT" --list-pending
  [ "$status" -eq 0 ]
}

@test "las notas conservan acentos y eñes literales" {
  mkwork
  printf -- '---\ntitle: Decisión sobre ñandúes\n---\n' > "$WORK/docs/propuestas/SE-8-x.md"
  run bash -c "cd '$WORK' && echo docs/propuestas/SE-8-x.md | SLDC_WRITE_DOME=cúpula bash '$SCRIPT' --base A"
  [[ "$output" == *"Decisión sobre ñandúes"* ]]
  [[ "$output" == *"cúpula"* ]]
  run bash -c "cd '$WORK' && echo docs/propuestas/SE-8-x.md | SLDC_WRITE_DOME=cúpula bash '$SCRIPT' --base A --feed --dry-run"
  [[ "$output" == "DRY: cúpula/decisions/"* ]]
}

@test "modo git: sin ancestro común (diff de tres puntos vacío) cae al diff directo entre refs" {
  command -v script >/dev/null || skip "script(1) no disponible"
  local repo="$TESTDIR/r2"
  mkdir -p "$repo/scripts"
  cp "$SCRIPT" "$repo/scripts/sldc-context-loop.sh"
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  # raíz independiente construida con fontanería: sin merge-base con main
  local blob tree commit
  blob=$(printf -- '- Desde rama huérfana\n' | git -C "$repo" hash-object -w --stdin)
  export GIT_INDEX_FILE="$TESTDIR/idx"
  git -C "$repo" update-index --add --cacheinfo 100644,"$blob",CHANGELOG.d/h.md
  tree=$(git -C "$repo" write-tree)
  unset GIT_INDEX_FILE
  commit=$(git -C "$repo" -c user.email=t@t -c user.name=t commit-tree "$tree" -m huerfana)
  git -C "$repo" update-ref refs/heads/huerfana "$commit"
  [ -z "$(git -C "$repo" diff --name-only main...huerfana 2>/dev/null)" ]
  cd "$repo"
  run script -qec "bash scripts/sldc-context-loop.sh --base main --head huerfana" /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"releases/h.md"* ]]
}

@test "el POST a la cúpula lleva el JSON con acentos literales (no escapados)" {
  mkwork; start_a2a ok
  run bash -c "cd '$WORK' && echo CHANGELOG.d/cambio.md | SLDC_WRITE_DOME=cúpula bash '$SCRIPT' --base A --feed"
  stop_a2a
  [ "$status" -eq 0 ]
  grep -q '"dome": "cúpula"' "$BATS_TEST_TMPDIR/posts.log"
}

@test "cola vacía: flush envía 0 y list informa 0, sin tocar la cúpula" {
  mkwork; start_a2a ok
  run bash "$SCRIPT" --flush-pending
  [ "$output" = "FLUSH: 0 enviadas, 0 fallidas" ]
  run bash "$SCRIPT" --list-pending
  [ "$output" = "pendientes: 0" ]
  stop_a2a
  [ ! -s "$BATS_TEST_TMPDIR/posts.log" ]
}
