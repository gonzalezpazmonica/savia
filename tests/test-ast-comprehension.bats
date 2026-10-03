#!/usr/bin/env bats
# test-ast-comprehension.bats — calibracion SE-376 de la skill ast-comprehension
# Ref: .claude/skills/ast-comprehension/SKILL.md (extraccion monolitica)
# Ref: docs/ast-strategy.md
# Ejercita scripts/ast-comprehend.sh con ficheros sinteticos de estructura
# conocida: clases, funciones e imports esperados se fijan de antemano.

SCRIPT="scripts/ast-comprehend.sh"
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SH="$REPO_ROOT/$SCRIPT"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}

# jq_py <expr-python sobre d> — evalua una expresion sobre el JSON de stdin
jq_py() {
  python3 -c "import json,sys; d=json.load(sys.stdin); print(($1))"
}

mk_python() {
  cat > "$1" <<'EOF'
import os
from collections import OrderedDict
class Foo:
    def bar(self):
        return 1
    async def qux(self):
        return 2
def baz():
    pass
EOF
}

mk_go() {
  cat > "$1" <<'EOF'
package main
import "fmt"
type Server struct{}
type Handler interface{}
func Hello() { fmt.Println("x") }
func (s *Server) Run() {}
EOF
}

# ── Contrato basico ──────────────────────────────────────────────────────────

@test "script uses set -uo pipefail and passes bash -n" {
  run grep -c '^set -uo pipefail' "$SH"
  [ "$output" -ge 1 ]
  run bash -n "$SH"
  [ "$status" -eq 0 ]
}

@test "python: output includes structure with classes, methods, functions and imports" {
  mk_python "$TMPDIR_TEST/a.py"
  run bash "$SH" "$TMPDIR_TEST/a.py"
  [ "$status" -eq 0 ]
  echo "$output" | jq_py "d['meta']['tool']" | grep -qx 'python-ast'
  run jq_py "sorted(c['name'] for c in d['structure']['classes'])" <<< "$output"
  [ "$output" = "['Foo']" ]
  mk_python "$TMPDIR_TEST/a.py"
  out=$(bash "$SH" "$TMPDIR_TEST/a.py")
  run jq_py "sorted(m['name'] for m in d['structure']['classes'][0]['methods'])" <<< "$out"
  [ "$output" = "['bar', 'qux']" ]
  run jq_py "'baz' in [f['name'] for f in d['structure']['functions']]" <<< "$out"
  [ "$output" = "True" ]
  run jq_py "d['structure']['imports']" <<< "$out"
  [ "$output" = "['os', 'from collections']" ]
}

@test "python: summary counts match the structure lists" {
  mk_python "$TMPDIR_TEST/a.py"
  out=$(bash "$SH" "$TMPDIR_TEST/a.py")
  run jq_py "len(d['structure']['classes']), len(d['structure']['functions'])" <<< "$out"
  [ "$output" = "(1, 3)" ]
  [[ "$out" == *"1 clase(s), 3 función(es)"* ]]
  # Contrato: functions incluye los metodos (ast.walk) y va ordenado por linea.
  run jq_py "[f['name'] for f in d['structure']['functions']]" <<< "$out"
  [ "$output" = "['bar', 'qux', 'baz']" ]
}

@test "grep fallback: go structs, interfaces and funcs detected without gawk" {
  mk_go "$TMPDIR_TEST/b.go"
  run bash "$SH" "$TMPDIR_TEST/b.go" --surface-only
  [ "$status" -eq 0 ]
  [[ "$output" != *"gensub"* ]]
  run jq_py "sorted(c['name'] for c in d['structure']['classes'])" <<< "$(bash "$SH" "$TMPDIR_TEST/b.go" --surface-only 2>/dev/null)"
  [ "$output" = "['Handler', 'Server']" ]
  run jq_py "sorted(f['name'] for f in d['structure']['functions'])" <<< "$(bash "$SH" "$TMPDIR_TEST/b.go" --surface-only 2>/dev/null)"
  [ "$output" = "['Hello', 'Run']" ]
}

@test "grep fallback: import with double quotes yields valid escaped JSON" {
  mk_go "$TMPDIR_TEST/b.go"
  run bash "$SH" "$TMPDIR_TEST/b.go" --surface-only
  [ "$status" -eq 0 ]
  run jq_py "d['structure']['imports']" <<< "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "['import \"fmt\"']" ]
}

