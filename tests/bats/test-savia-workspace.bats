#!/usr/bin/env bats
# SE-373 — savia setup · modulo workspace: composicion multi-repo (AC-0..AC-7)
# Ref: docs/specs/SE-373-savia-setup-workspace.spec.md
# CRIT-001: sandbox local; solo lectura de repos hijos.

W="bash scripts/savia-workspace.sh"

setup() {
    TMPD="$(mktemp -d)"
    WDIR="$TMPD/w"
    SV="$TMPD/home"
    mkdir -p "$SV" "$WDIR"
}

teardown() {
    rm -rf "$TMPD"
}

mk_repos() {
    for r in "$@"; do
        mkdir -p "$WDIR/$r"
        (cd "$WDIR/$r" && git init -q && echo "# $r" > README.md && \
         git add -A && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null)
    done
}

@test "SE-373 AC-0: genera AGENTS.md con repos y mapa de relaciones" {
    mk_repos product-a-api product-a-web
    run env SAVIA_HOME_OVERRIDE="$SV" $W "$WDIR"
    [ "$status" -eq 0 ]
    [ -f "$WDIR/AGENTS.md" ]
    grep -q 'product-a-api' "$WDIR/AGENTS.md"
    grep -q 'product-a-web' "$WDIR/AGENTS.md"
    grep -q '`product-a-api` | `product-a-web`' "$WDIR/AGENTS.md"
}

@test "SE-373 AC-1: la composicion instruye lazy-load (no leer todos)" {
    mk_repos product-a-api product-a-web
    env SAVIA_HOME_OVERRIDE="$SV" $W "$WDIR" >/dev/null
    grep -qi 'BAJO DEMANDA (lazy load)' "$WDIR/AGENTS.md"
    grep -qi 'no leas todos' "$WDIR/AGENTS.md"
}

@test "SE-373 AC-2: re-ejecucion idempotente y preserva overrides manuales" {
    mk_repos product-a-api product-a-web product-b-web
    env SAVIA_HOME_OVERRIDE="$SV" $W "$WDIR" >/dev/null
    # override manual: api tambien sirve a product-b-web
    cat > "$SV/a.json" <<'EOF'
{"workspace":{"relations_manual":{"product-a-api":["product-b-web"]}}}
EOF
    run env SAVIA_HOME_OVERRIDE="$SV" $W "$WDIR" --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    grep -q '`product-a-api` | `product-a-web`, `product-b-web`' "$WDIR/AGENTS.md"
    # re-ejecutar sin answers: el override persiste desde el estado
    run env SAVIA_HOME_OVERRIDE="$SV" $W "$WDIR"
    grep -q 'product-b-web' "$WDIR/AGENTS.md"
    # sin duplicar filas
    N=$(grep -c 'product-a-api' "$WDIR/AGENTS.md")
    [ "$N" -ge 2 ]  # inventario + relacion
}

@test "SE-373 AC-3: --dry-run no escribe nada" {
    mk_repos product-a-api product-a-web
    run env SAVIA_HOME_OVERRIDE="$SV" $W "$WDIR" --dry-run
    [ "$status" -eq 0 ]
    [ ! -f "$WDIR/AGENTS.md" ]
    [ ! -f "$SV/savia-setup.json" ]
}

@test "SE-373 AC-4: --answers con relaciones manuales produce el mapa esperado" {
    mk_repos product-a-api product-a-web product-b-web product-b-api
    cat > "$SV/a.json" <<'EOF'
{"workspace":{"relations_manual":{"product-b-api":["product-b-web"]}}}
EOF
    env SAVIA_HOME_OVERRIDE="$SV" $W "$WDIR" --answers "$SV/a.json" >/dev/null
    grep -q '`product-b-api` | `product-b-web`' "$WDIR/AGENTS.md"
}

