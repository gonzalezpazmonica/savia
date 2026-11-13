#!/usr/bin/env bats
# test-se532-agent-catalog.bats — SE-532 S1: esquema de cabecera y referencias cruzadas.
# Cada regla R1..R10 tiene un caso negativo sobre una copia mutada y su corrección que pasa.
# Spec: docs/specs/SE-532-catalogo-de-agentes-con-esquema-y-retirada.spec.md (rama de la PR #1550)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
VAL="$REPO_ROOT/scripts/validate-agent-catalog.py"

setup() {
  FX="$(mktemp -d)"
  mkdir -p "$FX/.opencode/agents/decision-trees" "$FX/.claude/agents" "$FX/config" \
           "$FX/contracts/capabilities" "$FX/scripts" "$FX/docs/rules/domain" "$FX/.opencode/commands"
  cp "$REPO_ROOT/config/agent-frontmatter.schema.json" "$FX/config/"
  mk_agent alpha
  mk_agent beta
  printf 'judges:\n  - agent: alpha\n    mode: auto\n' > "$FX/config/judge-routing.yaml"
  printf 'protected_agents:\n  - alpha\n\nautonomous_modes:\n  - overnight-sprint\n' > "$FX/.opencode/protected-jobs.yaml"
  printf 'id: agent.alpha\nversion: 1\n' > "$FX/contracts/capabilities/agent.alpha.yaml"
  printf 'El revisor dijo que alpha es útil.\n' > "$FX/docs/rules/domain/prosa.md"
  git -C "$FX" init -q
  git -C "$FX" config user.email t@example.com
  git -C "$FX" config user.name t
  set_base
}

teardown() { rm -rf "$FX"; }

mk_agent() {  # mk_agent <nombre>
  printf -- '---\nname: %s\ndescription: Agente de prueba\nmodel_tier: mid\npermission_level: L1\ntools:\n  read: true\n  bash: false\n---\n# %s\n' \
    "$1" "$1" > "$FX/.opencode/agents/$1.md"
}

run_val() { run python3 "$VAL" --root "$FX" --skip-steps "$@"; }

# Fija origin/main del fixture en el HEAD actual (la base de las excepciones).
set_base() {
  git -C "$FX" add -A
  git -C "$FX" commit -q -m base
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
}

# ── Catálogo real ────────────────────────────────────────────────────────────
@test "catálogo real: pasa con las excepciones congeladas y los dos pasos delegados" {
  base=origin/main
  git -C "$REPO_ROOT" rev-parse --verify -q "$base^{commit}" >/dev/null || base=HEAD
  AGENT_CATALOG_BASE_REF="$base" run python3 "$VAL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"errores: 0"* ]]
}

@test "catálogo real: la lista congelada tiene 19 líneas y ninguna es de un agente inexistente" {
  n=$(grep -cvE '^(#|$)' "$REPO_ROOT/docs/agent-catalog-exceptions.txt")
  [ "$n" -eq 19 ]
  while IFS='|' read -r agent _rest; do
    agent="${agent// /}"
    [ -f "$REPO_ROOT/.opencode/agents/$agent.md" ]
  done < <(grep -vE '^(#|$)' "$REPO_ROOT/docs/agent-catalog-exceptions.txt")
}

@test "fixture limpio pasa (sin excepciones y sin errores)" {
  run_val
  [ "$status" -eq 0 ]
  [[ "$output" == *"errores: 0"* ]]
}

# ── AC-1 y R1..R5 ────────────────────────────────────────────────────────────
@test "AC-1: clave desconocida falla nombrando el fichero y pasa al corregirla" {
  sed -i 's/^permission_level: L1/permision_level: L1/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R3 .opencode/agents/alpha.md:"* ]]
  [[ "$output" == *"permision_level"* ]]
  sed -i 's/^permision_level/permission_level/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 0 ]
}

@test "AC-1: sin model_tier falla (R2) y pasa al añadirlo" {
  sed -i '/^model_tier:/d' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R2 .opencode/agents/alpha.md"* ]]
  [[ "$output" == *"model_tier"* ]]
  sed -i 's/^description:/model_tier: fast\ndescription:/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 0 ]
}

