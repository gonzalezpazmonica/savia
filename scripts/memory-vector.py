#!/usr/bin/env python3
"""Vector memory index — semantic search over plain-text JSONL.

SPEC-018: Derived index over memory-store.jsonl. JSONL is source of truth.
Zero vendor lock-in: local model (all-MiniLM-L6-v2), FAISS or hnswlib for ANN.

Usage:
    python3 memory-vector.py rebuild [--store PATH]
    python3 memory-vector.py search "query" [--top K] [--store PATH]
    python3 memory-vector.py status [--store PATH]
    python3 memory-vector.py benchmark [--store PATH]
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

# --- Dependency detection (3 levels) ---
LEVEL = 0  # 0=grep only, 1=python no deps, 2=full vector
ANN_BACKEND = None  # "hnswlib" or "faiss"

try:
    import faiss
    ANN_BACKEND = "faiss"
except ImportError:
    pass

if ANN_BACKEND is None:
    try:
        import hnswlib
        ANN_BACKEND = "hnswlib"
    except ImportError:
        pass

try:
    from sentence_transformers import SentenceTransformer
    if ANN_BACKEND:
        LEVEL = 2
    else:
        LEVEL = 1  # has ST but no ANN backend
except ImportError:
    if ANN_BACKEND:
        LEVEL = 1  # has ANN but no ST
    pass

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
RERANKER_NAME = "cross-encoder/ms-marco-MiniLM-L-6-v2"
DIMENSIONS = 384

# Detect reranker (SPEC-028)
HAS_RERANKER = False
try:
    from sentence_transformers import CrossEncoder
    HAS_RERANKER = True
except ImportError:
    pass
DEFAULT_STORE = os.environ.get(
    "STORE_FILE",
    os.path.join(os.environ.get("PROJECT_ROOT", "."), "output/.memory-store.jsonl"),
)


def _index_path(store: str) -> str:
    ext = ".faiss" if ANN_BACKEND == "faiss" else ".idx"
    return store.replace(".jsonl", f"-index{ext}")


def _map_path(store: str) -> str:
    return store.replace(".jsonl", "-index.map")


def _npy_path(store: str) -> str:
    return store.replace(".jsonl", "-index.npy")


def _load_jsonl(store: str) -> list[dict]:
    entries = []
    if not os.path.exists(store):
        return entries
    with open(store, "r") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                obj["_line"] = i
                entries.append(obj)
            except json.JSONDecodeError:
                continue
    return entries


def _result(i: int, entry: dict, score: float) -> dict:
    """Resultado de búsqueda. Lleva el origen y valid_to de la propia línea (SE-352):
    el filtro de origen no debe deducirlos por topic_key, que comparten las revisiones."""
    return {
        "rank": i + 1,
        "score": score,
        "title": entry.get("title", ""),
        "type": entry.get("type", ""),
        "topic_key": entry.get("topic_key", ""),
        "content": entry.get("content", "")[:200],
        "ts": entry.get("ts", ""),
        "origin": entry.get("origin") or "untrusted",
        "valid_to": entry.get("valid_to"),
    }


def _compose_text(entry: dict) -> str:
    """Compose indexable text from entry fields."""
    parts = [
        entry.get("title", ""),
        entry.get("content", "").replace("\\n", " "),
        entry.get("topic_key", ""),
    ]
    concepts = entry.get("concepts", [])
    if isinstance(concepts, list):
        parts.extend(concepts)
    return " ".join(p for p in parts if p and p != "null")


def cmd_rebuild(store: str) -> None:
    if LEVEL < 2:
        print("Error: deps not installed. Run:")
        print("  bash scripts/install-memory-deps.sh")
        sys.exit(1)

    entries = _load_jsonl(store)
    if not entries:
        print("No entries in store. Nothing to index.")
        return

    print(f"Loading model {MODEL_NAME}...")
    t0 = time.time()
    model = SentenceTransformer(MODEL_NAME)
    print(f"Model loaded in {time.time() - t0:.1f}s")

    texts = [_compose_text(e) for e in entries]

    print(f"Generating {len(texts)} embeddings...")
    t0 = time.time()
    embeddings = model.encode(texts, show_progress_bar=False, normalize_embeddings=True)
    print(f"Embeddings done in {time.time() - t0:.1f}s")

    import numpy as np
    idx_path = _index_path(store)
    map_path = _map_path(store)
    tmp_idx = idx_path + ".tmp"
    tmp_map = map_path + ".tmp"

    emb_np = np.array(embeddings, dtype="float32")

    if ANN_BACKEND == "faiss":
        index = faiss.IndexFlatIP(DIMENSIONS)
        faiss.normalize_L2(emb_np)
        index.add(emb_np)
        faiss.write_index(index, tmp_idx)
    else:
        idx = hnswlib.Index(space="cosine", dim=DIMENSIONS)
        idx.init_index(max_elements=max(len(entries) * 2, 100), ef_construction=200, M=16)
        idx.add_items(emb_np, list(range(len(entries))))
        idx.set_ef(50)
        idx.save_index(tmp_idx)

    with open(tmp_map, "w") as f:
        for i, entry in enumerate(entries):
            f.write(f"{i}\t{entry['_line']}\t{entry.get('title', '')}\n")

    os.replace(tmp_idx, idx_path)
    os.replace(tmp_map, map_path)

    size_kb = os.path.getsize(idx_path) / 1024
    print(f"Index ({ANN_BACKEND}): {len(entries)} entries, {size_kb:.0f} KB -> {idx_path}")


def cmd_search(store: str, query: str, top_k: int = 10) -> None:
    idx_path = _index_path(store)
    map_path = _map_path(store)

    if LEVEL < 2 or not os.path.exists(idx_path):
        # Fallback info
        if not os.path.exists(idx_path):
            print("# Vector index not found — using grep fallback", file=sys.stderr)
        else:
            print("# Deps not installed — using grep fallback", file=sys.stderr)
        # Output empty JSON so caller knows to fallback
        print(json.dumps({"fallback": True, "results": []}))
        return

    import numpy as np
    model = SentenceTransformer(MODEL_NAME)
    query_emb = model.encode([query], normalize_embeddings=True)

    if ANN_BACKEND == "faiss":
        index = faiss.read_index(idx_path)
        total = index.ntotal
        if total == 0:
            print(json.dumps({"fallback": False, "results": []}))
            return
        q = np.array(query_emb, dtype="float32")
        faiss.normalize_L2(q)
        fetch_k = min((top_k * 3 if HAS_RERANKER else top_k), total)
        distances_raw, labels_raw = index.search(q, fetch_k)
        labels = labels_raw
        distances = 1.0 - distances_raw  # convert IP similarity to distance
    else:
        idx = hnswlib.Index(space="cosine", dim=DIMENSIONS)
        idx.load_index(idx_path)
        idx.set_ef(50)
        total = idx.get_current_count()
        if total == 0:
            print(json.dumps({"fallback": False, "results": []}))
            return
        fetch_k = min((top_k * 3 if HAS_RERANKER else top_k), total)
        labels, distances = idx.knn_query(query_emb, k=fetch_k)

    # Load map: idx_pos -> jsonl_line
    line_map = {}
    with open(map_path, "r") as f:
        for row in f:
            parts = row.strip().split("\t")
            if len(parts) >= 2:
                line_map[int(parts[0])] = int(parts[1])

    entries = _load_jsonl(store)
    entry_by_line = {e["_line"]: e for e in entries}

    # Build candidate list
    candidates = []
    for label, dist in zip(labels[0], distances[0]):
        jsonl_line = line_map.get(int(label))
        entry = entry_by_line.get(jsonl_line, {})
        candidates.append({
            "vector_score": round(1.0 - float(dist), 4),
            "text": _compose_text(entry),
            "entry": entry,
        })

    # SPEC-028: Rerank with cross-encoder if available
    reranked = False
    if HAS_RERANKER and len(candidates) > 1:
        try:
            reranker = CrossEncoder(RERANKER_NAME)
            pairs = [(query, c["text"]) for c in candidates]
            rerank_scores = reranker.predict(pairs)
            for c, rs in zip(candidates, rerank_scores):
                c["rerank_score"] = round(float(rs), 4)
            candidates.sort(key=lambda x: -x["rerank_score"])
            reranked = True
        except Exception:
            pass  # Fallback to vector order

    results = [_result(i, c["entry"], c.get("rerank_score", c["vector_score"]))
               for i, c in enumerate(candidates[:top_k])]

    print(json.dumps({"fallback": False, "reranked": reranked, "results": results}, indent=2))


def cmd_status(store: str) -> None:
    idx_path = _index_path(store)
    map_path = _map_path(store)
    store_exists = os.path.exists(store)
    idx_exists = os.path.exists(idx_path)

    store_lines = 0
    if store_exists:
        with open(store, "r") as f:
            store_lines = sum(1 for line in f if line.strip())

    idx_entries = 0
    idx_size = 0
    if idx_exists:
        idx_size = os.path.getsize(idx_path)
        if os.path.exists(map_path):
            with open(map_path, "r") as f:
                idx_entries = sum(1 for _ in f)

    stale = store_lines > idx_entries
    print(f"Level: {LEVEL} ({'vector' if LEVEL == 2 else 'grep' if LEVEL == 0 else 'partial deps'})")
    print(f"Store: {store_lines} entries ({store})")
    print(f"Index: {idx_entries} entries, {idx_size / 1024:.0f} KB ({idx_path})")
    if stale:
        print(f"STALE: {store_lines - idx_entries} new entries — run: bash scripts/memory-store.sh rebuild-index")
    elif idx_exists:
        print("UP TO DATE")
    else:
        print("NO INDEX — run: bash scripts/memory-store.sh rebuild-index")

    print(f"Reranker: {'available' if HAS_RERANKER else 'not installed'}")

    if LEVEL < 2:
        print("\nInstall deps for vector search:")
        print("  bash scripts/install-memory-deps.sh")


def cmd_benchmark(store: str) -> None:
    """Compare grep vs vector search quality on synthetic corpus."""
    if LEVEL < 2:
        print("Error: deps required for benchmark. Run: bash scripts/install-memory-deps.sh")
        sys.exit(1)

    # Synthetic corpus with known ground truth
    corpus = [
        {"type": "bug", "title": "Token refresh timeout", "content": "Login fails after session expiry due to token cache not initialized on cold start"},
        {"type": "decision", "title": "PostgreSQL for relational data", "content": "Chose PostgreSQL over MySQL for better JSON support and extensions"},
        {"type": "bug", "title": "N+1 query in OrderService", "content": "LoadOrderItems iterates with lazy loading causing 200ms latency"},
        {"type": "pattern", "title": "Sprint velocity dropped 12%", "content": "Team capacity reduced by 2 blocked items and 3 underestimated PBIs"},
        {"type": "bug", "title": "Pipeline timeout on staging", "content": "Deploy failed because integration tests exceeded 10 min limit"},
        {"type": "decision", "title": "GraphQL for frontend", "content": "REST too granular for dashboard queries, GraphQL reduces round trips"},
        {"type": "discovery", "title": "Redis connection pool exhausted", "content": "Default pool size 10 too small for 50 concurrent requests"},
        {"type": "pattern", "title": "Retry with exponential backoff", "content": "External API calls need jitter to avoid thundering herd"},
        {"type": "decision", "title": "Kubernetes for orchestration", "content": "Docker Compose insufficient for multi-region HA deployment"},
        {"type": "bug", "title": "Memory leak in background worker", "content": "Event handlers not unsubscribed causing GC pressure"},
        {"type": "convention", "title": "Async all the way", "content": "Never use Task.Result or .Wait in async context to avoid deadlocks"},
        {"type": "discovery", "title": "CORS misconfigured on API", "content": "Wildcard origin allowed, should be restricted to app domain"},
        {"type": "pattern", "title": "Feature flags for rollout", "content": "LaunchDarkly for gradual rollout, kill switch on incidents"},
        {"type": "decision", "title": "Terraform for IaC", "content": "ARM templates too verbose, Terraform declarative and multi-cloud"},
        {"type": "bug", "title": "Timezone mismatch in reports", "content": "Server UTC but client local, dates off by hours in dashboard"},
        {"type": "convention", "title": "Conventional commits", "content": "feat/fix/docs/chore prefix for automated changelog generation"},
        {"type": "discovery", "title": "Sentry alert fatigue", "content": "Too many low-severity alerts, team ignoring real issues"},
        {"type": "decision", "title": "Monorepo with Nx", "content": "Separate repos caused version drift, Nx enforces consistency"},
        {"type": "pattern", "title": "Circuit breaker on external calls", "content": "Polly circuit breaker prevents cascade failures on downstream outage"},
        {"type": "bug", "title": "CSS z-index conflict in modal", "content": "Dropdown menu renders behind modal overlay, needs z-index 1050"},
    ]

    # Queries with ground truth (title of expected best match)
    queries = [
        ("auth problems", "Token refresh timeout"),
        ("performance issues", "N+1 query in OrderService"),
        ("database decision", "PostgreSQL for relational data"),
        ("team capacity", "Sprint velocity dropped 12%"),
        ("deploy failure", "Pipeline timeout on staging"),
        ("API design choice", "GraphQL for frontend"),
        ("connection issues", "Redis connection pool exhausted"),
        ("infrastructure", "Kubernetes for orchestration"),
        ("memory problems", "Memory leak in background worker"),
        ("security vulnerability", "CORS misconfigured on API"),
    ]

    # Write synthetic corpus to temp JSONL
    import tempfile
    tmp_dir = tempfile.mkdtemp()
    tmp_store = os.path.join(tmp_dir, ".memory-store.jsonl")
    with open(tmp_store, "w") as f:
        for i, entry in enumerate(corpus):
            obj = {
                "ts": f"2026-03-{i+1:02d}T10:00:00Z",
                "type": entry["type"],
                "title": entry["title"],
                "content": entry["content"],
                "concepts": [],
                "tokens_est": len(entry["content"]) // 4,
                "topic_key": f"{entry['type']}/{entry['title'].lower().replace(' ', '-')[:30]}",
                "project": "null",
                "hash": "test",
                "rev": 1,
            }
            f.write(json.dumps(obj) + "\n")

    # Build index
    old_store = store
    cmd_rebuild(tmp_store)

    # --- Grep search (keyword matching) ---
    def grep_search(query_str: str, entries_list: list[dict], k: int = 5) -> list[str]:
        scored = []
        for e in entries_list:
            score = 0
            text = f"{e['title']} {e['content']}".lower()
            for word in query_str.lower().split():
                if word in text:
                    score += 1
            if score > 0:
                scored.append((score, e["title"]))
        scored.sort(reverse=True)
        return [t for _, t in scored[:k]]

    # --- Vector search ---
    model = SentenceTransformer(MODEL_NAME)

    import numpy as np
    idx_path = _index_path(tmp_store)

    if ANN_BACKEND == "faiss":
        ann_index = faiss.read_index(idx_path)
        def vector_search(query_str: str, k: int = 5) -> list[str]:
            qemb = model.encode([query_str], normalize_embeddings=True)
            q = np.array(qemb, dtype="float32")
            faiss.normalize_L2(q)
            _, labels_r = ann_index.search(q, min(k, ann_index.ntotal))
            return [corpus[int(l)]["title"] for l in labels_r[0] if l >= 0]
    else:
        idx = hnswlib.Index(space="cosine", dim=DIMENSIONS)
        idx.load_index(idx_path)
        idx.set_ef(50)
        def vector_search(query_str: str, k: int = 5) -> list[str]:
            qemb = model.encode([query_str], normalize_embeddings=True)
            labels, _ = idx.knn_query(qemb, k=min(k, idx.get_current_count()))
            return [corpus[int(l)]["title"] for l in labels[0]]

    # --- Compare ---
    grep_hits = 0
    vector_hits = 0
    print(f"\n{'Query':<25} {'Expected':<35} {'Grep':^6} {'Vector':^6}")
    print("-" * 80)

    for query_str, expected_title in queries:
        grep_results = grep_search(query_str, corpus)
        vec_results = vector_search(query_str)

        grep_found = expected_title in grep_results
        vec_found = expected_title in vec_results

        if grep_found:
            grep_hits += 1
        if vec_found:
            vector_hits += 1

        g_mark = "Y" if grep_found else "-"
        v_mark = "Y" if vec_found else "-"
        print(f"{query_str:<25} {expected_title:<35} {g_mark:^6} {v_mark:^6}")

    print("-" * 80)
    grep_recall = grep_hits / len(queries) * 100
    vector_recall = vector_hits / len(queries) * 100
    improvement = vector_recall - grep_recall

    print(f"Recall@5:  Grep={grep_recall:.0f}%  Vector={vector_recall:.0f}%  Improvement=+{improvement:.0f}pp")

    # Cleanup
    import shutil
    shutil.rmtree(tmp_dir, ignore_errors=True)

    # Exit code: 0 if vector > grep, 1 if not
    if vector_recall <= grep_recall:
        print("\nFAIL: Vector search did not improve over grep")
        sys.exit(1)
    print(f"\nPASS: Vector search improved recall by +{improvement:.0f} percentage points")


def main():
    parser = argparse.ArgumentParser(description="Vector memory index (SPEC-018)")
    parser.add_argument("command", choices=["rebuild", "build", "search", "status", "benchmark"])
    parser.add_argument("query", nargs="?", default="")
    parser.add_argument("--store", default=DEFAULT_STORE)
    parser.add_argument("--top", type=int, default=10)
    args = parser.parse_args()

    if args.command in ("rebuild", "build"):
        cmd_rebuild(args.store)
    elif args.command == "search":
        if not args.query:
            print("Error: query required", file=sys.stderr)
            sys.exit(1)
        cmd_search(args.store, args.query, args.top)
    elif args.command == "status":
        cmd_status(args.store)
    elif args.command == "benchmark":
        cmd_benchmark(args.store)


if __name__ == "__main__":
    main()
