#!/usr/bin/env bats
# Ref: SE-338 — rule-manifest-generate.sh (AC-5: determinismo, no-mutación, stale)

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GEN="$ROOT_DIR/scripts/rule-manifest-generate.sh"
  TMPD="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPD" 2>/dev/null || true
}

@test "SE-338: genera manifest JSON válido con total == nº de reglas" {
  out="$TMPD/manifest.json"
  run bash "$GEN" --output "$out" --domain-dir "$ROOT_DIR/docs/rules/domain"
  [ "$status" -eq 0 ]
  python3 -c "
import json,sys,glob,os
m=json.load(open('$out'))
rules=[os.path.basename(f) for f in glob.glob('$ROOT_DIR/docs/rules/domain/*.md')
       if os.path.basename(f) not in ('INDEX.md','rule-manifest.json')]
assert m['total'] == len(rules), (m['total'], len(rules))
assert len(m['rules']) == len(rules)
for k,v in m['rules'].items():
    assert v['tier'] in ('tier1','tier2','dormant')
    assert 'consumers' in v
"
}

@test "SE-338: --check detecta stale (fichero nuevo en domain-dir)" {
  out="$TMPD/manifest.json"
  bash "$GEN" --output "$out" --domain-dir "$ROOT_DIR/docs/rules/domain" >/dev/null
  # añadir una regla fake → manifest ya no refleja el filesystem
  echo "---\ncontext_tier: L1\n---\n# fake\n" > "$TMPD/domain-extra.md"
  mkdir -p "$TMPD/dom"
  cp "$ROOT_DIR/docs/rules/domain/"*.md "$TMPD/dom/" 2>/dev/null
  cp "$TMPD/domain-extra.md" "$TMPD/dom/fake-rule.md"
  cp "$out" "$TMPD/dom/rule-manifest.json"
  run bash "$GEN" --check --output "$TMPD/dom/rule-manifest.json" --domain-dir "$TMPD/dom"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "stale"
}

@test "SE-338: no-mutación — generar no toca las reglas" {
  before=$(sha256sum "$ROOT_DIR/docs/rules/domain/radical-honesty.md" | cut -d' ' -f1)
  run bash "$GEN" --output "$TMPD/m.json"
  [ "$status" -eq 0 ]
  after=$(sha256sum "$ROOT_DIR/docs/rules/domain/radical-honesty.md" | cut -d' ' -f1)
  [ "$before" == "$after" ]
}

@test "SE-338: determinista — 2 generaciones → mismo inventario (ignorando generated)" {
  bash "$GEN" --output "$TMPD/a.json" >/dev/null
  sleep 1
  bash "$GEN" --output "$TMPD/b.json" >/dev/null
  python3 -c "
import json
a=json.load(open('$TMPD/a.json')); b=json.load(open('$TMPD/b.json'))
a.pop('generated'); b.pop('generated')
assert a == b
"
}

# ── Comportamiento discriminante (S03 calidad) ───────────────────────────────

# Dominio sintético: una regla por tier + excluidos + ruido.
mk_domain() {
  D="$TMPD/dom"
  mkdir -p "$D/archive"
  printf -- '---\ncontext_tier: L1\n---\n# a\n' > "$D/a-l1.md"
  printf -- '---\ncontext_tier: L2\n---\n# b\n' > "$D/b-l2.md"
  printf -- '---\ncontext_tier: L3\n---\n# c\n' > "$D/c-l3.md"
  printf -- '---\ncontext_tier: L0\n---\n# d\n' > "$D/d-l0.md"
  printf -- '# sin frontmatter\n' > "$D/e-none.md"
  printf -- '---\ncontext_tier: LX\n---\n# raro\n' > "$D/g-raro.md"
  printf -- '---\r\ncontext_tier: L1\r\n---\r\n# crlf\r\n' > "$D/f-crlf.md"
  printf -- '# indice\n' > "$D/INDEX.md"
  printf '{}\n' > "$D/rule-manifest.json"
  printf 'ruido\n' > "$D/notas.txt"
  printf -- '---\ncontext_tier: L1\n---\n' > "$D/archive/viejo.md"
}

@test "usa modo estricto de bash (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$GEN"
}

@test "L1 -> tier1, L2 y L3 -> tier2, L0 o sin frontmatter -> dormant" {
  mk_domain
  run bash "$GEN" --output "$TMPD/m.json" --domain-dir "$D"
  [ "$status" -eq 0 ]
  run jq -r '[.rules["a-l1.md"].tier, .rules["b-l2.md"].tier, .rules["c-l3.md"].tier, .rules["d-l0.md"].tier, .rules["e-none.md"].tier] | join(",")' "$TMPD/m.json"
  [ "$output" = "tier1,tier2,tier2,dormant,dormant" ]
}

