#!/usr/bin/env bash
# glm-compute-digest.sh — Computes SHA-256 of governance-layer-manifest.json
# and replaces the manifest_digest.value field in-place.
#
# Usage: bash scripts/glm-compute-digest.sh [--dry-run]
# Exit codes: 0=success, 1=error

set -uo pipefail

MANIFEST=".well-known/governance-layer-manifest.json"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: $MANIFEST not found. Run from repo root." >&2
  exit 1
fi

# Create a canonicalized version with <computed> placeholder stripped for hashing
TMP=$(mktemp /tmp/glm-digest.XXXXXX)
trap 'rm -f "$TMP"' EXIT

# Only manifest_digest.value is replaced by the placeholder — the same
# transformation glm-verify.sh applies. Replacing every "value" field (as this
# script used to) hashed a different text than verify and left the other
# fields' content outside the digest.
STORED=$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1])).get("manifest_digest", {}).get("value", ""))
' "$MANIFEST" 2>/dev/null) || { echo "ERROR: $MANIFEST is not valid JSON" >&2; exit 1; }
if [[ "$STORED" != "<computed>" && ! "$STORED" =~ ^[a-f0-9]{64}$ ]]; then
  echo "ERROR: manifest_digest.value must be <computed> or a sha256 hex digest" >&2
  exit 1
fi
sed "s/\"value\": \"${STORED}\"/\"value\": \"<computed>\"/" "$MANIFEST" > "$TMP"

DIGEST=$(sha256sum "$TMP" | awk '{print $1}')

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY-RUN: digest would be sha256:${DIGEST}"
  exit 0
fi

# Replace in-place only the digest field (never other 64-hex "value" fields).
sed -i "s/\"value\": \"${STORED}\"/\"value\": \"${DIGEST}\"/" "$MANIFEST"

echo "PASS: manifest_digest updated → sha256:${DIGEST}"
