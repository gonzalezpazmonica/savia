#!/usr/bin/env bats
# rule-usage-analyzer.sh: validación de --root / --output (revisión PR #1353)

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rule-usage-analyzer.sh"

@test "--root without value fails with a clear error, not unbound variable" {
  run bash "$SCRIPT" --root
  [ "$status" -eq 2 ]
  [[ "$output" == *"--root requiere"* ]]
  [[ "$output" != *"unbound"* ]]
}

@test "--root pointing to a nonexistent directory fails" {
  run bash "$SCRIPT" --root /nonexistent-dir-xyz
  [ "$status" -eq 2 ]
  [[ "$output" == *"--root requiere"* ]]
}

@test "--output without value fails" {
  run bash "$SCRIPT" --output
  [ "$status" -eq 2 ]
  [[ "$output" == *"--output requiere"* ]]
}

@test "--root with an existing empty directory still succeeds" {
  local d
  d=$(mktemp -d)
  run bash "$SCRIPT" --root "$d" --summary
  rmdir "$d"
  [ "$status" -eq 0 ]
}

# --- Comportamiento: clasificacion por niveles sobre un arbol propio ---

mk_root() {
  R="$BATS_TEST_TMPDIR/root"
  mkdir -p "$R/docs/rules/domain" "$R/.opencode/commands" "$R/.opencode/skills" "$R/.opencode/agents"
  for r in alpha beta gamma delta; do echo "# $r" > "$R/docs/rules/domain/$r.md"; done
  echo "ref @docs/rules/domain/alpha.md y @docs/rules/domain/beta.md" > "$R/CLAUDE.md"
  echo "usa @docs/rules/domain/beta.md y @docs/rules/domain/gamma.md" > "$R/.opencode/commands/cmd.md"
  echo "usa @docs/rules/domain/gamma.md" > "$R/.opencode/skills/skill.md"
}

@test "summary cuenta tier1, tier2 y dormidas; beta (en CLAUDE.md y en un comando) es tier1" {
  mk_root
  run bash "$SCRIPT" --root "$R" --summary
  [ "$status" -eq 0 ]
  [ "$output" = "Rules: 4 total | 2 tier1 | 1 tier2 | 1 dormant" ]
}

@test "el manifiesto JSON asigna nivel y consumidores a cada regla" {
  mk_root
  run bash "$SCRIPT" --root "$R"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["total"]==4 and d["tier1_count"]==2 and d["tier2_count"]==1 and d["dormant_count"]==1, d
r=d["rules"]
assert r["alpha.md"]["tier"]=="tier1" and r["alpha.md"]["consumers"]=="CLAUDE.md", r["alpha.md"]
assert r["beta.md"]["tier"]=="tier1"
assert sorted(r["beta.md"]["consumers"].split(","))==[".opencode/commands/cmd.md","CLAUDE.md"], r["beta.md"]
assert r["gamma.md"]["tier"]=="tier2"
assert sorted(r["gamma.md"]["consumers"].split(","))==[".opencode/commands/cmd.md",".opencode/skills/skill.md"]
assert r["delta.md"]=={"tier":"dormant","consumers":""}, r["delta.md"]
'
}

@test "sin reglas ni CLAUDE.md todo es cero y el JSON sigue siendo valido" {
  local d="$BATS_TEST_TMPDIR/vacio"
  mkdir -p "$d"
  run bash "$SCRIPT" --root "$d" --summary
  [ "$output" = "Rules: 0 total | 0 tier1 | 0 tier2 | 0 dormant" ]
  run bash "$SCRIPT" --root "$d"
  echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["total"]==0 and d["rules"]=={}'
}

@test "una referencia con nombre distinto no cuenta: delta2 no promueve a delta" {
  mk_root
  echo "x @docs/rules/domain/delta2.md" > "$R/.opencode/agents/a.md"
  run bash "$SCRIPT" --root "$R" --summary
  [ "$output" = "Rules: 4 total | 2 tier1 | 1 tier2 | 1 dormant" ]
  run bash "$SCRIPT" --root "$R"
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["rules"]["delta.md"]=={"tier":"dormant","consumers":""}, d["rules"]["delta.md"]
'
}

@test "una regla citada solo desde un comando pasa de dormida a tier2" {
  mk_root
  echo "x @docs/rules/domain/delta.md" > "$R/.opencode/agents/a.md"
  run bash "$SCRIPT" --root "$R" --summary
  [ "$output" = "Rules: 4 total | 2 tier1 | 2 tier2 | 0 dormant" ]
}

@test "las reglas con subdirectorios o sin .md se ignoran" {
  mk_root
  mkdir -p "$R/docs/rules/domain/sub"; echo x > "$R/docs/rules/domain/sub/zeta.md"; echo x > "$R/docs/rules/domain/nota.txt"
  run bash "$SCRIPT" --root "$R" --summary
  [[ "$output" == "Rules: 4 total"* ]]
}

@test "--output escribe el manifiesto en el fichero y no en stdout" {
  mk_root
  run bash "$SCRIPT" --root "$R" --output "$BATS_TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["total"]==4' "$BATS_TEST_TMPDIR/m.json"
}

@test "--output a una ruta no escribible falla con exit 2 y sin JSON en stdout" {
  mk_root
  run bash "$SCRIPT" --root "$R" --output "$BATS_TEST_TMPDIR/no/existe/m.json"
  [ "$status" -eq 2 ]
  [[ "$output" != *'"total"'* ]]
}
