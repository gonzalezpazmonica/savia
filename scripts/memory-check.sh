#!/bin/bash
# memory-check.sh — Health check of all Savia memory layers
# Verifies: auto-memory, memory-store, vector, sqlite cache, knowledge graph,
# agent memory, personal vault, session-hot, instincts, topic file consistency.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTO_MEM="$HOME/.claude/projects/-home-monica-claude/memory"
SAVIA_DIR="$HOME/.savia"
MEMORY_PYTHON="${SAVIA_MEMORY_PYTHON:-$SAVIA_DIR/venv/bin/python}"
[[ -x "$MEMORY_PYTHON" ]] || MEMORY_PYTHON="$SAVIA_DIR/venv/Scripts/python.exe"

# Colors
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; N='\033[0m'
PASS=0; WARN=0; FAIL=0

ok()   { echo -e "  ${G}OK${N}   $1"; PASS=$((PASS+1)); }
warn() { echo -e "  ${Y}WARN${N} $1"; WARN=$((WARN+1)); }
fail() { echo -e "  ${R}FAIL${N} $1"; FAIL=$((FAIL+1)); }
info() { echo -e "  ${B}i${N}    $1"; }

section() { echo; echo -e "${B}[$1] $2${N}"; }

echo "🦉 Savia Memory Health Check"
echo "=============================="

