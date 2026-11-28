#!/usr/bin/env bash
# rule-manifest-generate.sh — Generador determinista de rule-manifest (SE-338)
#
# Reconstruye docs/rules/domain/rule-manifest.json desde el filesystem con el
# schema actual {tier, consumers}. Read-only del resto del repo: NUNCA modifica
# reglas, CRITERIO ni CONSTITUCION. PURE_BASH + python3 stdlib, sin red
# (CRIT-001).
#
# Uso:
#   rule-manifest-generate.sh [--check] [--output FILE] [--domain-dir DIR]
#     --check       exit 1 si el manifest está stale (diff de inventario)
#     --output      default: docs/rules/domain/rule-manifest.json
#     --domain-dir  default: docs/rules/domain
#   Exit: 0 ok · 1 stale/FAIL · 2 usage

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CHECK=false
OUTPUT="$ROOT/docs/rules/domain/rule-manifest.json"
DOMAIN_DIR="$ROOT/docs/rules/domain"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --domain-dir) DOMAIN_DIR="$2"; shift 2 ;;
    --help|-h) sed -n '2,14p' "${BASH_SOURCE[0]}" | grep -E '^#' | sed 's/^#//'; exit 0 ;;
    *) echo "Uso: rule-manifest-generate.sh [--check] [--output FILE] [--domain-dir DIR]" >&2; exit 2 ;;
  esac
done

[[ -d "$DOMAIN_DIR" ]] || { echo "ERROR: $DOMAIN_DIR no existe" >&2; exit 2; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# 1) Inventario: basename + tier por frontmatter (excluye INDEX.md, manifest, archive/)
{
  for f in "$DOMAIN_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    b="$(basename "$f")"
    [[ "$b" == "INDEX.md" || "$b" == "rule-manifest.json" ]] && continue
    tier="dormant"
    ct=$(grep -m1 '^context_tier:' "$f" 2>/dev/null | sed 's/context_tier:\s*//; s/\r//')
    case "$ct" in
      L1) tier="tier1" ;;
      L2|L3) tier="tier2" ;;
      *) tier="dormant" ;;
    esac
    printf '%s\t%s\n' "$b" "$tier"
  done
} | sort > "$TMP.rules"

# 2) Generar JSON determinista (python3 stdlib) con sorted keys + counts
python3 - "$TMP.rules" <<'PY' > "$TMP.json"
import sys, json, datetime, os

rules_path = sys.argv[1]
entries = []
for line in open(rules_path):
    line = line.rstrip("\n")
    if not line.strip():
        continue
    base, tier = line.split("\t", 1)
    entries.append((base, tier))

entries.sort(key=lambda x: x[0])
rules = {b: {"tier": t, "consumers": ""} for b, t in entries}
t1 = sum(1 for t in entries if t[1] == "tier1")
t2 = sum(1 for t in entries if t[1] == "tier2")
dorm = sum(1 for t in entries if t[1] == "dormant")
manifest = {
    "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "total": len(entries),
    "tier1_count": t1,
    "tier2_count": t2,
    "dormant_count": dorm,
    "rules": rules,
}
json.dump(manifest, sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
PY

if $CHECK; then
  # Compara inventario (rules+counts) ignorando el timestamp `generated`.
  if [[ -f "$OUTPUT" ]]; then
    if python3 - "$OUTPUT" "$TMP.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
a.pop("generated", None); b.pop("generated", None)
sys.exit(0 if a == b else 1)
PY
    then
      echo "OK: rule-manifest.json está al día"
      exit 0
    else
      echo "STALE: rule-manifest.json desactualizado. Ejecuta: bash scripts/rule-manifest-generate.sh" >&2
      exit 1
    fi
  else
    echo "MISSING: $OUTPUT no existe. Ejecuta: bash scripts/rule-manifest-generate.sh" >&2
    exit 1
  fi
fi

# 3) Escribir solo el manifest (RN-01: nunca toca reglas/CRITERIO/CONSTITUCION)
cp "$TMP.json" "$OUTPUT"
echo "Generated $OUTPUT ($(python3 -c "import sys; import json,sys; print(json.load(open(sys.argv[1]))['total'])" "$OUTPUT" ) reglas)"