@test "SE-373 AC-5: directorio sin repos -> exit 2 con error claro" {
    E="$TMPD/vacio"; mkdir -p "$E"
    run env SAVIA_HOME_OVERRIDE="$SV" $W "$E"
    [ "$status" -eq 2 ]
    echo "$output" | grep -qi 'no hay repos'
}

@test "SE-373 AC-6: registra en savia-setup.json.workspaces" {
    mk_repos product-a-api product-a-web
    env SAVIA_HOME_OVERRIDE="$SV" $W "$WDIR" >/dev/null
    python3 - "$SV/savia-setup.json" "$WDIR" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ws = d.get("workspaces", {})
assert any(k == sys.argv[2] for k in ws), ws
print("ok")
PY
}

@test "SE-373 AC-7: no regresion — suite SE-372 sigue verde" {
    run bats tests/bats/test-savia-setup.bats
    [ "$status" -eq 0 ]
}

# ── Comportamiento: inventario, heurística de relaciones, estado y salidas ──

ws() { env SAVIA_HOME_OVERRIDE="$SV" bash scripts/savia-workspace.sh "$@"; }

@test "inventario: tabla con cada repo y su remote origin; sin remote muestra raya" {
    mk_repos alfa-api alfa-web
    git -C "$WDIR/alfa-api" remote add origin https://example.test/org/alfa-api.git
    ws "$WDIR" >/dev/null
    grep -qF '| `alfa-api` | `https://example.test/org/alfa-api.git` |' "$WDIR/AGENTS.md"
    grep -qF '| `alfa-web` | `—` |' "$WDIR/AGENTS.md"
}

@test "cabecera con el nombre del directorio y secciones en orden" {
    mk_repos alfa-api alfa-web
    ws "$WDIR" >/dev/null
    [ "$(sed -n 1p "$WDIR/AGENTS.md")" = "# Workspace — w (multi-repo)" ]
    local a b c
    a=$(grep -n '^## Repos (inventario)' "$WDIR/AGENTS.md" | cut -d: -f1)
    b=$(grep -n '^## Mapa de relaciones' "$WDIR/AGENTS.md" | cut -d: -f1)
    c=$(grep -n '^## Reglas por repo' "$WDIR/AGENTS.md" | cut -d: -f1)
    [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]
}

@test "heurística: solo los repos con sufijo api/backend/server/service/srv son proveedores" {
    mk_repos x-api x-web y-backend y-app z-server z-ui w-service w-cli v-srv v-front
    ws "$WDIR" >/dev/null
    grep -qF '| `x-api` | `x-web` |' "$WDIR/AGENTS.md"
    grep -qF '| `y-backend` | `y-app` |' "$WDIR/AGENTS.md"
    grep -qF '| `z-server` | `z-ui` |' "$WDIR/AGENTS.md"
    grep -qF '| `w-service` | `w-cli` |' "$WDIR/AGENTS.md"
    grep -qF '| `v-srv` | `v-front` |' "$WDIR/AGENTS.md"
    grep -qF '| `x-web` | — |' "$WDIR/AGENTS.md"
}

@test "heurística: repos de otro producto no se relacionan" {
    mk_repos alfa-api beta-web
    ws "$WDIR" >/dev/null
    grep -qF '| `alfa-api` | — |' "$WDIR/AGENTS.md"
}

@test "heurística: un proveedor no se sirve a sí mismo" {
    mk_repos p-api p-web
    ws "$WDIR" >/dev/null
    run grep -F '| `p-api` | `p-api`' "$WDIR/AGENTS.md"
    [ "$status" -eq 1 ]
}

@test "heurística: coincidencia por prefijo (consumidor con más texto tras el producto)" {
    mk_repos shop-api shop-admin-web shop-web
    ws "$WDIR" >/dev/null
    grep -qF '| `shop-api` | `shop-admin-web`, `shop-web` |' "$WDIR/AGENTS.md"
}

