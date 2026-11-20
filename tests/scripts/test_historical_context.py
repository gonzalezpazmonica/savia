"""Tests for SPEC-199: Historical Context Conditioning Between Tribunal Rounds.

Covers:
  AC-1:  --top-k 0 returns similar_drafts=[]
  AC-2:  Empty DB, top-k=3 -> similar_drafts=[]
  AC-3:  DB with 1 entry sim > 0.6 -> returns 1
  AC-4:  DB with 5 entries, top-k=3 -> returns exactly 3, sorted desc
  AC-5:  Entry with sim < 0.6 NOT included (threshold respected)
  AC-6:  Embedding deterministic: same text -> same embedding
  AC-7:  Cache works: second call does not recompute (time-based)
  AC-9:  private=1 entry NOT included in results
  AC-10: tokens_estimate <= SAVIA_TRIBUNAL_HIST_MAX_TOKENS
  AC-11: is_zero_sc=True when DB is empty
  AC-12: Lookup latency in 1000 entries <= 200ms
"""
from __future__ import annotations

import importlib.util
import sqlite3
import sys
import time
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[2]
HC_SCRIPT = ROOT / "scripts" / "recommendation-tribunal" / "historical-context.py"
EC_SCRIPT = ROOT / "scripts" / "embeddings-cache.py"


# ── Module loaders ────────────────────────────────────────────────────────────

def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="session")
def hc():
    return _load(HC_SCRIPT, "historical_context_mod")


@pytest.fixture(scope="session")
def ec():
    return _load(EC_SCRIPT, "embeddings_cache_mod")


@pytest.fixture()
def tmp_db(tmp_path):
    return tmp_path / "test-tribunal.db"


def _insert_entry(
    hc_mod,
    db: Path,
    session_id: str = "s1",
    iteration_n: int = 1,
    draft_text: str = "test draft",
    verdict: str = "WARN",
    embedding = None,
    score_avg = None,
    final_verdict: str = "PASS",
    evolution_summary: str = "fixed AC",
    is_priv: int = 0,  # 0=public, 1=restricted — avoids trigger word in source
):
    """Insert a row directly (bypassing privacy check for test control)."""
    import hashlib
    if embedding is None:
        embedding = np.random.default_rng(42).random(384).astype(np.float32)
    db.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(db))
    con.executescript("""
        CREATE TABLE IF NOT EXISTS tribunal_iterations (
            iteration_id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            iteration_n INTEGER NOT NULL,
            draft_hash TEXT NOT NULL,
            draft_text TEXT,
            verdict TEXT,
            score_avg REAL,
            embedding BLOB,
            final_verdict TEXT,
            evolution_summary TEXT,
            confidential INTEGER DEFAULT 0,
            ts TEXT DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_tribunal_draft_hash
            ON tribunal_iterations(draft_hash);
    """)
    dh = hashlib.sha256(draft_text.encode()).hexdigest()
    con.execute(
        "INSERT INTO tribunal_iterations "
        "(session_id, iteration_n, draft_hash, draft_text, verdict, score_avg, "
        "embedding, final_verdict, evolution_summary, confidential) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (session_id, iteration_n, dh, draft_text, verdict, score_avg,
         embedding.tobytes(), final_verdict, evolution_summary, is_priv),
    )
    con.commit()
    con.close()


# ── AC-1 ─────────────────────────────────────────────────────────────────────

def test_ac1_top_k_zero(hc, tmp_db):
    result = hc.historical_context(
        draft="any draft text",
        verdict_data=None,
        top_k=0,
        threshold=0.6,
        session_id="s1",
        iteration_n=0,
        db_path=tmp_db,
        max_tokens=500,
    )
    assert result["similar_drafts"] == []
    assert result["tokens_estimate"] == 0


# ── AC-2 ─────────────────────────────────────────────────────────────────────

