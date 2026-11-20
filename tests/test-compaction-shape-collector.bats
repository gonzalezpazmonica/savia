#!/usr/bin/env bats
# Ref: SE-529 S0.1 — colector de forma de las cargas de compactación.
# Invariantes: opt-in por entorno, solo forma y longitudes, nunca texto, siempre exit 0.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COL="$REPO_ROOT/scripts/compaction-shape-collector.py"
  T="$(mktemp -d)"
  export SAVIA_COMPACT_SHAPE_LOG="$T/state/shape.jsonl"
  export HOME="$T/home"
  mkdir -p "$HOME/.claude/projects/p1"
  SENT="ZQXJ-SENTINEL-7731"
}
teardown() { rm -rf "$T"; }

run_col() { # $1 event $2 frontend ; stdin = payload
  python3 -I "$COL" --event "$1" --frontend "$2"
}

@test "sin SAVIA_COMPACT_SHAPE no escribe nada y sale 0" {
  run bash -c "echo '{\"hook_event_name\":\"PreCompact\"}' | python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$SAVIA_COMPACT_SHAPE_LOG" ]
}

@test "SAVIA_COMPACT_SHAPE=0 tampoco escribe" {
  run bash -c "echo '{}' | SAVIA_COMPACT_SHAPE=0 python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  [ ! -e "$SAVIA_COMPACT_SHAPE_LOG" ]
}

@test "activo: registra evento, frontend, campos, tipos y longitudes; stdout vacío" {
  run bash -c "printf '%s' '{\"session_id\":\"abcd\",\"hook_event_name\":\"PreCompact\",\"trigger\":\"manual\",\"custom_instructions\":\"\"}' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run python3 -I -c "
import json,sys
r=[json.loads(l) for l in open('$SAVIA_COMPACT_SHAPE_LOG')]
assert len(r)==1, r
r=r[0]
assert r['event']=='PreCompact' and r['frontend']=='claude-code'
f=r['payload']['keys']
assert f['session_id']=={'t':'str','bytes':4}, f
assert f['trigger']['bytes']==6
assert f['custom_instructions']['bytes']==0
"
  [ "$status" -eq 0 ]
}

@test "ningún valor de texto llega al registro (payload, anidados, listas)" {
  P="{\"session_id\":\"$SENT\",\"x\":{\"deep\":\"$SENT\",\"l\":[\"$SENT\",1,null,true]},\"summary\":\"$SENT $SENT\"}"
  run bash -c "printf '%s' '$P' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PostCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  run grep -q "$SENT" "$SAVIA_COMPACT_SHAPE_LOG"
  [ "$status" -ne 0 ]
  grep -q '"summary"' "$SAVIA_COMPACT_SHAPE_LOG"
  # longitud del resumen: 2*18+1 = 37 bytes
  grep -q '"bytes": 37' "$SAVIA_COMPACT_SHAPE_LOG"
}

@test "nombres de campo con texto libre se sustituyen" {
  P="{\"hola $SENT mundo con espacios\":\"v\",\"ok_key\":1}"
  run bash -c "printf '%s' '$P' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PostCompact --frontend opencode"
  [ "$status" -eq 0 ]
  run grep -q "$SENT" "$SAVIA_COMPACT_SHAPE_LOG"
  [ "$status" -ne 0 ]
  grep -q 'ok_key' "$SAVIA_COMPACT_SHAPE_LOG"
}

@test "entrada vacía, basura y binaria: exit 0, parse_error, sin contenido" {
  for inp in '' 'not json '"$SENT" '[1,2' ; do
    run bash -c "printf '%s' '$inp' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PreCompact --frontend claude-code"
    [ "$status" -eq 0 ]
  done
  run bash -c "head -c 2000 /dev/urandom | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  run grep -q "$SENT" "$SAVIA_COMPACT_SHAPE_LOG"
  [ "$status" -ne 0 ]
  [ "$(grep -c '"parse_error": true' "$SAVIA_COMPACT_SHAPE_LOG")" -ge 4 ]
}

@test "frontend o evento fuera de lista: exit 0 y se anota como 'other' sin eco del valor" {
  run bash -c "echo '{}' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event \"$SENT\" --frontend \"$SENT\""
  [ "$status" -eq 0 ]
  run grep -q "$SENT" "$SAVIA_COMPACT_SHAPE_LOG"
  [ "$status" -ne 0 ]
  grep -q '"event": "other"' "$SAVIA_COMPACT_SHAPE_LOG"
}

