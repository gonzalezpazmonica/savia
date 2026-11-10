# SE-493 S1 — helpers comunes de los tests del Effect Ledger.
# Remoto simulado: stub de `gh` en PATH que cuenta las peticiones de efecto (`gh pr merge`).
# Ledger temporal por test; HOME temporal; nunca se toca el HOME real.

SE493_HEAD_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SE493_HEAD_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
SE493_REPO="ejemplo/repo-a"

se493_setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LEDGER_PY="$REPO_DIR/scripts/effect-ledger.py"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SAVIA_EFFECT_TEST=1
  export SAVIA_EFFECT_LEDGER="$BATS_TEST_TMPDIR/led/ledger.db"
  unset SAVIA_EFFECT_NOW SAVIA_EFFECT_FAULT SAVIA_EFFECT_REGISTRY SAVIA_EFFECT_PROC SAVIA_AUTONOMOUS_RUN
  printf 'active_slug: "operadora-sintetica-a"\n' > "$BATS_TEST_TMPDIR/active-user.md"
  export SAVIA_ACTIVE_USER_FILE="$BATS_TEST_TMPDIR/active-user.md"
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
S="$(dirname "$0")"
case "$1 $2" in
  "api user")
    [[ -f "$S/user.rc" ]] && exit "$(cat "$S/user.rc")"
    cat "$S/user" 2>/dev/null; exit 0 ;;
  "pr view")
    echo x >> "$S/view.count"
    cat "$S/view.out" 2>/dev/null; exit "$(cat "$S/view.rc" 2>/dev/null || echo 0)" ;;
  "pr merge")
    echo x >> "$S/merge.count"
    exit "$(cat "$S/merge.rc" 2>/dev/null || echo 0)" ;;
esac
exit 1
EOF
  chmod +x "$STUB/gh"
  echo "cuenta-sintetica-a" > "$STUB/user"
  export PATH="$STUB:$PATH"
  se493_view_open "$SE493_HEAD_A"
}

se493_teardown() {
  local p
  [[ -f "$BATS_TEST_TMPDIR/holders" ]] || return 0
  while read -r p; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done < "$BATS_TEST_TMPDIR/holders"
  return 0
}

led() { python3 -I "$LEDGER_PY" "$@"; }

# Contador de peticiones de efecto (gh pr merge).
merges() { [[ -f "$STUB/merge.count" ]] && wc -l < "$STUB/merge.count" | tr -d ' ' || echo 0; }
views() { [[ -f "$STUB/view.count" ]] && wc -l < "$STUB/view.count" | tr -d ' ' || echo 0; }

se493_view_open() {  # head [autoMerge]
  local am="${2:-null}"
  printf '{"state":"OPEN","mergedAt":null,"mergeCommit":null,"mergedBy":null,"headRefOid":"%s","autoMergeRequest":%s}\n' "$1" "$am" > "$STUB/view.out"
  echo 0 > "$STUB/view.rc"
}
se493_view_merged() {  # head login [commit]
  printf '{"state":"MERGED","mergedAt":"2026-11-10T10:00:00Z","mergeCommit":{"oid":"%s"},"mergedBy":{"login":"%s"},"headRefOid":"%s","autoMergeRequest":null}\n' \
    "${3:-cccccccccccccccccccccccccccccccccccccccc}" "$2" "$1" > "$STUB/view.out"
  echo 0 > "$STUB/view.rc"
}
se493_view_raw() { printf '%s' "$1" > "$STUB/view.out"; echo "${2:-0}" > "$STUB/view.rc"; }

# Proceso llamador vivo; su PID se pasa con --holder-pid.
# stdio redirigida: un hijo con la salida abierta colgaría `run`.
se493_holder() { sleep 600 >/dev/null 2>&1 </dev/null & HOLDER=$!; echo "$HOLDER" >> "$BATS_TEST_TMPDIR/holders"; }

# prepare de pr.merge con un llamador vivo. Uso: se493_prepare <N> <head> [method] [extra...]
se493_prepare() {
  local n="$1" h="$2" m="${3:-squash}"; shift 3 2>/dev/null || shift $#
  se493_holder
  led prepare pr.merge --repo "$SE493_REPO" --number "$n" --head "$h" --method "$m" --holder-pid "$HOLDER" "$@"
}

# Lleva PR <n> a DISPATCHED con head <h>. Deja EID, TOK y DISPATCHED_AT.
se493_to_dispatched() {
  local n="$1" h="${2:-$SE493_HEAD_A}" out
  se493_view_open "$h"
  out=$(se493_prepare "$n" "$h" squash) || return 1
  read -r _ EID TOK <<<"$out"
  led dispatch "$EID" --claim "$TOK" >/dev/null || return 1
  DISPATCHED_AT=$(led status "$SE493_REPO#$n" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["dispatched_at"])')
}

# Campo del registro actual de una clave.
field() { led status "$1" | python3 -I -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print("" if v is None else v)' "$2"; }
