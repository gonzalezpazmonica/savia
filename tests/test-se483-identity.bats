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
  mkdir -p "$TMP/root/.claude/profiles" "$TMP/root/docs/rules/domain" "$TMP/root/.claude-plugin"
  cp "$SRC" "$TMP/root/.claude/profiles/savia.md"
  for f in CLAUDE.md AGENTS.md README.md llms.txt plugin.json docs/critical-facts.md docs/rules/domain/savia-core.md .claude-plugin/plugin.json; do
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

# ── S03t: el gate completo (comprobaciones 1-9) en un árbol sintético ────────
# docs-identity-check.sh deriva ROOT de su ruta: se copia a un árbol propio con
# superficies mínimas y válidas, y cada caso rompe exactamente una comprobación.

s03t_root() {
  GR="$BATS_TEST_TMPDIR/gate"
  mkdir -p "$GR/scripts" "$GR/.claude/profiles" "$GR/docs/rules/domain" "$GR/.claude-plugin"
  cp "$LIB" "$GR/scripts/docs-identity-check.sh"
  cp "$SRC" "$GR/.claude/profiles/savia.md"
  GL="$(bash "$LIB" long)"; GS="$(bash "$LIB" short)"
  # Contador canónico leído del propio script: los fixtures siguen al gate cuando cambie.
  CN="$(grep -m1 -oP 'sin contador canonical \K[0-9]+' "$LIB")"; [ -n "$CN" ]
  printf '# Savia\n\nSistema agéntico soberano. '"$CN"' cosas.\n\n%s\n' "$GL" > "$GR/README.md"
  for f in CLAUDE.md AGENTS.md llms.txt; do printf '# Savia\n%s\n' "$GL" > "$GR/$f"; done
  for f in docs/critical-facts.md docs/rules/domain/savia-core.md plugin.json .claude-plugin/plugin.json; do printf '%s\n' "$GS" > "$GR/$f"; done
  G="$GR/scripts/docs-identity-check.sh"
}

@test "gate: árbol coherente pasa con exit 0 y mensaje PASS" {
  s03t_root
  run bash "$G"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: identidad documental consistente (Savia)"* ]]
}

@test "gate negativo: README cuyo primer título no es '# Savia' falla con exit 1" {
  s03t_root
  printf '# PM-Workspace\n\nsoberano '"$CN"'\n%s\n' "$GL" > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"título actual no es '# Savia' (es: # PM-Workspace)"* ]]
  [[ "$output" == *"1 fallo(s)"* ]]
}

@test "gate negativo: traducción sin la palabra soberano falla y se nombra el fichero" {
  s03t_root
  printf '# Savia\n'"$CN"' sin identidad\n' > "$GR/README.en.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"README.en.md sin identidad canónica"* ]]
}

@test "gate: traducción con 'sovereign' en inglés sí cuenta como identidad" {
  s03t_root
  printf '# Savia\nA sovereign system. '"$CN"'\n' > "$GR/README.en.md"
  run bash "$G"
  [ "$status" -eq 0 ]
}

@test "gate negativo: contadores del README distintos de la realidad fallan" {
  s03t_root
  mkdir -p "$GR/.opencode/commands" "$GR/.opencode/agents" "$GR/.claude/skills/a"
  : > "$GR/.opencode/commands/x.md"
  printf '# Savia\n\nsoberano '"$CN"'\n\n999 comandos · 1 agentes · 1 skills · 5 hooks\n%s\n' "$GL" > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contadores README (999 comandos"* ]]
  [[ "$output" == *"realidad (1 comandos · 0 agentes · 1 skills)"* ]]
}

@test "gate: contadores del README iguales a la realidad pasan" {
  s03t_root
  mkdir -p "$GR/.opencode/commands" "$GR/.opencode/agents" "$GR/.claude/skills/a"
  : > "$GR/.opencode/commands/x.md"
  printf '# Savia\n\nsoberano '"$CN"'\n\n1 comandos · 0 agentes · 1 skills · 5 hooks\n%s\n' "$GL" > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 0 ]
}

