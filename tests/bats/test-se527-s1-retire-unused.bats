#!/usr/bin/env bats
# SE-527 S1 — retirar sin uso: fiction-framing-judge, structural-framing-judge,
# tabular-analyst y configurator (90 → 86).
# Spec: docs/specs/SE-527-recorte-de-agentes-sobrantes.spec.md (AC-S0, AC-S1, AC-S2, AC-S5, AC-S6)

RETIRED=(fiction-framing-judge structural-framing-judge tabular-analyst configurator)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CHECKER="$REPO_ROOT/tests/se527_retired_refs.py"
  VERIFY="$REPO_ROOT/scripts/judge-routing-verify.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Copia mínima del repo para los casos negativos: solo lo que el comprobador escanea aquí.
mini_root() {
  mkdir -p "$TMP/root/.opencode/agents" "$TMP/root/scripts" "$TMP/root/docs/specs" "$TMP/root/docs/rules"
  printf -- '---\nname: architect\n---\n' > "$TMP/root/.opencode/agents/architect.md"
  printf '# limpio\nUn configurador de prosa no cuenta.\n' > "$TMP/root/docs/rules/ok.md"
}

# ── AC-S0: sin ficheros ni referencias vivas ─────────────────────────────

@test "AC-S0: los cuatro agentes retirados no tienen fichero en .opencode ni en .claude" {
  for n in "${RETIRED[@]}"; do
    [ ! -e "$REPO_ROOT/.opencode/agents/$n.md" ]
    [ ! -e "$REPO_ROOT/.claude/agents/$n.md" ]
  done
}

@test "AC-S0: ninguna referencia viva a los agentes retirados en el repo" {
  run python3 "$CHECKER" --root "$REPO_ROOT" "${RETIRED[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: 0 referencia"* ]]
}

@test "AC-S0 negativo: el comprobador falla si se reintroduce una fila de tabla" {
  mini_root
  printf '| configurator | fast | L1 |\n' > "$TMP/root/docs/rules/catalog.md"
  run python3 "$CHECKER" --root "$TMP/root" configurator
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/rules/catalog.md:1"* ]]
}

@test "AC-S0 negativo: el comprobador falla con subagent_type y con agent: en YAML" {
  mini_root
  printf 'subagent_type: "tabular-analyst"\n' > "$TMP/root/docs/rules/a.md"
  printf '  - agent: fiction-framing-judge\n' > "$TMP/root/docs/rules/b.yaml"
  run python3 "$CHECKER" --root "$TMP/root" tabular-analyst fiction-framing-judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/rules/a.md:1"* ]]
  [[ "$output" == *"docs/rules/b.yaml:1"* ]]
}

@test "AC-S0 negativo: el comprobador falla si vuelve el fichero del agente" {
  mini_root
  printf -- '---\nname: structural-framing-judge\n---\n' > "$TMP/root/.opencode/agents/structural-framing-judge.md"
  run python3 "$CHECKER" --root "$TMP/root" structural-framing-judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"fichero del agente retirado"* ]]
}

@test "AC-S0 negativo: en scripts/ basta el nombre literal" {
  mini_root
  printf 'case "$x" in *-orchestrator|configurator) ;; esac\n' > "$TMP/root/scripts/x.sh"
  run python3 "$CHECKER" --root "$TMP/root" configurator
  [ "$status" -eq 1 ]
  [[ "$output" == *"scripts/x.sh:1"* ]]
}

