#!/bin/bash
# readiness-check.sh — Deterministic capability checklist
# Runs on install, update, or manually. Reports what works and what needs setup.
# Exit 0 if core capabilities pass. Exit 1 only if critical failures.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Counters
PASS=0; WARN=0; FAIL=0; SKIP=0; TOTAL=0

check() {
    local level="$1" name="$2" cmd="$3"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf "  %-4s %-45s %s\n" "OK" "$name" ""
    else
        case "$level" in
            critical)
                FAIL=$((FAIL + 1))
                printf "  %-4s %-45s %s\n" "FAIL" "$name" "[CRITICAL]"
                ;;
            recommended)
                WARN=$((WARN + 1))
                printf "  %-4s %-45s %s\n" "WARN" "$name" "[optional]"
                ;;
            optional)
                SKIP=$((SKIP + 1))
                printf "  %-4s %-45s %s\n" "SKIP" "$name" "[optional]"
                ;;
        esac
    fi
}

echo ""
echo "Savia Readiness Check"
echo "====================================="
echo ""

# --- 1. Core runtime ---
echo "[1/9] Core Runtime"
check critical "bash >= 4.0" "LC_ALL=C bash --version | head -1 | grep -E 'version [4-9]'"
check critical "git" "git --version"
check critical "python3" "command -v python3"
check critical "jq" "command -v jq"
check recommended "node/npm (for Claude Code / OpenCode)" "command -v node"
check recommended "bats (test runner)" "command -v bats"

# --- 2. Workspace structure ---
echo ""
echo "[2/9] Workspace Structure"
check critical "CLAUDE.md exists" "test -f '$ROOT_DIR/CLAUDE.md'"
check critical ".opencode/commands/ exists" "test -d '$ROOT_DIR/.claude/commands'"
check critical ".opencode/agents/ exists" "test -d '$ROOT_DIR/.claude/agents'"
check critical ".opencode/skills/ exists" "test -d '$ROOT_DIR/.claude/skills'"
check critical "docs/rules/ exists" "test -d '$ROOT_DIR/docs/rules'"
check critical "scripts/ exists" "test -d '$ROOT_DIR/scripts'"
check critical ".claude/settings.json exists" "test -f '$ROOT_DIR/.claude/settings.json'"

# --- 3. Scripts health ---
echo ""
echo "[3/9] Scripts Health"
check critical "memory-store.sh executable" "test -f '$ROOT_DIR/scripts/memory-store.sh'"
check critical "memory-store.sh runs" "bash '$ROOT_DIR/scripts/memory-store.sh' help | grep -q 'save'"
check critical "validate-ci-local.sh exists" "test -f '$ROOT_DIR/scripts/validate-ci-local.sh'"
check critical "confidentiality-sign.sh exists" "test -f '$ROOT_DIR/scripts/confidentiality-sign.sh'"
check recommended "memory-vector.py valid Python" "python3 -c 'import ast, sys; ast.parse(sys.stdin.read())' < '$ROOT_DIR/scripts/memory-vector.py'"

# --- 4. Vector memory (optional tier) ---
echo ""
echo "[4/9] Vector Memory (SPEC-018)"
MEMORY_PYTHON="${SAVIA_MEMORY_PYTHON:-$HOME/.savia/venv/bin/python}"
[[ -x "$MEMORY_PYTHON" ]] || MEMORY_PYTHON="$HOME/.savia/venv/Scripts/python.exe"
check optional "memory venv installed" "test -x '$MEMORY_PYTHON'"
check optional "faiss backend installed" "'$MEMORY_PYTHON' -c 'import faiss, sentence_transformers'"
if [[ -x "$MEMORY_PYTHON" ]] && "$MEMORY_PYTHON" -c "import faiss, sentence_transformers" 2>/dev/null; then
    printf "  %-4s %-45s %s\n" "INFO" "Vector search: Level 2 (full)" ""
else
    printf "  %-4s %-45s %s\n" "INFO" "Vector search: Level 0 (grep fallback)" ""
    printf "  %-4s %-45s %s\n" "TIP " "Install: bash scripts/install-memory-deps.sh" ""
