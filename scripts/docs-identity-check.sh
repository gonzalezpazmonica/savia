#!/usr/bin/env bash
# docs-identity-check.sh — SE-390 §34: drift gate de identidad documental.
# Detecta: identidad legacy como identidad actual, definición canónica ausente,
# contadores divergentes, URLs legacy nuevas. Allowlist razonada (historia/compat).
#
# SE-483: también es la fuente programática de la identidad canónica.
#   source scripts/docs-identity-check.sh   → savia_identity long|short,
#                                             savia_identity_check (sin ejecutar el gate)
#   bash scripts/docs-identity-check.sh      → gate completo (incluye la frase canónica)
#   bash scripts/docs-identity-check.sh canonical|long|short
# La frase vive en .claude/profiles/savia.md entre <!-- identity:long --> y
# <!-- /identity:long --> (ídem short). Fail-closed: sin fichero, sin marcador
# de cierre o sin frase → exit 1 y nada en stdout.

savia_identity() {
  local kind="${1:-}" root="${SAVIA_IDENTITY_ROOT:-}"
  case "$kind" in long|short) ;; *) echo "savia_identity: tipo inválido '$kind' (long|short)" >&2; return 1 ;; esac
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  local root="${SAVIA_IDENTITY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

set -uo pipefail
case "${1:-}" in
  canonical) savia_identity_check; exit $? ;;
  long|short) savia_identity "$1"; exit $? ;;
  "") ;;
  *) echo "Uso: docs-identity-check.sh [canonical|long|short]" >&2; exit 2 ;;
esac
ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
FAILS=0

# ── 1. First-screen identity: README empieza como Savia, no como PM-Workspace
first_h1=$(grep -m1 '^# ' "$ROOT/README.md" 2>/dev/null || echo "")
if [[ "$first_h1" != "# Savia" ]]; then
  echo "FAIL: README.md título actual no es '# Savia' (es: $first_h1)"; FAILS=$((FAILS+1))
fi

# ── 2. Definición canónica corta presente en README y traducciones
DEF_ES="Sistema agéntico soberano para gobernar y ejecutar trabajo con IA"
for f in "$ROOT"/README.md "$ROOT"/README.en.md "$ROOT"/README.ca.md "$ROOT"/README.gl.md "$ROOT"/README.pt.md "$ROOT"/README.fr.md "$ROOT"/README.de.md "$ROOT"/README.it.md "$ROOT"/README.eu.md; do
  [[ -f "$f" ]] || continue
  if ! grep -qiE "soberan|sovereign|sobiran|souver|sovran|subiran" "$f"; then
    echo "FAIL: $f sin identidad canónica (agéntico soberano)"; FAILS=$((FAILS+1))
  fi
done

# ── 3. Contadores de capacidades == realidad (derivados)
c_cmds=$(find -L "$ROOT/.opencode/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
c_agents=$(find "$ROOT/.opencode/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
c_skills=$(find "$ROOT/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
line=$(grep -m1 -oP '[0-9]+ comandos · [0-9]+ agentes · [0-9]+ skills · [0-9]+ hooks' "$ROOT/README.md" 2>/dev/null || echo "")
exp="$c_cmds comandos · $c_agents agentes · $c_skills skills"
if [[ -n "$line" && "$line" != "$exp"* ]]; then
  echo "FAIL: contadores README ($line) != realidad ($exp)"; FAILS=$((FAILS+1))
fi

# ── 4. URLs legacy nuevas en fuentes de identidad (allowlist: histórico/compat)
# Los badges/installs deben apuntar a gonzalezpazmonica/savia
bad_urls=$(grep -rn "gonzalezpazmonica/pm-workspace" "$ROOT/README.md" 2>/dev/null | grep -vEi "origin|history|históric|legacy|compatibility|compatibilidad" | head -3)
[[ -n "$bad_urls" ]] && { echo "FAIL: URLs legacy como identidad actual en README.md:"; echo "$bad_urls"; FAILS=$((FAILS+1)); }

# ── 5. Identidad de máquina (CLAUDE.md/AGENTS.md) reciben Savia
for f in "$ROOT/CLAUDE.md" "$ROOT/AGENTS.md"; do
  [[ -f "$f" ]] || continue
  grep -qiE "Savia" "$f" || { echo "FAIL: $f sin identidad Savia"; FAILS=$((FAILS+1)); }
done

# ── 6. pm-workspace como identidad ACTUAL en primeras 15 líneas de README (allowlist marker)
head15=$(head -15 "$ROOT/README.md")
if echo "$head15" | grep -qi "pm-workspace es\|pm-workspace convierte" && ! echo "$head15" | grep -qiE "origen|origin|históric|legacy|antes"; then
  echo "FAIL: README first-screen usa identidad legacy como actual"; FAILS=$((FAILS+1))
fi


# ── 7. URLs operativas legacy NO permitidas (raw / actions / clone / cd) ──
LEG=$(grep -rn "github.com/gonzalezpazmonica/pm-workspace" "$ROOT"/README*.md 2>/dev/null | grep -viE "histor|origin|legacy|antes|nac|born|nacio" | head -3)
[[ -n "$LEG" ]] && { echo "FAIL: URLs operativas legacy pm-workspace en README*:"; echo "$LEG"; FAILS=$((FAILS+1)); }

# ── 8. Contadores uniformes: las 9 traducciones == canonical de README.md ──
CANON=$(grep -m1 -oP '\*\*[0-9]+ [a-zç]+[^\*]{0,80}\[0-9]+\|hooks[^\*]{0,20}\*\*' "$ROOT/README.md" 2>/dev/null | head -1)
for f in "$ROOT"/README.en.md "$ROOT"/README.ca.md "$ROOT"/README.gl.md "$ROOT"/README.eu.md "$ROOT"/README.fr.md "$ROOT"/README.de.md "$ROOT"/README.pt.md "$ROOT"/README.it.md; do
  [[ -f "$f" ]] || continue
  # canonical numbers presentes y sin numeros stale 532/65/86/58
  if grep -qE "532|65 agents|65 agents|86 skills|58 hooks" "$f"; then
    echo "FAIL: contadores stale en $(basename "$f")"; FAILS=$((FAILS+1))
  fi
done
# canonical: README y traducciones deben tener 567 ... 89 ... 136 ... 124
for f in "$ROOT"/README*.md; do
  [[ -f "$f" ]] || continue
  if ! grep -qE "567" "$f"; then
    echo "FAIL: $(basename "$f") sin contador canonical 567"; FAILS=$((FAILS+1))
  fi
done

# ── 9. Frase canónica (SE-483): superficies == fuente única de savia.md ──
SAVIA_IDENTITY_ROOT="$ROOT" savia_identity_check >/dev/null || { SAVIA_IDENTITY_ROOT="$ROOT" savia_identity_check; FAILS=$((FAILS+1)); }

if [[ $FAILS -gt 0 ]]; then echo "-- docs-identity-check: $FAILS fallo(s)"; exit 1; fi
echo "PASS: identidad documental consistente (Savia)"
exit 0
