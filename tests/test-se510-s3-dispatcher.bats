#!/usr/bin/env bats
# SE-510 S3 (parcial): despachador PreToolUse con fallo cerrado (AC-5) y tabla generada (AC-6).
# El despachador se copia a un árbol temporal con su propia tabla y hooks de prueba.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    T="$(mktemp -d)"
    mkdir -p "$T/hooks/dispatchers" "$T/h" "$T/scripts" "$T/.claude"
    cp "${DISPATCHER_UNDER_TEST:-$REPO/hooks/dispatchers/dispatch-pretooluse.sh}" "$T/hooks/dispatchers/dispatch-pretooluse.sh"
    D="$T/hooks/dispatchers/dispatch-pretooluse.sh"
    IN='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
}
teardown() { chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"; }

mkhook() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/h/$1.sh"; }
row() { printf '%s\t%s\t%s\t%s\tprueba\n' "$1" "h/$2.sh" "${3:-spawn}" "${4:-yes}" >> "$T/hooks/routing-pretooluse.tsv"; }

@test "AC-5: hook que sale 0 -> 0" {
    mkhook ok 'exit 0'; row Bash ok
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]
}
@test "AC-5: hook que sale 2 -> 2" {
    mkhook no 'exit 2'; row Bash no
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
}
@test "AC-5: hook bloqueante que sale 1 -> 2 con el motivo" {
    mkhook e1 'exit 1'; row Bash e1
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"exit 1"* ]]
}
@test "AC-5: hook registrado que falta -> 2" {
    row Bash ausente
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"que falta"* ]]
}
@test "AC-5: tabla ausente -> 2" {
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"tabla de despacho ausente"* ]]
}
@test "AC-5: tabla ilegible -> 2" {
    [ "$(id -u)" -ne 0 ] || skip "root lee todo"
    mkhook ok 'exit 0'; row Bash ok; chmod 000 "$T/hooks/routing-pretooluse.tsv"
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
}
@test "AC-5: JSON malformado -> 2" {
    mkhook ok 'exit 0'; row Bash ok
    run bash "$D" <<< '{"tool_name": '; [ "$status" -eq 2 ]
    [[ "$output" == *"malformada"* ]]
}
@test "AC-5: stdin vacío -> 2" {
    mkhook ok 'exit 0'; row Bash ok
    run bash "$D" < /dev/null; [ "$status" -eq 2 ]
}
@test "AC-5: JSON válido sin nombre de herramienta -> 2" {
    mkhook ok 'exit 0'; row Bash ok
    run bash "$D" <<< '{"tool_input":{}}'; [ "$status" -eq 2 ]
}
@test "AC-5: hook que excede el tiempo -> 2" {
    mkhook slow 'sleep 5; exit 0'; row Bash slow
    DISPATCH_HOOK_TIMEOUT=1 run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"tiempo agotado"* ]]
}
@test "AC-5: fila mal formada (mode inválido) -> 2" {
    mkhook ok 'exit 0'; row Bash ok magia
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"mal formada"* ]]
}
@test "límite: hook roto que no casa con la herramienta no bloquea" {
    mkhook e1 'exit 1'; row Edit e1
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]
}
@test "límite: hook NO bloqueante que sale 1 no bloquea (se avisa)" {
    mkhook e1 'exit 1'; row Bash e1 spawn no
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}
@test "el primer exit 2 corta: los hooks siguientes no se ejecutan" {
    mkhook no 'exit 2'; mkhook mark "touch $T/marca"; row Bash no; row Bash mark
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [ ! -e "$T/marca" ]
}
@test "la entrada llega a cada hook por stdin, intacta" {
    mkhook eco "cat > $T/visto"; row Bash eco
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]
    [ "$(cat "$T/visto")" = "$IN" ]
}