@test "AC-1/R4: tools como lista falla y como mapa pasa" {
  printf -- '---\nname: alpha\ndescription: x\nmodel_tier: mid\npermission_level: L1\ntools: [read, bash]\n---\n' > "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R4 .opencode/agents/alpha.md"* ]]
  mk_agent alpha
  run_val
  [ "$status" -eq 0 ]
}

@test "R4: tools con un valor que no es booleano falla" {
  sed -i 's/^  bash: false/  bash: "no"/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R4 .opencode/agents/alpha.md"* ]]
}

@test "R2: model_tier con un identificador de modelo falla (tiers en fuente, no modelos)" {
  sed -i 's/^model_tier: mid/model_tier: claude-sonnet-5-5/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R2 .opencode/agents/alpha.md"* ]]
  [[ "$output" == *"claude-sonnet-5-5"* ]]
}

@test "R2: permission_level fuera de L0..L4 y description vacía fallan" {
  sed -i 's/^permission_level: L1/permission_level: L9/' "$FX/.opencode/agents/alpha.md"
  sed -i 's/^description: .*/description: ""/' "$FX/.opencode/agents/beta.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"alpha.md"*"permission_level"* ]]
  [[ "$output" == *"beta.md"*"description"* ]]
}

@test "R2: límite de entero: maxTurns 0 falla y 1 pasa" {
  sed -i 's/^---$/---/;0,/^---$/!b' "$FX/.opencode/agents/alpha.md"
  sed -i 's/^tools:/maxTurns: 0\ntools:/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"maxTurns"* ]]
  sed -i 's/^maxTurns: 0/maxTurns: 1/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 0 ]
}

@test "R1: fichero sin cabecera falla" {
  printf '# alpha sin cabecera\n' > "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1 .opencode/agents/alpha.md:1"* ]]
}

@test "R1: cabecera sin cerrar falla" {
  printf -- '---\nname: alpha\ndescription: x\n' > "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1 .opencode/agents/alpha.md"*"sin cerrar"* ]]
}

@test "R1: cabecera vacía falla" {
  printf -- '---\n---\n# vacío\n' > "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1 .opencode/agents/alpha.md"* ]]
}

@test "R1: clave duplicada falla" {
  sed -i 's/^model_tier: mid/model_tier: mid\nmodel_tier: fast/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1 .opencode/agents/alpha.md"*"duplicada"* ]]
}

@test "R1: YAML inválido (dos puntos sin comillas) falla" {
  sed -i 's/^description: .*/description: Usar cuando: pasa algo/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1 .opencode/agents/alpha.md"* ]]
}

@test "R5: name distinto del fichero falla; con mayúsculas también" {
  sed -i 's/^name: alpha/name: Alpha/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R5 .opencode/agents/alpha.md"* ]]
  sed -i 's/^name: Alpha/name: alpha/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 0 ]
}

# ── R6..R9 ───────────────────────────────────────────────────────────────────
@test "R6: fila de routing con un agente inexistente falla y pasa al corregirla" {
  printf 'judges:\n  - agent: alpha\n    mode: auto\n  - agent: fantasma\n    mode: auto\n' > "$FX/config/judge-routing.yaml"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R6 config/judge-routing.yaml:4"*"fantasma"* ]]
  printf 'judges:\n  - agent: alpha\n    mode: auto\n' > "$FX/config/judge-routing.yaml"
  run_val
  [ "$status" -eq 0 ]
}

@test "R7: protected_agents con un agente inexistente falla" {
  printf 'protected_agents:\n  - alpha\n  - fantasma\n' > "$FX/.opencode/protected-jobs.yaml"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R7 .opencode/protected-jobs.yaml:3"*"fantasma"* ]]
}

@test "R7: protected-jobs ilegible falla (fail-closed)" {
  printf 'protected_agents: [alpha\n' > "$FX/.opencode/protected-jobs.yaml"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R7 .opencode/protected-jobs.yaml"* ]]
}

@test "R8: contrato sin agente falla" {
  printf 'id: agent.fantasma\n' > "$FX/contracts/capabilities/agent.fantasma.yaml"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R8 contracts/capabilities/agent.fantasma.yaml"* ]]
}

@test "R8: contrato con id incoherente falla y pasa al corregirlo" {
  printf 'id: agent.otro\n' > "$FX/contracts/capabilities/agent.alpha.yaml"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R8 contracts/capabilities/agent.alpha.yaml:1"* ]]
  printf 'id: agent.alpha\n' > "$FX/contracts/capabilities/agent.alpha.yaml"
  run_val
  [ "$status" -eq 0 ]
}