@test "gate negativo: URL pm-workspace como identidad actual en README falla; con 'origin' se admite" {
  s03t_root
  printf '# Savia\n\nsoberano '"$CN"'\nInstalar https://github.com/gonzalezpazmonica/pm-workspace\n%s\n' "$GL" > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"URLs legacy como identidad actual en README.md"* ]]
  printf '# Savia\n\nsoberano '"$CN"'\nRepositorio origin https://github.com/gonzalezpazmonica/pm-workspace\n%s\n' "$GL" > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 0 ]
}

@test "gate negativo: CLAUDE.md sin la palabra Savia falla" {
  s03t_root
  printf 'nada\n%s\n' "$GL" | sed 's/Savia/X/g' > "$GR/CLAUDE.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDE.md sin identidad Savia"* ]]
}

@test "gate negativo: primera pantalla que dice 'pm-workspace es' falla; con 'origen' pasa" {
  s03t_root
  printf '# Savia\n\nsoberano '"$CN"'\npm-workspace es un gestor\n%s\n' "$GL" > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"identidad legacy como actual"* ]]
  printf '# Savia\n\nsoberano '"$CN"'\npm-workspace es el origen del proyecto\n%s\n' "$GL" > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 0 ]
}

@test "gate negativo: traducción con contador obsoleto (532) falla" {
  s03t_root
  printf '# Savia\nsoberano '"$CN"' y 532\n' > "$GR/README.fr.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contadores stale en README.fr.md"* ]]
}

@test "gate negativo: README sin el contador canónico (valor fijado en el script) falla" {
  s03t_root
  printf '# Savia\n\nsoberano\n%s\n' "$GL" > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"README.md sin contador canonical $CN"* ]]
}

@test "gate negativo: superficie sin la frase canónica hace fallar el gate completo y sugiere regenerar" {
  s03t_root
  printf '# Savia\notra frase\n' > "$GR/AGENTS.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AGENTS.md sin la frase larga canónica"* ]]
  [[ "$output" == *"Regenerar:"* ]]
}

@test "gate límite: varios fallos se suman en el contador final" {
  s03t_root
  printf '# Otra cosa\nsin nada\n' > "$GR/README.md"
  run bash "$G"
  [ "$status" -eq 1 ]
  [[ "$output" =~ ([0-9]+)\ fallo\(s\) ]]
  [ "${BASH_REMATCH[1]}" -ge 3 ]
}

@test "argumento desconocido sale con 2 y muestra el uso" {
  s03t_root
  run bash "$G" nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"Uso: docs-identity-check.sh"* ]]
}

@test "canonical: árbol coherente pasa y cuenta 8 superficies; sin una superficie falla" {
  s03t_root
  run env SAVIA_IDENTITY_ROOT="$GR" bash "$G" canonical
  [ "$status" -eq 0 ]
  [[ "$output" == *"presente en 8 superficies"* ]]
  : > "$GR/llms.txt"
  run env SAVIA_IDENTITY_ROOT="$GR" bash "$G" canonical
  [ "$status" -eq 1 ]
  [[ "$output" == *"llms.txt sin la frase larga canónica"* ]]
}

@test "seguridad: el verificador de identidad declara set -uo pipefail" {
  grep -q "^set -uo pipefail" "$LIB"
}

@test "edge empty: savia-core.md vacío en el árbol hace fallar el gate y se nombra" {
  s03t_root
  : > "$GR/docs/rules/domain/savia-core.md"
  run env SAVIA_IDENTITY_ROOT="$GR" bash "$G" canonical
  [ "$status" -eq 1 ]
  [[ "$output" == *"savia-core.md"* ]]
}

@test "edge boundary: la frase corta aparece literal en el savia-core.md real" {
  run bash "$LIB" short
  [ "$status" -eq 0 ]
  [[ "$(grep -cF -- "$output" "$ROOT/docs/rules/domain/savia-core.md")" -ge 1 ]]
}

@test "negativo: argumento desconocido (nonexistent) en el verificador sale con 2" {
  run bash "$LIB" nonexistent-mode
  [ "$status" -eq 2 ]
  [[ "$output" == *"Uso: docs-identity-check.sh"* ]]
}