# ── AC-6: la tabla se genera desde settings.json ──────────────────────────────
gen_tree() {
    cp "$REPO/scripts/dispatch-table.py" "$T/scripts/"
    cp "$REPO/.claude/settings.json" "$T/.claude/settings.json"
    cp "$REPO/hooks/routing-pretooluse.tsv" "$T/hooks/routing-pretooluse.tsv"
}
@test "AC-6: la tabla del repo coincide con settings.json" {
    run python3 "$REPO/scripts/dispatch-table.py" check
    [ "$status" -eq 0 ]
}
@test "AC-6: una entrada nueva en settings.json sin regenerar la tabla -> falla" {
    gen_tree
    python3 - "$T/.claude/settings.json" <<'P'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["hooks"]["PreToolUse"].append({"matcher": "Bash", "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/nuevo.sh", "timeout": 5}]})
json.dump(s, open(p, "w"))
P
    run python3 "$T/scripts/dispatch-table.py" check
    [ "$status" -eq 1 ]
    [[ "$output" == *"DRIFT"* ]]
}
@test "AC-6: tabla editada a mano (hook quitado) -> falla" {
    gen_tree
    sed -i '/block-force-push/d' "$T/hooks/routing-pretooluse.tsv"
    run python3 "$T/scripts/dispatch-table.py" check
    [ "$status" -eq 1 ]
}
@test "AC-6: settings.json ausente -> exit 2, no PASS" {
    gen_tree; rm "$T/.claude/settings.json"
    run python3 "$T/scripts/dispatch-table.py" check
    [ "$status" -eq 2 ]
}
@test "AC-6: command con forma no despachable aborta la generación (exit 2)" {
    gen_tree
    python3 - "$T/.claude/settings.json" <<'P'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = "nohup algo-raro --en-segundo-plano"
json.dump(s, open(p, "w"))
P
    run python3 "$T/scripts/dispatch-table.py" check
    [ "$status" -eq 2 ]
}
@test "AC-6: todo hook de la tabla real existe (si no, el despachador bloquearía todo)" {
    while IFS=$'\t' read -r m s rest; do
        [[ -z "$m" || "$m" == \#* ]] && continue
        [ -f "$REPO/${s%% *}" ] || { echo "falta: $s"; false; }
    done < "$REPO/hooks/routing-pretooluse.tsv"
}

# ── Revisión de la PR #1616: semántica de matcher, modo, orden y generador ────
@test "P1: matcher regex mcp__.* casa con una herramienta MCP (el hook se ejecuta)" {
    mkhook mark "touch $T/marca"; row 'mcp__.*|WebFetch' mark
    run bash "$D" <<< '{"tool_name":"mcp__github__create_issue","tool_input":{}}'
    [ "$status" -eq 0 ]; [ -e "$T/marca" ]
}
@test "P1 negativo: matcher mcp__.* no casa con Bash" {
    mkhook mark "touch $T/marca"; row 'mcp__.*|WebFetch' mark
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]; [ ! -e "$T/marca" ]
}
@test "P2: matcher que no es regex válida -> 2 (no se salta la fila)" {
    mkhook ok 'exit 0'; row '((Bash' ok
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"matcher inválido"* ]]
}
@test "P2: modo source -> 2 (no se puede acotar con timeout)" {
    mkhook ok 'exit 0'; row Bash ok source
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"no soportado"* ]]
}
@test "P2: la última fila sin salto de línea también se ejecuta" {
    mkhook no 'exit 2'; printf 'Bash\th/no.sh\tspawn\tyes\tprueba' > "$T/hooks/routing-pretooluse.tsv"
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
}
@test "P2: los argumentos de la tabla llegan literales (sin expansión de globs)" {
    mkhook args "printf '%s\n' \"\$@\" > $T/args"; touch "$T/glob-a" "$T/glob-b"
    printf 'Bash\th/args.sh guard %s/glob-*\tspawn\tyes\tprueba\n' "$T" > "$T/hooks/routing-pretooluse.tsv"
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]
    [ "$(cat "$T/args")" = "$(printf 'guard\n%s/glob-*' "$T")" ]
}
@test "P2: un comando repetido en la tabla se ejecuta una vez por acción" {
    mkhook cnt "echo x >> $T/cuenta"; row Bash cnt; row 'Bash|Edit' cnt
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]
    [ "$(wc -l < "$T/cuenta")" -eq 1 ]
}
@test "P1: los no bloqueantes corren después de los bloqueantes (un exit 2 los corta)" {
    mkhook mark "touch $T/marca"; mkhook no 'exit 2'; row Bash mark spawn no; row Bash no
    run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]; [ ! -e "$T/marca" ]
}
@test "P1 negativo: un no bloqueante que sale 2 no bloquea" {
    mkhook no 'exit 2'; row Bash no spawn no
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]; [[ "$output" == *"WARNING"* ]]
}
@test "P2: el tiempo agotado mata también los hijos del hook" {
    mkhook slow "(sleep 2; touch $T/huerfano) & sleep 5"; row Bash slow
    DISPATCH_HOOK_TIMEOUT=1 run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    sleep 2.5; [ ! -e "$T/huerfano" ]
}