@test "grep fallback: rust import line with colons is not truncated" {
  printf 'use std::collections::HashMap;\nstruct Cache {}\npub trait Store {}\nfn get() {}\n' > "$TMPDIR_TEST/c.rs"
  out=$(bash "$SH" "$TMPDIR_TEST/c.rs" --surface-only)
  run jq_py "d['structure']['imports']" <<< "$out"
  [ "$output" = "['use std::collections::HashMap;']" ]
  run jq_py "[c['name'] for c in d['structure']['classes']], [f['name'] for f in d['structure']['functions']]" <<< "$out"
  [ "$output" = "(['Cache', 'Store'], ['get'])" ]
}

@test "tool field is truthful: never claims gopls or ts-morph when absent" {
  mk_go "$TMPDIR_TEST/b.go"
  printf 'export class Svc {}\nexport function run() {}\n' > "$TMPDIR_TEST/c.ts"
  gt=$(bash "$SH" "$TMPDIR_TEST/b.go" 2>/dev/null | jq_py "d['meta']['tool']")
  tt=$(bash "$SH" "$TMPDIR_TEST/c.ts" 2>/dev/null | jq_py "d['meta']['tool']")
  if ! command -v gopls >/dev/null 2>&1; then [ "$gt" = "grep-structural" ]; fi
  if ! node -e "require('ts-morph')" >/dev/null 2>&1; then [ "$tt" = "grep-structural" ]; fi
  run jq_py "sorted(c['name'] for c in d['structure']['classes'])" <<< "$(bash "$SH" "$TMPDIR_TEST/c.ts" 2>/dev/null)"
  [ "$output" = "['Svc']" ]
}

# ── Complejidad ──────────────────────────────────────────────────────────────

@test "boundary: zero decision points gives 0 with no stderr noise" {
  printf 'def a():\n    return 1\n' > "$TMPDIR_TEST/z.py"
  run --separate-stderr bash "$SH" "$TMPDIR_TEST/z.py"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  run jq_py "d['complexity']['total_decision_points'], d['complexity']['hotspots'][0]['warn']" <<< "$output"
  [ "$output" = "(0, False)" ]
}

@test "boundary: 15 decision points do not warn, 16 do" {
  for i in $(seq 1 15); do echo "if (x$i) {}"; done > "$TMPDIR_TEST/w15.js"
  for i in $(seq 1 16); do echo "if (x$i) {}"; done > "$TMPDIR_TEST/w16.js"
  run jq_py "d['complexity']['total_decision_points'], d['complexity']['hotspots'][0]['warn']" <<< "$(bash "$SH" "$TMPDIR_TEST/w15.js" 2>/dev/null)"
  [ "$output" = "(15, False)" ]
  run jq_py "d['complexity']['total_decision_points'], d['complexity']['hotspots'][0]['warn']" <<< "$(bash "$SH" "$TMPDIR_TEST/w16.js" 2>/dev/null)"
  [ "$output" = "(16, True)" ]
}

# ── Errores y argumentos ─────────────────────────────────────────────────────

@test "error: no target exits 1 with JSON error on stderr" {
  run --separate-stderr bash "$SH"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *'"error"'* ]]
}

@test "error: nonexistent target fails with non-zero exit and empty stdout" {
  run --separate-stderr bash "$SH" "$TMPDIR_TEST/nope"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  echo "$stderr" | jq_py "d['error']" | grep -q 'Target not found'
}

@test "invalid: unknown flag is rejected with exit 2" {
  mk_python "$TMPDIR_TEST/a.py"
  run --separate-stderr bash "$SH" "$TMPDIR_TEST/a.py" --bogus
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--bogus"* ]]
}

@test "invalid: --output without value is rejected with exit 2" {
  mk_python "$TMPDIR_TEST/a.py"
  run bash "$SH" "$TMPDIR_TEST/a.py" --output
  [ "$status" -eq 2 ]
}

@test "error: python syntax error is surfaced in structure.error" {
  printf 'def broken(:\n' > "$TMPDIR_TEST/bad.py"
  run bash "$SH" "$TMPDIR_TEST/bad.py"
  [ "$status" -eq 0 ]
  run jq_py "'error' in d['structure']" <<< "$output"
  [ "$output" = "True" ]
}

