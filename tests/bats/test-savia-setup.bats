#!/usr/bin/env bats
# SE-372 — Savia Setup: inicializador interactivo (AC-0..AC-8)
# Ref: docs/specs/SE-372-savia-setup.spec.md
# CRIT-001: sandbox local; remoto solo infra propia salvo --allow-any-remote.

SETUP="bash scripts/savia-setup.sh"

setup() {
    TMPD="$(mktemp -d)"
    SB="$TMPD/root"
    SV="$TMPD/home"
    mkdir -p "$SB/.claude/profiles" "$SB/.claude/rules" "$SB/vaults" "$SV"
    python3 - "$SB/opencode.json" <<'PY'
import json, sys
d = {"mcp": {
    "codegraph": {"type": "local", "enabled": True},
    "codebase-memory-mcp": {"type": "local", "enabled": True},
    "savia-vaults": {"type": "local", "enabled": False}}}
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
}

teardown() {
    rm -rf "$TMPD"
}

answers_min() {
    cat > "$SV/a.json" <<'EOF'
{"profile":{"name":"Mónica","role":"Operadora"},
 "frontend":{"primary":"opencode"},
 "models":{"provider":"ollama"},
 "mcp":{"enabled":["savia-vaults"],"disabled":["codegraph","codebase-memory-mcp"]},
 "vaults":{"domes":[{"name":"SaviaLearning","mode":"local","confidentiality":"N2","backup":"local"}],"root_served":true},
 "federation":{"enabled":true,"remotes":[]},
 "backends":{},"autonomy":{}}
EOF
}

@test "SE-372 AC-0: --help documenta modulos y --check muestra estado" {
    run $SETUP --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "vaults"
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --check
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "estado por area"
}

@test "SE-372 AC-1: headless aplica mcp+prefs+dome+estado" {
    answers_min
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    python3 -c "import json;d=json.load(open('$SB/opencode.json'));assert d['mcp']['savia-vaults']['enabled'] is True;assert d['mcp']['codegraph']['enabled'] is False"
    [ -f "$SV/preferences.yaml" ] && grep -q '^provider: ollama' "$SV/preferences.yaml"
    [ -f "$SB/vaults/SaviaLearning/INDEX.md" ]
    [ -f "$SV/savia-setup.json" ]
    [ -f "$SB/.claude/profiles/active-user.md" ]
}

@test "SE-372 AC-2: re-ejecucion idempotente (sin duplicar dome ni romper)" {
    answers_min
    env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --answers "$SV/a.json" >/dev/null
    local antes
    antes=$(find "$SB/vaults" -name INDEX.md | wc -l)
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    local despues
    despues=$(find "$SB/vaults" -name INDEX.md | wc -l)
    [ "$antes" -eq "$despues" ]
    python3 -c "import json; json.load(open('$SB/opencode.json'))"
}

@test "SE-372 AC-3: modulo mcp --off codegraph deshabilita sin tocar resto" {
    answers_min
    env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --answers "$SV/a.json" >/dev/null
    python3 - "$SB/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["mcp"]["enabled"] = []  # noop
PY
    cat > "$SV/m.json" <<'EOF'
{"mcp":{"enabled":[],"disabled":["codegraph"]}}
EOF
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" mcp --answers "$SV/m.json"
    [ "$status" -eq 0 ]
    python3 -c "import json;d=json.load(open('$SB/opencode.json'));assert d['mcp']['codegraph']['enabled'] is False;assert d['mcp']['savia-vaults']['enabled'] is True"
}

@test "SE-372 AC-4: vault remoto propio configura git remote (sin push)" {
    cat > "$SV/r.json" <<'EOF'
{"mcp":{"enabled":[],"disabled":[]},
 "vaults":{"domes":[{"name":"SaviaDomains","mode":"remote","remote_url":"git@example.com:org/vault.git","confidentiality":"N1"}]}}
EOF
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" vaults --answers "$SV/r.json"
    [ "$status" -eq 0 ]
    git -C "$SB/vaults/SaviaDomains" remote get-url origin 2>/dev/null | grep -q 'git@example.com:org/vault.git'
}