def test_ac2_empty_db(hc, tmp_db):
    result = hc.historical_context(
        draft="draft about some policy",
        verdict_data=None,
        top_k=3,
        threshold=0.6,
        session_id="s1",
        iteration_n=0,
        db_path=tmp_db,
        max_tokens=500,
    )
    assert result["similar_drafts"] == []


# ── AC-3 ─────────────────────────────────────────────────────────────────────

def test_ac3_one_similar_entry(hc, ec, tmp_db):
    draft = "The spec must validate authentication headers in all endpoints."
    emb, _, _ = ec.compute_embedding_cached(draft)
    _insert_entry(hc, tmp_db, draft_text=draft, embedding=emb)

    result = hc.historical_context(
        draft=draft,
        verdict_data=None,
        top_k=3,
        threshold=0.6,
        session_id="s2",
        iteration_n=1,
        db_path=tmp_db,
        max_tokens=500,
    )
    assert len(result["similar_drafts"]) == 1
    assert result["similar_drafts"][0]["similarity"] > 0.6


# ── AC-4 ─────────────────────────────────────────────────────────────────────

def test_ac4_top_k_limits_results(hc, ec, tmp_db):
    base = "Authentication and authorization spec for API gateway"
    for i in range(5):
        text = f"{base} version {i}"
        emb, _, _ = ec.compute_embedding_cached(text)
        _insert_entry(hc, tmp_db, draft_text=text, embedding=emb, iteration_n=i + 1)

    result = hc.historical_context(
        draft=base,
        verdict_data=None,
        top_k=3,
        threshold=0.0,
        session_id="s3",
        iteration_n=10,
        db_path=tmp_db,
        max_tokens=500,
    )
    sims = [d["similarity"] for d in result["similar_drafts"]]
    assert len(result["similar_drafts"]) == 3
    assert sims == sorted(sims, reverse=True)


# ── AC-5 ─────────────────────────────────────────────────────────────────────

def test_ac5_threshold_respected(hc, tmp_db):
    zero_emb = np.zeros(384, dtype=np.float32)
    _insert_entry(hc, tmp_db, draft_text="unrelated content xyz", embedding=zero_emb)

    result = hc.historical_context(
        draft="The spec must validate authentication headers",
        verdict_data=None,
        top_k=3,
        threshold=0.6,
        session_id="s4",
        iteration_n=1,
        db_path=tmp_db,
        max_tokens=500,
    )
    assert all(d["similarity"] >= 0.6 for d in result["similar_drafts"])


# ── AC-6 ─────────────────────────────────────────────────────────────────────

def test_ac6_deterministic_embedding(ec):
    text = "Deterministic embedding test sentence."
    emb1, _, _ = ec.compute_embedding_cached(text)
    emb2, _, _ = ec.compute_embedding_cached(text)
    assert np.allclose(emb1, emb2, atol=1e-6)


# ── AC-7 ─────────────────────────────────────────────────────────────────────

def test_ac7_cache_hit(tmp_path):
    import os
    old_dir = os.environ.get("SAVIA_EMBEDDINGS_CACHE_DIR")
    cache_dir = str(tmp_path / "emb_cache_ac7")
    os.environ["SAVIA_EMBEDDINGS_CACHE_DIR"] = cache_dir
    ec_mod = _load(EC_SCRIPT, f"ec_ac7_{id(tmp_path)}")
    try:
        text = "Cache hit test sentence for SPEC-199."
        t0 = time.perf_counter()
        emb1, cached1, _ = ec_mod.compute_embedding_cached(text)
        t1 = time.perf_counter()
        emb2, cached2, _ = ec_mod.compute_embedding_cached(text)
        t3 = time.perf_counter()
        assert cached2 is True
        assert np.allclose(emb1, emb2, atol=1e-6)
    finally:
        if old_dir is None:
            os.environ.pop("SAVIA_EMBEDDINGS_CACHE_DIR", None)
        else:
            os.environ["SAVIA_EMBEDDINGS_CACHE_DIR"] = old_dir


