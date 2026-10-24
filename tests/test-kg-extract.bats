#!/usr/bin/env bats
# kg-extract.py — extracción determinista de entidades (SE-291).
# Comportamiento: patrones, deduplicado, evidencia, cobertura, quality gate,
# modos, entrada/salida y extractor LLM con un router falso.

setup() {
  EXTRACTOR="$BATS_TEST_DIRNAME/../scripts/kg-extract.py"
  TESTDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TESTDIR"
}

# extrae un campo de la salida JSON con una expresión Python sobre `d`
jq_py() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

ext() { python3 "$EXTRACTOR" --mode deterministic --input "$TESTDIR/in.txt" "$@"; }

names() { ext | jq_py "'|'.join(sorted(e['name'] for e in d['entities']))"; }

mod() {
  python3 - "$@" <<'PY'
import importlib.util, sys, asyncio, json
spec = importlib.util.spec_from_file_location("kg", sys.argv[1])
kg = importlib.util.module_from_spec(spec); spec.loader.exec_module(kg)
exec(sys.argv[2])
PY
}

@test "kg-extract exists and is executable" {
  [ -f "$EXTRACTOR" ]
  [ -x "$EXTRACTOR" ]
}

@test "deterministic mode extracts ISO and slash dates as event entities" {
  echo "Released on 2026-08-02 and 15/01/2025" > "$TESTDIR/in.txt"
  run ext
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name": "Date: 2026-08-02"'* ]]
  [[ "$output" == *'"name": "Date: 15/01/2025"'* ]]
  [ "$(ext | jq_py "{e['type'] for e in d['entities'] if e['pattern']=='date'}")" = "{'event'}" ]
}

@test "deterministic mode extracts spec IDs with 2 to 4 digits only" {
  echo "See SE-291 and SE-88 but not SE-7 nor SE-12345 alone" > "$TESTDIR/in.txt"
  n="$(names)"
  [[ "$n" == *"Spec: SE-291"* ]]
  [[ "$n" == *"Spec: SE-88"* ]]
  [[ "$n" != *"Spec: SE-7"* ]]
  [[ "$n" != *"Spec: SE-12345"* ]]
}

@test "deterministic mode extracts emails as person entities" {
  echo "Contact: dev+ops@savia.local" > "$TESTDIR/in.txt"
  run ext
  [[ "$output" == *'"name": "Email: dev+ops@savia.local"'* ]]
  [ "$(ext | jq_py "[e['type'] for e in d['entities'] if e['pattern']=='email']")" = "['person']" ]
}

@test "deterministic mode extracts URLs and stops at whitespace" {
  echo 'Docs at https://example.org/a/b?x=1 and more' > "$TESTDIR/in.txt"
  n="$(names)"
  [[ "$n" == *"URL: https://example.org/a/b?x=1"* ]]
}

@test "deterministic mode extracts file paths" {
  echo "See projects/savia-vaults/src/server/mcp.ts" > "$TESTDIR/in.txt"
  [[ "$(names)" == *"File: projects/savia-vaults/src/server/mcp.ts"* ]]
}

@test "deterministic mode extracts PR references in both notations" {
  echo "Fixed in PR #1234 and PR 77 and #4321" > "$TESTDIR/in.txt"
  n="$(names)"
  [[ "$n" == *"PR: PR #1234"* ]]
  [[ "$n" == *"PR: PR 77"* ]]
  [[ "$n" == *"PR: #4321"* ]]
}

@test "deterministic mode extracts percentages, person names and known agent names" {
  echo "Ana Maria Lopez said architect and code-reviewer reached 87.5 % today" > "$TESTDIR/in.txt"
  n="$(names)"
  [[ "$n" == *"Metric: 87.5 %"* ]]
  [[ "$n" == *"Person: Ana Maria Lopez"* ]]
  [[ "$n" == *"Agent: architect"* ]]
  [[ "$n" == *"Agent: code-reviewer"* ]]
}

@test "generic version and commit-hash patterns are skipped as noise" {
  echo "Release v0.3.0 and 1.2.3 with commit deadbeef1 and abc1234" > "$TESTDIR/in.txt"
  n="$(names)"
  [[ "$n" != *"Version:"* ]]
  [[ "$n" != *"Commit:"* ]]
}

@test "confidence is 1.0 and method regex for every extracted entity" {
  echo "SE-291 was merged on 2026-08-02" > "$TESTDIR/in.txt"
  [ "$(ext | jq_py "{(e['confidence'], e['extraction_method'], e['verified_in_source']) for e in d['entities']}")" = "{(1.0, 'regex', True)}" ]
}

@test "repeated mentions of the same entity are deduplicated by name and type" {
  echo "SE-291 then SE-291 and SE-291 again" > "$TESTDIR/in.txt"
  [ "$(ext | jq_py "[e['name'] for e in d['entities'] if e['pattern']=='spec_id']")" = "['Spec: SE-291']" ]
}