@test "SE-372 AC-4b: vault remoto NO propio se rechaza (CRIT-001) salvo --allow-any-remote" {
    cat > "$SV/r.json" <<'EOF'
{"mcp":{"enabled":[],"disabled":[]},
 "vaults":{"domes":[{"name":"SaviaLabs","mode":"remote","remote_url":"https://thirdparty.io/data/vault.git","confidentiality":"N2"}]}}
EOF
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" vaults --answers "$SV/r.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'RECHAZADO'
    git -C "$SB/vaults/SaviaLabs" remote get-url origin 2>/dev/null && return 1 || true
    # override explicito permite
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" vaults --answers "$SV/r.json" --allow-any-remote
    echo "$output" | grep -vq 'RECHAZADO'
    git -C "$SB/vaults/SaviaLabs" remote get-url origin 2>/dev/null | grep -q 'thirdparty.io'
}

@test "SE-372 AC-6: --check tras aplicar reporta areas configuradas" {
    answers_min
    env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --answers "$SV/a.json" >/dev/null
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --check
    echo "$output" | grep -q 'ollama'
    echo "$output" | grep -q 'savia-vaults'
}

@test "SE-372 AC-7: opencode.json sigue siendo JSON valido tras merge" {
    answers_min
    env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --answers "$SV/a.json" >/dev/null
    python3 -c "import json; json.load(open('$SB/opencode.json')); print('json ok')"
}

@test "SE-372: answers invalido -> exit 2" {
    echo '{no-json' > "$SV/bad.json"
    run env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --answers "$SV/bad.json"
    [ "$status" -eq 2 ]
}

@test "SE-372: federation enabled escribe .federation.json" {
    answers_min
    env SAVIA_HOME_OVERRIDE="$SV" $SETUP --root "$SB" --answers "$SV/a.json" >/dev/null
    [ -f "$SB/vaults/.federation.json" ]
    grep -q '"enabled": true' "$SB/vaults/.federation.json"
}

# ── Comportamiento: contenido de cada área aplicada, fusión de estado, guardas ──

run_setup() { env SAVIA_HOME_OVERRIDE="$SV" bash scripts/savia-setup.sh --root "$SB" "$@"; }
jqf() { jq -r "$1" "$2"; }

@test "identity: escribe active-user con slug, nombre y rol; slug derivado sin tildes raras ni espacios" {
    echo '{"profile":{"name":"Ana María Ruiz","role":"PM"}}' > "$SV/a.json"
    run run_setup identity --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"perfil activo: ana_mar_a_ruiz"* ]]
    local f="$SB/.claude/profiles/active-user.md"
    grep -q '^active_slug: "ana_mar_a_ruiz"$' "$f"
    grep -q '^active_name: "Ana María Ruiz"$' "$f"
    grep -q '^active_role: "PM"$' "$f"
    [ "$(head -1 "$f")" = "---" ]
}

