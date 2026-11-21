#!/usr/bin/env bats
# BATS tests for scripts/sovereignty-classify.sh + sovereignty-decide.sh
# SE-314 S1-S4 — determinismo, umbrales, regex/LLM, caché.
# Ref: docs/propuestas/SE-314-sovereignty-classifier-redesign.md

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$CLAUDE_PROJECT_DIR" "$CLAUDE_PROJECT_DIR/config/classifier"
  cp config/classifier/prompt-v2.txt config/classifier/prompt-v3.txt "$CLAUDE_PROJECT_DIR/config/classifier/" 2>/dev/null || true
  cp config/sovereignty-thresholds.yaml "$CLAUDE_PROJECT_DIR/config/" 2>/dev/null || true
  rm -rf "$CLAUDE_PROJECT_DIR/output/classifier-cache" 2>/dev/null || true
  export TEST_INPUT="$CLAUDE_PROJECT_DIR/input.txt"
}

@test "sovereignty-classify.sh existe y es ejecutable" {
  [[ -f scripts/sovereignty-classify.sh ]]
  [[ -x scripts/sovereignty-classify.sh ]]
}

@test "sovereignty-decide.sh existe y es ejecutable" {
  [[ -f scripts/sovereignty-decide.sh ]]
  [[ -x scripts/sovereignty-decide.sh ]]
}

@test "prompt-v2.txt versionado existe" {
  [[ -f config/classifier/prompt-v2.txt ]]
}

@test "sovereignty-thresholds.yaml existe y es YAML válido" {
  [[ -f config/sovereignty-thresholds.yaml ]]
  run python3 -c "import yaml; yaml.safe_load(open('config/sovereignty-thresholds.yaml'))"
  [ "$status" -eq 0 ]
}

