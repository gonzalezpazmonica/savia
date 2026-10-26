#!/usr/bin/env bats
# SE-264 / SE-317: consolidación de memoria (memory-consolidate.sh y .py).
# Cada caso copia los scripts a un repo temporal: nunca toca la memoria ni el
# output/ reales. Se comprueban salidas, ficheros resultantes y códigos.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/scripts" "$TMP/.claude/external-memory/auto"
  cp "$ROOT/scripts/memory-consolidate.sh" "$ROOT/scripts/memory-consolidate.py" "$TMP/scripts/"
  SH="$TMP/scripts/memory-consolidate.sh"
  PY="$TMP/scripts/memory-consolidate.py"
  AUTO="$TMP/.claude/external-memory/auto"
  MEM="$AUTO/MEMORY.md"
  STORE="$TMP/store.jsonl"
  OUTD="$TMP/output/memory-consolidation"
}

teardown() {
  rm -rf "$TMP"
}

mkmem() {
  cat > "$MEM" <<'MD'
# MEMORY Index
<!-- ENTRIES_START -->
- decision: SE-260 ok [decision/se-260]
- decision: Adopt event sourcing for the billing ledger [decision/ledger]
- decision: Adopt event sourcing for the billing ledger again [decision/ledger]
- decision: Real decision about the deployment pipeline layout [decision/deploy]
- episode: test [ep-x]
- decision: OK1 [decision/ok1]
<!-- ENTRIES_END -->
## Notas al pie
MD
}

