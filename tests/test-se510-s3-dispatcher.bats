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
@test "el despachador real, con la tabla real, permite o bloquea con motivo (nunca error mudo)" {
    run bash "$REPO/hooks/dispatchers/dispatch-pretooluse.sh" <<< "$IN"
    [ "$status" -eq 0 ] || { [ "$status" -eq 2 ] && [[ "$output" == *"dispatch-pretooluse"* ]]; }
}
