#!/usr/bin/env bash
# hooks-integrity-check.sh — SE-094: detect orphan and phantom hooks.
#
# Verifies two-way integrity between filesystem and .claude/settings.json:
#   - PHANTOM: registered in settings.json but no .sh file on disk
#     (searches .claude/hooks/, optional .opencode/hooks/, and scripts/)
#   - ORPHAN: .sh file exists in either hooks directory but no registration
#
# Exit 0 if zero violations, 2 otherwise.
# Ref: SE-094, ROADMAP.md §Tier 0
#
# Modo --blocking (D23-5 / D-T2): verifica que los guards de seguridad llevan
# `blocking: true` según config/hooks-blocking-policy.txt.
#   Uso: bash scripts/hooks-integrity-check.sh --blocking [--settings F] [--policy F]
#   Salida: 0 = cumple · 1 = violaciones (una línea VIOLATION por cada una) ·
#           2 = error de uso, de lectura o de política.
#   Ref: docs/rules/domain/hooks-blocking-guards.md

set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

blocking_audit() {
  SETTINGS="$REPO_ROOT/.claude/settings.json"
  POLICY="$REPO_ROOT/config/hooks-blocking-policy.txt"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --settings) SETTINGS="${2:-}"; shift 2 ;;
      --policy) POLICY="${2:-}"; shift 2 ;;
      -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
      *) echo "ERROR: argumento desconocido: $1" >&2; exit 2 ;;
    esac
  done

  for f in "$SETTINGS" "$POLICY"; do
    if [[ ! -f "$f" ]]; then
      echo "ERROR: no existe $f"
      exit 2
    fi
  done

  python3 - "$SETTINGS" "$POLICY" <<'PY'
import json, re, sys

settings_path, policy_path = sys.argv[1], sys.argv[2]
try:
    settings = json.load(open(settings_path, encoding="utf-8"))
except (OSError, ValueError) as e:
    print(f"ERROR: settings ilegible ({settings_path}): {e}")
    sys.exit(2)

policy = {}
for n, raw in enumerate(open(policy_path, encoding="utf-8"), 1):
    line = raw.split("#", 1)[0].strip()
    if not line:
        continue
    parts = line.split(None, 2)
    verb, name = parts[0], parts[1] if len(parts) > 1 else ""
    reason = parts[2].strip() if len(parts) > 2 else ""
    if verb not in ("blocking", "excluded", "reviewed") or not name:
        print(f"ERROR: política línea {n}: se esperaba '<blocking|excluded|reviewed> <hook> [motivo]': {raw.rstrip()}")
        sys.exit(2)
    if verb != "blocking" and len(reason) < 10:
        print(f"ERROR: política línea {n}: '{verb} {name}' necesita un motivo de al menos 10 caracteres")
        sys.exit(2)
    policy[name] = verb

# Identidad de un hook: nombre del script (.sh/.py) del comando; el campo name es solo etiqueta.
occurrences = {}
for event, groups in (settings.get("hooks") or {}).items():
    for g in groups if isinstance(groups, list) else []:
        for h in g.get("hooks") or []:
            m = re.search(r"([A-Za-z0-9_.-]+)\.(?:sh|py)\b", h.get("command") or "")
            if not m:
                continue
            occurrences.setdefault(m.group(1), []).append((event, g.get("matcher"), h.get("blocking")))

violations = []
for name, verb in sorted(policy.items()):
    occ = occurrences.get(name, [])
    if verb == "blocking" and not occ:
        violations.append(f"{name}: declarado blocking pero no registrado en settings.json")
    for event, matcher, b in occ:
        where = f"{event}[{matcher}]"
        if verb == "blocking" and b is not True:
            violations.append(f"{name} en {where}: sin blocking true (valor {json.dumps(b)})")
        if verb != "blocking" and b is True:
            violations.append(f"{name} en {where}: blocking true pero la política lo marca {verb}")

for name, occ in sorted(occurrences.items()):
    if name in policy:
        continue
    if any(b is True for _, _, b in occ):
        violations.append(f"{name}: blocking true no declarado en la política")
    if name.startswith("block-"):
        violations.append(f"{name}: guard block-* sin clasificar en la política (blocking, excluded o reviewed)")