@test "AC-S0 límite: la historia (specs) y la prosa con palabra común no cuentan" {
  mini_root
  printf '| configurator | historia |\n' > "$TMP/root/docs/specs/SE-1.spec.md"
  printf 'El reconciler de prosa y un configurator genérico.\n' > "$TMP/root/docs/rules/prosa.md"
  run python3 "$CHECKER" --root "$TMP/root" configurator
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "AC-S0 fail-closed: fichero no legible como UTF-8 no se da por limpio" {
  mini_root
  printf 'ok \xc3\n' > "$TMP/root/docs/rules/roto.md"
  run python3 "$CHECKER" --root "$TMP/root" configurator
  [ "$status" -eq 1 ]
  [[ "$output" == *"no legible"* ]]
}

@test "AC-S0 uso: sin nombres o sin .opencode/agents sale con 2" {
  run python3 "$CHECKER" --root "$REPO_ROOT"
  [ "$status" -eq 2 ]
  run python3 "$CHECKER" --root "$TMP" configurator
  [ "$status" -eq 2 ]
}

# ── Routing: fila sobrante falla (spec S1, validación a) ─────────────────

@test "routing: el verificador pasa sin las dos filas disabled retiradas" {
  run grep -qE 'agent: (fiction|structural)-framing-judge' "$REPO_ROOT/config/judge-routing.yaml"
  [ "$status" -eq 1 ]
  run bash "$VERIFY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "routing negativo: una fila sobrante sin fichero de agente hace fallar el verificador" {
  mkdir -p "$TMP/r/config"
  cp -r "$REPO_ROOT/.opencode" "$TMP/r/.opencode"
  cp "$REPO_ROOT/config/judge-routing.yaml" "$TMP/r/config/"
  printf '\n  - agent: zz-retired-judge\n    mode: disabled\n    rationale: "sobrante"\n' >> "$TMP/r/config/judge-routing.yaml"
  PROJECT_ROOT="$TMP/r" run bash "$VERIFY"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE ROW: zz-retired-judge"* ]]
  # La fila sobrante es el único error (y no un aviso más otro error ajeno).
  [[ "$output" =~ Errors:[[:space:]]+1$'\n' ]]
}

@test "routing negativo: un juez sin fila hace fallar el verificador" {
  mkdir -p "$TMP/r/config"
  cp -r "$REPO_ROOT/.opencode" "$TMP/r/.opencode"
  cp "$REPO_ROOT/config/judge-routing.yaml" "$TMP/r/config/"
  printf -- '---\nname: zz-new-judge\n---\n' > "$TMP/r/.opencode/agents/zz-new-judge.md"
  PROJECT_ROOT="$TMP/r" run bash "$VERIFY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING ROW: zz-new-judge"* ]]
}

# ── Sustitutos nombrados (spec S1, validación b) ─────────────────────────

@test "sustitutos: la skill tabular-intelligence y docs/RESOLVER.md existen y se citan" {
  [ -f "$REPO_ROOT/.claude/skills/tabular-intelligence/SKILL.md" ]
  grep -q 'skill:tabular-intelligence' "$REPO_ROOT/docs/RESOLVER.md"
  grep -q 'RESOLVER.md' "$REPO_ROOT/scripts/skill-suggest.sh"
}

@test "RESOLVER.md es UTF-8 válido (el truncado no parte caracteres)" {
  run python3 -c "open('$REPO_ROOT/docs/RESOLVER.md','rb').read().decode('utf-8')"
  [ "$status" -eq 0 ]
}

# ── AC-S1: recuentos ─────────────────────────────────────────────────────

@test "AC-S1: CLAUDE.md declara el nº real de agentes de .opencode/agents" {
  real=$(find "$REPO_ROOT/.opencode/agents" -maxdepth 1 -type f -name '*.md' ! -name README.md | wc -l)
  [ "$real" -eq 86 ]
  grep -q "agents(${real})" "$REPO_ROOT/CLAUDE.md"
  grep -q "Catálogo ${real} agentes" "$REPO_ROOT/CLAUDE.md"
  run grep -nE 'agents\(90\)|Catálogo 90 agentes' "$REPO_ROOT/CLAUDE.md"
  [ "$status" -eq 1 ]
}

# ── AC-S5 / AC-S6 ────────────────────────────────────────────────────────

@test "AC-S5: los seis agentes por lenguaje siguen en .opencode/agents" {
  for n in go java php ruby python typescript; do
    [ -f "$REPO_ROOT/.opencode/agents/${n}-developer.md" ]
  done
}

@test "AC-S6: las variantes congeladas de SE-511 siguen idénticas byte a byte" {
  run python3 - "$REPO_ROOT/tests/evals/se511-d4/variants" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
meta = json.load(open(os.path.join(d, "meta.json")))
bad = [v for v, m in meta.items()
       if hashlib.sha256(open(os.path.join(d, v + ".md"), "rb").read()).hexdigest() != m["sha256"]]
print("cambiadas:", bad)
sys.exit(1 if bad else 0)
PY
  echo "$output"
  [ "$status" -eq 0 ]
}
