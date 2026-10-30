#!/usr/bin/env bash
# scripts/lib/savia-identity.sh — Fuente única de la identidad de Savia (SE-483)
# Source this from other scripts: source "$ROOT/scripts/lib/savia-identity.sh"
# Provides: savia_identity long|short → imprime la frase canónica.
# Lee `.claude/profiles/savia.md`, sección «Identidad canónica», entre los
# marcadores <!-- identity:long --> / <!-- /identity:long --> (ídem short).
# Fail-closed: si falta el fichero, el marcador o la frase, sale con 1 y no
# imprime nada; ningún generador debe escribir una identidad vacía.

savia_identity() {
  local kind="${1:-}" root="${SAVIA_IDENTITY_ROOT:-}"
  case "$kind" in long|short) ;; *) echo "savia_identity: tipo inválido '$kind' (long|short)" >&2; return 1 ;; esac
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  local src="${SAVIA_IDENTITY_FILE:-$root/.claude/profiles/savia.md}"
  [[ -f "$src" ]] || { echo "savia_identity: falta $src" >&2; return 1; }
  local phrase
  phrase=$(awk -v op="<!-- identity:$kind -->" -v cl="<!-- /identity:$kind -->" '
    $0 == op { inside=1; next }
    $0 == cl { inside=0; exit }
    inside { sub(/^> ?/, ""); if (length($0)) { printf "%s%s", sep, $0; sep=" " } }
  ' "$src")
  [[ -n "$phrase" ]] || { echo "savia_identity: frase '$kind' vacía o sin marcadores en $src" >&2; return 1; }
  printf '%s\n' "$phrase"
}
