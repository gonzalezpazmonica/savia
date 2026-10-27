#!/usr/bin/env bats
# test-se253-hooks-hygiene.bats — SE-253 Slice 5: Hook registry hygiene
# AC-5.1: No empty matchers in PreToolUse/PostToolUse
# AC-5.2: No orphan hooks in root dir
# AC-5.3: doc-counts-check.sh passes
# AC-5.4: HOOKS-STRATEGY.md lacks fossil count "69"

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SETTINGS="$REPO_ROOT/.claude/settings.json"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
HOOKS_STRATEGY="$REPO_ROOT/.opencode/HOOKS-STRATEGY.md"
DOC_COUNTS="$REPO_ROOT/scripts/doc-counts-check.sh"

@test "AC-5.1: settings.json has zero empty matchers in PreToolUse" {
  run python3 -c "
import json, sys
d = json.load(open('$SETTINGS'))
empty = [h for h in d.get('hooks',{}).get('PreToolUse',[]) if h.get('matcher','') == '']
if empty:
    print(f'FAIL: {len(empty)} empty matchers in PreToolUse')
    sys.exit(1)
print('PASS')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "AC-5.1: settings.json has zero empty matchers in PostToolUse" {
  run python3 -c "
import json, sys
d = json.load(open('$SETTINGS'))
empty = [h for h in d.get('hooks',{}).get('PostToolUse',[]) if h.get('matcher','') == '']
if empty:
    for h in empty:
        print('FAIL matcher empty:', h.get('hooks',[{}])[0].get('command','?')[:60])
    sys.exit(1)
print('PASS')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "AC-5.2: _legacy dir exists for deactivated hooks" {
  [ -d "$HOOKS_DIR/_legacy" ]
}

@test "AC-5.2: recommendation-tribunal-pre-output.sh is in _legacy (PreOutput event unavailable)" {
  [ -f "$HOOKS_DIR/_legacy/recommendation-tribunal-pre-output.sh" ]
}

@test "AC-5.2: recommendation-tribunal-pre-output.sh NOT in active hooks root" {
  [ ! -f "$HOOKS_DIR/recommendation-tribunal-pre-output.sh" ]
}

@test "AC-5.2: recommendation-tribunal-followup.sh is registered in settings.json" {
  grep -q "recommendation-tribunal-followup.sh" "$SETTINGS"
}

@test "AC-5.2: twin-posttooluse.sh is registered in settings.json" {
  grep -q "twin-posttooluse.sh" "$SETTINGS"
}

@test "AC-5.2: twin-posttooluse.sh has non-empty matcher" {
  run python3 -c "
import json
d = json.load(open('$SETTINGS'))
for event_hooks in d.get('hooks',{}).values():
    if not isinstance(event_hooks, list): continue
    for h in event_hooks:
        for subh in h.get('hooks',[]):
            if 'twin-posttooluse' in subh.get('command',''):
                if h.get('matcher','') == '':
                    print('FAIL: empty matcher')
                    exit(1)
                print('PASS: matcher=' + repr(h.get('matcher')))
                exit(0)
print('hook not found — skip')
"
  [[ "$output" != *"FAIL"* ]]
}

@test "AC-5.3: scripts/doc-counts-check.sh exists and is executable" {
  [ -f "$DOC_COUNTS" ]
  [ -x "$DOC_COUNTS" ]
}

@test "AC-5.3: doc-counts-check.sh passes on current repo state" {
  run bash "$DOC_COUNTS" --warn
  [ "$status" -eq 0 ]
}

@test "AC-5.4: HOOKS-STRATEGY.md does not declare '69 hooks' (fossilized count)" {
  run grep -c "69 hooks" "$HOOKS_STRATEGY"
  [ "$status" -ne 0 ] || [ "$output" -eq 0 ]
}

@test "AC-5.4: _legacy README exists to document deactivated hooks" {
  [ -f "$HOOKS_DIR/_legacy/README.md" ]
}

# ── Comportamiento con árbol sintético (SE-456) ───────────────────────────────
# El script deduce la raíz de su propia ruta: se copia a un árbol temporal con
# hooks, agentes y documentos declarados a mano.

dc_root() {  # dc_root <hooks reales> <agentes reales> <hooks declarados> <agentes declarados>
  T="$(mktemp -d)"
  mkdir -p "$T/scripts" "$T/.claude/hooks" "$T/.opencode/agents"
  cp "$DOC_COUNTS" "$T/scripts/doc-counts-check.sh"
  local i
  for ((i = 1; i <= $1; i++)); do echo "#!/bin/sh" > "$T/.claude/hooks/h$i.sh"; done
  for ((i = 1; i <= $2; i++)); do echo "# a" > "$T/.opencode/agents/a$i.md"; done
  printf '# Estrategia\nHay %s hooks registrados y 3 hooks más.\n' "$3" > "$T/.opencode/HOOKS-STRATEGY.md"
  printf '# Agentes\nEl equipo tiene %s agents y 5 agents opcionales.\n' "$4" > "$T/AGENTS.md"
  echo '{"hooks":{}}' > "$T/.claude/settings.json"
}

teardown() { [[ -n "${T:-}" ]] && rm -rf "$T"; true; }

@test "doc-counts: declarado igual al real → OK en hooks y agentes, exit 0 también con --check" {
  dc_root 5 4 5 4
  run bash "$T/scripts/doc-counts-check.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: hooks count — declared=5 real=5"* ]]
  [[ "$output" == *"OK: agents count — declared=4 real=4"* ]]
  [[ "$output" != *"DIFF"* ]]
}

