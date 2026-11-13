#!/usr/bin/env bats
# Ref: SE-529 S0.3/S0.4 — líneas base: solo recuentos, nunca texto.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  BASE="$REPO_ROOT/scripts/compaction-baseline-counts.py"
  T="$(mktemp -d)"; SENT="ZQXJ-SENTINEL-9917"
  mkdir -p "$T/proj/-home-u-alpha" "$T/proj/-home-u-beta/memory" "$T/ws/output"
  python3 -I - "$T" "$SENT" <<'PY'
import json,sys
t,s=sys.argv[1:3]
def turn(ty,txt): return json.dumps({"type":ty,"message":{"role":ty,"content":txt+" "+s}})+"\n"
def boundary(tr): return json.dumps({"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":tr,"preTokens":9}})+"\n"
with open(t+"/proj/-home-u-alpha/a.jsonl","w") as f:
    for i in range(35): f.write(turn("user" if i%2==0 else "assistant","x"*10))
    f.write(boundary("auto"))
    f.write(json.dumps({"type":"user","isCompactSummary":True,"message":{"role":"user","content":s}})+"\n")
    for i in range(3): f.write(turn("user","y"))
    f.write(boundary("manual"))
with open(t+"/proj/-home-u-beta/b.jsonl","w") as f:
    f.write(turn("user","z")); f.write(boundary("manual")); f.write("no json "+s+"\n")
with open(t+"/proj/-home-u-beta/memory/session-hot.md","w") as f:
    f.write("## Session Context (2026-01-01T00:00:00Z)\nDecisions: "+s+"\n\n## Session Context (2026-01-02T00:00:00Z)\nTask: "+s+"\n")
rows=[]
for i in range(30):
    rows.append({"ts":"2026-01-01T00:00:00Z","type":"decision","title":"t"+s,"content":"c"*100+s,"project":"pa" if i<10 else ("null" if i<25 else "pb"),"importance_tier":"A" if i<3 else "C","goal":"x"})
rows.append({"ts":"2026-01-01T00:00:00Z","type":"session-summary","title":"pre-compact auto-save","content":"c","project":"null","importance_tier":"B"})
with open(t+"/ws/output/.memory-store.jsonl","w") as f:
    for r in rows: f.write(json.dumps(r)+"\n")
PY
}
teardown() { rm -rf "$T"; }

@test "S0.3: cuenta compactaciones por disparador y por proyecto anónimo" {
  run python3 -I "$BASE" --transcripts-dir "$T/proj" --store "$T/ws/output/.memory-store.jsonl" --post-script /nonexistent
  [ "$status" -eq 0 ]
  echo "$output" | python3 -I -c "
import json,sys
r=json.load(sys.stdin)['s03']
assert r['sessions_scanned']==2, r
assert r['compactions']==3, r
assert r['by_trigger']=={'auto':1,'manual':2}, r
assert sorted(r['by_project'].values())==[1,2], r
assert r['with_summary_line']==1, r
assert r['session_hot_rows']==2, r
assert r['tail_bytes_30_turns']['n']==3, r
assert r['tail_bytes_30_turns']['p90']>0, r
"
}

@test "S0.3: los nombres de proyecto no salen; ningún texto llega a la salida" {
  run python3 -I "$BASE" --transcripts-dir "$T/proj" --store "$T/ws/output/.memory-store.jsonl" --post-script /nonexistent
  [ "$status" -eq 0 ]
  run grep -q "alpha\|beta" <<<"$output"
  [ "$status" -ne 0 ]
  run grep -q "$SENT" <<<"$output"
  [ "$status" -ne 0 ]
}

@test "S0.4: reparto por proyecto (null aparte), por tier y fracción del activo" {
  run python3 -I "$BASE" --transcripts-dir "$T/proj" --store "$T/ws/output/.memory-store.jsonl" --post-script /nonexistent --active-project pb
  [ "$status" -eq 0 ]
  echo "$output" | python3 -I -c "
import json,sys
r=json.load(sys.stdin)['s04']
assert r['entries']==31, r
assert r['null_project']==16, r
assert r['null_share']==round(16/31,3), r
assert r['by_tier']=={'A':3,'B':1,'C':27}, r
assert r['tier_a_share']==round(3/31,3), r
assert r['precompact_autosave_entries']==1, r
assert r['active_project_in_last20']['count']==5, r
"
}

@test "S0.4: bytes que imprime post-compaction.sh con HOME aislado, sin tocar session-hot real" {
  run python3 -I "$BASE" --transcripts-dir "$T/proj" --store "$T/ws/output/.memory-store.jsonl" --post-script "$REPO_ROOT/scripts/post-compaction.sh" --active-project pb
  [ "$status" -eq 0 ]
  echo "$output" | python3 -I -c "
import json,sys
r=json.load(sys.stdin)['s04']
assert r['post_compaction_stdout_bytes']>0, r
assert r['post_compaction_exit']==0, r
"
}

@test "almacén ausente o transcripts ausentes: no revienta y lo declara" {
  run python3 -I "$BASE" --transcripts-dir "$T/nope" --store "$T/nope.jsonl" --post-script /nonexistent
  [ "$status" -eq 0 ]
  echo "$output" | python3 -I -c "
import json,sys
r=json.load(sys.stdin)
assert r['s03']['sessions_scanned']==0 and r['s03']['compactions']==0, r
assert r['s04']['entries']==0 and r['s04']['store_present'] is False, r
"
}

@test "línea de almacén corrupta se cuenta aparte y no rompe" {
  echo 'basura {' >> "$T/ws/output/.memory-store.jsonl"
  run python3 -I "$BASE" --transcripts-dir "$T/proj" --store "$T/ws/output/.memory-store.jsonl" --post-script /nonexistent
  [ "$status" -eq 0 ]
  echo "$output" | python3 -I -c "
import json,sys
r=json.load(sys.stdin)['s04']
assert r['entries']==31 and r['corrupt_lines']==1, r
"
}
