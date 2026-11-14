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
            o = e.get("origin") or "untrusted"
            if e.get("topic_key"): by_topic[e["topic_key"]] = o
            if e.get("title"): by_title[e["title"]] = o
    return by_topic, by_title


def filter_origin(results, store, min_origin):
    """Descarta resultados por debajo de min_origin. Sin min_origin no filtra."""
    if not min_origin:
        return results
    need = ORIGIN_RANK[min_origin]
    by_topic, by_title = _origin_maps(store)
    kept = []
    for r in results:
        o = by_topic.get(r.get("topic_key", "")) or by_title.get(r.get("title", "")) or "untrusted"
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