@test "identity: slug explícito gana, rol por defecto Operadora, activated_at es de ahora" {
    echo '{"profile":{"name":"Lola","slug":"lola42"}}' > "$SV/a.json"
    run_setup identity --answers "$SV/a.json" >/dev/null
    local f="$SB/.claude/profiles/active-user.md"
    grep -q '^active_slug: "lola42"$' "$f"
    grep -q '^active_role: "Operadora"$' "$f"
    local at
    at=$(sed -n 's/^activated_at: "\(.*\)"$/\1/p' "$f")
    run python3 - "$at" <<'PY'
import sys, datetime
t = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
assert abs((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()) < 300, sys.argv[1]
print("ok")
PY
    [ "$output" = "ok" ]
}

@test "identity: sin nombre no crea el perfil activo" {
    echo '{"profile":{"role":"PM"}}' > "$SV/a.json"
    run run_setup identity --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    [ ! -f "$SB/.claude/profiles/active-user.md" ]
}

@test "models: preferences.yaml con version, frontend, provider y los tres tiers de modelo" {
    cat > "$SV/a.json" <<'JSON'
{"frontend":{"primary":"claude-code"},
 "models":{"provider":"deepseek","model_heavy":"deepseek/h","model_mid":"deepseek/m","model_fast":"deepseek/f","auth_kind":"oauth"}}
JSON
    run run_setup models --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    local p="$SV/preferences.yaml"
    grep -qx 'version: 1' "$p"
    grep -qx 'frontend: claude-code' "$p"
    grep -qx 'provider: deepseek' "$p"
    grep -qx 'model_heavy: deepseek/h' "$p"
    grep -qx 'model_mid: deepseek/m' "$p"
    grep -qx 'model_fast: deepseek/f' "$p"
    grep -qx 'auth_kind: oauth' "$p"
    grep -qx 'has_hooks: yes' "$p"
    grep -qx 'budget_kind: none' "$p"
}

@test "models: defaults opencode/ollama/api-key y sin líneas model_* si no se piden" {
    echo '{"models":{}}' > "$SV/a.json"
    run_setup models --answers "$SV/a.json" >/dev/null
    local p="$SV/preferences.yaml"
    grep -qx 'frontend: opencode' "$p"
    grep -qx 'provider: ollama' "$p"
    grep -qx 'auth_kind: api-key' "$p"
    run grep -c '^model_' "$p"
    [ "$output" = "0" ]
}

@test "models: re-ejecutar no duplica claves y conserva las líneas ajenas" {
    printf 'tiers:\n  x: 1\nprovider: viejo\n' > "$SV/preferences.yaml"
    echo '{"models":{"provider":"zai-coding-plan"}}' > "$SV/a.json"
    run_setup models --answers "$SV/a.json" >/dev/null
    run_setup models --answers "$SV/a.json" >/dev/null
    [ "$(grep -c '^provider:' "$SV/preferences.yaml")" = "1" ]
    grep -qx 'provider: zai-coding-plan' "$SV/preferences.yaml"
    grep -qx 'tiers:' "$SV/preferences.yaml"
    grep -qx '  x: 1' "$SV/preferences.yaml"
}

@test "mcp: un servidor conocido ausente se crea deshabilitado; los no mencionados conservan su estado" {
    python3 - "$SB/opencode.json" <<'PY'
import json, sys
json.dump({"mcp": {"codegraph": {"type": "local", "enabled": True}}}, open(sys.argv[1], "w"))
PY
    echo '{"mcp":{"enabled":[],"disabled":[]}}' > "$SV/a.json"
    run run_setup mcp --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"opencode.json mcp: ninguno"* ]]
    [ "$(jqf '.mcp.codegraph.enabled' "$SB/opencode.json")" = "true" ]
    [ "$(jqf '.mcp["savia-vaults"].enabled' "$SB/opencode.json")" = "false" ]
    [ "$(jqf '.mcp["codebase-memory-mcp"].type' "$SB/opencode.json")" = "local" ]
}

@test "mcp: habilitados se listan en la salida; un servidor desconocido en enabled no se crea" {
    echo '{"mcp":{"enabled":["savia-vaults","otro"],"disabled":["codegraph"]}}' > "$SV/a.json"
    run run_setup mcp --answers "$SV/a.json"
    [[ "$output" == *"enabled=savia-vaults,otro"* ]]
    [ "$(jqf '.mcp["savia-vaults"].enabled' "$SB/opencode.json")" = "true" ]
    [ "$(jqf '.mcp.codegraph.enabled' "$SB/opencode.json")" = "false" ]
    [ "$(jqf '.mcp | has("otro")' "$SB/opencode.json")" = "false" ]
}

@test "autonomy: escribe revisora y aviso en pm-config.local y reemplaza el valor anterior" {
    echo '{"autonomy":{"autonomous_reviewer":"alguien","research_notify":"canal"}}' > "$SV/a.json"
    run run_setup autonomy --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    local f="$SB/.claude/rules/pm-config.local.md"
    grep -qx 'AUTONOMOUS_REVIEWER="alguien"' "$f"
    grep -qx 'AUTONOMOUS_RESEARCH_NOTIFY="canal"' "$f"
    echo '{"autonomy":{"autonomous_reviewer":"otra"}}' > "$SV/b.json"
    run_setup autonomy --answers "$SV/b.json" >/dev/null
    [ "$(grep -c '^AUTONOMOUS_REVIEWER=' "$f")" = "1" ]
    grep -qx 'AUTONOMOUS_REVIEWER="otra"' "$f"
    grep -qx 'AUTONOMOUS_RESEARCH_NOTIFY="canal"' "$f"
}

@test "autonomy: sin revisora ni aviso no crea el fichero" {
    echo '{"autonomy":{}}' > "$SV/a.json"
    run_setup autonomy --answers "$SV/a.json" >/dev/null
    [ ! -f "$SB/.claude/rules/pm-config.local.md" ]
}