@test "R9: decision_tree que apunta a un fichero inexistente falla y pasa al crearlo" {
  sed -i 's/^tools:/decision_tree: decision-trees\/alpha-decisions.md\ntools:/' "$FX/.opencode/agents/alpha.md"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"R9 .opencode/agents/alpha.md"*"alpha-decisions.md"* ]]
  printf '# arbol\n' > "$FX/.opencode/agents/decision-trees/alpha-decisions.md"
  run_val
  [ "$status" -eq 0 ]
}

# ── R10 / AC-6 ───────────────────────────────────────────────────────────────
@test "R10: agente retirado que aún tiene fichero falla (opencode y espejo)" {
  cp "$FX/.opencode/agents/beta.md" "$FX/.claude/agents/beta.md"
  run_val --retired beta
  [ "$status" -eq 1 ]
  [[ "$output" == *"R10 .opencode/agents/beta.md"* ]]
  [[ "$output" == *"R10 .claude/agents/beta.md"* ]]
}

@test "R10: retirado citado en subagent_type de un comando falla con fichero y línea" {
  printf 'uno\nUsa subagent_type: beta para revisar\n' > "$FX/.opencode/commands/revisar.md"
  rm "$FX/.opencode/agents/beta.md"
  run_val --retired beta
  [ "$status" -eq 1 ]
  [[ "$output" == *"R10 .opencode/commands/revisar.md:2"* ]]
}

@test "R10: retirado en routing, protegidos, contrato y allowlist falla por cada origen" {
  rm "$FX/.opencode/agents/alpha.md"
  printf '| `alpha` | .opencode only | x |\n' > "$FX/docs/agents-sync-allowlist.md"
  run_val --retired alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"R10 config/judge-routing.yaml"* ]]
  [[ "$output" == *"R10 .opencode/protected-jobs.yaml"* ]]
  [[ "$output" == *"R10 contracts/capabilities/agent.alpha.yaml"* ]]
  [[ "$output" == *"R10 docs/agents-sync-allowlist.md"* ]]
}

@test "R10: nombre literal en scripts/ cuenta" {
  rm "$FX/.opencode/agents/beta.md"
  printf '#!/bin/bash\norphans=("beta")\n' > "$FX/scripts/lista.sh"
  run_val --retired beta
  [ "$status" -eq 1 ]
  [[ "$output" == *"R10 scripts/lista.sh:2"* ]]
}

@test "R10: la prosa con la palabra común no cuenta; limpio pasa (AC-6)" {
  mk_agent revisor
  rm "$FX/.opencode/agents/revisor.md"
  printf 'El revisor dijo que alpha es útil. El revisor es una persona.\n' > "$FX/docs/rules/domain/prosa.md"
  run_val --retired revisor
  [ "$status" -eq 0 ]
}

@test "R10: la historia (CHANGELOG, specs-archive) no cuenta" {
  rm "$FX/.opencode/agents/beta.md"
  mkdir -p "$FX/docs/specs-archive"
  printf 'subagent_type: beta\n' > "$FX/CHANGELOG.md"
  printf 'subagent_type: beta\n' > "$FX/docs/specs-archive/x.md"
  run_val --retired beta
  [ "$status" -eq 0 ]
}

@test "R10: metacaracteres de expresión regular se buscan como texto literal" {
  printf 'subagent_type: a.b\nsubagent_type: axb\n' > "$FX/.opencode/commands/c.md"
  run_val --retired axb
  [ "$status" -eq 1 ]
  [[ "$output" == *"R10 .opencode/commands/c.md:2"* ]]
  [[ "$output" != *"c.md:1"* ]]
  printf 'subagent_type: axb\n' > "$FX/.opencode/commands/c.md"
  run_val --retired 'a.b'
  [ "$status" -eq 0 ]
  run_val --retired 'a.*'
  [ "$status" -eq 0 ]
  run_val --retired '[a-z]+'
  [ "$status" -eq 0 ]
}

