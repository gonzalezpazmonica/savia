#!/usr/bin/env bash
# Arnés EEP de pruebas (SE-496 R4, F0). Solo en tests/: ningún hook lo invoca y no decide sobre
# efectos reales. evaluate -> gancho -> recheck; solo si recheck da ALLOW crea el marcador.
# Uso: se496-eep-harness.sh <peticion.json> <marcador> [orden-gancho]
# Entorno: SE496_KERNEL (ruta del kernel; por defecto el del repo), SE496_RECEIPT (donde guardar el recibo).
set -uo pipefail
REQ="${1:?peticion.json}"; MARK="${2:?marcador}"; HOOK="${3:-}"
KERNEL="${SE496_KERNEL:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/authority_kernel.py}"
RECEIPT="${SE496_RECEIPT:-$(mktemp)}"
[[ -f "$KERNEL" ]] || { echo "EEP: kernel ausente ($KERNEL); no se ejecuta" >&2; exit 3; }
python3 -I "$KERNEL" evaluate <"$REQ" >"$RECEIPT"; rc=$?
[[ $rc -eq 0 ]] || { echo "EEP: evaluate no concede (exit $rc); no se ejecuta" >&2; exit "$rc"; }
[[ -z "$HOOK" ]] || bash -c "$HOOK"
python3 -I "$KERNEL" recheck --prior "$RECEIPT" <"$REQ" >"$RECEIPT.re"; rc=$?
[[ $rc -eq 0 ]] || { echo "EEP: recheck no concede (exit $rc); no se ejecuta" >&2; cat "$RECEIPT.re" >&2; exit "$rc"; }
: >"$MARK"   # en lugar de la orden real