@test "backends: bloque azure-devops en CLAUDE.local.md; reemplazo sin duplicar y sin pisar el resto" {
    printf '# otro bloque\nX=1\n' > "$SB/CLAUDE.local.md"
    echo '{"backends":{"azure_devops":{"enabled":true,"org_url":"https://dev.azure.com/org1"}}}' > "$SV/a.json"
    run run_setup backends --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLAUDE.local.md backend: https://dev.azure.com/org1"* ]]
    echo '{"backends":{"azure_devops":{"enabled":true,"org_url":"https://dev.azure.com/org2"}}}' > "$SV/b.json"
    run_setup backends --answers "$SV/b.json" >/dev/null
    local f="$SB/CLAUDE.local.md"
    [ "$(grep -c 'savia setup' "$f")" = "1" ]
    grep -qx 'AZURE_DEVOPS_ORG_URL="https://dev.azure.com/org2"' "$f"
    run grep org1 "$f"
    [ "$status" -eq 1 ]
    grep -qx 'X=1' "$f"
}

@test "backends: deshabilitado o sin org_url no escribe nada" {
    echo '{"backends":{"azure_devops":{"enabled":false,"org_url":"https://x"}}}' > "$SV/a.json"
    run_setup backends --answers "$SV/a.json" >/dev/null
    [ ! -f "$SB/CLAUDE.local.md" ]
    echo '{"backends":{"azure_devops":{"enabled":true}}}' > "$SV/b.json"
    run_setup backends --answers "$SV/b.json" >/dev/null
    [ ! -f "$SB/CLAUDE.local.md" ]
}

@test "vaults: INDEX.md de la cúpula lleva nivel, dominio y no se sobrescribe" {
    echo '{"vaults":{"domes":[{"name":"SaviaLabs","confidentiality":"N3"}]}}' > "$SV/a.json"
    run run_setup vaults --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"vault: SaviaLabs mode=local nivel=N3"* ]]
    local idx="$SB/vaults/SaviaLabs/INDEX.md"
    grep -q '^confidentiality: N3$' "$idx"
    grep -q '^domain: SAVI$' "$idx"
    echo "editado a mano" >> "$idx"
    run_setup vaults --answers "$SV/a.json" >/dev/null
    grep -q 'editado a mano' "$idx"
}

@test "vaults: nivel por defecto N2 y cúpula sin nombre se omite" {
    echo '{"vaults":{"domes":[{"name":"Plana"},{"mode":"local"}]}}' > "$SV/a.json"
    run run_setup vaults --answers "$SV/a.json"
    [[ "$output" == *"vault: Plana mode=local nivel=N2"* ]]
    grep -q '^confidentiality: N2$' "$SB/vaults/Plana/INDEX.md"
    [ "$(ls "$SB/vaults" | wc -l)" = "1" ]
}

@test "vaults: modo remote sin remote_url avisa y se queda local sin repo git" {
    echo '{"vaults":{"domes":[{"name":"SinUrl","mode":"remote"}]}}' > "$SV/a.json"
    run run_setup vaults --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN dome SinUrl en modo remote sin remote_url"* ]]
    [ ! -d "$SB/vaults/SinUrl/.git" ]
}

@test "vaults: remotos de infra propia (git@, github.com, localhost, 127., file://) se aceptan" {
    local i=0 u
    for u in "git@h:o/r.git" "https://github.com/o/r.git" "http://localhost:3000/o/r.git" "127.0.0.1:o/r.git" "file:///tmp/r.git"; do
        i=$((i+1))
        jq -n --arg n "d$i" --arg u "$u" '{vaults:{domes:[{name:$n,mode:"remote",remote_url:$u}]}}' > "$SV/a.json"
        run run_setup vaults --answers "$SV/a.json"
        [ "$status" -eq 0 ]
        [[ "$output" != *"RECHAZADO"* ]]
        [ "$(git -C "$SB/vaults/d$i" remote get-url origin)" = "$u" ]
    done
}

@test "vaults: remoto ajeno se rechaza, con el mensaje que nombra el dome y la URL" {
    echo '{"vaults":{"domes":[{"name":"Fuera","mode":"remote","remote_url":"https://ajeno.example/x.git"}]}}' > "$SV/a.json"
    run run_setup vaults --answers "$SV/a.json"
    [[ "$output" == *"RECHAZADO dome Fuera : remoto https://ajeno.example/x.git no es infra propia"* ]]
    [ ! -d "$SB/vaults/Fuera/.git" ]
    [[ "$output" != *"vault: Fuera"* ]]
}

@test "vaults: segunda ejecución con otra URL actualiza el origin existente" {
    echo '{"vaults":{"domes":[{"name":"D","mode":"remote","remote_url":"git@h:o/uno.git"}]}}' > "$SV/a.json"
    run_setup vaults --answers "$SV/a.json" >/dev/null
    echo '{"vaults":{"domes":[{"name":"D","mode":"remote","remote_url":"git@h:o/dos.git"}]}}' > "$SV/b.json"
    run_setup vaults --answers "$SV/b.json" >/dev/null
    [ "$(git -C "$SB/vaults/D" remote get-url origin)" = "git@h:o/dos.git" ]
}