# ── Layer 1: Auto-memory (MEMORY.md + topic files) ─────────────────
section "1/10" "Auto-memory (MEMORY.md + topic files)"
if [[ -d "$AUTO_MEM" ]]; then
  if [[ -f "$AUTO_MEM/MEMORY.md" ]]; then
    lines=$(wc -l < "$AUTO_MEM/MEMORY.md")
    bytes=$(wc -c < "$AUTO_MEM/MEMORY.md")
    if (( lines <= 200 )); then ok "MEMORY.md: $lines lines (cap 200)"
    else fail "MEMORY.md: $lines lines > 200 cap"; fi
    if (( bytes <= 25600 )); then ok "MEMORY.md: $bytes bytes (cap 25KB)"
    else fail "MEMORY.md: $bytes bytes > 25KB cap"; fi
  else
    fail "MEMORY.md not found at $AUTO_MEM"
  fi
  topic_count=$(find "$AUTO_MEM" -maxdepth 1 -name "*.md" ! -name "MEMORY.md" 2>/dev/null | wc -l)
  info "Topic files: $topic_count"

  # Orphan check: topic files not referenced in MEMORY.md
  if [[ -f "$AUTO_MEM/MEMORY.md" ]]; then
    orphans=0
    for f in "$AUTO_MEM"/*.md; do
      [[ -f "$f" ]] || continue
      base=$(basename "$f")
      [[ "$base" == "MEMORY.md" ]] && continue
      if ! grep -q "$base" "$AUTO_MEM/MEMORY.md" 2>/dev/null; then
        orphans=$((orphans+1))
      fi
    done
    if (( orphans == 0 )); then ok "All topic files indexed in MEMORY.md"
    else warn "$orphans topic files not referenced in MEMORY.md"; fi
  fi
else
  fail "Auto-memory directory missing: $AUTO_MEM"
fi

# ── Layer 2: memory-store (JSONL) ──────────────────────────────────
section "2/10" "Memory-store (JSONL entries)"
if [[ -x "$ROOT/scripts/memory-store.sh" ]]; then
  stats=$(bash "$ROOT/scripts/memory-store.sh" stats 2>&1 | head -1)
  if [[ -n "$stats" ]]; then ok "$stats"
  else warn "memory-store.sh stats empty"; fi
else
  fail "memory-store.sh missing or not executable"
fi

# ── Layer 3: Vector memory (SPEC-018) ──────────────────────────────
section "3/10" "Vector memory (sentence-transformers + faiss-cpu)"
if [[ -x "$MEMORY_PYTHON" ]] && "$MEMORY_PYTHON" -c "import sentence_transformers, faiss" 2>/dev/null; then
  ok "sentence-transformers + faiss-cpu installed in ~/.savia/venv"
  idx="$HOME/.savia/vector-index"
  if [[ -d "$idx" ]] || [[ -f "$idx.bin" ]]; then ok "vector index present"
  else info "vector index not built yet"; fi
else
  warn "vector deps missing (run: bash scripts/install-memory-deps.sh)"
fi

# ── Layer 4: SQLite memory-cache ───────────────────────────────────
section "4/10" "SQLite memory-cache.db"
if [[ -f "$SAVIA_DIR/memory-cache.db" ]]; then
  cnt=$(python3 -c "import sys; import sqlite3; c=sqlite3.connect(sys.argv[1]); print(c.execute('SELECT COUNT(*) FROM cache').fetchone()[0])" "$SAVIA_DIR/memory-cache.db" 2>/dev/null || echo "?")
  ok "memory-cache.db: $cnt entries"
else
  warn "memory-cache.db not found"
fi

# ── Layer 5: Knowledge graph ───────────────────────────────────────
section "5/10" "Knowledge graph (entities + relations)"
if [[ -f "$SAVIA_DIR/knowledge-graph.db" ]]; then
  ents=$(python3 -c "import sys; import sqlite3; c=sqlite3.connect(sys.argv[1]); print(c.execute('SELECT COUNT(*) FROM entities').fetchone()[0])" "$SAVIA_DIR/knowledge-graph.db" 2>/dev/null || echo "?")
  rels=$(python3 -c "import sys; import sqlite3; c=sqlite3.connect(sys.argv[1]); print(c.execute('SELECT COUNT(*) FROM relations').fetchone()[0])" "$SAVIA_DIR/knowledge-graph.db" 2>/dev/null || echo "?")
  ok "knowledge-graph.db: $ents entities, $rels relations"
else
  warn "knowledge-graph.db not found"
fi

# ── Layer 6: Agent memory (public/private/project) ─────────────────
section "6/10" "Agent memory (3 levels)"
for dir in public-agent-memory private-agent-memory; do
  if [[ -d "$ROOT/$dir" ]]; then
    c=$(find "$ROOT/$dir" -name "MEMORY.md" 2>/dev/null | wc -l)
    ok "$dir: $c agents with memory"
  else
    warn "$dir directory missing"
  fi
done
proj_mem=$(find "$ROOT/projects" -path "*/agent-memory/*" -name "MEMORY.md" 2>/dev/null | wc -l)
info "project agent-memory: $proj_mem files across all projects"

# ── Layer 7: Personal Vault (N3) ───────────────────────────────────
section "7/10" "Personal Vault"
if [[ -d "$SAVIA_DIR/personal-vault" ]]; then
  ok "personal-vault exists at $SAVIA_DIR/personal-vault"
else
  info "personal-vault not initialized (optional, run /vault-init)"
fi

# ── Layer 8: session-hot.md (pre-compact extraction) ───────────────
section "8/10" "session-hot.md (pre-compact extraction)"
if [[ -f "$AUTO_MEM/session-hot.md" ]]; then
  age_sec=$(( $(date +%s) - $(stat -c %Y "$AUTO_MEM/session-hot.md" 2>/dev/null || echo 0) ))
  age_h=$((age_sec/3600))
  if (( age_h < 24 )); then ok "session-hot.md fresh (${age_h}h old)"
  else warn "session-hot.md stale (${age_h}h old, TTL 24h)"; fi
else
  info "session-hot.md not present (normal if no recent pre-compact)"
fi

# ── Layer 9: Instincts registry ────────────────────────────────────
section "9/10" "Instincts registry"
if [[ -f "$ROOT/.claude/instincts/registry.json" ]]; then
  cnt=$(python3 -c "import sys; import json; d=json.load(open(sys.argv[1])); print(len(d) if isinstance(d,list) else len(d.get('instincts',[])))" "$ROOT/.claude/instincts/registry.json" 2>/dev/null || echo "?")
  ok "instincts registry: $cnt entries"
else
  warn "instincts registry.json missing"
fi

# ── Layer 10: Memory stack loader ──────────────────────────────────
section "10/10" "Memory stack loader (memory-stack-load.sh)"
if [[ -x "$ROOT/scripts/memory-stack-load.sh" ]]; then
  ok "memory-stack-load.sh executable"
else
  fail "memory-stack-load.sh missing or not executable"
fi

# ── Summary ────────────────────────────────────────────────────────
echo
echo "=============================="
echo -e "  ${G}PASS: $PASS${N}  |  ${Y}WARN: $WARN${N}  |  ${R}FAIL: $FAIL${N}"
echo "=============================="

if (( FAIL > 0 )); then
  echo -e "${R}❌ Memory health: issues detected${N}"
  exit 1
elif (( WARN > 0 )); then
  echo -e "${Y}⚠️  Memory health: OK with warnings${N}"
  exit 0
else
  echo -e "${G}✅ Memory health: all layers OK${N}"
  exit 0
fi