@test "transcript: forma, tipos de línea, líneas no JSON y turnos finales; sin texto" {
  TP="$HOME/.claude/projects/p1/s.jsonl"
  python3 -I - "$TP" "$SENT" <<'PY'
import json,sys
p,s=sys.argv[1:3]
with open(p,'w') as f:
    for i in range(40):
        f.write(json.dumps({"type":"user","message":{"role":"user","content":s+" u"+str(i)}})+"\n")
        f.write(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":s*3},{"type":"tool_use","name":"Bash","input":{"command":s}}]}})+"\n")
    f.write("esto no es json "+s+"\n")
    f.write(json.dumps({"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"manual","preTokens":5}})+"\n")
PY
  run bash -c "printf '%s' '{\"transcript_path\":\"$TP\",\"cwd\":\"/x\"}' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  run grep -q "$SENT" "$SAVIA_COMPACT_SHAPE_LOG"
  [ "$status" -ne 0 ]
  run grep -q "$TP" "$SAVIA_COMPACT_SHAPE_LOG"
  [ "$status" -ne 0 ]
  run python3 -I -c "
import json
r=json.loads(open('$SAVIA_COMPACT_SHAPE_LOG').readline())
t=r['transcript']
assert t['present'] and t['exists'] and t['regular'], t
assert t['base']=='frontend_data_dir', t
assert t['line_count']==82, t
assert t['json_lines']==81 and t['non_json_lines']==1, t
assert t['line_types']['user']==40 and t['line_types']['assistant']==40, t
assert t['line_types']['system:compact_boundary']==1, t
assert t['block_types']['text']==40 and t['block_types']['tool_use']==40, t
assert t['last30_turn_bytes']>0 and t['p90_line_bytes']>0, t
assert t['has_compact_boundary'] is True
"
  [ "$status" -eq 0 ]
}

@test "transcript ausente / fuera de la carpeta del frontend / enlace simbólico" {
  echo '{"type":"user"}' > "$T/out.jsonl"
  ln -s "$T/out.jsonl" "$HOME/.claude/projects/p1/link.jsonl"
  for tp in "$HOME/.claude/projects/p1/nope.jsonl" "$T/out.jsonl" "$HOME/.claude/projects/p1/link.jsonl"; do
    run bash -c "printf '%s' '{\"transcript_path\":\"$tp\"}' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PreCompact --frontend claude-code"
    [ "$status" -eq 0 ]
  done
  run python3 -I -c "
import json
rs=[json.loads(l)['transcript'] for l in open('$SAVIA_COMPACT_SHAPE_LOG')]
assert rs[0]['exists'] is False and rs[0]['base']=='frontend_data_dir', rs[0]
assert rs[1]['exists'] is True and rs[1]['base']=='other', rs[1]
assert rs[2]['symlink'] is True and rs[2]['base']=='other', rs[2]
assert 'line_count' not in rs[1] and 'line_count' not in rs[2]
"
  [ "$status" -eq 0 ]
}

@test "transcript enorme: solo lee el final y lo declara" {
  TP="$HOME/.claude/projects/p1/big.jsonl"
  python3 -I - "$TP" <<'PY'
import json,sys
with open(sys.argv[1],'w') as f:
    for i in range(30000):
        f.write(json.dumps({"type":"user","message":{"role":"user","content":"x"*400}})+"\n")
PY
  run bash -c "printf '%s' '{\"transcript_path\":\"$TP\"}' | SAVIA_COMPACT_SHAPE=1 SAVIA_COMPACT_SHAPE_MAX_READ=1048576 python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  run python3 -I -c "
import json
t=json.loads(open('$SAVIA_COMPACT_SHAPE_LOG').readline())['transcript']
assert t['truncated'] is True and t['size_bytes']>1048576, t
assert t['bytes_read']<=1048576, t
"
  [ "$status" -eq 0 ]
}

@test "el registro queda con permisos privados" {
  run bash -c "echo '{}' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$SAVIA_COMPACT_SHAPE_LOG")" = "600" ]
  [ "$(stat -c %a "$(dirname "$SAVIA_COMPACT_SHAPE_LOG")")" = "700" ]
}

@test "ruta de registro imposible: exit 0 sin romper la compactación" {
  run bash -c "echo '{}' | SAVIA_COMPACT_SHAPE=1 SAVIA_COMPACT_SHAPE_LOG=/proc/nope/x.jsonl python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tipos de línea con guion (queue-operation) se registran con su nombre; con texto libre, como other" {
  TP="$HOME/.claude/projects/p1/h.jsonl"
  printf '%s\n' '{"type":"queue-operation"}' "{\"type\":\"hola $SENT con espacios\"}" > "$TP"
  run bash -c "printf '%s' '{\"transcript_path\":\"$TP\"}' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  run grep -q "$SENT" "$SAVIA_COMPACT_SHAPE_LOG"
  [ "$status" -ne 0 ]
  run python3 -I -c "
import json
t=json.loads(open('$SAVIA_COMPACT_SHAPE_LOG').readline())['transcript']
assert t['line_types']=={'queue-operation':1,'other':1}, t
"
  [ "$status" -eq 0 ]
}

@test "sonda: --dry-run genera ajustes temporales con 3 eventos y sin la marca en la orden" {
  run python3 -I "$REPO_ROOT/scripts/compaction-shape-probe.py" --dry-run --out "$T/probe"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -I -c "
import json,sys
s=json.load(sys.stdin)['hooks']
assert set(s)=={'PreCompact','PostCompact','SessionStart'}, s
assert any(h['matcher']=='compact' for h in s['SessionStart'])
"
  # marcas conocidas: el valor se lee del fichero en tiempo de ejecución y no está en ningún script
  mkdir -p "$T/probe/work"
  M1="aaaaaaaaaaaa"; M2="bbbbbbbbbbbb"
  python3 -I - "$REPO_ROOT/scripts/compaction-shape-probe.py" "$T/probe" "$M1" "$M2" <<'PY'
import importlib.util, sys, os
src, out, m1, m2 = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("probe", src); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
os.makedirs(out + "/hooks", exist_ok=True)
open(out + "/m1", "w").write(m1 + "\n"); open(out + "/m2", "w").write(m2 + "\n")
m.build(out, out + "/m1", out + "/m2")
PY
  run grep -rl -e "$M1" -e "$M2" "$T/probe/hooks" "$T/probe/settings.json"
  [ "$status" -ne 0 ]
  run bash "$T/probe/hooks/post.sh" </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "ZMK-$M1" ]
  run bash "$T/probe/hooks/sc.sh" </dev/null
  [ "$output" = "ZMK-$M2" ]
}

@test "sonda: una ruta con comilla simple no inyecta órdenes en el hook" {
  EVIL="$T/x'; touch $T/pwned; echo '"
  run python3 -I "$REPO_ROOT/scripts/compaction-shape-probe.py" --dry-run --out "$EVIL"
  [ "$status" -eq 0 ]
  run bash "$EVIL/hooks/pre.sh" </dev/null
  [ "$status" -eq 0 ]
  [ ! -e "$T/pwned" ]
  [ -e "$EVIL/shape.jsonl" ]
}

@test "sonda: rounds inválido falla (fail-closed)" {
  run python3 -I "$REPO_ROOT/scripts/compaction-shape-probe.py" --rounds 0 --dry-run --out "$T/probe"
  [ "$status" -ne 0 ]
}

@test "tipos de línea que parecen palabra corta pero no son del vocabulario: other" {
  TP="$HOME/.claude/projects/p1/e.jsonl"
  printf '{"type":"zqxjsentinel","subtype":"zqxjsub","message":{"content":[{"type":"zqxjblock"}]}}\n' > "$TP"
  run bash -c "printf '%s' '{\"transcript_path\":\"$TP\"}' | SAVIA_COMPACT_SHAPE=1 python3 -I '$COL' --event PreCompact --frontend claude-code"
  [ "$status" -eq 0 ]
  run grep -qi "zqxj" "$SAVIA_COMPACT_SHAPE_LOG"
  [ "$status" -ne 0 ]
  run python3 -I -c "
import json
t=json.loads(open('$SAVIA_COMPACT_SHAPE_LOG').readline())['transcript']
assert t['line_types']=={'other:other':1}, t
"
  [ "$status" -eq 0 ]
}
