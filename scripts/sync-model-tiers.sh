#!/usr/bin/env bash
# sync-model-tiers.sh — RETIRED (2026-09-26).
#
# This script rewrote `model: heavy|mid|fast` into provider model IDs inside
# versioned sources. That destroyed the tier, leaked vendor names into the repo
# (PV-06) and broke every frontend except the one it was run for.
#
# Tiers are now resolved at runtime from the LOCAL definition
# (~/.savia/preferences.yaml → tiers.<frontend>.<tier>). Nothing needs syncing.
# To validate sources run: bash scripts/model-tier-lint.sh
set -euo pipefail
echo "sync-model-tiers.sh está retirado: los tiers se resuelven en runtime desde ~/.savia/preferences.yaml." >&2
echo "Valida las fuentes con: bash scripts/model-tier-lint.sh" >&2
exit 1
