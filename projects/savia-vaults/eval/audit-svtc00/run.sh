#!/usr/bin/env bash
set -euo pipefail
audit_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$audit_dir/../.." && pwd)
test -f "$project_dir/node_modules/tsx/dist/loader.mjs" || {
  echo 'Faltan dependencias locales: ejecutar npm ci --ignore-scripts en projects/savia-vaults.' >&2
  exit 2
}
exec node --import "$project_dir/node_modules/tsx/dist/loader.mjs" "$audit_dir/audit.ts" "${1:-all}" "${2:-}"