@test "context_tier con fin de línea CRLF se reconoce (no cae a dormant)" {
  mk_domain
  bash "$GEN" --output "$TMPD/m.json" --domain-dir "$D" >/dev/null
  run jq -r '.rules["f-crlf.md"].tier' "$TMPD/m.json"
  [ "$output" = "tier1" ]
}

@test "excluye INDEX.md, rule-manifest.json, archive/ y ficheros no markdown" {
  mk_domain
  bash "$GEN" --output "$TMPD/m.json" --domain-dir "$D" >/dev/null
  run jq -r '.rules | keys | join(",")' "$TMPD/m.json"
  [ "$output" = "a-l1.md,b-l2.md,c-l3.md,d-l0.md,e-none.md,f-crlf.md,g-raro.md" ]
}

@test "los contadores suman el total y reflejan cada tier" {
  mk_domain
  bash "$GEN" --output "$TMPD/m.json" --domain-dir "$D" >/dev/null
  run jq -e '.total == 7 and .tier1_count == 2 and .tier2_count == 2 and .dormant_count == 3 and (.tier1_count + .tier2_count + .dormant_count == .total)' "$TMPD/m.json"
  [ "$status" -eq 0 ]
}

@test "cada regla lleva consumers vacío y el manifest tiene timestamp UTC" {
  mk_domain
  bash "$GEN" --output "$TMPD/m.json" --domain-dir "$D" >/dev/null
  run jq -e '([.rules[].consumers] | all(. == "")) and (.generated | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' "$TMPD/m.json"
  [ "$status" -eq 0 ]
}

@test "--check devuelve OK con exit 0 cuando el manifest refleja el inventario" {
  mk_domain
  bash "$GEN" --output "$D/rule-manifest.json" --domain-dir "$D" >/dev/null
  # el timestamp no cuenta como diferencia de inventario
  jq '.generated = "2000-01-01T00:00:00Z"' "$D/rule-manifest.json" > "$TMPD/g.json"
  cp "$TMPD/g.json" "$D/rule-manifest.json"
  run bash "$GEN" --check --output "$D/rule-manifest.json" --domain-dir "$D"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
}

@test "--check detecta stale cuando cambia el tier de una regla sin cambiar el total" {
  mk_domain
  bash "$GEN" --output "$D/rule-manifest.json" --domain-dir "$D" >/dev/null
  printf -- '---\ncontext_tier: L1\n---\n# b\n' > "$D/b-l2.md"
  run bash "$GEN" --check --output "$D/rule-manifest.json" --domain-dir "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
}

@test "--check with nonexistent manifest exits 1 with MISSING and does not create it" {
  mk_domain
  run bash "$GEN" --check --output "$TMPD/no-existe.json" --domain-dir "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING"* ]]
  [[ ! -e "$TMPD/no-existe.json" ]]
}

@test "--check never rewrites a stale manifest (fail without mutation)" {
  mk_domain
  printf '{"total":0,"rules":{}}\n' > "$D/rule-manifest.json"
  before="$(cksum < "$D/rule-manifest.json")"
  run bash "$GEN" --check --output "$D/rule-manifest.json" --domain-dir "$D"
  [ "$status" -eq 1 ]
  [ "$(cksum < "$D/rule-manifest.json")" = "$before" ]
}

@test "nonexistent domain-dir exits 2 with error and creates no output" {
  run bash "$GEN" --output "$TMPD/m.json" --domain-dir "$TMPD/nada"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR"* ]]
  [[ ! -e "$TMPD/m.json" ]]
}

@test "invalid argument exits 2 with usage" {
  run bash "$GEN" --borrar
  [ "$status" -eq 2 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "empty domain-dir yields a manifest with zero rules" {
  mkdir -p "$TMPD/vacio"
  run bash "$GEN" --output "$TMPD/m.json" --domain-dir "$TMPD/vacio"
  [ "$status" -eq 0 ]
  run jq -e '.total == 0 and .rules == {}' "$TMPD/m.json"
  [ "$status" -eq 0 ]
}

@test "la salida es JSON con claves de reglas ordenadas (determinista)" {
  mk_domain
  bash "$GEN" --output "$TMPD/m.json" --domain-dir "$D" >/dev/null
  run jq -e '(.rules | keys) == (.rules | keys | sort)' "$TMPD/m.json"
  [ "$status" -eq 0 ]
  run grep -n '"a-l1.md"' "$TMPD/m.json"
  first="${output%%:*}"
  run grep -n '"f-crlf.md"' "$TMPD/m.json"
  [ "$first" -lt "${output%%:*}" ]
}
