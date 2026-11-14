#!/usr/bin/env python3
"""Filtro de clase de origen para resultados de memoria (SE-352).

Entrada sin origin o desconocida = untrusted (fail-safe). Un resultado que no se puede
resolver contra el almacén también cuenta como untrusted.

Usage: memory-origin.py filter --store PATH --min-origin owner|agent|untrusted|system < results.json
"""
import argparse, json, os, sys

ORIGIN_RANK = {"owner": 4, "agent": 3, "untrusted": 2, "system": 1}


def _origin_maps(store):
    by_topic, by_title = {}, {}
    if not os.path.exists(store):
        return by_topic, by_title
    with open(store) as f:
        for line in f:
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            if e.get("valid_to"):  # superseded: no cuenta (el grep de bash también las salta)
                continue
            o = e.get("origin") or "untrusted"
            # Clave ambigua (varios orígenes): gana el de menor rango, nunca el último escrito.
            for m, k in ((by_topic, e.get("topic_key")), (by_title, e.get("title"))):
                if k and (k not in m or ORIGIN_RANK.get(o, 2) < ORIGIN_RANK.get(m[k], 2)):
                    m[k] = o
    return by_topic, by_title


def filter_origin(results, store, min_origin):
    """Descarta resultados por debajo de min_origin. Sin min_origin no filtra."""
    if not min_origin:
        return results
    need = ORIGIN_RANK[min_origin]
    by_topic, by_title = _origin_maps(store)
    kept = []
    for r in results:
        cands = [m[k] for m, k in ((by_topic, r.get("topic_key", "")), (by_title, r.get("title", ""))) if k in m]
        # Si topic y título resuelven distinto, el menor rango manda (fail-closed).
        o = min(cands, key=lambda x: ORIGIN_RANK.get(x, 2)) if cands else "untrusted"
        if ORIGIN_RANK.get(o, 2) >= need:
            kept.append(r)
    return kept


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("cmd", choices=["filter"])
    p.add_argument("--store", required=True)
    p.add_argument("--min-origin", choices=list(ORIGIN_RANK), required=True)
    a = p.parse_args()
    d = json.load(sys.stdin)
    d["results"] = filter_origin(d.get("results", []), a.store, a.min_origin)
    print(json.dumps(d, ensure_ascii=False))