@test "evidence span stores character offsets and up to 60 characters of context each side" {
  python3 -c "print('x'*100 + ' SE-291 ' + 'y'*100)" > "$TESTDIR/in.txt"
  [ "$(ext | jq_py "[e['evidence_span']['start'] for e in d['entities'] if e['pattern']=='spec_id'][0]")" = "101" ]
  [ "$(ext | jq_py "[e['evidence_span']['end'] for e in d['entities'] if e['pattern']=='spec_id'][0]")" = "107" ]
  [ "$(ext | jq_py "len([e['evidence_span']['text'] for e in d['entities'] if e['pattern']=='spec_id'][0])")" = "126" ]
}

@test "evidence near the start of the text is not clipped below zero" {
  printf 'SE-291 ok' > "$TESTDIR/in.txt"
  [ "$(ext | jq_py "[e['evidence_span']['text'] for e in d['entities'] if e['pattern']=='spec_id'][0]")" = "SE-291 ok" ]
}

@test "source_hash is a stable 16-hex digest of the whole input" {
  echo "SE-291" > "$TESTDIR/in.txt"
  a="$(ext | jq_py "d['entities'][0]['source_hash']")"
  b="$(ext | jq_py "d['entities'][0]['source_hash']")"
  [ "$a" = "$b" ]
  [[ "$a" =~ ^[0-9a-f]{16}$ ]]
  echo "SE-292" > "$TESTDIR/in.txt"
  c="$(ext | jq_py "d['entities'][0]['source_hash']")"
  [ "$a" != "$c" ]
}

@test "empty input handled gracefully with zero entities and needs_llm true" {
  echo "" > "$TESTDIR/in.txt"
  run ext
  [ "$status" -eq 0 ]
  [[ "$output" == *'"entity_count": 0'* ]]
  [ "$(ext | jq_py "d['needs_llm']")" = "True" ]
}

@test "coverage is entities per word as a percentage and needs_llm flips below 1 percent" {
  echo "SE-291 SE-292" > "$TESTDIR/in.txt"
  [ "$(ext | jq_py "(d['coverage_pct'] == round(d['entity_count'] / 2 * 100, 1), d['needs_llm'])")" = "(True, False)" ]
  python3 -c "print('SE-291 ' + 'palabra ' * 300)" > "$TESTDIR/in.txt"
  [ "$(ext | jq_py "d['needs_llm']")" = "True" ]
}

@test "source defaults to the input path and --source overrides it" {
  echo "SE-291" > "$TESTDIR/in.txt"
  [ "$(ext | jq_py "d['source']")" = "$TESTDIR/in.txt" ]
  run ext --source "my-doc.pdf"
  [[ "$output" == *'"source_document": "my-doc.pdf"'* ]]
  [ "$(ext --source my-doc.pdf | jq_py "d['source']")" = "my-doc.pdf" ]
}

@test "input is read from stdin when --input is - or omitted" {
  run bash -c "echo 'SE-291' | python3 '$EXTRACTOR'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Spec: SE-291"* ]]
  run bash -c "echo 'SE-292' | python3 '$EXTRACTOR' -i -"
  [[ "$output" == *"Spec: SE-292"* ]]
}

@test "--output writes the JSON to a file and prints nothing" {
  echo "SE-291" > "$TESTDIR/in.txt"
  run ext --output "$TESTDIR/out.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(python3 -c "import json; print(json.load(open('$TESTDIR/out.json'))['entity_count'])")" -ge 1 ]
}

@test "missing input file fails with a non-zero exit" {
  run ext --input "$TESTDIR/no-existe.txt"
  [ "$status" -ne 0 ]
}

@test "invalid mode is rejected by the argument parser with exit 2" {
  echo "x" > "$TESTDIR/in.txt"
  run python3 "$EXTRACTOR" --mode bogus --input "$TESTDIR/in.txt"
  [ "$status" -eq 2 ]
}

@test "hybrid mode gives the deterministic result" {
  echo "SE-291 on 2026-08-02" > "$TESTDIR/in.txt"
  a="$(python3 "$EXTRACTOR" --mode hybrid --input "$TESTDIR/in.txt" | jq_py "sorted(e['name'] for e in d['entities'])")"
  b="$(python3 "$EXTRACTOR" --mode deterministic --input "$TESTDIR/in.txt" | jq_py "sorted(e['name'] for e in d['entities'])")"
  [ "$a" = "$b" ]
}

