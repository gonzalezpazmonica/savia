#!/usr/bin/env bats
# Ref: SE-527 S1, H1/H2 de la refutación de #1563; contrato TDD cruzado.
# Solo tests: ejecutar con bats tests/bats/test-se527-huecos-verificadores.bats.
# Estrategia: matrices de orden/sangría/comillas, cada despacho con su negativo
# de nombre parecido y regresión del árbol real. Sin copias del repo ni red.
# H1: JUDGE_ROUTING_FILE y JUDGE_AGENTS_DIR seleccionan entradas independientes
# de PROJECT_ROOT. H2: CLI --root ARBOL NOMBRE...; diagnóstico fichero:línea:
# por hallazgo (en multilínea se admite la línea de la clave o la del valor).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  VERIFY="$REPO_ROOT/scripts/judge-routing-verify.sh"
  CHECKER="$REPO_ROOT/tests/se527_retired_refs.py"
  TMP="$(mktemp -d)"
  ROOT="$TMP/root"
  ROUTING="$ROOT/config/judge-routing.yaml"
  AGENTS="$ROOT/.opencode/agents"
  mkdir -p "$AGENTS" "$ROOT/config" "$ROOT/.claude/commands"
  printf '# Agente ficticio\n' > "$AGENTS/fixture-judge.md"
  printf 'judges: []\n' > "$ROUTING"
  # Los nombres solo se insertan en los ficheros temporales: este test no
  # introduce despachos vivos de retirados en el árbol real que comprueba.
  RETIRED_NAME=configurator
  RETIRED=(fiction-framing-judge structural-framing-judge tabular-analyst configurator)
}

teardown() {
  rm -rf "$TMP"
}

# Las seis permutaciones de agent/mode/rationale se ejercitan con tres
# sangrías YAML válidas (incluida la secuencia sin sangrar) y tres comillas.
write_row() {
  local order="$1" indent="$2" quote="$3" name="$4" key prefix value
  prefix="${indent}- "
  for key in $order; do
    case "$key" in
      agent) value="${quote}${name}${quote}" ;;
      mode) value=disabled ;;
      rationale) value='"Fixture de contrato"' ;;
    esac
    printf '%s%s: %s\n' "$prefix" "$key" "$value"
    prefix="${indent}  "
  done
}

routing_matrix() {
  local order="$1" expected="$2" name indent quote
  name=fixture-judge
  if [[ "$expected" == stale ]]; then
    name=fixture-missing-judge
  fi
  for indent in '  ' '      ' ''; do
    for quote in '' "'" '"'; do
      printf 'judges:\n' > "$ROUTING"
      # Mantiene la paridad del juez existente también en los casos colgantes.
      if [[ "$expected" == stale ]]; then
        write_row 'agent mode rationale' "$indent" '' fixture-judge >> "$ROUTING"
      fi
      write_row "$order" "$indent" "$quote" "$name" >> "$ROUTING"
      run env PROJECT_ROOT="$ROOT" JUDGE_ROUTING_FILE="$ROUTING" \
        JUDGE_AGENTS_DIR="$AGENTS" bash "$VERIFY"
      printf 'orden=%s sangría=%s comillas=%s\n%s\n' "$order" "${#indent}" "$quote" "$output"
      if [[ "$expected" == stale ]]; then
        [ "$status" -ne 0 ]
        [[ "$output" == *"STALE ROW: $name"* ]]
      else
        [ "$status" -eq 0 ]
        [[ "$output" == *"PASS"* ]]
        [[ "$output" != *"STALE ROW:"* ]]
      fi
    done
  done
}

@test "H1 válido: agent mode rationale, sangría y comillas" {
  routing_matrix 'agent mode rationale' valid
}
@test "H1 error: agent mode rationale, sangría y comillas" {
  routing_matrix 'agent mode rationale' stale
}
@test "H1 válido: agent rationale mode, sangría y comillas" {
  routing_matrix 'agent rationale mode' valid
}
@test "H1 error: agent rationale mode, sangría y comillas" {
  routing_matrix 'agent rationale mode' stale
}
@test "H1 válido: mode agent rationale, sangría y comillas" {
  routing_matrix 'mode agent rationale' valid
}
@test "H1 error: mode agent rationale, sangría y comillas" {
  routing_matrix 'mode agent rationale' stale
}
@test "H1 válido: mode rationale agent, sangría y comillas" {
  routing_matrix 'mode rationale agent' valid
}
@test "H1 error: mode rationale agent, sangría y comillas" {
  routing_matrix 'mode rationale agent' stale
}
@test "H1 válido: rationale agent mode, sangría y comillas" {
  routing_matrix 'rationale agent mode' valid
}
@test "H1 error: rationale agent mode, sangría y comillas" {
  routing_matrix 'rationale agent mode' stale
}
@test "H1 válido: rationale mode agent, sangría y comillas" {
  routing_matrix 'rationale mode agent' valid
}
@test "H1 error: rationale mode agent, sangría y comillas" {
  routing_matrix 'rationale mode agent' stale
}