# Tabla REAL con hooks espía: comprueba la semántica de despacho de settings.json, no la autoconsistencia.
spy_tree() {
    cp "$REPO/hooks/routing-pretooluse.tsv" "$T/hooks/routing-pretooluse.tsv"
    while IFS=$'\t' read -r m s rest; do
        [[ -z "$m" || "$m" == \#* ]] && continue
        mkdir -p "$T/$(dirname "${s%% *}")"
        printf '#!/usr/bin/env bash\necho %s >> %s/log\n' "$(basename "${s%% *}")" "$T" > "$T/${s%% *}"
    done < "$REPO/hooks/routing-pretooluse.tsv"
}
@test "tabla real: una herramienta MCP dispara mcp-effect-guard y no los guardas de Bash" {
    spy_tree
    run bash "$D" <<< '{"tool_name":"mcp__github__create_pull_request","tool_input":{}}'
    [ "$status" -eq 0 ]
    grep -qx mcp-effect-guard.sh "$T/log"
    run grep -cx block-force-push.sh "$T/log"; [ "$output" = "0" ]
}
@test "tabla real: Bash dispara block-force-push y agent-git-discipline una sola vez" {
    spy_tree
    run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]
    grep -qx block-force-push.sh "$T/log"
    [ "$(grep -cx agent-git-discipline.sh "$T/log")" -eq 1 ]
    run grep -cx mcp-effect-guard.sh "$T/log"; [ "$output" = "0" ]
}
@test "tabla real: los hooks async de settings.json son bloqueante=no y el resto yes" {
    run python3 "$BATS_TEST_DIRNAME/fixtures/se510-async-vs-table.py" "$REPO/.claude/settings.json" "$REPO/hooks/routing-pretooluse.tsv"
    [ "$status" -eq 0 ]
}
@test "AC-6: async:true en settings.json genera bloqueante=no (y sin async, yes)" {
    gen_tree
    python3 - "$T/.claude/settings.json" <<'P'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["hooks"]["PreToolUse"].append({"matcher": "Bash", "hooks": [
    {"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/asincrono.sh", "async": True},
    {"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/sincrono.sh"}]})
json.dump(s, open(p, "w"))
P
    run python3 "$T/scripts/dispatch-table.py" generate; [ "$status" -eq 0 ]
    [[ "$output" == *$'.claude/hooks/asincrono.sh\tspawn\tno\t'* ]]
    [[ "$output" == *$'.claude/hooks/sincrono.sh\tspawn\tyes\t'* ]]
}
@test "AC-6: matcher no despachable en un grupo command aborta (exit 2)" {
    gen_tree
    python3 - "$T/.claude/settings.json" <<'P'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["hooks"]["PreToolUse"][0]["matcher"] = "Bash(rm *)"
json.dump(s, open(p, "w"))
P
    run python3 "$T/scripts/dispatch-table.py" generate; [ "$status" -eq 2 ]
    [[ "$output" == *"matcher no despachable"* ]]
}
@test "AC-6: command con metacaracteres de shell aborta la generación (exit 2)" {
    gen_tree
    python3 - "$T/.claude/settings.json" <<'P'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = "\"$CLAUDE_PROJECT_DIR\"/a.sh && \"$CLAUDE_PROJECT_DIR\"/b.sh"
json.dump(s, open(p, "w"))
P
    run python3 "$T/scripts/dispatch-table.py" generate; [ "$status" -eq 2 ]
    [[ "$output" == *"no despachable"* ]]
}

# ── Revisión de la PR #1616 (ronda 2): SIGPIPE, kill, timeout, generador ──────
@test "P1: entrada de 200 KB y hook que sale 0 sin leer stdin -> 0 (sin bloqueo falso por SIGPIPE)" {
    mkhook ok 'exit 0'; row Bash ok
    python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"x"*200000}}))' > "$T/big.json"
    run bash "$D" < "$T/big.json"; [ "$status" -eq 0 ]
}
@test "P1: la entrada de 200 KB llega íntegra al hook que sí la lee" {
    mkhook eco "cat > $T/visto"; row Bash eco
    python3 -c 'import json,sys; sys.stdout.write(json.dumps({"tool_name":"Bash","tool_input":{"command":"y"*200000}}))' > "$T/big.json"
    run bash "$D" < "$T/big.json"; [ "$status" -eq 0 ]
    cmp -s "$T/big.json" "$T/visto"
}
@test "P2: hook que ignora TERM se mata con KILL y bloquea (no cuelga)" {
    mkhook terco "trap '' TERM; sleep 30"; row Bash terco
    start=$SECONDS
    DISPATCH_HOOK_TIMEOUT=1 run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"tiempo agotado"* ]]
    [ $((SECONDS - start)) -lt 15 ]
}
@test "P2: DISPATCH_HOOK_TIMEOUT=0 (sin límite) -> 2" {
    mkhook ok 'exit 0'; row Bash ok
    DISPATCH_HOOK_TIMEOUT=0 run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    [[ "$output" == *"DISPATCH_HOOK_TIMEOUT inválido"* ]]
}
@test "P2: DISPATCH_HOOK_TIMEOUT no numérico o > 100 -> 2" {
    mkhook ok 'exit 0'; row Bash ok
    DISPATCH_HOOK_TIMEOUT=abc run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
    DISPATCH_HOOK_TIMEOUT=101 run bash "$D" <<< "$IN"; [ "$status" -eq 2 ]
}
@test "límite: DISPATCH_HOOK_TIMEOUT=100 es válido" {
    mkhook ok 'exit 0'; row Bash ok
    DISPATCH_HOOK_TIMEOUT=100 run bash "$D" <<< "$IN"; [ "$status" -eq 0 ]
}
@test "AC-6: timeout no numérico en settings.json -> exit 2 (no 1 ni traza)" {
    gen_tree
    python3 - "$T/.claude/settings.json" <<'P'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["hooks"]["PreToolUse"][0]["hooks"][0]["timeout"] = "diez"
json.dump(s, open(p, "w"))
P
    run python3 "$T/scripts/dispatch-table.py" check; [ "$status" -eq 2 ]
    [[ "$output" == *"timeout no numérico"* ]]
}
@test "AC-6: grupo PreToolUse que no es un objeto -> exit 2" {
    gen_tree
    python3 - "$T/.claude/settings.json" <<'P'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["hooks"]["PreToolUse"].append("Bash")
json.dump(s, open(p, "w"))
P
    run python3 "$T/scripts/dispatch-table.py" check; [ "$status" -eq 2 ]
}
@test "AC-6: ruta de hook con '..' aborta la generación (exit 2)" {
    gen_tree
    python3 - "$T/.claude/settings.json" <<'P'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = "\"$CLAUDE_PROJECT_DIR\"/../fuera/x.sh"
json.dump(s, open(p, "w"))
P
    run python3 "$T/scripts/dispatch-table.py" generate; [ "$status" -eq 2 ]
    [[ "$output" == *"'..'"* ]]
}
@test "tabla real: todo hook tiene shebang de bash (el despachador lo lanza con bash)" {
    while IFS=$'\t' read -r m s rest; do
        [[ -z "$m" || "$m" == \#* ]] && continue
        head -1 "$REPO/${s%% *}" | grep -Eq '^#!(/usr/bin/env bash|/bin/bash|/usr/bin/bash)' \
            || { echo "shebang no bash: $s"; false; }
    done < "$REPO/hooks/routing-pretooluse.tsv"
}