@test "AC-S1.3: salida JSON válida con jq, hash = sha256 del input" {
  printf '%s' "hello world public content" > "$TEST_INPUT"
  run bash scripts/sovereignty-classify.sh < "$TEST_INPUT"
  [ "$status" -eq 0 ]
  HASH=$(printf '%s' "hello world public content" | sha256sum | cut -d' ' -f1)
  run jq -e --arg h "sha256:$HASH" '.schema == "savia.classify/2.0" and .hash == $h' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "AC-S1.1: determinismo byte-idéntico (mismo input → misma salida)" {
  # Texto <50 chars: se resuelve sin LLM (determinista en CI, sin Ollama).
  echo "public technical documentation content" > "$TEST_INPUT"
  R1=$(bash scripts/sovereignty-classify.sh --no-cache < "$TEST_INPUT" 2>/dev/null)
  R2=$(bash scripts/sovereignty-classify.sh --no-cache < "$TEST_INPUT" 2>/dev/null)
  [[ "$R1" == "$R2" ]]
  run jq -e '.label == "public"' <<< "$R1"
  [ "$status" -eq 0 ]
}

@test "AC-S3.2: secreto real (IP interna) bloquea sin depender del LLM" {
  echo "host at 10.0.0.1 internal" > "$TEST_INPUT"
  OUT=$(bash scripts/sovereignty-classify.sh < "$TEST_INPUT" 2>/dev/null)
  run jq -e '.label == "confidential" and (.deterministic_matches | index("internal_ip"))' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "AC-S3.3: deterministic_matches presente en salida" {
  echo "plain public content here" > "$TEST_INPUT"
  OUT=$(bash scripts/sovereignty-classify.sh --no-cache < "$TEST_INPUT" 2>/dev/null)
  run jq -e '.deterministic_matches | type == "array"' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "AC-S4.1: 2ª clasificación del mismo contenido es cache_hit" {
  head -c 1200 scripts/savia-env.sh > "$TEST_INPUT"
  R1=$(bash scripts/sovereignty-classify.sh < "$TEST_INPUT" 2>/dev/null)
  R2=$(bash scripts/sovereignty-classify.sh < "$TEST_INPUT" 2>/dev/null)
  run jq -e '.cache_hit == false' <<< "$R1"
  [ "$status" -eq 0 ]
  run jq -e '.cache_hit == true' <<< "$R2"
  [ "$status" -eq 0 ]
}

@test "AC-S2.3: confidence < 0.70 en N1 → ALLOW (decide)" {
  echo "hello world public short" > "$TEST_INPUT"
  OUT=$(bash scripts/sovereignty-classify.sh < "$TEST_INPUT" 2>/dev/null)
  DEC=$(printf '%s' "$OUT" | bash scripts/sovereignty-decide.sh --dest n1)
  run jq -e '.action == "ALLOW" and .reason == "below_threshold"' <<< "$DEC"
  [ "$status" -eq 0 ]
}

@test "AC-S2.1: confidential confidence alta en N1 → BLOCK (decide)" {
  echo "host at 10.0.0.1 internal network" > "$TEST_INPUT"
  OUT=$(bash scripts/sovereignty-classify.sh < "$TEST_INPUT" 2>/dev/null)
  DEC=$(printf '%s' "$OUT" | bash scripts/sovereignty-decide.sh --dest n1 2>/dev/null || true)
  run jq -e '.action == "BLOCK" and .label == "confidential"' <<< "$DEC"
  [ "$status" -eq 0 ]
}

@test "usage inválido falla (exit 2)" {
  run bash scripts/sovereignty-classify.sh --bogus-flag
  [ "$status" -eq 2 ]
}

@test "classifier declares set -uo pipefail" {
  head -30 scripts/sovereignty-classify.sh | grep -q 'set -uo pipefail'
}

@test "missing prompt file → ambiguous with error, never a weaker fallback prompt" {
  rm -f "$CLAUDE_PROJECT_DIR/config/classifier/prompt-v3.txt"
  printf '%s' "texto de mas de cincuenta caracteres que obligaria a consultar al modelo local" > "$TEST_INPUT"
  # El script comprueba antes que Ollama responde; sin un Ollama local el resultado sería
  # ollama_unavailable y no se llegaría a la rama que se prueba. Un curl falso lo simula alcanzable.
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BATS_TEST_TMPDIR/fakebin/curl"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/curl"
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run bash scripts/sovereignty-classify.sh --no-cache < "$TEST_INPUT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .label)" = "ambiguous" ]
  [ "$(echo "$output" | jq -r .error)" = "prompt_missing" ]
}

@test "empty input → error exit 1 (nothing to classify)" {
  run bash -c "printf '' | bash scripts/sovereignty-classify.sh --no-cache"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No text provided"* ]]
}

@test "boundary: text under 50 chars is public without calling the model" {
  printf '%s' "hola mundo" > "$TEST_INPUT"
  run bash scripts/sovereignty-classify.sh --no-cache < "$TEST_INPUT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .label)" = "public" ]
  [ "$(echo "$output" | jq -r .confidence)" = "0.65" ]
}

@test "unreachable model (nonexistent endpoint) → ambiguous, cached, never BLOCK" {
  printf '%s' "texto de mas de cincuenta caracteres sin secretos ni datos personales concretos" > "$TEST_INPUT"
  OLLAMA_URL="http://127.0.0.1:9" run bash scripts/sovereignty-classify.sh < "$TEST_INPUT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .label)" = "ambiguous" ]
  run bash -c "bash scripts/sovereignty-classify.sh < '$TEST_INPUT' | bash scripts/sovereignty-decide.sh --dest n1"
  [[ "$output" != *'"action":"BLOCK"'* ]]
}

@test "deterministic secret wins even with the model unreachable (zero LLM)" {
  printf 'server at %s.%s.%s.%s inside the vpc for the sales team' 10 20 30 40 > "$TEST_INPUT"
  OLLAMA_URL="http://127.0.0.1:9" run bash scripts/sovereignty-classify.sh --no-cache < "$TEST_INPUT"
  [ "$(echo "$output" | jq -r .label)" = "confidential" ]
  [[ "$output" == *"internal_ip"* ]]
}