@test "H1 rutas explícitas: error colgante aunque PROJECT_ROOT tenga paridad válida" {
  printf 'judges:\n  - agent: fixture-judge\n    mode: disabled\n' > "$ROUTING"
  mkdir -p "$TMP/otros agentes"
  printf 'judges:\n  - mode: disabled\n    agent: fixture-missing-judge\n' > "$TMP/otro routing.yaml"
  run env PROJECT_ROOT="$ROOT" JUDGE_ROUTING_FILE="$TMP/otro routing.yaml" \
    JUDGE_AGENTS_DIR="$TMP/otros agentes" bash "$VERIFY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"STALE ROW: fixture-missing-judge"* ]]
}

@test "H1 rutas explícitas: válido aunque PROJECT_ROOT tenga una fila colgante" {
  printf 'judges:\n  - agent: fixture-missing-judge\n    mode: disabled\n' > "$ROUTING"
  mkdir -p "$TMP/otros agentes"
  printf '# Agente ficticio\n' > "$TMP/otros agentes/otro-judge.md"
  printf 'judges:\n  - mode: disabled\n    agent: otro-judge\n' > "$TMP/otro routing.yaml"
  run env PROJECT_ROOT="$ROOT" JUDGE_ROUTING_FILE="$TMP/otro routing.yaml" \
    JUDGE_AGENTS_DIR="$TMP/otros agentes" bash "$VERIFY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  [[ "$output" != *"STALE ROW:"* ]]
}

@test "H1 válido: una fila puede apuntar a un agente existente sin sufijo judicial" {
  printf '# Agente ficticio\n' > "$AGENTS/fixture-worker.md"
  printf 'judges:\n' > "$ROUTING"
  write_row 'agent mode rationale' '  ' '' fixture-judge >> "$ROUTING"
  write_row 'agent mode rationale' '  ' '' fixture-worker >> "$ROUTING"
  run env PROJECT_ROOT="$ROOT" JUDGE_ROUTING_FILE="$ROUTING" \
    JUDGE_AGENTS_DIR="$AGENTS" bash "$VERIFY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "H1 fail-closed: un YAML explícito inexistente no usa el routing por defecto" {
  printf 'judges:\n  - agent: fixture-judge\n    mode: disabled\n' > "$ROUTING"
  run env PROJECT_ROOT="$ROOT" JUDGE_ROUTING_FILE="$TMP/nonexistent.yaml" \
    JUDGE_AGENTS_DIR="$AGENTS" bash "$VERIFY"
  [ "$status" -ne 0 ]
  [[ "$output" != *"PASS"* ]]
}

@test "H1 fail-closed: un directorio explícito inexistente no usa los agentes por defecto" {
  printf 'judges:\n  - agent: fixture-judge\n    mode: disabled\n' > "$ROUTING"
  run env PROJECT_ROOT="$ROOT" JUDGE_ROUTING_FILE="$ROUTING" \
    JUDGE_AGENTS_DIR="$TMP/nonexistent" bash "$VERIFY"
  [ "$status" -ne 0 ]
  [[ "$output" != *"PASS"* ]]
}

# El fichero está fuera de scripts/config: un literal suelto no basta para
# detectar el despacho. Dos líneas previas permiten comprobar la localización.
write_dispatch() {
  local form="$1" name="$2" file="$3"
  printf '# Fixture\n\n' > "$file"
  case "$form" in
    inline) printf 'subagent_type: %s\n' "$name" ;;
    next) printf 'subagent_type:\n  %s\n' "$name" ;;
    single) printf "subagent_type: '%s'\n" "$name" ;;
    double) printf 'subagent_type: "%s"\n' "$name" ;;
    next-single) printf "subagent_type:\n  '%s'\n" "$name" ;;
    next-double) printf 'subagent_type:\n  "%s"\n' "$name" ;;
    flow) printf '{subagent_type: %s}\n' "$name" ;;
    json) printf '{"subagent_type": "%s"}\n' "$name" ;;
    flow-next) printf '{subagent_type:\n  %s}\n' "$name" ;;
    json-next) printf '{"subagent_type":\n  "%s"}\n' "$name" ;;
    *) return 2 ;;
  esac >> "$file"
}