@test "se ignoran ficheros, directorios ocultos y directorios sin .git" {
    mk_repos real-api real-web
    mkdir -p "$WDIR/.oculto" "$WDIR/sin-git"
    (cd "$WDIR/.oculto" && git init -q)
    echo hola > "$WDIR/fichero.txt"
    ws "$WDIR" >/dev/null
    run grep -E 'oculto|sin-git|fichero.txt' "$WDIR/AGENTS.md"
    [ "$status" -eq 1 ]
}

@test "un worktree/submódulo con .git como fichero cuenta como repo" {
    mk_repos real-api
    mkdir -p "$WDIR/wt-web"
    echo "gitdir: /tmp/otro" > "$WDIR/wt-web/.git"
    ws "$WDIR" >/dev/null
    grep -qF '| `wt-web` |' "$WDIR/AGENTS.md"
}

@test "override manual en forma de consumidor se invierte hacia el proveedor" {
    mk_repos alfa-api beta-web
    cat > "$SV/a.json" <<'JSON'
{"workspace":{"relations_manual":{"beta-web":["alfa-api"]}}}
JSON
    ws "$WDIR" --answers "$SV/a.json" >/dev/null
    grep -qF '| `alfa-api` | `beta-web` |' "$WDIR/AGENTS.md"
}

@test "override manual no duplica un consumidor ya detectado ni se sirve a sí mismo" {
    mk_repos alfa-api alfa-web
    cat > "$SV/a.json" <<'JSON'
{"workspace":{"relations_manual":{"alfa-api":["alfa-web","alfa-api"]}}}
JSON
    ws "$WDIR" --answers "$SV/a.json" >/dev/null
    grep -qF '| `alfa-api` | `alfa-web` |' "$WDIR/AGENTS.md"
}

@test "override manual sobre un repo que no existe se ignora y no entra en el estado" {
    mk_repos alfa-api alfa-web
    cat > "$SV/a.json" <<'JSON'
{"workspace":{"relations_manual":{"fantasma-api":["alfa-web"]}}}
JSON
    run ws "$WDIR" --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    run grep fantasma "$WDIR/AGENTS.md"
    [ "$status" -eq 1 ]
    [ "$(jq -r --arg w "$WDIR" '.workspaces[$w].relations_manual | keys | length' "$SV/savia-setup.json")" = "0" ]
}

@test "answers ilegible se ignora sin romper la generación" {
    mk_repos alfa-api alfa-web
    echo "no es json" > "$SV/a.json"
    run ws "$WDIR" --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    grep -qF '| `alfa-api` | `alfa-web` |' "$WDIR/AGENTS.md"
}

@test "estado: repos, relaciones y manual persistidos con version 1 y sello temporal real" {
    mk_repos alfa-api alfa-web
    cat > "$SV/a.json" <<'JSON'
{"workspace":{"relations_manual":{"alfa-api":["alfa-web"]}}}
JSON
    ws "$WDIR" --answers "$SV/a.json" >/dev/null
    local st="$SV/savia-setup.json"
    [ "$(jq -r .version "$st")" = "1" ]
    [ "$(jq -c --arg w "$WDIR" '.workspaces[$w].repos' "$st")" = '["alfa-api","alfa-web"]' ]
    [ "$(jq -c --arg w "$WDIR" '.workspaces[$w].relations[0]' "$st")" = '{"repo":"alfa-api","served_by":["alfa-web"]}' ]
    [ "$(jq -c --arg w "$WDIR" '.workspaces[$w].relations_manual' "$st")" = '{"alfa-api":["alfa-web"]}' ]
    run python3 - "$st" "$WDIR" <<'PY'
import json, sys, datetime
d = json.load(open(sys.argv[1]))["workspaces"][sys.argv[2]]["updated_at"]
t = datetime.datetime.strptime(d, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
age = abs((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds())
assert age < 300, (d, age)
print("ok")
PY
    [ "$output" = "ok" ]
}

@test "estado: un segundo workspace se añade sin pisar el primero; estado corrupto se reinicia" {
    mk_repos alfa-api alfa-web
    ws "$WDIR" >/dev/null
    local W2="$TMPD/w2"; mkdir -p "$W2/b-api"; git -C "$W2/b-api" init -q
    ws "$W2" >/dev/null
    [ "$(jq -r '.workspaces | keys | length' "$SV/savia-setup.json")" = "2" ]
    echo "{corrupto" > "$SV/savia-setup.json"
    run ws "$WDIR"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.workspaces | keys | length' "$SV/savia-setup.json")" = "1" ]
}

@test "estado previo: el override manual guardado se aplica sin --answers" {
    mk_repos alfa-api alfa-web beta-web
    cat > "$SV/a.json" <<'JSON'
{"workspace":{"relations_manual":{"alfa-api":["beta-web"]}}}
JSON
    ws "$WDIR" --answers "$SV/a.json" >/dev/null
    unlink "$WDIR/AGENTS.md"
    ws "$WDIR" >/dev/null
    grep -qF '| `alfa-api` | `alfa-web`, `beta-web` |' "$WDIR/AGENTS.md"
}

@test "salida: confirma la ruta, el estado registrado y lista los repos" {
    mk_repos alfa-api alfa-web
    run ws "$WDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ composicion: $WDIR/AGENTS.md"* ]]
    [[ "$output" == *"✓ estado registrado: workspaces[w]"* ]]
    [[ "$output" == *"repos: alfa-api, alfa-web"* ]]
}