fi

# --- 4b. Hardware (SPEC-021) ---
echo ""
echo "[4b/9] Hardware (SPEC-021)"
RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 0)
if [[ ! "$RAM_MB" =~ ^[0-9]+$ || "$RAM_MB" -eq 0 ]] && command -v powershell.exe &>/dev/null; then
    RAM_MB=$(powershell.exe -NoProfile -Command '[math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)' 2>/dev/null | tr -d '\r' || echo 0)
fi
DISK_FREE_MB=$(df -m "$ROOT_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0)
GPU_DETECTED=$(command -v nvidia-smi &>/dev/null && echo "yes" || echo "no")
check critical "RAM >= 4 GB" "test $RAM_MB -ge 4096"
check critical "Disk free >= 2 GB" "test $DISK_FREE_MB -ge 2048"
check recommended "CPU cores >= 2" "test $CPU_CORES -ge 2"
check optional "GPU detected (nvidia)" "test '$GPU_DETECTED' = 'yes'"
printf "  %-4s %-45s %s\n" "INFO" "RAM: ${RAM_MB}MB | Disk: ${DISK_FREE_MB}MB | CPU: ${CPU_CORES} | GPU: ${GPU_DETECTED}" ""

# --- 4c. Connectivity ---
ONLINE="no"
if curl -s --max-time 3 "https://1.1.1.1/cdn-cgi/trace" >/dev/null 2>&1; then
    ONLINE="yes"
fi
printf "  %-4s %-45s %s\n" "INFO" "Internet: $ONLINE (offline-first: always works)" ""

# --- 4d. SQLite Cache Systems (SPEC-089/090) ---
echo ""
echo "[4d/7] SQLite Cache Systems"
check recommended "python3 sqlite3 module" "python3 -c 'import sqlite3'"
check recommended "memory-cache-rebuild.sh exists" "test -f '$ROOT_DIR/scripts/memory-cache-rebuild.sh'"
check recommended "memory-stack-load.sh exists" "test -f '$ROOT_DIR/scripts/memory-stack-load.sh'"
check recommended "knowledge-graph.sh exists" "test -f '$ROOT_DIR/scripts/knowledge-graph.sh'"
if [[ -f "$HOME/.savia/memory-cache.db" ]]; then
    MCACHE_ENTRIES=$(python3 -c "import sqlite3; c=sqlite3.connect('$HOME/.savia/memory-cache.db'); print(c.execute('SELECT COUNT(*) FROM memory_entries').fetchone()[0])" 2>/dev/null || echo "0")
    printf "  %-4s %-45s %s\n" "INFO" "Memory cache: $MCACHE_ENTRIES entries" ""
else
    printf "  %-4s %-45s %s\n" "TIP " "Run: bash scripts/memory-cache-rebuild.sh" ""
fi
if [[ -f "$HOME/.savia/knowledge-graph.db" ]]; then
    KG_ENTITIES=$(python3 -c "import sqlite3; c=sqlite3.connect('$HOME/.savia/knowledge-graph.db'); print(c.execute('SELECT COUNT(*) FROM entities').fetchone()[0])" 2>/dev/null || echo "0")
    KG_RELS=$(python3 -c "import sqlite3; c=sqlite3.connect('$HOME/.savia/knowledge-graph.db'); print(c.execute('SELECT COUNT(*) FROM relations').fetchone()[0])" 2>/dev/null || echo "0")
    printf "  %-4s %-45s %s\n" "INFO" "Knowledge graph: $KG_ENTITIES entities, $KG_RELS relations" ""
else
    printf "  %-4s %-45s %s\n" "TIP " "Run: bash scripts/knowledge-graph.sh build" ""
fi

# --- 4e. Savia Shield (Data Sovereignty) ---
echo ""
echo "[4e/7] Savia Shield"
check recommended "ollama installed" "command -v ollama"
if command -v ollama &>/dev/null; then
    if ollama list 2>/dev/null | grep -q "qwen2.5"; then
        printf "  %-4s %-45s %s\n" "OK  " "Ollama model loaded (qwen2.5)" ""
    else
        printf "  %-4s %-45s %s\n" "TIP " "Run: ollama pull qwen2.5:7b" ""
    fi
fi
check recommended "block-gitignored-references.sh" "test -f '$ROOT_DIR/.opencode/hooks/block-gitignored-references.sh'"
check recommended "data-sovereignty-gate.sh" "test -f '$ROOT_DIR/.opencode/hooks/data-sovereignty-gate.sh'"
check recommended "context-budget-check.sh" "test -f '$ROOT_DIR/scripts/context-budget-check.sh'"
check recommended "tool-result-trim.sh" "test -f '$ROOT_DIR/scripts/tool-result-trim.sh'"

# --- 5. Hooks ---
echo ""
echo "[5/9] Hooks"
check critical "settings.json valid JSON" "python3 -c 'import json, sys; json.load(sys.stdin)' < '$ROOT_DIR/.claude/settings.json'"
HOOKS_DIR="$ROOT_DIR/.claude/hooks"
if [[ -d "$HOOKS_DIR" ]]; then
    HOOK_COUNT=$(ls "$HOOKS_DIR"/*.sh 2>/dev/null | wc -l)
    printf "  %-4s %-45s %s\n" "INFO" "$HOOK_COUNT hooks found in .opencode/hooks/" ""
    for h in "$HOOKS_DIR"/*.sh; do
        [[ -f "$h" ]] || continue
        HNAME=$(basename "$h")
        check recommended "hook $HNAME has set -" "head -5 '$h' | grep -q 'set -'"
    done
fi

# --- 6. Tests ---
echo ""
echo "[8/9] Tests"
check critical "tests/ directory exists" "test -d '$ROOT_DIR/tests'"
check critical "run-all.sh exists" "test -f '$ROOT_DIR/tests/run-all.sh'"
if command -v bats &>/dev/null; then
    TEST_COUNT=$(find "$ROOT_DIR/tests" -name '*.bats' | wc -l)
    printf "  %-4s %-45s %s\n" "INFO" "$TEST_COUNT .bats test files found" ""
fi

# --- 7. Git & CI ---
echo ""
echo "[9/9] Git & CI"
check critical "git repo initialized" "git -c safe.directory='$ROOT_DIR' -C '$ROOT_DIR' rev-parse --is-inside-work-tree || test -f '$ROOT_DIR/.git'"
check recommended "not on main branch" "test \"\$(git -C '$ROOT_DIR' branch --show-current)\" != 'main'" || true
check recommended ".gitignore exists" "test -f '$ROOT_DIR/.gitignore'"
check recommended "GitHub remote configured" "git -C '$ROOT_DIR' remote get-url origin 2>/dev/null | grep -q 'github.com'"
check critical "CLAUDE.md counts match reality (drift)" "bash '$ROOT_DIR/scripts/claude-md-drift-check.sh' >/dev/null 2>&1"
# SE-501 AC-11: rule-manifest.json no se versiona; se genera con derived.sh ensure antes de comprobarlo.
check critical "rule-manifest.json up to date (bash scripts/derived.sh ensure)" "bash '$ROOT_DIR/scripts/derived.sh' ensure --only rules >/dev/null 2>&1 && bash '$ROOT_DIR/scripts/rule-manifest-generate.sh' --check >/dev/null 2>&1"

# --- Summary ---
echo ""
echo "====================================="
printf "  PASS: %d  |  WARN: %d  |  FAIL: %d  |  SKIP: %d  |  TOTAL: %d\n" "$PASS" "$WARN" "$FAIL" "$SKIP" "$TOTAL"
echo "====================================="

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "CRITICAL failures detected. Fix before using pm-workspace."
    exit 1
fi

if [[ $WARN -gt 0 ]]; then
    echo ""
    echo "All critical checks pass. $WARN optional items could be installed."
fi

if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    echo ""
    echo "All checks pass. Savia is fully operational."
fi

# Write stamp so session-init knows readiness was verified for this commit
if [[ $FAIL -eq 0 ]]; then
    mkdir -p "$HOME/.pm-workspace"
    git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null > "$HOME/.pm-workspace/.readiness-stamp" || true
fi

exit 0