@test "vaults: --push-remotes confirma y empuja al remoto; sin la bandera no empuja" {
    local bare="$TMPD/bare.git"
    git init -q --bare "$bare"
    jq -n --arg u "file://$bare" '{vaults:{domes:[{name:"P",mode:"remote",remote_url:$u}]}}' > "$SV/a.json"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    run_setup vaults --answers "$SV/a.json" >/dev/null
    [ "$(git -C "$bare" branch -a | wc -l)" = "0" ]
    run run_setup vaults --answers "$SV/a.json" --push-remotes
    [ "$status" -eq 0 ]
    [ "$(git -C "$bare" branch -a | wc -l)" = "1" ]
    git -C "$SB/vaults/P" log --format=%s -1 | grep -qx 'chore: savia setup dome'
}

@test "vaults: push fallido avisa y deja el remoto configurado" {
    jq -n '{vaults:{domes:[{name:"Q",mode:"remote",remote_url:"file:///no/existe/jamas.git"}]}}' > "$SV/a.json"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    run run_setup vaults --answers "$SV/a.json" --push-remotes
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN push fallo: Q"* ]]
    [ "$(git -C "$SB/vaults/Q" remote get-url origin)" = "file:///no/existe/jamas.git" ]
}

@test "federation: .federation.json con remotos y sello real; salida lista los remotos" {
    echo '{"federation":{"enabled":true,"remotes":["git@h:a","git@h:b"]}}' > "$SV/a.json"
    run run_setup federation --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"federacion: git@h:a, git@h:b"* ]]
    local f="$SB/vaults/.federation.json"
    [ "$(jqf '.enabled' "$f")" = "true" ]
    [ "$(jq -c '.remotes' "$f")" = '["git@h:a","git@h:b"]' ]
    run python3 - "$(jqf '.updated_at' "$f")" <<'PY'
import sys, datetime
t = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
assert abs((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()) < 300, sys.argv[1]
print("ok")
PY
    [ "$output" = "ok" ]
}

@test "federation: habilitada sin remotos dice 'on (sin remotos)'; deshabilitada no escribe" {
    echo '{"federation":{"enabled":true,"remotes":[]}}' > "$SV/a.json"
    run run_setup federation --answers "$SV/a.json"
    [[ "$output" == *"federacion: on (sin remotos)"* ]]
    echo '{"federation":{"enabled":false}}' > "$SV/b.json"
    unlink "$SB/vaults/.federation.json"
    run run_setup federation --answers "$SV/b.json"
    [ "$status" -eq 0 ]
    [ ! -f "$SB/vaults/.federation.json" ]
}

@test "estado: fusiona por área sin borrar claves previas ni otras áreas" {
    cat > "$SV/a.json" <<'JSON'
{"profile":{"name":"Uno","role":"R1"},"models":{"provider":"ollama","model_heavy":"h1"},"autonomy":{"autonomous_reviewer":"x"}}
JSON
    run_setup --answers "$SV/a.json" >/dev/null
    echo '{"models":{"provider":"deepseek"}}' > "$SV/b.json"
    run_setup --answers "$SV/b.json" >/dev/null
    local st="$SV/savia-setup.json"
    [ "$(jqf '.models.provider' "$st")" = "deepseek" ]
    [ "$(jqf '.models.model_heavy' "$st")" = "h1" ]
    [ "$(jqf '.profile.name' "$st")" = "Uno" ]
    [ "$(jqf '.autonomy.autonomous_reviewer' "$st")" = "x" ]
    [ "$(jqf '.version' "$st")" = "1" ]
}

@test "estado: un área que no es objeto sustituye al valor previo" {
    echo '{"mcp":{"enabled":["a"]}}' > "$SV/a.json"
    run_setup mcp --answers "$SV/a.json" >/dev/null
    echo '{"mcp":{"enabled":["b"],"disabled":[]}}' > "$SV/b.json"
    run_setup mcp --answers "$SV/b.json" >/dev/null
    [ "$(jq -c '.mcp.enabled' "$SV/savia-setup.json")" = '["b"]' ]
}