@test "doc-counts: la tolerancia es ±2 y 3 de diferencia ya es DIFF" {
  dc_root 7 4 5 4
  run bash "$T/scripts/doc-counts-check.sh" --warn
  [[ "$output" == *"OK: hooks count — declared=5 real=7 (within tolerance"* ]]
  dc_root 3 4 5 4
  run bash "$T/scripts/doc-counts-check.sh" --warn
  [[ "$output" == *"OK: hooks count — declared=5 real=3"* ]]
  dc_root 8 4 5 4
  run bash "$T/scripts/doc-counts-check.sh" --warn
  [[ "$output" == *"DIFF: HOOKS-STRATEGY.md declares 5 hooks, disk has 8 (diff: 3)"* ]]
  dc_root 5 1 5 4
  run bash "$T/scripts/doc-counts-check.sh" --warn
  [[ "$output" == *"DIFF: AGENTS.md declares 4 agents, disk has 1 (diff: -3)"* ]]
}

@test "doc-counts: --warn (y por defecto) imprime el DIFF pero sale 0; --check sale 1" {
  dc_root 10 4 5 4
  run bash "$T/scripts/doc-counts-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIFF: HOOKS-STRATEGY.md"* ]]
  run bash "$T/scripts/doc-counts-check.sh" --warn
  [ "$status" -eq 0 ]
  run bash "$T/scripts/doc-counts-check.sh" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIFF: HOOKS-STRATEGY.md declares 5 hooks, disk has 10 (diff: 5)"* ]]
}

@test "doc-counts: --check también falla si solo difieren los agentes" {
  dc_root 5 9 5 4
  run bash "$T/scripts/doc-counts-check.sh" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIFF: AGENTS.md declares 4 agents, disk has 9 (diff: 5)"* ]]
  [[ "$output" == *"OK: hooks count"* ]]
}

@test "doc-counts: --fix reescribe solo el primer número declarado y deja el resto del texto" {
  dc_root 10 9 5 4
  run bash "$T/scripts/doc-counts-check.sh" --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIXED: HOOKS-STRATEGY.md now declares 10 hooks"* ]]
  [[ "$output" == *"FIXED: AGENTS.md now declares 9 agents"* ]]
  grep -q "Hay 10 hooks registrados y 3 hooks más." "$T/.opencode/HOOKS-STRATEGY.md"
  grep -q "El equipo tiene 9 agents y 5 agents opcionales." "$T/AGENTS.md"
  # tras corregir, --check ya no encuentra diferencias
  run bash "$T/scripts/doc-counts-check.sh" --check
  [ "$status" -eq 0 ]
}

@test "doc-counts: --fix conserva la palabra 'registered' y no toca documentos ya correctos" {
  dc_root 10 4 5 4
  printf 'Total: 5 registered hooks\n' > "$T/.opencode/HOOKS-STRATEGY.md"
  before="$(cat "$T/AGENTS.md")"
  run bash "$T/scripts/doc-counts-check.sh" --fix
  [ "$status" -eq 0 ]
  [ "$(cat "$T/.opencode/HOOKS-STRATEGY.md")" = "Total: 10 registered hooks" ]
  [ "$(cat "$T/AGENTS.md")" = "$before" ]
}

@test "doc-counts: modo desconocido → exit 2 y no modifica nada" {
  dc_root 10 9 5 4
  before="$(cat "$T/AGENTS.md")"
  run bash "$T/scripts/doc-counts-check.sh" --reparar
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown mode '--reparar'"* ]]
  [ "$(cat "$T/AGENTS.md")" = "$before" ]
}

@test "doc-counts: sin hooks .sh en disco no aborta y cuenta 0" {
  dc_root 0 4 5 4
  run bash "$T/scripts/doc-counts-check.sh" --warn
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIFF: HOOKS-STRATEGY.md declares 5 hooks, disk has 0"* ]]
  [[ "$output" == *"OK: agents count"* ]]
}

@test "doc-counts: sin número declarado ('unknown') no se compara ni falla con --check" {
  dc_root 5 4 5 4
  echo "Sin cifras aquí" > "$T/.opencode/HOOKS-STRATEGY.md"
  echo "Tampoco aquí" > "$T/AGENTS.md"
  run bash "$T/scripts/doc-counts-check.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" != *"hooks count"* ]]
  [[ "$output" != *"agents count"* ]]
}

@test "doc-counts: sin AGENTS.md ni HOOKS-STRATEGY.md no hay salida de comparación" {
  dc_root 5 4 5 4
  rm "$T/AGENTS.md" "$T/.opencode/HOOKS-STRATEGY.md"
  run bash "$T/scripts/doc-counts-check.sh" --check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "doc-counts: los agentes cuentan solo .md del primer nivel" {
  dc_root 5 3 5 3
  mkdir -p "$T/.opencode/agents/references"
  echo x > "$T/.opencode/agents/references/r.md"
  echo x > "$T/.opencode/agents/notas.txt"
  run bash "$T/scripts/doc-counts-check.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: agents count — declared=3 real=3"* ]]
}