dispatch_case() {
  local form="$1" expected="$2" name="$RETIRED_NAME"
  if [[ "$expected" == clean ]]; then
    name="${RETIRED_NAME}-v2"
  fi
  write_dispatch "$form" "$name" "$ROOT/.claude/commands/ejemplo.md"
  run python3 "$CHECKER" --root "$ROOT" "$RETIRED_NAME"
  printf 'forma=%s nombre=%s\n%s\n' "$form" "$name" "$output"
  if [[ "$expected" == hit ]]; then
    [ "$status" -ne 0 ]
    [[ "$output" =~ \.claude/commands/ejemplo\.md:(3|4): ]]
  else
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: 0 referencia"* ]]
    [[ "$output" != *".claude/commands/ejemplo.md:"* ]]
  fi
}

@test "H2 error: despacho en la misma línea" { dispatch_case inline hit; }
@test "H2 negativo: misma línea no confunde una subcadena" { dispatch_case inline clean; }
@test "H2 error: nombre en la línea siguiente" { dispatch_case next hit; }
@test "H2 negativo: línea siguiente no confunde una subcadena" { dispatch_case next clean; }
@test "H2 error: nombre entre comillas simples" { dispatch_case single hit; }
@test "H2 negativo: comillas simples no confunden una subcadena" { dispatch_case single clean; }
@test "H2 error: nombre entre comillas dobles" { dispatch_case double hit; }
@test "H2 negativo: comillas dobles no confunden una subcadena" { dispatch_case double clean; }
@test "H2 error: comillas simples en la línea siguiente" { dispatch_case next-single hit; }
@test "H2 negativo: comillas simples multilínea no confunden una subcadena" { dispatch_case next-single clean; }
@test "H2 error: comillas dobles en la línea siguiente" { dispatch_case next-double hit; }
@test "H2 negativo: comillas dobles multilínea no confunden una subcadena" { dispatch_case next-double clean; }
@test "H2 error: flujo YAML" { dispatch_case flow hit; }
@test "H2 negativo: flujo YAML no confunde una subcadena" { dispatch_case flow clean; }
@test "H2 error: objeto JSON" { dispatch_case json hit; }
@test "H2 negativo: objeto JSON no confunde una subcadena" { dispatch_case json clean; }
@test "H2 error: flujo YAML multilínea" { dispatch_case flow-next hit; }
@test "H2 negativo: flujo YAML multilínea no confunde una subcadena" { dispatch_case flow-next clean; }
@test "H2 error: objeto JSON multilínea" { dispatch_case json-next hit; }
@test "H2 negativo: objeto JSON multilínea no confunde una subcadena" { dispatch_case json-next clean; }

@test "H2 error: informa cada hallazgo en varios ficheros y líneas" {
  write_dispatch inline "$RETIRED_NAME" "$ROOT/.claude/commands/a.md"
  printf '\nsubagent_type:\n  %s\n' "$RETIRED_NAME" >> "$ROOT/.claude/commands/a.md"
  write_dispatch json-next "$RETIRED_NAME" "$ROOT/.claude/commands/b.md"
  run python3 "$CHECKER" --root "$ROOT" "$RETIRED_NAME"
  [ "$status" -ne 0 ]
  [[ "$output" == *".claude/commands/a.md:3:"* ]]
  [[ "$output" =~ \.claude/commands/a\.md:(5|6): ]]
  [[ "$output" =~ \.claude/commands/b\.md:(3|4): ]]
}

@test "H2 fail-closed: una raíz inexistente no pasa por limpia" {
  run python3 "$CHECKER" --root "$TMP/nonexistent" "$RETIRED_NAME"
  [ "$status" -ne 0 ]
  [[ "$output" != *"PASS"* ]]
}

@test "No regresión: ambos verificadores pasan sobre el árbol real de la rama" {
  run env PROJECT_ROOT="$REPO_ROOT" \
    JUDGE_ROUTING_FILE="$REPO_ROOT/config/judge-routing.yaml" \
    JUDGE_AGENTS_DIR="$REPO_ROOT/.opencode/agents" bash "$VERIFY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  run python3 "$CHECKER" --root "$REPO_ROOT" "${RETIRED[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: 0 referencia"* ]]
}