@test "llm and ece modes report that a ProviderRouter is required" {
  echo "x" > "$TESTDIR/in.txt"
  run python3 "$EXTRACTOR" --mode llm --input "$TESTDIR/in.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode 'llm' requires ProviderRouter"* ]]
  run python3 "$EXTRACTOR" --mode ece --input "$TESTDIR/in.txt"
  [[ "$output" == *"Mode 'ece' requires ProviderRouter"* ]]
}

@test "quality gate keeps verified regex entities as active" {
  echo "SE-291 on 2026-08-02" > "$TESTDIR/in.txt"
  run ext --quality-gate
  [ "$status" -eq 0 ]
  [ "$(ext --quality-gate | jq_py "{e['status'] for e in d['entities']}")" = "{'active'}" ]
  [ "$(ext --quality-gate | jq_py "d['entity_count'] == len(d['entities'])")" = "True" ]
}

@test "quality gate drops unverified entities and tiers the rest by confidence" {
  run mod "$EXTRACTOR" '
p = kg.HybridPipeline()
out = p.quality_gate([
  {"name": "a", "verified_in_source": False, "confidence": 1.0},
  {"name": "b", "verified_in_source": True, "confidence": 0.4},
  {"name": "c", "verified_in_source": True, "confidence": 0.5},
  {"name": "d", "verified_in_source": True, "confidence": 0.69},
  {"name": "e", "verified_in_source": True, "confidence": 0.7},
  {"name": "f", "confidence": 1.0},
])
print([(e["name"], e["status"]) for e in out])
'
  [ "$output" = "[('b', 'rejected'), ('c', 'proposed'), ('d', 'proposed'), ('e', 'active')]" ]
}

@test "quality gate records the rejection reason" {
  run mod "$EXTRACTOR" '
e1 = {"verified_in_source": False}
e2 = {"verified_in_source": True, "confidence": 0.1}
kg.HybridPipeline().quality_gate([e1, e2])
print(e1["rejection_reason"], "|", e2["rejection_reason"])
'
  [ "$output" = "not found in source text | low confidence" ]
}

@test "llm extractor without a router returns an error and no entities" {
  run mod "$EXTRACTOR" '
r = asyncio.run(kg.LLMEnhancedExtractor().extract("txt", "s"))
print(r["error"], r["entities"], r["relations"], r["source"])
'
  [ "$output" = "ProviderRouter not available [] [] s" ]
}

@test "llm extractor enriches entities, flags unverified ones and scores relations" {
  run mod "$EXTRACTOR" '
class R:
    def __init__(s, c): s.content = c
class Router:
    async def complete(s, req):
        assert req["tier"] == "mid" and req["temperature"] == 0.1
        return R("prefacio {\"entities\":[{\"name\":\"Ana\",\"value\":\"Ana\",\"evidence_span\":\"Ana habla\"},{\"name\":\"Zed\",\"value\":\"Zed\",\"type\":\"person\"}],\"relations\":[{\"source\":\"Ana\",\"target\":\"Zed\",\"relation\":\"MENTIONS\"}]} fin")
r = asyncio.run(kg.LLMEnhancedExtractor(Router()).extract("Ana habla con alguien", "doc"))
e = r["entities"]
print(r["entity_count"], e[0]["verified_in_source"], e[1]["verified_in_source"], e[0]["confidence"], e[0]["type"], e[1]["type"], e[0]["evidence_span"], r["relations"][0]["confidence"])
'
  [ "$output" = "2 True False 0.7 document person {'text': 'Ana habla'} 0.6" ]
}

@test "llm extractor falls back to empty results on invalid model output or router failure" {
  run mod "$EXTRACTOR" '
class R:
    content = "sin json"
class Bad:
    async def complete(s, req): return R()
class Boom:
    async def complete(s, req): raise RuntimeError("x")
for rt in (Bad(), Boom()):
    r = asyncio.run(kg.LLMEnhancedExtractor(rt).extract("t", "s"))
    print(r["entity_count"], r["relations"])
'
  [ "$output" = "$(printf '0 []\n0 []')" ]
}

@test "llm extractor truncates the prompt text to 4000 characters" {
  run mod "$EXTRACTOR" '
seen = {}
class R:
    content = "{}"
class Rt:
    async def complete(s, req):
        seen["p"] = req["messages"][0]["content"]; return R()
asyncio.run(kg.LLMEnhancedExtractor(Rt()).extract("Ж" * 5000, "s"))
print(seen["p"].count("Ж"))
'
  [ "$output" = "4000" ]
}

@test "quality gate on a result without entities does not crash" {
  echo "x" > "$TESTDIR/in.txt"
  run python3 "$EXTRACTOR" --mode llm --input "$TESTDIR/in.txt" --quality-gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"requires ProviderRouter"* ]]
}

@test "output is pretty-printed JSON with two-space indentation" {
  echo "SE-291" > "$TESTDIR/in.txt"
  run ext
  [[ "${lines[1]}" == '  "source": '* ]]
}
