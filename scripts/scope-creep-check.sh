#!/usr/bin/env bash
# scope-creep-check.sh — SE-315 S2: compara un diff contra el alcance de su spec.
#
# Clasifica cada fichero del diff (base..head) contra el alcance declarado de
# la spec (via scope-declare.sh):
#   - declared:  coincide exactamente con un declared_paths de la spec
#   - related:   mismo directorio que un path declarado (dirname o root_dir)
#   - unrelated: no coincide con nada declarado
#
# Emite veredicto:
#   - IN_SCOPE    → todo declared/related
#   - EXTRA_FILES → hay unrelated (y al menos un declared/related presente)
#   - MIXED_SCOPE → declared + unrelated en el mismo PR
#   - NO_DECLARED → la spec no declara paths (report-only, sin veredicto fuerte)
#
# Report-only por diseño (AC-S2.4): exit 0 salvo error de uso. El veredicto va
# en JSON y se puede consultar con --verdict.
#
# Uso:
#   scope-creep-check.sh --spec <spec-file> [--base <ref>] [--head <ref>] [--json]
#   scope-creep-check.sh --spec <spec-file> --verdict
#   scope-creep-check.sh --spec <spec-file> --files-unrelated
#
# Exit: 0 PASS, 2 usage/error. Ref: SE-315.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."

SPEC=""
BASE="origin/main"
HEAD="HEAD"
MODE="json"
VERDICT=""
UNRELATED_FILES=""

usage() {
  cat <<EOF
Usage: $0 --spec <spec-file> [--base <ref>] [--head <ref>] [--json|--verdict|--files-unrelated]

Compara el diff base..head contra el alcance declarado de la spec.

  --spec <file>       Spec que motiva el PR (docs/propuestas/*.md o projects/*/specs/*.md)
  --base <ref>        Ref base del diff (default: origin/main)
  --head <ref>        Ref head del diff (default: HEAD)
  --json              Emitir JSON completo (default)
  --verdict           Emitir solo el veredicto (IN_SCOPE|EXTRA_FILES|MIXED_SCOPE|NO_DECLARED)
  --files-unrelated   Emitir la lista de ficheros unrelated (una por línea)

Exit: 0 PASS, 2 uso inválido o spec inexistente.
Ref: SE-315 (scope-creep-gate).
EOF
}

[[ $# -eq 0 ]] && { usage; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec) SPEC="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --head) HEAD="$2"; shift 2 ;;
    --json) MODE="json"; shift ;;
    --verdict) MODE="verdict"; shift ;;
    --files-unrelated) MODE="files"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: argumento desconocido '$1'" >&2; usage; exit 2 ;;
  esac
done

[[ -z "$SPEC" ]] && { echo "ERROR: falta --spec" >&2; usage; exit 2; }
[[ -f "$SPEC" ]] || { echo "ERROR: spec no existe: $SPEC" >&2; exit 2; }

# ── Extraer alcance declarado ──────────────────────────────────────────────
declare_json=$(bash "$SCRIPT_DIR/scope-declare.sh" "$SPEC") || {
  echo "ERROR: scope-declare.sh falló" >&2; exit 2
}

# ── Obtener diff de ficheros ───────────────────────────────────────────────
changed_files=$(git diff "$BASE..$HEAD" --name-only 2>/dev/null) || {
  echo "ERROR: git diff $BASE..$HEAD falló (¿ref inválida?)" >&2; exit 2
}
changed_files=$(echo "$changed_files" | grep -v '^$' || true)

# ── Clasificar con python (lógica determinista compartida) ─────────────────
python3 - "$SPEC" "$declare_json" "$changed_files" "$MODE" <<'PYEOF'
import json
import os
import sys

spec = sys.argv[1]
declared_json = sys.argv[2]
changed_raw = sys.argv[3]
mode = sys.argv[4]

decl = json.loads(declared_json)
declared_paths = set(decl.get("declared_paths", []))
root_dirs = set(decl.get("root_dirs", []))

changed = [c for c in changed_raw.splitlines() if c.strip()]

# whitelist estructural del workspace — nunca scope creep
WHITELIST_PREFIXES = (
    "CHANGELOG.md",
    "CHANGELOG.d/",
    ".scm/",
    ".confidentiality-signature",
    ".pr-summary.md",
    "AGENTS.md",
    "SKILLS.md",
    "docs/propuestas/INDEX.md",
)

declared = []
related = []
unrelated = []


def under(child, parent):
    """child == parent o cuelga de parent, por componentes de ruta (no por prefijo de texto)."""
    return child == parent or child.startswith(parent + "/")


for f in changed:
    if f.startswith(WHITELIST_PREFIXES):
        declared.append(f)  # estructural — siempre in-scope
        continue
    if f in declared_paths:
        declared.append(f)
        continue
    # related: mismo dirname o mismo root_dir que algún path declarado
    f_dir = os.path.dirname(f)
    f_root = f.split("/", 1)[0] if "/" in f else f
    is_related = False
    if declared_paths:
        for d in (os.path.dirname(p) for p in declared_paths):
            # f_dir vacío (fichero en la raíz) no es "padre" de nada declarado.
            if d and f_dir and (under(f_dir, d) or under(d, f_dir)):
                is_related = True
                break
        if not is_related:
            for r in root_dirs:
                if r and (f_dir == r or f_root == r):
                    is_related = True
                    break
    if is_related:
        related.append(f)
    else:
        unrelated.append(f)

# ── Veredicto ──────────────────────────────────────────────────────────────
if not declared_paths:
    verdict = "NO_DECLARED"
elif unrelated:
    if declared or related:
        verdict = "MIXED_SCOPE"
    else:
        verdict = "EXTRA_FILES"
else:
    verdict = "IN_SCOPE"

result = {
    "spec_id": decl.get("spec_id", "unknown"),
    "spec_file": decl.get("spec_file", os.path.basename(spec)),
    "verdict": verdict,
    "total_changed": len(changed),
    "declared": declared,
    "related": related,
    "unrelated": unrelated,
    "recommendation": {
        "IN_SCOPE": "keep — diff alineado con la spec",
        "EXTRA_FILES": "split — mover ficheros ajenos a commit separado",
        "MIXED_SCOPE": "justify — declarar el extra en .pr-summary.md o split",
        "NO_DECLARED": "review — la spec no declara paths; verificar manualmente",
    }.get(verdict, "keep"),
}

if mode == "verdict":
    print(verdict)
elif mode == "files":
    for f in unrelated:
        print(f)
else:
    print(json.dumps(result, indent=2))
PYEOF