# ── Rutas, directorios y salida ──────────────────────────────────────────────

@test "edge: filename with double quote and spaces yields valid JSON" {
  mkdir -p "$TMPDIR_TEST/my dir"
  mk_python "$TMPDIR_TEST/my dir/we\"ird 'x.py"
  run bash "$SH" "$TMPDIR_TEST/my dir"
  [ "$status" -eq 0 ]
  run jq_py "len(d), d[0]['meta']['file'].endswith('we\"ird \\'x.py')" <<< "$output"
  [ "$output" = "(1, True)" ]
}

@test "empty: empty directory gives empty JSON array" {
  mkdir -p "$TMPDIR_TEST/empty"
  run bash "$SH" "$TMPDIR_TEST/empty"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "empty: zero-byte file reports 0 lines and empty structure" {
  : > "$TMPDIR_TEST/e.py"
  run bash "$SH" "$TMPDIR_TEST/e.py"
  [ "$status" -eq 0 ]
  run jq_py "d['meta']['lines'], d['structure']['classes'], d['structure']['functions']" <<< "$output"
  [ "$output" = "(0, [], [])" ]
}

@test "directory: walks sources and skips node_modules" {
  mkdir -p "$TMPDIR_TEST/p/src" "$TMPDIR_TEST/p/node_modules/x"
  mk_python "$TMPDIR_TEST/p/src/a.py"
  mk_go "$TMPDIR_TEST/p/src/b.go"
  echo 'function f(){}' > "$TMPDIR_TEST/p/node_modules/x/i.js"
  echo 'texto' > "$TMPDIR_TEST/p/src/README.md"
  run bash "$SH" "$TMPDIR_TEST/p"
  [ "$status" -eq 0 ]
  run jq_py "sorted(x['meta']['language'] for x in d)" <<< "$output"
  [ "$output" = "['go', 'python']" ]
}

@test "large: 600 functions are all reported, no silent truncation" {
  for i in $(seq 1 600); do echo "fn f$i() {}"; done > "$TMPDIR_TEST/big.rs"
  run bash "$SH" "$TMPDIR_TEST/big.rs"
  [ "$status" -eq 0 ]
  run jq_py "len(d['structure']['functions'])" <<< "$output"
  [ "$output" = "600" ]
}

@test "output: --output writes JSON to a path with spaces and keeps stdout empty" {
  mk_python "$TMPDIR_TEST/a.py"
  run --separate-stderr bash "$SH" "$TMPDIR_TEST/a.py" --output "$TMPDIR_TEST/out dir/r.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run jq_py "d['meta']['language']" < "$TMPDIR_TEST/out dir/r.json"
  [ "$output" = "python" ]
}

@test "concurrency: parallel --output to the same file leaves valid JSON" {
  mk_python "$TMPDIR_TEST/a.py"
  for i in 1 2 3 4; do
    bash "$SH" "$TMPDIR_TEST/a.py" --output "$TMPDIR_TEST/r.json" 2>/dev/null &
  done
  wait
  run jq_py "d['meta']['language']" < "$TMPDIR_TEST/r.json"
  [ "$status" -eq 0 ]
  [ "$output" = "python" ]
  run bash -c "ls '$TMPDIR_TEST' | grep -c 'r.json.'"
  [ "$output" = "0" ]
}

# ── Ficheros ilegibles (fail-closed) ─────────────────────────────────────────

@test "error: unreadable go file fails with exit 3 and structure.error, not an empty success" {
  [ "$(id -u)" -ne 0 ] || skip "root lee ficheros con modo 000"
  mk_go "$TMPDIR_TEST/u.go"
  chmod 000 "$TMPDIR_TEST/u.go"
  run --separate-stderr bash "$SH" "$TMPDIR_TEST/u.go" --surface-only
  chmod 600 "$TMPDIR_TEST/u.go"
  [ "$status" -eq 3 ]
  run jq_py "d['structure']['error'], d['meta']['tool']" <<< "$output"
  [ "$output" = "('unreadable', 'none')" ]
}

@test "error: unreadable python file is rejected through the python-ast layer too" {
  [ "$(id -u)" -ne 0 ] || skip "root lee ficheros con modo 000"
  mk_python "$TMPDIR_TEST/u.py"
  chmod 000 "$TMPDIR_TEST/u.py"
  run --separate-stderr bash "$SH" "$TMPDIR_TEST/u.py"
  chmod 600 "$TMPDIR_TEST/u.py"
  [ "$status" -eq 3 ]
  run jq_py "d['structure']['error'], d['summary'].startswith('No se pudo leer')" <<< "$output"
  [ "$output" = "('unreadable', True)" ]
}

@test "error: directory with one unreadable file keeps the rest and exits 3" {
  [ "$(id -u)" -ne 0 ] || skip "root lee ficheros con modo 000"
  mkdir -p "$TMPDIR_TEST/d"
  mk_python "$TMPDIR_TEST/d/a.py"
  mk_go "$TMPDIR_TEST/d/b.go"
  chmod 000 "$TMPDIR_TEST/d/b.go"
  run --separate-stderr bash "$SH" "$TMPDIR_TEST/d"
  chmod 600 "$TMPDIR_TEST/d/b.go"
  [ "$status" -eq 3 ]
  run jq_py "[(x['meta']['language'], x['structure'].get('error')) for x in d]" <<< "$output"
  [ "$output" = "[('python', None), ('go', 'unreadable')]" ]
}

# ── Discriminacion adicional (P2 de la revision) ─────────────────────────────

@test "grep fallback: csharp class with public and private methods" {
  cat > "$TMPDIR_TEST/s.cs" <<'EOF'
using System;
namespace App {
  public class Svc {
    public int Run(int x) { return x; }
    private static List<string> Helper() { return null; }
  }
}
EOF
  run bash "$SH" "$TMPDIR_TEST/s.cs"
  [ "$status" -eq 0 ]
  run jq_py "[c['name'] for c in d['structure']['classes']], [f['name'] for f in d['structure']['functions']], d['structure']['imports']" <<< "$output"
  [ "$output" = "(['Svc'], ['Run', 'Helper'], ['using System;'])" ]
}

@test "directory: skips vendor and dist, and lists files in sorted path order" {
  mkdir -p "$TMPDIR_TEST/p/vendor/v" "$TMPDIR_TEST/p/dist" "$TMPDIR_TEST/p/src"
  echo 'func V() {}' > "$TMPDIR_TEST/p/vendor/v/v.go"
  echo 'function d(){}' > "$TMPDIR_TEST/p/dist/d.js"
  for n in e c a d b; do echo "fn $n() {}" > "$TMPDIR_TEST/p/src/$n.rs"; done
  run bash "$SH" "$TMPDIR_TEST/p"
  [ "$status" -eq 0 ]
  run jq_py "[x['meta']['file'].rsplit('/', 1)[1] for x in d]" <<< "$output"
  [ "$output" = "['a.rs', 'b.rs', 'c.rs', 'd.rs', 'e.rs']" ]
}

@test "meta.lines counts lines of a non-empty file" {
  mk_go "$TMPDIR_TEST/b.go"
  run bash "$SH" "$TMPDIR_TEST/b.go" --surface-only
  [ "$status" -eq 0 ]
  run jq_py "d['meta']['lines']" <<< "$output"
  [ "$output" = "6" ]
}

@test "invalid: --output pointing to an existing directory fails and leaves no temp file" {
  mk_python "$TMPDIR_TEST/a.py"
  mkdir -p "$TMPDIR_TEST/outdir"
  run --separate-stderr bash "$SH" "$TMPDIR_TEST/a.py" --output "$TMPDIR_TEST/outdir"
  [ "$status" -ne 0 ]
  run bash -c "ls -A '$TMPDIR_TEST/outdir' | wc -l; ls '$TMPDIR_TEST' | grep -c 'outdir\\.' || true"
  [ "$output" = "$(printf '0\n0')" ]
}

@test "locale es_ES: output is identical to C locale" {
  mk_go "$TMPDIR_TEST/b.go"
  a=$(LC_ALL=C bash "$SH" "$TMPDIR_TEST/b.go" 2>/dev/null)
  b=$(LC_ALL=es_ES.UTF-8 bash "$SH" "$TMPDIR_TEST/b.go" 2>/dev/null)
  [ -n "$a" ]
  [ "$a" = "$b" ]
}