@test "módulo sin --answers reaplica desde el estado guardado" {
    echo '{"models":{"provider":"deepseek"}}' > "$SV/a.json"
    run_setup --answers "$SV/a.json" >/dev/null
    unlink "$SV/preferences.yaml"
    run run_setup models
    [ "$status" -eq 0 ]
    grep -qx 'provider: deepseek' "$SV/preferences.yaml"
}

@test "todo: --answers sin módulo aplica prefs, perfil y federación a la vez" {
    cat > "$SV/a.json" <<'JSON'
{"profile":{"name":"Zoe"},"models":{"provider":"deepseek"},"federation":{"enabled":true,"remotes":[]},"mcp":{"enabled":[],"disabled":[]}}
JSON
    run run_setup --answers "$SV/a.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"estado: $SV/savia-setup.json"* ]]
    grep -qx 'provider: deepseek' "$SV/preferences.yaml"
    grep -q 'active_name: "Zoe"' "$SB/.claude/profiles/active-user.md"
    [ -f "$SB/vaults/.federation.json" ]
}

@test "--check lista proveedor, frontend, mcp activos, vaults y federación" {
    printf 'provider: deepseek\n' > "$SV/preferences.yaml"
    echo '{"frontend":{"primary":"opencode"}}' > "$SV/savia-setup.json"
    mkdir -p "$SB/vaults/Alfa" "$SB/vaults/Beta"
    touch "$SB/vaults/.federation.json"
    run run_setup --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"preferences    si"* ]]
    [[ "$output" == *"provider       deepseek"* ]]
    [[ "$output" == *"frontend       opencode"* ]]
    [[ "$output" == *"mcp            codegraph,codebase-memory-mcp"* ]]
    [[ "$output" == *"vaults         Alfa Beta"* ]]
    [[ "$output" == *"federation     on"* ]]
}

@test "--check sin nada configurado: preferences no, federación off, mcp ninguno si todos desactivados" {
    echo '{"mcp":{"codegraph":{"enabled":false}}}' > "$SB/opencode.json"
    run run_setup --check
    [[ "$output" == *"preferences    no"* ]]
    [[ "$output" == *"federation     off"* ]]
    [[ "$output" == *"mcp            ninguno"* ]]
    [[ "$output" == *"workspaces     ninguno"* ]]
}

@test "errores: opción desconocida y opencode.json ausente salen con 2; sin respuestas ni estado también" {
    run run_setup --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"uso invalido: --bogus"* ]]
    unlink "$SB/opencode.json"
    run run_setup --check
    [ "$status" -eq 2 ]
    [[ "$output" == *"opencode.json no encontrado"* ]]
}

@test "errores: --answers con fichero inexistente falla con 2 sin crear estado" {
    run run_setup --answers "$SV/no-existe.json"
    [ "$status" -eq 2 ]
    [ ! -f "$SV/savia-setup.json" ]
}

@test "workspace: el subcomando delega en savia-workspace.sh con sus argumentos" {
    run run_setup workspace
    [ "$status" -eq 2 ]
    [[ "$output" == *"uso: savia-workspace.sh"* ]]
}

# ── Asistente interactivo (necesita terminal: se ejecuta bajo un pty) ───────

# wizard <entradas-separadas-por-\n> [args…] → ejecuta el asistente con stdin en un pty
wizard() {
    local input="$1"; shift
    run bash -c "printf '$input' | SAVIA_HOME_OVERRIDE='$SV' timeout 60 script -qec 'bash scripts/savia-setup.sh --root $SB $*' /dev/null"
}

@test "asistente: guarda solo la elección de cada menú (no el texto del menú) y deriva los modelos" {
    command -v script >/dev/null || skip "script(1) no disponible"
    # nombre, rol, proveedor 3=deepseek, frontend 2=claude-code, vaults 1=local, domes n, mcp n/n/n, fed n
    wizard 'Ana\nPM\n3\n2\n1\nn\nn\nn\nn\nn\n'
    [ "$status" -eq 0 ]
    local st="$SV/savia-setup.json"
    [ "$(jq -r .profile.name "$st")" = "Ana" ]
    [ "$(jq -r .profile.role "$st")" = "PM" ]
    [ "$(jq -r .models.provider "$st")" = "deepseek" ]
    [ "$(jq -r .frontend.primary "$st")" = "claude-code" ]
    [ "$(jq -r .models.model_heavy "$st")" = "deepseek/deepseek-v4-flash" ]
    grep -qx 'provider: deepseek' "$SV/preferences.yaml"
    grep -qx 'frontend: claude-code' "$SV/preferences.yaml"
    [[ "$output" == *"=== Savia configurada ==="* ]]
}