out_file() { ls "$OUTD"/*-"$1".jsonl 2>/dev/null | head -1; }

# ── memory-consolidate.py ─────────────────────────────────────────────────

@test "MC-T01: py report counts totals, tests, duplicates and keepers" {
  mkmem
  run python3 "$PY" --report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total:       6 entries"* ]]
  [[ "$output" == *"Test:        2 (will remove)"* ]]
  [[ "$output" == *"Duplicates:  1 (will dedup)"* ]]
  [[ "$output" == *"Keep:        3"* ]]
  [[ "$output" == *"Status: CLEAN"* ]]
}

@test "MC-T02: py dry-run reports how many would go and leaves the file intact" {
  mkmem
  cp "$MEM" "$TMP/before.md"
  run python3 "$PY" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN: 3 would be removed"* ]]
  cmp "$MEM" "$TMP/before.md"
  [ ! -d "$AUTO/archive" ]
}

@test "MC-T03: py lists exactly the test-looking entries to remove" {
  mkmem
  run python3 "$PY" --report
  [[ "$output" == *"~ - episode: test [ep-x]"* ]]
  [[ "$output" == *"~ - decision: OK1 [decision/ok1]"* ]]
  [[ "$output" != *"~ - decision: Real decision"* ]]
}

@test "MC-T04: py SE-nnn entry is kept even when short or matching a test pattern" {
  cat > "$MEM" <<'MD'
<!-- ENTRIES_START -->
- decision: SE-165 done [decision/se-165]
- decision: SPEC-12 dummy fake Edge [decision/spec-12]
- decision: SE-x ok [d/s]
<!-- ENTRIES_END -->
MD
  run python3 "$PY" --report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Test:        1 (will remove)"* ]]
  [[ "$output" == *"~ - decision: SE-x ok [d/s]"* ]]
  [[ "$output" == *"Keep:        2"* ]]
}

@test "MC-T05: py entry whose text after the prefix is 25 characters is kept, 24 is removed" {
  cat > "$MEM" <<'MD'
<!-- ENTRIES_START -->
- decision: abcdefghijklmnopqr [d/a]
- decision: abcdefghijklmnopq [d/b]
<!-- ENTRIES_END -->
MD
  run python3 "$PY" --report
  [[ "$output" == *"Test:        1 (will remove)"* ]]
  [[ "$output" != *"~ - decision: abcdefghijklmnopqr [d/a]"* ]]
  [[ "$output" == *"~ - decision: abcdefghijklmnopq [d/b]"* ]]
}

@test "MC-T06: py flags a kept entry whose referenced note file is missing as stale" {
  mkmem
  mkdir -p "$AUTO/decision"
  : > "$AUTO/decision/ledger.md"
  run python3 "$PY" --report
  # 3 keepers: se-260 and deploy have no file; ledger has one
  [[ "$output" == *"Stale refs:  2"* ]]
}

@test "MC-T07: py --apply removes tests and duplicates, keeps header and a backup" {
  mkmem
  run python3 "$PY" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed: 3 entries"* ]]
  [[ "$output" == *"Remaining: 3 entries"* ]]
  [[ "$output" == *"=== CONSOLIDATED ==="* ]]
  run cat "$MEM"
  [[ "${lines[0]}" == "# MEMORY Index" ]]
  [[ "$output" == *"SE-260"* ]]
  [[ "$output" != *"ep-x"* ]]
  [[ "$output" != *"OK1"* ]]
  [ "$(grep -c 'decision/ledger' "$MEM")" -eq 1 ]
  # Las entradas siguen entre los marcadores y lo que va tras END se conserva
  [ "${lines[1]}" = "<!-- ENTRIES_START -->" ]
  [ "${lines[5]}" = "<!-- ENTRIES_END -->" ]
  [ "${lines[6]}" = "## Notas al pie" ]
  [ "${#lines[@]}" -eq 7 ]
  ls "$AUTO"/archive/MEMORY-*.md
  grep -q 'ep-x' "$AUTO"/archive/MEMORY-*.md
}

@test "MC-T08a: py long entry that matches a test pattern is flagged, a long real one is not" {
  cat > "$MEM" <<'MD'
<!-- ENTRIES_START -->
- decision: Test decision about rebuilding the whole cache layer [d/pat]
- decision: Rotate the signing keys every quarter without downtime [d/real]
<!-- ENTRIES_END -->
MD
  run python3 "$PY" --report
  [[ "$output" == *"Test:        1 (will remove)"* ]]
  [[ "$output" == *"~ - decision: Test decision about rebuilding"* ]]
}

@test "MC-T08b: py --apply twice works when the archive directory already exists" {
  mkmem
  run python3 "$PY" --apply
  [ "$status" -eq 0 ]
  sleep 1
  run python3 "$PY" --apply
  [ "$status" -eq 0 ]
  [ "$(ls "$AUTO"/archive | wc -l)" -eq 2 ]
}

@test "MC-T08: py with no arguments behaves as report and does not write" {
  mkmem
  cp "$MEM" "$TMP/before.md"
  run python3 "$PY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Status: CLEAN"* ]]
  cmp "$MEM" "$TMP/before.md"
}

# ── memory-consolidate.sh ─────────────────────────────────────────────────

@test "MC-T09: sh --help prints usage and exits 0" {
  run bash "$SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory-consolidate.sh scan|link|distill|prune"* ]]
  [[ "$output" == *"Exit: 0 ok, 2 uso"* ]]
}

@test "MC-T10: sh without action exits 2 with usage on stderr" {
  run bash "$SH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "MC-T11: sh unknown action exits 2" {
  : > "$STORE"
  run bash "$SH" explode --store "$STORE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"acción desconocida 'explode'"* ]]
}

@test "MC-T12: sh unknown option exits 2" {
  run bash "$SH" scan --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento desconocido '--bogus'"* ]]
}

@test "MC-T13: sh missing store exits 2 and names the path" {
  run bash "$SH" scan --store "$TMP/nope.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"store no existe: $TMP/nope.jsonl"* ]]
}

@test "MC-T14: scan flags identical content as duplicate with score 1.0" {
  cat > "$STORE" <<'J'
{"hash":"a1","title":"One","content":"Use blue-green deploys"}
{"hash":"b2","title":"Two","content":"  USE blue-green deploys "}
{"hash":"c3","title":"Three","content":"Completely unrelated thing about cats"}
J
  run bash "$SH" scan --store "$STORE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scan: 1 candidato(s)"* ]]
  f="$(out_file scan)"
  [ "$(wc -l < "$f")" -eq 1 ]
  python3 - "$f" <<'PY'
import json, sys
r = json.loads(open(sys.argv[1]).readline())
assert r["type"] == "duplicate" and r["score"] == 1.0, r
assert (r["a"]["hash"], r["b"]["hash"]) == ("a1", "b2"), r
PY
}

@test "MC-T15: scan flags near-duplicates above 0.85 only" {
  cat > "$STORE" <<'J'
{"hash":"a1","content":"The deployment pipeline runs the unit tests first"}
{"hash":"b2","content":"The deployment pipeline runs the unit tests first."}
{"hash":"c3","content":"The deployment pipeline runs"}
J
  run bash "$SH" scan --store "$STORE"
  [ "$status" -eq 0 ]
  f="$(out_file scan)"
  python3 - "$f" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
kinds = {(r["a"]["hash"], r["b"]["hash"]): r for r in rows}
assert ("a1", "b2") in kinds and kinds[("a1", "b2")]["type"] == "near_duplicate", rows
assert kinds[("a1", "b2")]["score"] > 0.85
assert ("a1", "c3") not in kinds and ("b2", "c3") not in kinds, rows
PY
}

@test "MC-T16: scan ignores empty-content notes and malformed lines" {
  cat > "$STORE" <<'J'
{"hash":"a1","content":""}
not json at all
{"hash":"b2","content":""}
{"hash":"c3"}

{"hash":"d4","content":"alone"}
J
  run bash "$SH" scan --store "$STORE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scan: 0 candidato(s)"* ]]
}

@test "MC-T17: link derives edges from cited hash and cited title" {
  cat > "$STORE" <<'J'
{"hash":"h111","title":"Event sourcing ledger decision","content":"base"}
{"hash":"h222","title":"Billing","content":"Follows h111 closely","concepts":["x"]}
{"hash":"h333","title":"Audit","content":"see the event sourcing ledger decision for context"}
{"hash":"h444","title":"Short","content":"short mention only"}
J
  run bash "$SH" link --store "$STORE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"link: 2 candidato(s)"* ]]
  python3 - "$(out_file link)" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
got = {(r["from"], r["to"], r["reason"]) for r in rows}
assert got == {("h222", "h111", "cites hash"), ("h333", "h111", "cites title")}, got
PY
}

@test "MC-T18: link never links a note to itself nor via titles of 12 chars or fewer" {
  cat > "$STORE" <<'J'
{"hash":"h111","title":"Twelve chars","content":"Twelve chars h111"}
{"hash":"h222","title":"x","content":"twelve chars appears here"}
J
  run bash "$SH" link --store "$STORE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"link: 0 candidato(s)"* ]]
}

@test "MC-T19: distill groups by topic_key then domain, needs 2+ notes, lists citations" {
  cat > "$STORE" <<'J'
{"hash":"a","title":"A","topic_key":"infra","concepts":["z","y"]}
{"hash":"b","title":"B","domain":"infra","concepts":["y","x"]}
{"hash":"c","title":"C","topic_key":"solo"}
{"title":"D"}
{"hash":"e"}
J
  run bash "$SH" distill --store "$STORE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"distill: 2 candidato(s)"* ]]
  python3 - "$(out_file distill)" <<'PY'
import json, sys
rows = {r["group"]: r for r in map(json.loads, open(sys.argv[1]))}
assert set(rows) == {"infra", "uncategorized"}, rows
i = rows["infra"]
assert i["sources"] == 2 and i["citations"] == ["a", "b"] and i["absorbed"] == ["a", "b"]
assert i["concepts"] == ["x", "y", "z"] and i["summary_title"] == "Insight: infra"
assert i["reason"] == "2 notes same episode/domain"
assert rows["uncategorized"]["citations"] == ["e"]
PY
}

@test "MC-T20: prune lists absorbed and tier D notes as dry-run candidates, never edits the store" {
  cat > "$STORE" <<'J'
{"hash":"a","title":"A","quality":"absorbed"}
{"hash":"b","title":"B","importance_tier":"D"}
{"hash":"c","title":"C","importance_tier":"A"}
{"hash":"d","title":"D","quality":"good"}
J
  cp "$STORE" "$TMP/store.before"
  run bash "$SH" prune --store "$STORE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prune: 2 candidato(s)"* ]]
  cmp "$STORE" "$TMP/store.before"
  python3 - "$(out_file prune)" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
assert [(r["hash"], r["reason"], r["dry_run"]) for r in rows] == [
    ("a", "absorbed (fuente de insight)", True), ("b", "importancia tier D", True)], rows
PY
}

@test "MC-T21: prune with --apply marks candidates as not dry-run" {
  echo '{"hash":"a","title":"A","quality":"absorbed"}' > "$STORE"
  run bash "$SH" prune --store "$STORE" --apply
  [ "$status" -eq 0 ]
  python3 - "$(out_file prune)" <<'PY'
import json, sys
assert json.loads(open(sys.argv[1]).readline())["dry_run"] is False
PY
}

@test "MC-T22: results are appended to a dated file named after the action" {
  echo '{"hash":"a","quality":"absorbed"}' > "$STORE"
  bash "$SH" prune --store "$STORE" >/dev/null
  bash "$SH" prune --store "$STORE" >/dev/null
  f="$(out_file prune)"
  [[ "$f" == "$OUTD/$(date -u +%Y%m%d)-prune.jsonl" ]]
  [ "$(wc -l < "$f")" -eq 2 ]
}
