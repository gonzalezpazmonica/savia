#!/usr/bin/env bats
# SE-483 — Identidad canónica de Savia: fuente única, generadores y superficies.
# Ref: docs/specs/SE-483-savia-identity-rd-metaorchestrator.spec.md

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LIB="$ROOT/scripts/docs-identity-check.sh"
  SRC="$ROOT/.claude/profiles/savia.md"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Copia las superficies de AC-2 y la fuente a un root aislado.
make_fixture_root() {
  mkdir -p "$TMP/root/.claude/profiles" "$TMP/root/docs" "$TMP/root/.claude-plugin"
  cp "$SRC" "$TMP/root/.claude/profiles/savia.md"
  for f in CLAUDE.md AGENTS.md README.md llms.txt plugin.json docs/critical-facts.md .claude-plugin/plugin.json; do
    cp "$ROOT/$f" "$TMP/root/$f"
  done
}

# ── Fuente única ──────────────────────────────────────────────────────────

@test "lib: extrae la frase larga y la corta de savia.md" {
  run bash "$LIB" long
  [ "$status" -eq 0 ]
  [[ "$output" == "Savia es una metaorquestadora agéntica de I+D+i:"* ]]
  [[ "$output" == *"con la autoridad siempre en la persona. Open source y soberana." ]]
  run bash "$LIB" short
  [ "$status" -eq 0 ]
  [ "$output" = "Savia — metaorquestadora agéntica de I+D+i, open source y soberana." ]
}

@test "lib negativo: tipo inválido sale con 1 sin salida en stdout" {
  run bash -c "source '$LIB'; savia_identity intro 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "lib negativo: fichero sin marcadores sale con 1 (fail-closed)" {
  printf '# Savia\n\nSin bloque canónico.\n' > "$TMP/savia.md"
  run bash -c "SAVIA_IDENTITY_FILE='$TMP/savia.md' bash '$LIB' long 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "lib límite: marcador de apertura sin cierre no emite nada" {
  printf '<!-- identity:long -->\n> Frase sin cierre\nresto del fichero\n' > "$TMP/savia.md"
  run bash -c "SAVIA_IDENTITY_FILE='$TMP/savia.md' bash '$LIB' long 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── AC-2 / AC-3: superficies contienen la frase de la fuente ─────────────

@test "AC-2: frase larga literal en CLAUDE.md, AGENTS.md, README.md y llms.txt" {
  long="$(bash "$LIB" long)"
  for f in CLAUDE.md AGENTS.md README.md llms.txt; do
    grep -qF -- "$long" "$ROOT/$f" || { echo "falta en $f"; false; }
  done
}

@test "AC-2: frase corta literal en critical-facts.md y plugin.json" {
  short="$(bash "$LIB" short)"
  grep -qF -- "- **Identidad**: $short" "$ROOT/docs/critical-facts.md"
  run jq -r .description "$ROOT/plugin.json"
  [ "$output" = "$short" ]
  run jq -r .description "$ROOT/.claude-plugin/plugin.json"
  [ "$output" = "$short" ]
}

@test "AC-3: check pasa en el repo actual" {
  run bash "$LIB" canonical
  [ "$status" -eq 0 ]
  [[ "$output" == PASS:* ]]
}

@test "AC-3 negativo: cambiar la fuente sin regenerar hace fallar el check" {
  make_fixture_root
  sed -i 's/Open source y soberana\./Open source, soberana y distinta./' "$TMP/root/.claude/profiles/savia.md"
  run env SAVIA_IDENTITY_ROOT="$TMP/root" bash "$LIB" canonical
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: CLAUDE.md sin la frase larga canónica"* ]]
  [[ "$output" == *"FAIL: AGENTS.md sin la frase larga canónica"* ]]
}

@test "AC-3 negativo: superficie corta desalineada hace fallar el check" {
  make_fixture_root
  jq '.description = "Complete PM automation"' "$ROOT/plugin.json" > "$TMP/root/plugin.json"
  run env SAVIA_IDENTITY_ROOT="$TMP/root" bash "$LIB" canonical
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: plugin.json sin la frase corta canónica"* ]]
}

# ── R1: los generadores leen la fuente única y fallan cerrados ───────────

@test "R1: llms-txt-generate escribe la frase de la fuente (también mutada) en llms.txt raíz" {
  sed 's/Open source y soberana\./Open source y soberana (prueba)./' "$SRC" > "$TMP/savia.md"
  run env SAVIA_IDENTITY_FILE="$TMP/savia.md" LLMS_ROOT="$TMP/llms.txt" LLMS_TXT="$TMP/d.txt" LLMS_FULL="$TMP/f.txt" \
    bash "$ROOT/scripts/llms-txt-generate.sh" root
  [ "$status" -eq 0 ]
  grep -qF "Open source y soberana (prueba)." "$TMP/llms.txt"
}

@test "R1 negativo: llms-txt-generate sin identidad sale con 2 y no escribe" {
  run env SAVIA_IDENTITY_FILE="$TMP/no-existe.md" LLMS_ROOT="$TMP/llms.txt" LLMS_TXT="$TMP/d.txt" LLMS_FULL="$TMP/f.txt" \
    bash "$ROOT/scripts/llms-txt-generate.sh" generate
  [ "$status" -eq 2 ]
  [ ! -e "$TMP/llms.txt" ]
  [ ! -e "$TMP/d.txt" ]
}

@test "R1: agents-md-generate incluye la frase larga de la fuente" {
  sed 's/Open source y soberana\./Open source y soberana (prueba)./' "$SRC" > "$TMP/savia.md"
  run env SAVIA_IDENTITY_FILE="$TMP/savia.md" bash "$ROOT/scripts/agents-md-generate.sh" --generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"**What this is:** Savia es una metaorquestadora"*"Open source y soberana (prueba)."* ]]
}

