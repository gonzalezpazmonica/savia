#!/usr/bin/env bash
# env-scrub.sh — SE-326 S5: sanitiza el entorno antes de spawn.
#
# Inspirado en deepseek-harness docs/defensive-patterns.md — "Never hand
# untrusted output the ambient environment or predictable paths": los comandos
# spawnados reciben un env sin *KEY*/*SECRET*/*TOKEN*/*PASSWORD*/*PAT*.
#
# Por defecto OFF: si SAVIA_SCRUB_ENV no está a 1, este script no hace nada
# (las sesiones interactivas no cambian de comportamiento). Con SAVIA_SCRUB_ENV=1
# construye un env mínimo con allowlist + credenciales vía ficheros (Rule #1).
#
# Uso:
#   env-scrub.sh run <cmd> [args...]     # ejecuta con env sanitizado (exit del cmd)
#   env-scrub.sh check <cmd>             # valida: exit 0 OK | 2 comando introduce secret
#   env-scrub.sh --list-dropped          # lista vars que matchean el patrón
#
# Exit codes (run): los del comando ejecutado.
set -uo pipefail

# ── OFF por defecto ─────────────────────────────────────────────────────────
if [[ "${SAVIA_SCRUB_ENV:-}" != "1" ]]; then
  exit 0
fi

# PAT solo cuenta como palabra completa (GH_PAT, PAT_FILE): como subcadena
# marcaría PATH, PYTHONPATH o MYPATH, que no son credenciales.
SECRET_PATTERN='KEY|SECRET|TOKEN|PASSWORD|(^|_)PAT(_|$)'
ALLOWLIST='PATH HOME SHELL LANG LC_ALL TERM USER CLAUDE_PROJECT_DIR SAVIA_WORKSPACE_DIR SAVIA_SCRUB_ENV'

list_dropped() {
  local name
  while IFS= read -r name; do
    [[ " $ALLOWLIST " == *" $name "* ]] && continue
    printf '%s\n' "$name"
  done < <(env | cut -d= -f1 | grep -E "$SECRET_PATTERN" || true)
}

build_scrubbed_env() {
  # env -i + allowlist explícita: ninguna var *KEY*/*SECRET*/*TOKEN*/*PASSWORD*/*PAT*
  # sobrevive por construcción.
  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    SHELL="${SHELL:-/bin/bash}" \
    LANG="${LANG:-C.UTF-8}" \
    LC_ALL="${LC_ALL:-C.UTF-8}" \
    TERM="${TERM:-xterm-256color}" \
    USER="${USER:-}" \
    CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}" \
    SAVIA_WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-}" \
    SAVIA_SCRUB_ENV=1 \
    "$@"
}

case "${1:-}" in
  run)
    shift
    # shellcheck disable=SC2046
    build_scrubbed_env "$@"
    ;;
  check)
    shift
    cmdline="$*"
    # Todo NOMBRE= del comando cuyo nombre case con el patrón (incluye TOKEN= a secas).
    leak=$(printf '%s' "$cmdline" | grep -oE '[A-Za-z_][A-Za-z0-9_]*=' 2>/dev/null \
      | tr -d '=' | grep -E "$SECRET_PATTERN" | sed 's/$/=/' || true)
    if [[ -n "$leak" ]]; then
      echo "WARN [env-scrub]: el comando introduce variable(s) secret(s) en el entorno: $leak" >&2
      echo "  Con SAVIA_SCRUB_ENV=1 las credenciales deben ir via \$(cat \$PAT_FILE), nunca por env." >&2
      exit 2
    fi
    exit 0
    ;;
  --list-dropped)
    list_dropped
    exit 0
    ;;
  *)
    echo "uso: env-scrub.sh run|check|--list-dropped" >&2
    exit 2
    ;;
esac