@test "R10: metacaracteres también son literales en el escaneo de scripts/" {
  printf '#!/bin/bash\necho axb\n' > "$FX/scripts/lista.sh"
  run_val --retired 'a.b'
  [ "$status" -eq 0 ]
  run_val --retired 'a.*'
  [ "$status" -eq 0 ]
  run_val --retired axb
  [ "$status" -eq 1 ]
  [[ "$output" == *"R10 scripts/lista.sh:2"* ]]
}

@test "R10: un nombre que empieza por - es un nombre, no una opción" {
  printf 'subagent_type: -x\n' > "$FX/.opencode/commands/c.md"
  run_val --retired -x
  [ "$status" -eq 1 ]
  [[ "$output" == *"R10 .opencode/commands/c.md:1"* ]]
}

@test "R10: --retired sin nombres es error de uso (2)" {
  run_val --retired
  [ "$status" -eq 2 ]
}

# ── Excepciones congeladas (AC-4) ────────────────────────────────────────────
@test "AC-4: sin fichero de excepciones ni base, un incumplimiento falla; --freeze lo congela y pasa" {
  sed -i 's/^tools:/ref: x\ntools:/' "$FX/.opencode/agents/alpha.md"
  set_base
  git -C "$FX" update-ref -d refs/remotes/origin/main
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
  run_val
  [ "$status" -eq 1 ]
  run_val --freeze
  [ "$status" -eq 0 ]
  grep -q '^alpha | R3 | ref |' "$FX/docs/agent-catalog-exceptions.txt"
  run_val
  [ "$status" -eq 0 ]
  [[ "$output" == *"excepciones congeladas aplicadas: 1"* ]]
}

@test "AC-4: --freeze no sobrescribe un fichero existente" {
  mkdir -p "$FX/docs"
  printf '# x\n' > "$FX/docs/agent-catalog-exceptions.txt"
  run_val --freeze
  [ "$status" -eq 2 ]
}

@test "AC-4: una excepción nueva respecto a la base falla" {
  sed -i 's/^tools:/ref: x\ntools:/' "$FX/.opencode/agents/alpha.md"
  mkdir -p "$FX/docs"
  printf '# vacío\n' > "$FX/docs/agent-catalog-exceptions.txt"
  set_base
  printf 'alpha | R3 | ref | 2026-11-13 | motivo\n' >> "$FX/docs/agent-catalog-exceptions.txt"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"excepción nueva respecto a origin/main"* ]]
}

@test "AC-4: una excepción obsoleta falla" {
  mkdir -p "$FX/docs"
  printf 'alpha | R3 | ref | 2026-11-13 | motivo\n' > "$FX/docs/agent-catalog-exceptions.txt"
  set_base
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"excepción obsoleta"* ]]
}

@test "AC-4: una excepción de un agente retirado falla" {
  mkdir -p "$FX/docs"
  printf 'fantasma | R3 | ref | 2026-11-13 | motivo\n' > "$FX/docs/agent-catalog-exceptions.txt"
  set_base
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"agente inexistente o retirado 'fantasma'"* ]]
}

@test "AC-4: excepción vigente en la base y sin cambios pasa (caso límite: encoger no falla)" {
  sed -i 's/^tools:/ref: x\ntools:/' "$FX/.opencode/agents/alpha.md"
  sed -i 's/^tools:/tags: y\ntools:/' "$FX/.opencode/agents/beta.md"
  mkdir -p "$FX/docs"
  printf 'alpha | R3 | ref | 2026-11-13 | m\nbeta | R3 | tags | 2026-11-13 | m\n' > "$FX/docs/agent-catalog-exceptions.txt"
  set_base
  run_val
  [ "$status" -eq 0 ]
  # encoger: se arregla beta y se quita su línea
  sed -i '/^tags:/d' "$FX/.opencode/agents/beta.md"
  sed -i '/^beta /d' "$FX/docs/agent-catalog-exceptions.txt"
  run_val
  [ "$status" -eq 0 ]
}

@test "AC-4: un fichero de excepciones borrado, existiendo en la base, falla" {
  mkdir -p "$FX/docs"
  printf '# vacío\n' > "$FX/docs/agent-catalog-exceptions.txt"
  set_base
  rm "$FX/docs/agent-catalog-exceptions.txt"
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta aquí"* ]]
}

@test "AC-4: si no se puede leer la base (sin origin/main) falla, no se trata como fichero ausente" {
  git -C "$FX" update-ref -d refs/remotes/origin/main
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se puede leer origin/main"* ]]
}

