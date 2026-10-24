#!/usr/bin/env bash
# release-invariants.sh — SE-379: hace imposibles en CI las inconsistencias públicas básicas.
# Uso: release-invariants.sh [--root DIR]   (default: repo root; --root para fixtures de test)
# Exit 0 = todas las invariantes OK (o skipped por falta de ficheros); exit 1 = alguna rota.
# Códigos: VERSION_REGRESSION CHANGELOG_VERSION_MISMATCH STALE_COUNTER
#          STALE_TRANSLATION ROADMAP_TIMESTAMP_DRIFT CHANGELOG_VERSION_MISMATCH
#          CAPABILITY_COUNT_MISMATCH GENERATED_VIEW_DRIFT
# SE-379 — docs/specs/SE-379-release-metadata-invariants.spec.md
set -uo pipefail
ROOT="."
[[ "${1:-}" == "--root" ]] && { ROOT="${2:-.}"; shift 2; }

FAILURES=()
fail() { FAILURES+=("$1"); echo "FAIL: $1"; }
ok() { echo "PASS: $1"; }
skip() { echo "SKIP: $1 (ficheros ausentes en root)"; }

changelog="$ROOT/CHANGELOG.md"
readme="$ROOT/README.md"
pkg="$ROOT/package.json"

# ── 1. VERSION_REGRESSION: una sola versión actual y sin duplicados ──────
if [[ -f "$changelog" ]]; then
  dup=$(grep -oP '^## \[\K[0-9.]+' "$changelog" | sort | uniq -d)
  if [[ -n "$dup" ]]; then
    fail "VERSION_REGRESSION: versiones duplicadas en CHANGELOG: $dup"
  else
    ok "VERSION_REGRESSION: sin duplicados"
  fi
else
  skip "VERSION_REGRESSION"
fi

# ── 2. CHANGELOG_VERSION_MISMATCH: package.json vs CHANGELOG ─────────────
if [[ -f "$changelog" && -f "$pkg" ]]; then
  cl_v=$(grep -oP '^## \[\K[0-9.]+' "$changelog" | head -1)
  pk_v=$(grep -oP '"version":\s*"\K[0-9.]+' "$pkg" | head -1)
  if [[ -n "$pk_v" && "$cl_v" != "$pk_v" ]]; then
    fail "CHANGELOG_VERSION_MISMATCH: CHANGELOG=$cl_v package.json=$pk_v"
  else
    ok "CHANGELOG_VERSION_MISMATCH"
  fi
else
  skip "CHANGELOG_VERSION_MISMATCH"
fi

# ── 3+4. Contadores reales vs README / traducciones ──────────────────────
count_disk() {
  case "$1" in
    comandos) find -L "$ROOT/.opencode/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l ;;
    agentes)  find "$ROOT/.opencode/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l ;;
    skills)   find "$ROOT/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l ;;
    hooks)    python3 -c "import json,sys;d=json.load(open('$ROOT/.claude/settings.json'));print(sum(len(m.get('hooks',[])) for ev in d.get('hooks',{}).values() for m in ev))" 2>/dev/null || echo 0 ;;
  esac
}
extract_readme_counts() {  # $1=file → imprime "comandos agentes skills hooks"
  grep -oP '(\d+)\s+comandos\s+·\s+(\d+)\s+agentes\s+·\s+(\d+)\s+skills\s+·\s+(\d+)\s+hooks' "$1" \
    | sed -E 's/([0-9]+) comandos · ([0-9]+) agentes · ([0-9]+) skills · ([0-9]+) hooks/\1 \2 \3 \4/' | head -1
}
if [[ -f "$readme" && -d "$ROOT/.opencode" ]]; then
  DISK="$(count_disk comandos) $(count_disk agentes) $(count_disk skills) $(count_disk hooks)"
  RD=$(extract_readme_counts "$readme")
  if [[ -z "$RD" ]]; then
    fail "STALE_COUNTER: README.md sin línea de contadores canónica"
  elif [[ "$RD" != "$DISK" ]]; then
    fail "CAPABILITY_COUNT_MISMATCH: README=($RD) disco=($DISK)"
  else
    ok "CAPABILITY_COUNT_MISMATCH"
  fi
  # ── STALE_TRANSLATION: traducciones con los mismos números que README ──
  bad_tr=""
  for tr in "$ROOT"/README.ca.md "$ROOT"/README.gl.md "$ROOT"/README.pt.md; do
    [[ -f "$tr" ]] || continue
    TR=$(extract_readme_counts "$tr")
    [[ -n "$TR" && "$TR" != "$RD" ]] && bad_tr="$bad_tr $(basename "$tr")($TR)"
  done
  [[ -n "$bad_tr" ]] && fail "STALE_TRANSLATION:$bad_tr" || ok "STALE_TRANSLATION"
