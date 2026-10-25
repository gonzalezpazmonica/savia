#!/usr/bin/env bash
# memory-consolidate.sh — SE-317: pase de reflexión sobre el knowledge store.
#
# Consolida la memoria de Savia por acumulación reactiva:
#   scan   — detecta duplicados y near-duplicates (fingerprint + difflib),
#   link   — propone aristas tipadas derived-from/supports/contradicts,
#   distill — agrupa episodios en insights (resumen con citas),
#   prune  — lista candidatos a eliminar (--dry-run, nunca borra solo).
#
# Todo candidato se escribe a output/memory-consolidation/{fecha}.jsonl para
# revisión humana. Ningún comando modifica el store salvo --apply explícito.
#
# Uso:
#   memory-consolidate.sh scan|link|distill|prune [--store <file>] [--apply]
#
# Exit: 0 ok, 2 uso. Ref: SE-317.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."

ACTION="${1:-}"
case "$ACTION" in
  -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[[ -z "$ACTION" ]] && { echo "usage: memory-consolidate.sh {scan|link|distill|prune} [--store <file>] [--apply]" >&2; exit 2; }
shift

STORE="$REPO_ROOT/output/.memory-store.jsonl"
APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --store) STORE="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    *) echo "ERROR: argumento desconocido '$1'" >&2; exit 2 ;;
  esac
done

[[ -f "$STORE" ]] || { echo "ERROR: store no existe: $STORE" >&2; exit 2; }

OUT_DIR="$REPO_ROOT/output/memory-consolidation"
mkdir -p "$OUT_DIR" 2>/dev/null || true
DATE_STAMP="$(date -u +%Y%m%d)"
OUT_FILE="$OUT_DIR/${DATE_STAMP}-${ACTION}.jsonl"

case "$ACTION" in
  scan|link|distill|prune) ;;
  *) echo "ERROR: acción desconocida '$ACTION'" >&2; exit 2 ;;
esac

# ── Lógica compartida (python, stdlib) ─────────────────────────────────────
python3 - "$STORE" "$OUT_FILE" "$ACTION" "$APPLY" "$DATE_STAMP" <<'PYEOF'
import difflib
import hashlib
import json
import os
import sys

store_path, out_file, action, apply_flag, date_stamp = sys.argv[1:6]
apply = apply_flag == "1"

def load_notes(path):
    notes = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                notes.append(json.loads(line))
            except Exception:
                continue
    return notes

def write_result(entry):
    with open(out_file, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")

def content_key(note):
    c = note.get("content", "") or ""
    return c.strip().lower()

notes = load_notes(store_path)
results = []

if action == "scan":
    # AC-S1.1: idénticas → score 1.0; AC-S1.2: near-duplicate > umbral.
    seen = {}
    for i, a in enumerate(notes):
        ka = content_key(a)
        if not ka:
            continue
        for j in range(i + 1, len(notes)):
            b = notes[j]
            kb = content_key(b)
            if not kb:
                continue
            if ka == kb:
                results.append({
                    "type": "duplicate", "score": 1.0,
                    "a": {"hash": a.get("hash"), "title": a.get("title"), "ts": a.get("ts")},
                    "b": {"hash": b.get("hash"), "title": b.get("title"), "ts": b.get("ts")},
                    "reason": "identical content",
                })
            else:
                ratio = difflib.SequenceMatcher(None, ka, kb).ratio()
                if ratio > 0.85:
                    results.append({
                        "type": "near_duplicate", "score": round(ratio, 3),
                        "a": {"hash": a.get("hash"), "title": a.get("title")},
                        "b": {"hash": b.get("hash"), "title": b.get("title")},
                        "reason": "similar content > 0.85",
                    })

elif action == "link":
    # AC-S2.1: nota que cita hash/título de otra → derived-from.
    titles = {}
    hashes = {}
    for n in notes:
        if n.get("hash"):
            hashes[n["hash"]] = n
        if n.get("title"):
            titles[n["title"].lower()] = n
    for n in notes:
        content = (n.get("content", "") or "") + " " + " ".join(n.get("concepts", []))
        content_l = content.lower()
        # cita explícita de hash
        for h, target in hashes.items():
            if h != n.get("hash") and h in content:
                results.append({
                    "type": "derived-from", "from": n.get("hash"), "to": h,
                    "from_title": n.get("title"), "to_title": target.get("title"),
                    "reason": "cites hash",
                })
        # mención de título de otra nota
        for t, target in titles.items():
            if target.get("hash") == n.get("hash"):
                continue
            if t and len(t) > 12 and t in content_l:
                results.append({
                    "type": "derived-from", "from": n.get("hash"), "to": target.get("hash"),
                    "from_title": n.get("title"), "to_title": target.get("title"),
                    "reason": "cites title",
                })

elif action == "distill":
    # AC-S3.1: agrupar por topic_key → insight con citas; AC-S3.2: fuentes absorbed.
    groups = {}
    for n in notes:
        tk = n.get("topic_key") or n.get("domain") or "uncategorized"
        groups.setdefault(tk, []).append(n)
    for tk, grp in groups.items():
        if len(grp) < 2:
            continue
        titles = [g.get("title", "?") for g in grp]
        hashes = [g.get("hash") for g in grp if g.get("hash")]
        concepts = set()
        for g in grp:
            concepts.update(g.get("concepts", []))
        results.append({
            "type": "insight",
            "group": tk,
            "sources": len(grp),
            "citations": hashes,
            "summary_title": f"Insight: {tk}",
            "concepts": sorted(concepts),
            "absorbed": hashes,  # fuentes → absorbed (no borradas)
            "reason": f"{len(grp)} notes same episode/domain",
        })

elif action == "prune":
    # AC-S4.1: --dry-run lista candidatos con razón; nunca borra solo.
    for n in notes:
        reason = None
        if n.get("quality") == "absorbed":
            reason = "absorbed (fuente de insight)"
        elif n.get("importance_tier") in ("D",):
            reason = "importancia tier D"
        if reason:
            results.append({
                "type": "prune_candidate",
                "hash": n.get("hash"),
                "title": n.get("title"),
                "ts": n.get("ts"),
                "reason": reason,
                "dry_run": not apply,
            })

for r in results:
    write_result(r)

print(f"{action}: {len(results)} candidato(s) -> {out_file}")
PYEOF