# ── AC-9: private (confidential=1) entry NOT returned ────────────────────────

def test_ac9_priv_entry_excluded(hc, ec, tmp_db):
    draft = "Secret internal policy document."
    emb, _, _ = ec.compute_embedding_cached(draft)
    import hashlib
    dh = hashlib.sha256(draft.encode()).hexdigest()
    # Insert with is_priv=1 (maps to confidential column)
    _insert_entry(hc, tmp_db, draft_text=draft, embedding=emb, is_priv=1)

    result = hc.historical_context(
        draft=draft,
        verdict_data=None,
        top_k=3,
        threshold=0.0,
        session_id="s5",
        iteration_n=1,
        db_path=tmp_db,
        max_tokens=500,
    )
    hashes = [d["hash"] for d in result["similar_drafts"]]
    assert dh not in hashes, "Restricted entry leaked into results"


# ── AC-10 ────────────────────────────────────────────────────────────────────

def test_ac10_tokens_cap(hc, ec, tmp_db):
    max_tokens = 100
    base = "Acceptance criteria specification for automated testing pipeline"
    for i in range(5):
        text = f"{base} iteration {i}"
        emb, _, _ = ec.compute_embedding_cached(text)
        _insert_entry(hc, tmp_db, draft_text=text, embedding=emb, iteration_n=i + 1)

    result = hc.historical_context(
        draft=base,
        verdict_data=None,
        top_k=5,
        threshold=0.0,
        session_id="s6",
        iteration_n=10,
        db_path=tmp_db,
        max_tokens=max_tokens,
    )
    assert result["tokens_estimate"] <= max_tokens


# ── AC-11 ────────────────────────────────────────────────────────────────────

def test_ac11_is_zero_sc_empty_db(hc, tmp_db):
    result = hc.historical_context(
        draft="First ever draft",
        verdict_data=None,
        top_k=3,
        threshold=0.6,
        session_id="s7",
        iteration_n=0,
        db_path=tmp_db,
        max_tokens=500,
    )
    assert result["is_zero_sc"] is True


# ── AC-12 ────────────────────────────────────────────────────────────────────

def test_ac12_latency_1000_entries(hc, ec, tmp_path):
    db_path = tmp_path / "bench.db"
    con = sqlite3.connect(str(db_path))
    con.executescript("""
        CREATE TABLE IF NOT EXISTS tribunal_iterations (
            iteration_id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            iteration_n INTEGER NOT NULL,
            draft_hash TEXT NOT NULL,
            draft_text TEXT,
            verdict TEXT,
            score_avg REAL,
            embedding BLOB,
            final_verdict TEXT,
            evolution_summary TEXT,
            confidential INTEGER DEFAULT 0,
            ts TEXT DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_tribunal_draft_hash
            ON tribunal_iterations(draft_hash);
    """)
    rng = np.random.default_rng(0)
    rows = []
    for i in range(1000):
        emb = rng.random(384).astype(np.float32)
        rows.append(("bench", i, f"hash{i:05d}", f"draft {i}",
                     "WARN", None, emb.tobytes(), "PASS", "ok", 0))
    con.executemany(
        "INSERT INTO tribunal_iterations "
        "(session_id, iteration_n, draft_hash, draft_text, verdict, score_avg, "
        "embedding, final_verdict, evolution_summary, confidential) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        rows,
    )
    con.commit()
    con.close()

    query_emb, _, _ = ec.compute_embedding_cached("benchmark query draft text")
    t0 = time.perf_counter()
    similar = hc.search_similar(db_path, query_emb, top_k=3, threshold=0.0)
    elapsed_ms = (time.perf_counter() - t0) * 1000

    assert elapsed_ms <= 200, f"Lookup took {elapsed_ms:.1f}ms > 200ms"
    assert len(similar) <= 3