for v in violations:
    print(f"VIOLATION {v}")
if violations:
    print(f"FAIL: {len(violations)} violación(es) de la política de hooks blocking")
    sys.exit(1)
print(f"OK: {sum(1 for v in policy.values() if v == 'blocking')} guards blocking conformes")
PY
}

if [[ "${1:-}" == "--blocking" ]]; then
  shift
  blocking_audit "$@"
  exit $?
fi
SETTINGS="$REPO_ROOT/.claude/settings.json"
HOOKS_DIR="$REPO_ROOT/.opencode/hooks"
CLAUDE_HOOKS_DIR="$REPO_ROOT/.claude/hooks"
SCRIPTS_DIR="$REPO_ROOT/scripts"

[[ -f "$SETTINGS" ]] || { echo "ERROR: $SETTINGS not found" >&2; exit 2; }
[[ -d "$CLAUDE_HOOKS_DIR" ]] || { echo "ERROR: $CLAUDE_HOOKS_DIR not found" >&2; exit 2; }

# Extract all hook script paths from settings.json
mapfile -t REGISTERED < <(python3 -c "
import json, re, sys
d = json.load(open('$SETTINGS'))
seen = set()
for event, lst in d.get('hooks', {}).items():
    for matcher in lst:
        for hook in matcher.get('hooks', []):
            cmd = hook.get('command', '')
            # Extract first .sh path from command
            m = re.search(r'([./\w-]+\.sh)', cmd)
            if m:
                path = m.group(1)
                # Strip leading quotes/dollar-expansion
                path = re.sub(r'^.*?(\.claude|\.opencode|scripts)/', r'\1/', path)
                if path not in seen:
                    seen.add(path)
                    print(path)
")

PHANTOM=()
for rel in "${REGISTERED[@]}"; do
  # Resolve relative to repo root; check both candidate locations
  if [[ -f "$REPO_ROOT/$rel" ]]; then
    continue  # found
  fi
  # Also try basename in either dir (handles variant paths)
  base="$(basename "$rel")"
  if [[ -f "$CLAUDE_HOOKS_DIR/$base" || -f "$HOOKS_DIR/$base" || -f "$SCRIPTS_DIR/$base" ]]; then
    continue
  fi
  PHANTOM+=("$rel")
done

# Allowlist: hooks that are intentionally WIRE-READY but NOT registered.
# Each entry MUST justify why (governance / spec reference / human-gate reason).
# Format: "filename.sh\tjustification" — one per line, TAB-separated.
ALLOWLIST_FILE="$REPO_ROOT/.claude/hooks-allowlist.tsv"

declare -A ALLOWED=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  while IFS=$'\t' read -r fname _just; do
    [[ -z "$fname" || "$fname" =~ ^# ]] && continue
    ALLOWED["$fname"]=1
  done < "$ALLOWLIST_FILE"
fi

# Detect orphans: .sh in either hooks directory not referenced in settings.json
# AND not on the allowlist (deliberate non-registration).
mapfile -t ORPHANS < <(
  while IFS= read -r f; do
    base="$(basename "$f")"
    [[ -n "${ALLOWED[$base]:-}" ]] && continue
    if ! grep -q "$base" "$SETTINGS" 2>/dev/null; then
      echo "$base"
    fi
  done < <(find -L "$CLAUDE_HOOKS_DIR" "$HOOKS_DIR" -maxdepth 1 -name '*.sh' -type f 2>/dev/null)
)

EXIT=0

if [[ ${#PHANTOM[@]} -gt 0 ]]; then
  echo "PHANTOM (registered in settings.json but no .sh found):"
  printf '  %s\n' "${PHANTOM[@]}"
  EXIT=2
fi

if [[ ${#ORPHANS[@]} -gt 0 ]]; then
  echo "ORPHAN (.sh in hooks directories without registration):"
  printf '  %s\n' "${ORPHANS[@]}"
  EXIT=2
fi

if [[ $EXIT -eq 0 ]]; then
  echo "PASS: hooks integrity OK"
  echo "  registered=${#REGISTERED[@]} on-disk-hooks=$(find -L "$CLAUDE_HOOKS_DIR" "$HOOKS_DIR" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')"
fi

exit $EXIT