@test "asistente: proveedor ollama y zai fijan sus tres modelos" {
    command -v script >/dev/null || skip "script(1) no disponible"
    wizard 'Ana\nPM\n1\n1\n1\nn\nn\nn\nn\nn\n'
    [ "$(jq -r .models.model_heavy "$SV/savia-setup.json")" = "ollama/llama3.1:70b" ]
    [ "$(jq -r .models.model_mid "$SV/savia-setup.json")" = "ollama/llama3.1:8b" ]
    [ "$(jq -r .models.model_fast "$SV/savia-setup.json")" = "ollama/llama3.1" ]
    unlink "$SV/savia-setup.json"
    wizard 'Ana\nPM\n2\n1\n1\nn\nn\nn\nn\nn\n'
    [ "$(jq -r .models.provider "$SV/savia-setup.json")" = "zai-coding-plan" ]
    [ "$(jq -r .models.model_heavy "$SV/savia-setup.json")" = "zai-coding-plan/glm-5.3" ]
    [ "$(jq -r .models.model_fast "$SV/savia-setup.json")" = "zai-coding-plan/glm-5.3-flash" ]
}

@test "asistente: opción fuera de rango o vacía cae en la primera opción" {
    command -v script >/dev/null || skip "script(1) no disponible"
    wizard 'Ana\nPM\n9\n\n1\nn\nn\nn\nn\nn\n'
    [ "$(jq -r .models.provider "$SV/savia-setup.json")" = "ollama" ]
    [ "$(jq -r .frontend.primary "$SV/savia-setup.json")" = "opencode" ]
    unlink "$SV/savia-setup.json"
    wizard 'Ana\nPM\n0\nx\n1\nn\nn\nn\nn\nn\n'
    [ "$(jq -r .models.provider "$SV/savia-setup.json")" = "ollama" ]
    unlink "$SV/savia-setup.json"
    wizard 'Ana\nPM\n4\n3\n1\nn\nn\nn\nn\nn\n'
    [ "$(jq -r .models.provider "$SV/savia-setup.json")" = "azure-openai" ]
    [ "$(jq -r .frontend.primary "$SV/savia-setup.json")" = "ambos" ]
}

@test "asistente: MCP según las respuestas y federación con endpoint" {
    command -v script >/dev/null || skip "script(1) no disponible"
    # mcp: vaults=y codegraph=n codebase=y ; federación y + endpoint
    wizard 'Ana\nPM\n1\n1\n1\nn\ny\nn\ny\ny\nhttps://fed.example\n'
    local st="$SV/savia-setup.json"
    [ "$(jq -c .mcp.enabled "$st")" = '["savia-vaults","codebase-memory-mcp"]' ]
    [ "$(jq -c .mcp.disabled "$st")" = '["codegraph"]' ]
    [ "$(jq -r .federation.enabled "$st")" = "true" ]
    [ "$(jq -c .federation.remotes "$st")" = '["https://fed.example"]' ]
    [ "$(jq -r '.mcp["savia-vaults"].enabled' "$SB/opencode.json")" = "true" ]
    [ "$(jq -r '.mcp.codegraph.enabled' "$SB/opencode.json")" = "false" ]
    [ -f "$SB/vaults/.federation.json" ]
}

@test "asistente: federación sin endpoint queda habilitada sin remotos; 'n' la deja apagada" {
    command -v script >/dev/null || skip "script(1) no disponible"
    wizard 'Ana\nPM\n1\n1\n1\nn\nn\nn\nn\ny\n\n'
    [ "$(jq -r .federation.enabled "$SV/savia-setup.json")" = "true" ]
    [ "$(jq -c .federation.remotes "$SV/savia-setup.json")" = '[]' ]
    unlink "$SV/savia-setup.json"
    wizard 'Ana\nPM\n1\n1\n1\nn\nn\nn\nn\nn\n'
    [ "$(jq -r .federation.enabled "$SV/savia-setup.json")" = "false" ]
}

@test "asistente: domes locales creados con su INDEX; respuesta 's' también cuenta como sí" {
    command -v script >/dev/null || skip "script(1) no disponible"
    wizard 'Ana\nPM\n1\n1\n1\ns\nn\nn\nn\nn\n'
    local d
    for d in SaviaLearning SaviaLabs savia-docs Fronesia; do
        [ -f "$SB/vaults/$d/INDEX.md" ]
    done
    [ "$(jq -r '.vaults.domes | length' "$SV/savia-setup.json")" = "4" ]
    [ "$(jq -r '.vaults.domes[0].mode' "$SV/savia-setup.json")" = "local" ]
}

