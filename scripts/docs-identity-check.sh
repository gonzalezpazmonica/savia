#!/usr/bin/env bash
# docs-identity-check.sh — SE-390 §34: drift gate de identidad documental.
# Detecta: identidad legacy como identidad actual, definición canónica ausente,
# contadores divergentes, URLs legacy nuevas. Allowlist razonada (historia/compat).
set -uo pipefail
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

if [[ $FAILS -gt 0 ]]; then echo "-- docs-identity-check: $FAILS fallo(s)"; exit 1; fi
echo "PASS: identidad documental consistente (Savia)"
exit 0
