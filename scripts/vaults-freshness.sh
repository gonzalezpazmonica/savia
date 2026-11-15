#!/usr/bin/env bash
# vaults-freshness.sh — ¿Va la cúpula savia-docs por detrás de la documentación del repo?
# Uso: bash scripts/vaults-freshness.sh [--path <cúpula>] [--max-hours N] [--summary]
#   --path       cúpula a medir (defecto: ${SAVIA_VAULTS_DIR:-$HOME/savia/vaults}/savia-docs)
#   --max-hours  atraso tolerado antes de STALE (defecto 168 = 1 semana)
#   --summary    una línea solo si hay que avisar (STALE/UNKNOWN); nada si FRESH/AGING/ABSENT
# Atraso = fecha del último commit del repo que toca docs/ o los documentos raíz sincronizados
# menos la fecha del origen del último snapshot de la cúpula (trailer Source-Commit de
# projects/savia-vaults/scripts/index-docs.sh). Un commit fuera de docs/ no cuenta.
# Salida: 0 FRESH/AGING · 1 STALE · 2 UNKNOWN (nunca sincronizada o ilegible: fail-closed)
#         · 3 ABSENT (la cúpula no existe en esta máquina) · 64 uso incorrecto.
set -uo pipefail

ROOT="${SAVIA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VAULT_PATH=""; MAX_HOURS=168; SUMMARY=0
SYNC_CMD="bash projects/savia-vaults/scripts/index-docs.sh"
SYNCED_PATHS=(docs CLAUDE.md SKILLS.md AGENTS.md README.md README.es.md CRITERIO.md CONSTITUCION.md)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) VAULT_PATH="${2:-}"; shift 2 ;;
    --max-hours) MAX_HOURS="${2:-}"; shift 2 ;;
    --summary) SUMMARY=1; shift ;;
    --help|-h) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "vaults-freshness: opción desconocida $1" >&2; exit 64 ;;
    *) [[ -z "$VAULT_PATH" ]] && VAULT_PATH="$1"; shift ;;
  esac
done
[[ "$MAX_HOURS" =~ ^[0-9]+$ ]] || { echo "vaults-freshness: --max-hours necesita un entero" >&2; exit 64; }
VAULT_PATH="${VAULT_PATH:-${SAVIA_VAULTS_DIR:-$HOME/savia/vaults}/savia-docs}"

say() { [[ $SUMMARY -eq 0 ]] && echo "$@"; return 0; }
warn() { echo "$@"; }

say "=== Vault Freshness ==="
say "Vault: $VAULT_PATH"

if [[ ! -d "$VAULT_PATH" ]]; then
  say "Status: ABSENT (la cúpula no existe en esta máquina)"
  exit 3
fi
if ! git -C "$VAULT_PATH" rev-parse --git-dir >/dev/null 2>&1; then
  warn "Cúpula savia-docs: UNKNOWN (sin git, no se puede medir). Sincroniza: $SYNC_CMD"
  [[ $SUMMARY -eq 0 ]] && echo "Status: UNKNOWN"
  exit 2
fi

SNAP="$(git -C "$VAULT_PATH" log -1 --grep='^index: Savia documentation snapshot' --format='%ct %H' 2>/dev/null)"
if [[ -z "$SNAP" ]]; then
  warn "Cúpula savia-docs: UNKNOWN (nunca sincronizada con el repo). Sincroniza: $SYNC_CMD"
  [[ $SUMMARY -eq 0 ]] && echo "Status: UNKNOWN (ningún snapshot index-docs en la cúpula)"
  exit 2
fi
SNAP_TS="${SNAP%% *}"; SNAP_SHA="${SNAP##* }"
SRC_SHA="$(git -C "$VAULT_PATH" log -1 --format=%B "$SNAP_SHA" 2>/dev/null | sed -n 's/^Source-Commit: //p' | head -1)"
# El trailer es texto del historial de la cúpula: solo un SHA llega a git (evita inyección de opciones).
[[ "$SRC_SHA" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || SRC_SHA=""
# Fecha del origen del snapshot: la del commit de origen si existe en el repo; si no, la del snapshot.
SYNC_TS="$SNAP_TS"
if [[ -n "$SRC_SHA" ]]; then
  T="$(git -C "$ROOT" log -1 --format=%ct "$SRC_SHA" 2>/dev/null || true)"
  [[ "$T" =~ ^[0-9]+$ ]] && SYNC_TS="$T"
fi

ORIGIN_TS="$(git -C "$ROOT" log -1 --format=%ct -- "${SYNCED_PATHS[@]}" 2>/dev/null || true)"
if ! [[ "$ORIGIN_TS" =~ ^[0-9]+$ ]]; then
  warn "Cúpula savia-docs: UNKNOWN (no se pudo leer el historial de docs/ en $ROOT)"
  [[ $SUMMARY -eq 0 ]] && echo "Status: UNKNOWN (repo origen ilegible)"
  exit 2
fi

LAG_S=$(( ORIGIN_TS - SYNC_TS )); [[ $LAG_S -lt 0 ]] && LAG_S=0
LAG_H=$(( LAG_S / 3600 )); LAG_D=$(( LAG_H / 24 ))
PENDING=""
if [[ -n "$SRC_SHA" ]] && git -C "$ROOT" cat-file -e "$SRC_SHA^{commit}" 2>/dev/null; then
  N="$(git -C "$ROOT" rev-list --count "$SRC_SHA..HEAD" -- "${SYNCED_PATHS[@]}" 2>/dev/null || echo "")"
  [[ -n "$N" ]] && PENDING=", $N commits de docs sin sincronizar"
fi
SNAP_DATE="$(date -d "@$SNAP_TS" +%Y-%m-%d 2>/dev/null || echo "$SNAP_TS")"
say "Último snapshot: $SNAP_DATE · atraso respecto a docs/: ${LAG_H} h (${LAG_D} d)${PENDING}"

if [[ $LAG_H -gt $MAX_HOURS ]]; then
  warn "Cúpula savia-docs atrasada ${LAG_D} días respecto a docs/ (STALE, snapshot $SNAP_DATE${PENDING}). Sincroniza: $SYNC_CMD"
  [[ $SUMMARY -eq 0 ]] && echo "Status: STALE (>${MAX_HOURS} h de atraso)"
  exit 1
elif [[ $LAG_H -gt 24 ]]; then
  say "Status: AGING (>24 h de atraso)"
else
  say "Status: FRESH"
fi
exit 0