else
  skip "CAPABILITY_COUNT_MISMATCH/STALE_TRANSLATION"
fi

# ── 5. ROADMAP_TIMESTAMP_DRIFT: roadmap menciona el año de la versión vigente ──
if [[ -f "$changelog" && -f "$ROOT/docs/ROADMAP.md" ]]; then
  cl_date=$(grep -oP '^## \[[0-9.]+\] — \K[0-9]{4}' "$changelog" | head -1)
  if [[ -n "$cl_date" ]] && ! grep -q "$cl_date" "$ROOT/docs/ROADMAP.md"; then
    fail "ROADMAP_TIMESTAMP_DRIFT: docs/ROADMAP.md no menciona el año $cl_date de la versión vigente"
  else
    ok "ROADMAP_TIMESTAMP_DRIFT"
  fi
else
  skip "ROADMAP_TIMESTAMP_DRIFT"
fi

# ── 6. GENERATED_VIEW_DRIFT: regenera el capability map en sandbox y compara ──
idx="$ROOT/.scm/INDEX.scm"
if [[ -f "$idx" && -x "$ROOT/scripts/generate-capability-map.py" ]]; then
  SB_VIEW=$(mktemp -d)
  # Enlaces duros si es posible (mismo dispositivo); por directorio, con
  # copia real como respaldo si falla (tmpfs, bind mounts, otro mount).
  for d in .claude .opencode scripts docs; do
    cp -al "$ROOT/$d" "$SB_VIEW/$d" 2>/dev/null || {
      mkdir -p "$SB_VIEW/$d"
      cp -a "$ROOT/$d/." "$SB_VIEW/$d/" 2>/dev/null
    }
  done
  ( cd "$SB_VIEW" && timeout 120 python3 "$SB_VIEW/scripts/generate-capability-map.py" >/dev/null 2>&1 )
  REG="$ROOT/.scm/registry.json"
  if [[ ! -f "$SB_VIEW/.scm/INDEX.scm" ]]; then
    fail "GENERATED_VIEW_DRIFT: no se pudo regenerar en sandbox"
  elif ! cmp -s "$SB_VIEW/.scm/INDEX.scm" "$idx"; then
    fail "GENERATED_VIEW_DRIFT: .scm/INDEX.scm difiere de la regeneración (ejecutar generate-capability-map.py)"
  elif [[ -f "$REG" ]] && ! cmp -s "$SB_VIEW/.scm/registry.json" "$REG"; then
    fail "GENERATED_VIEW_DRIFT: .scm/registry.json difiere de la regeneración (ejecutar generate-capability-map.py)"
  else
    ok "GENERATED_VIEW_DRIFT"
  fi
  rm -rf "$SB_VIEW"
else
  skip "GENERATED_VIEW_DRIFT"
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo "-- release-invariants: ${#FAILURES[@]} invariante(s) rota(s)"
  exit 1
fi
echo "-- release-invariants: todo consistente"
exit 0