@test "R1 negativo: agents-md-generate sin identidad sale con 2" {
  run env SAVIA_IDENTITY_FILE="$TMP/no-existe.md" bash "$ROOT/scripts/agents-md-generate.sh" --generate
  [ "$status" -eq 2 ]
}

@test "R1 negativo: generate-critical-facts sin identidad sale con 2 (modo --check, no escribe)" {
  cd "$ROOT"
  run env SAVIA_IDENTITY_FILE="$TMP/no-existe.md" bash scripts/generate-critical-facts.sh --check
  [ "$status" -eq 2 ]
}

@test "R1: persona savia del Modelfile lleva la frase larga" {
  run bash "$ROOT/scripts/slm-modelfile-gen.sh" --name test --gguf x.gguf --output "$TMP/Modelfile" --persona savia
  [ "$status" -eq 0 ]
  grep -qF "$(bash "$LIB" long)" "$TMP/Modelfile"
  grep -q "buhita" "$TMP/Modelfile"
}

@test "R1 negativo: persona savia sin identidad sale con 2 y no escribe Modelfile" {
  run env SAVIA_IDENTITY_FILE="$TMP/no-existe.md" bash "$ROOT/scripts/slm-modelfile-gen.sh" \
    --name test --gguf x.gguf --output "$TMP/Modelfile" --persona savia
  [ "$status" -eq 2 ]
  [ ! -e "$TMP/Modelfile" ]
}

# ── AC-1: sin identidad PM en las superficies nucleares ──────────────────

@test "AC-1: ninguna superficie nuclear dice PM automatizada / AI project management" {
  cd "$ROOT"
  run git grep -n "PM automatizada\|AI project management\|Project Manager automatizado" -- \
    CLAUDE.md AGENTS.md README.md 'docs/readme/01-*' plugin.json .claude-plugin/ llms.txt 'docs/llms*.txt' \
    .claude/profiles/savia.md docs/rules/domain/profile-onboarding.md
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── R3: presentación con fuente única y sin emojis ───────────────────────

@test "R3: la presentación canónica existe en savia.md y no lleva emoji" {
  intro=$(awk '/<!-- identity:intro -->/{f=1;next} /<!-- \/identity:intro -->/{f=0} f' "$SRC")
  [[ "$intro" == *"Soy Savia"* ]]
  [[ "$intro" != *"🦉"* ]]
}

@test "R3: onboarding y /profile-setup remiten a la presentación, sin copiarla" {
  for f in docs/rules/domain/profile-onboarding.md .claude/commands/profile-setup.md; do
    grep -q "identity:intro" "$ROOT/$f"
    run grep -c "🦉" "$ROOT/$f"
    [ "$output" = "0" ]
    run grep -c "la buhita de pm-workspace" "$ROOT/$f"
    [ "$output" = "0" ]
  done
}

# ── R4: catálogo de agentes por capacidad ────────────────────────────────

@test "R4: agents-catalog abre con metaorquestación y clasifica cada agente una vez" {
  cat="$ROOT/docs/rules/domain/agents-catalog.md"
  first=$(grep -m1 '^- \*\*' "$cat")
  [[ "$first" == "- **Metaorquestación"* ]]
  listed=$(awk '/^## Por capacidad/{f=1;next} /^## /{f=0} f && /^- \*\*/' "$cat" | sed 's/^[^:]*: //' | tr ',' '\n' | sed 's/^ *//' | sort)
  agents=$(find "$ROOT/.opencode/agents" -maxdepth 1 -name '*.md' -exec basename {} .md \; | sort)
  [ "$listed" = "$agents" ]
}