@test "--dry-run imprime el contenido que escribiría" {
    mk_repos alfa-api alfa-web
    run ws "$WDIR" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == "--- dry-run: se escribiria $WDIR/AGENTS.md ---"* ]]
    [[ "$output" == *"# Workspace — w (multi-repo)"* ]]
    [[ "$output" == *'| `alfa-api` | `alfa-web` |'* ]]
}

@test "uso: sin directorio, directorio inexistente y opción desconocida salen con 2" {
    run ws
    [ "$status" -eq 2 ]
    [[ "$output" == *"uso: savia-workspace.sh"* ]]
    run ws "$TMPD/no-existe"
    [ "$status" -eq 2 ]
    [[ "$output" == *"directorio no existe"* ]]
    run ws "$WDIR" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"uso invalido: --bogus"* ]]
}

@test "--help sale 0 y muestra el uso" {
    run ws --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"savia-workspace.sh <dir>"* ]]
}

@test "solo escribe AGENTS.md en la raíz: los repos hijos quedan intactos" {
    mk_repos alfa-api alfa-web
    local before after
    before=$(git -C "$WDIR/alfa-api" status --porcelain | wc -l)
    ws "$WDIR" >/dev/null
    after=$(git -C "$WDIR/alfa-api" status --porcelain | wc -l)
    [ "$before" = "$after" ]
    [ ! -e "$WDIR/alfa-api/AGENTS.md" ]
}

@test "override manual con clave que no es repo no se invierte: un fantasma no se vuelve consumidor" {
    mk_repos alfa-api beta-web
    cat > "$SV/a.json" <<'JSON'
{"workspace":{"relations_manual":{"fantasma":["alfa-api"]}}}
JSON
    ws "$WDIR" --answers "$SV/a.json" >/dev/null
    run grep fantasma "$WDIR/AGENTS.md"
    [ "$status" -eq 1 ]
}

@test "override manual invertido no duplica un consumidor ya detectado por la heurística" {
    mk_repos alfa-api alfa-web
    cat > "$SV/a.json" <<'JSON'
{"workspace":{"relations_manual":{"alfa-web":["alfa-api"]}}}
JSON
    ws "$WDIR" --answers "$SV/a.json" >/dev/null
    grep -qF '| `alfa-api` | `alfa-web` |' "$WDIR/AGENTS.md"
}

@test "estado: nombres de repo no ASCII se guardan literales" {
    mk_repos ñandú-api ñandú-web
    ws "$WDIR" >/dev/null
    grep -q 'ñandú-api' "$SV/savia-setup.json"
}