# ── dni_nif: la letra de control decide (TRWAGMYFPDXBNJZSQVHLCKE[n % 23]) ──
# Números sintéticos: la letra se calcula aquí, no es el DNI de nadie.
check_letter() { local l="TRWAGMYFPDXBNJZSQVHLCKE"; echo "${l:$(( 10#$1 % 23 )):1}"; }
classify_offline() {
  printf '%s' "$1" > "$TEST_INPUT"
  OLLAMA_URL="http://127.0.0.1:9" bash scripts/sovereignty-classify.sh --no-cache < "$TEST_INPUT" 2>/dev/null
}

@test "dni_nif: DNI with valid check letter → confidential" {
  local dni="12345678$(check_letter 12345678)"
  [ "$dni" = "12345678Z" ]
  OUT=$(classify_offline "dni del titular: $dni")
  run jq -e '.label == "confidential" and (.deterministic_matches | index("dni_nif"))' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "dni_nif: check letter is case-insensitive" {
  OUT=$(classify_offline "dni del titular: 12345678z.")
  run jq -e '.deterministic_matches | index("dni_nif")' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "dni_nif: same digits with a wrong letter is not a DNI" {
  OUT=$(classify_offline "dni del titular: 12345678A")
  run jq -e '.deterministic_matches | index("dni_nif") | not' <<< "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -r .label <<< "$OUT")" != "confidential" ]
}

@test "dni_nif: pairing-code alphabet literal is not a DNI" {
  OUT=$(classify_offline 'ALPHABET: &[u8] = b"23456789ABCDEFGHJKMNPQRSTVWXYZ";')
  run jq -e '.deterministic_matches | index("dni_nif") | not' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "dni_nif: a valid ID after an invalid one is still found" {
  local second="87654321$(check_letter 87654321)"
  OUT=$(classify_offline "refs 12345678A $second fin")
  run jq -e '.deterministic_matches | index("dni_nif")' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "dni_nif: NIE with valid check letter (X=0) → confidential" {
  local nie="X1234567$(check_letter 01234567)"
  [ "$nie" = "X1234567L" ]
  OUT=$(classify_offline "nie del titular: $nie")
  run jq -e '.label == "confidential" and (.deterministic_matches | index("dni_nif"))' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "dni_nif: NIE prefixes Y=1 and Z=2 are mapped before the check" {
  OUT=$(classify_offline "nie Y1234567$(check_letter 11234567)")
  run jq -e '.deterministic_matches | index("dni_nif")' <<< "$OUT"
  [ "$status" -eq 0 ]
  OUT=$(classify_offline "nie Z1234567$(check_letter 21234567)")
  run jq -e '.deterministic_matches | index("dni_nif")' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "dni_nif: NIE with a wrong letter is not a DNI/NIE" {
  OUT=$(classify_offline "nie del titular: X1234567A")
  run jq -e '.deterministic_matches | index("dni_nif") | not' <<< "$OUT"
  [ "$status" -eq 0 ]
}

@test "dni_nif: non-ASCII digits under a UTF-8 locale never abort detection" {
  local loc
  loc=$(locale -a 2>/dev/null | grep -iE '^es_ES\.utf-?8$' | head -1)
  [ -n "$loc" ] || loc=$(locale -a 2>/dev/null | grep -iE '\.utf-?8$' | grep -viE '^C\.' | head -1)
  [ -n "$loc" ] || skip "no non-C UTF-8 locale installed"
  printf 'ref ١٢٣٤٥٦٧٨Z dni del titular 12345678Z' > "$TEST_INPUT"
  OUT=$(LANG="$loc" LC_ALL="$loc" OLLAMA_URL="http://127.0.0.1:9" \
        bash scripts/sovereignty-classify.sh --no-cache < "$TEST_INPUT" 2>"$BATS_TEST_TMPDIR/err")
  run jq -e '.label == "confidential" and (.deterministic_matches | index("dni_nif"))' <<< "$OUT"
  [ "$status" -eq 0 ]
  ! grep -q '10#' "$BATS_TEST_TMPDIR/err"
}

@test "cache key includes the layer-1 rules (script hash in prompt_version)" {
  OUT=$(classify_offline "plain text")
  run jq -e --arg h "$(sha256sum scripts/sovereignty-classify.sh | cut -c1-8)" '.prompt_version | endswith("+l1-" + $h)' <<< "$OUT"
  [ "$status" -eq 0 ]
}