@test "AC-4: línea de excepciones mal formada o de una regla que no admite excepción falla" {
  mkdir -p "$FX/docs"
  printf 'alpha | R5 | name | 2026-11-13 | m\nsolo-dos | campos\n' > "$FX/docs/agent-catalog-exceptions.txt"
  set_base
  run_val
  [ "$status" -eq 1 ]
  [[ "$output" == *"no admite excepciones"* ]]
  [[ "$output" == *"mal formada"* ]]
}

# ── Entorno (AC-5) ───────────────────────────────────────────────────────────
@test "AC-5: sin PyYAML sale 2, nunca 0" {
  stub="$(mktemp -d)"
  printf 'raise ImportError("sin yaml")\n' > "$stub/yaml.py"
  PYTHONPATH="$stub" run python3 "$VAL" --root "$FX" --skip-steps
  rm -rf "$stub"
  [ "$status" -eq 2 ]
  [[ "$output" == *"PyYAML"* ]]
}

@test "AC-5: sin directorio de agentes sale 2" {
  rm -rf "$FX/.opencode/agents"
  run_val
  [ "$status" -eq 2 ]
}

@test "AC-5: sin esquema o con esquema ilegible sale 2" {
  rm "$FX/config/agent-frontmatter.schema.json"
  run_val
  [ "$status" -eq 2 ]
  printf '{no es json' > "$FX/config/agent-frontmatter.schema.json"
  run_val
  [ "$status" -eq 2 ]
}

@test "argumento desconocido sale 2" {
  run_val --no-existe
  [ "$status" -eq 2 ]
}

# ── Pasos delegados (SE-253 y SE-273) ────────────────────────────────────────
@test "pasos: un paso delegado que falla hace fallar el validador y se reporta" {
  printf '#!/bin/bash\necho "VERDICT: FAIL"\nexit 1\n' > "$FX/scripts/agents-catalog-sync.sh"
  printf '#!/bin/bash\nexit 0\n' > "$FX/scripts/judge-routing-verify.sh"
  run python3 "$VAL" --root "$FX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STEP scripts/agents-catalog-sync.sh"* ]]
}

@test "pasos: los dos pasos en verde y el catálogo limpio pasan" {
  printf '#!/bin/bash\nexit 0\n' > "$FX/scripts/agents-catalog-sync.sh"
  printf '#!/bin/bash\nexit 0\n' > "$FX/scripts/judge-routing-verify.sh"
  run python3 "$VAL" --root "$FX"
  [ "$status" -eq 0 ]
}

@test "pasos: un paso delegado ausente falla (fail-closed)" {
  run python3 "$VAL" --root "$FX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"paso delegado ausente"* ]]
}

# ── AC-7 / selección de CI ───────────────────────────────────────────────────
@test "AC-7: la PR no toca agentes, protegidos, routing ni ci.yml" {
  base=origin/main
  git -C "$REPO_ROOT" rev-parse --verify -q "$base^{commit}" >/dev/null || skip "sin origin/main para comparar"
  changed=$(git -C "$REPO_ROOT" diff --name-only "$base"...HEAD)
  [[ "$changed" != *".opencode/agents/"* ]]
  [[ "$changed" != *".claude/agents/"* ]]
  [[ "$changed" != *".opencode/protected-jobs.yaml"* ]]
  [[ "$changed" != *"config/judge-routing.yaml"* ]]
  [[ "$changed" != *".github/workflows/ci.yml"* ]]
}

@test "selección de CI: cambiar un agente, el esquema, el routing, los protegidos o un contrato selecciona este test" {
  run python3 - "$REPO_ROOT/tests/bats/.deps-rules.yaml" <<'PY'
import sys, yaml
t = "test-se532-agent-catalog.bats"
rules = {r.get("dir") or r.get("file"): r["tests"] for r in yaml.safe_load(open(sys.argv[1]))["rules"]}
need = [".opencode/agents/", "config/agent-frontmatter.schema.json", "config/judge-routing.yaml",
        ".opencode/protected-jobs.yaml", "contracts/capabilities/"]
missing = [d for d in need if t not in rules.get(d, [])]
print("FALTA: %s" % missing if missing else "OK")
sys.exit(1 if missing else 0)
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "OK" ]]
}
