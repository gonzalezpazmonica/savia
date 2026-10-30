#!/usr/bin/env bash
# scripts/lib/savia-identity.sh — Fuente única de la identidad de Savia (SE-483)
# Source this from other scripts: source "$ROOT/scripts/lib/savia-identity.sh"
# Provides: savia_identity long|short → imprime la frase canónica.
#           savia_identity_check      → verifica que las superficies la contienen.
# Lee `.claude/profiles/savia.md`, sección «Identidad canónica», entre los
# marcadores <!-- identity:long --> / <!-- /identity:long --> (ídem short).
# Fail-closed: si falta el fichero, un marcador o la frase, sale con 1 y no
# imprime nada; ningún generador debe escribir una identidad vacía.
# Uso directo: bash scripts/lib/savia-identity.sh check   (exit 0 PASS, 1 FAIL)

savia_identity() {
  local kind="${1:-}" root="${SAVIA_IDENTITY_ROOT:-}"
  case "$kind" in long|short) ;; *) echo "savia_identity: tipo inválido '$kind' (long|short)" >&2; return 1 ;; esac
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  local src="${SAVIA_IDENTITY_FILE:-$root/.claude/profiles/savia.md}"
  [[ -f "$src" ]] || { echo "savia_identity: falta $src" >&2; return 1; }
  local phrase
  # Solo se emite si el bloque abre y cierra: un marcador huérfano no vale.
  phrase=$(awk -v op="<!-- identity:$kind -->" -v cl="<!-- /identity:$kind -->" '
    $0 == op { inside=1; next }
    $0 == cl && inside { closed=1; exit }
    inside { sub(/^> ?/, ""); if (length($0)) { buf = buf sep $0; sep=" " } }
    END { if (closed) printf "%s", buf }
  ' "$src")
  [[ -n "$phrase" ]] || { echo "savia_identity: frase '$kind' vacía o sin marcadores en $src" >&2; return 1; }
  printf '%s\n' "$phrase"
}

# Superficies que deben llevar la frase literal (SE-483 AC-2).
SAVIA_IDENTITY_LONG_SURFACES=(CLAUDE.md AGENTS.md README.md llms.txt)
SAVIA_IDENTITY_SHORT_SURFACES=(docs/critical-facts.md plugin.json .claude-plugin/plugin.json)

savia_identity_check() {
  local root="${SAVIA_IDENTITY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  local long short f fails=0
  long=$(savia_identity long) || return 1
  short=$(savia_identity short) || return 1
  for f in "${SAVIA_IDENTITY_LONG_SURFACES[@]}"; do
    grep -qF -- "$long" "$root/$f" 2>/dev/null || { echo "FAIL: $f sin la frase larga canónica"; fails=$((fails+1)); }
  done
  for f in "${SAVIA_IDENTITY_SHORT_SURFACES[@]}"; do
    grep -qF -- "$short" "$root/$f" 2>/dev/null || { echo "FAIL: $f sin la frase corta canónica"; fails=$((fails+1)); }
  done
  if (( fails > 0 )); then
    echo "Regenerar: bash scripts/generate-critical-facts.sh · bash scripts/agents-md-generate.sh --apply · bash scripts/llms-txt-generate.sh; CLAUDE.md, README.md y plugin.json a mano"
    return 1
  fi
  echo "PASS: identidad canónica presente en $(( ${#SAVIA_IDENTITY_LONG_SURFACES[@]} + ${#SAVIA_IDENTITY_SHORT_SURFACES[@]} )) superficies"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  case "${1:-}" in
    check) savia_identity_check; exit $? ;;
    long|short) savia_identity "$1"; exit $? ;;
    *) echo "Uso: savia-identity.sh check|long|short" >&2; exit 2 ;;
  esac
fi