@test "asistente: modo remoto configura el git remote de cada cúpula (mode remote, no 'remoto')" {
    command -v script >/dev/null || skip "script(1) no disponible"
    wizard 'Ana\nPM\n1\n1\n2\ngit@h:o/r.git\ny\nn\nn\nn\nn\n'
    [ "$(jq -r '.vaults.domes[0].mode' "$SV/savia-setup.json")" = "remote" ]
    [ "$(git -C "$SB/vaults/SaviaLabs" remote get-url origin)" = "git@h:o/r.git" ]
}

@test "asistente: con nombre y rol ya guardados no los pregunta de nuevo" {
    command -v script >/dev/null || skip "script(1) no disponible"
    echo '{"profile":{"name":"Previa","role":"Jefa"}}' > "$SV/savia-setup.json"
    # solo menús y síes/noes: proveedor, frontend, vaults, domes, 3 mcp, fed
    wizard '1\n1\n1\nn\nn\nn\nn\nn\n'
    [ "$status" -eq 0 ]
    [ "$(jq -r .profile.name "$SV/savia-setup.json")" = "Previa" ]
    [ "$(jq -r .profile.role "$SV/savia-setup.json")" = "Jefa" ]
    [[ "$output" != *"Nombre de la operadora"* ]]
    grep -q 'active_name: "Previa"' "$SB/.claude/profiles/active-user.md"
}

@test "sin terminal y sin argumentos muestra el estado (no entra al asistente)" {
    run bash -c "SAVIA_HOME_OVERRIDE='$SV' bash scripts/savia-setup.sh --root '$SB' < /dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Savia setup — estado por area"* ]]
    [[ "$output" != *"configuracion interactiva"* ]]
}

@test "estado: caracteres no ASCII se guardan literales en el estado y en opencode.json" {
    echo '{"profile":{"name":"Ñandú Ruiz"},"mcp":{"enabled":["savia-vaults"],"disabled":[]}}' > "$SV/a.json"
    run_setup --answers "$SV/a.json" >/dev/null
    grep -q 'Ñandú Ruiz' "$SV/savia-setup.json"
    python3 - "$SB/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["nota"] = "señal"; json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
    echo '{"mcp":{"enabled":[],"disabled":[]}}' > "$SV/b.json"
    run_setup mcp --answers "$SV/b.json" >/dev/null
    grep -q 'señal' "$SB/opencode.json"
}

@test "federación: un fallo de lectura del estado no se traga el error" {
    echo '{"federation":{"enabled":true}}' > "$SV/a.json"
    run_setup --answers "$SV/a.json" > /dev/null
    echo '{roto' > "$SV/savia-setup.json"
    run run_setup federation
    [ "$status" -eq 2 ]
}

@test "módulo con estado previo y sin respuestas aplica el módulo pedido, no todos" {
    echo '{"models":{"provider":"deepseek"},"autonomy":{"autonomous_reviewer":"x"}}' > "$SV/a.json"
    run_setup --answers "$SV/a.json" >/dev/null
    unlink "$SV/preferences.yaml"
    unlink "$SB/.claude/rules/pm-config.local.md"
    run run_setup autonomy
    [ "$status" -eq 0 ]
    [ -f "$SB/.claude/rules/pm-config.local.md" ]
    [ ! -f "$SV/preferences.yaml" ]
}

@test "remote en vault sin repo previo: si falla 'git remote add' el error no pasa inadvertido" {
    echo '{"vaults":{"domes":[{"name":"V","mode":"remote","remote_url":"git@h:o/r.git"}]}}' > "$SV/a.json"
    run_setup vaults --answers "$SV/a.json" >/dev/null
    [ -d "$SB/vaults/V/.git" ]
    git -C "$SB/vaults/V" remote get-url origin >/dev/null
}

@test "sin terminal y sin argumentos, aunque haya estado guardado, solo informa: no reaplica nada" {
    echo '{"models":{"provider":"deepseek"},"profile":{"name":"Zoe"}}' > "$SV/savia-setup.json"
    run bash -c "SAVIA_HOME_OVERRIDE='$SV' bash scripts/savia-setup.sh --root '$SB' < /dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"estado por area"* ]]
    [ ! -f "$SV/preferences.yaml" ]
    [ ! -f "$SB/.claude/profiles/active-user.md" ]
}
