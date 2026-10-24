#!/usr/bin/env bash
# blast-radius.sh — Calcula el blast radius de un fichero (CodeFlow-inspired)
# Dado un fichero, muestra que otros ficheros dependen de el.
#
# Usage: bash scripts/blast-radius.sh [options] <file> [file2 ...]
#
# SE-318 (extension): modos de símbolo y diff (pre-write):
#   bash scripts/blast-radius.sh --symbol <name> [--file <path>]
#   bash scripts/blast-radius.sh --diff <base..head>
#   bash scripts/blast-radius.sh --list-backends
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Defaults ──
DEPTH=2
FORMAT="table"
USE_MCP=false
USE_GREP=false
FILES=()

# ── Parse args ──
FILES=()

usage() {
  cat <<EOF
Usage: bash scripts/blast-radius.sh [options] <file> [file2 ...]

Calculate the blast radius of files — who depends on this file?

Options:
  --project DIR    Project root directory. Default: current dir
  --depth N        Max dependency depth to trace (1-5). Default: 2
  --format table|json  Output format. Default: table
  --mcp            Force MCP trace via codebase-memory-mcp
  --grep           Force grep-based fallback

Examples:
  blast-radius.sh src/main.sh
  blast-radius.sh --depth 3 --json src/utils.sh
  blast-radius.sh --project ~/myproject src/app.ts
  blast-radius.sh --symbol public_api        # SE-318
  blast-radius.sh --diff origin/main..HEAD   # SE-318
EOF
}

# ── SE-318: modos symbol / diff / list-backends ─────────────────────────────
# Se despachan antes del parseo file-based (SE-260). Conserva ambas interfaces.
FIRST_ARG="${1:-}"
if [[ "$FIRST_ARG" == "--symbol" || "$FIRST_ARG" == "--diff" || "$FIRST_ARG" == "--list-backends" ]]; then
  # ── Extensions de código (fallback grep) ──
  CODE_EXTS="sh py ts js tsx jsx java cs go rb php rs vue svelte c cpp h hpp"

  list_sources() {
    local file_filter="${1:-}"
    if [[ -n "$file_filter" ]]; then
      [[ -f "$file_filter" ]] && printf '%s\n' "$file_filter"
      return
    fi
    # git ls-files relativo al cwd; se usa solo para filtro por fichero.
    git ls-files 2>/dev/null \
      | grep -E "\.(sh|py|ts|js|tsx|jsx|java|cs|go|rb|php|rs|vue|svelte|c|cpp|h|hpp)$" \
      | grep -vE "(^|/)(node_modules|\.git|\.codegraph|vendor|dist|build|__pycache__)/"
  }

  grep_callers() {
    local sym="$1" file_filter="${2:-}"
    if [[ -n "$file_filter" ]]; then
      local sources
      sources=$(list_sources "$file_filter")
      [[ -z "$sources" ]] && return 0
      grep -HnE "\b${sym}\b" $sources 2>/dev/null \
        | grep -vE ":(#|//|/\*|\*|--|<!--)[[:space:]]*$" \
        | grep -vE "\b(import|from|require|use|include|package|module|export|#include)\b.*\b${sym}\b" \
        | grep -vE ":[[:space:]]*(def|func|function|class|public|private|protected|static|fn|sub|void|int|string|bool|var|let|const)[[:space:]]+${sym}[[:space:]]*(\()?" \
        | cut -d: -f1 \
        | sort -u
    else
      # git grep usa el cwd implícitamente (portable para fixtures y workspace)
      git grep -lE "\b${sym}\b" -- "*.sh" "*.py" "*.ts" "*.js" "*.tsx" "*.jsx" "*.java" "*.cs" "*.go" "*.rb" "*.php" "*.rs" "*.vue" "*.svelte" "*.c" "*.cpp" "*.h" "*.hpp" 2>/dev/null \
        | grep -vE "(^|/)(node_modules|\.git|\.codegraph|vendor|dist|build|__pycache__)/" \
        | while IFS= read -r f; do
            if grep -nE "\b${sym}\b" "$f" 2>/dev/null \
                | grep -vE ":(#|//|/\*|\*|--|<!--)[[:space:]]*$" \
                | grep -vE "\b(import|from|require|use|include|package|module|export|#include)\b.*\b${sym}\b" \
                | grep -vE ":[[:space:]]*(def|func|function|class|public|private|protected|static|fn|sub|void|int|string|bool|var|let|const)[[:space:]]+${sym}[[:space:]]*(\()?" \
                | grep -qE ":.*\b${sym}\b"; then
              printf '%s\n' "$f"
            fi
          done
    fi
  }

  diff_symbols() {
    local range="$1"
    local base head
    base="${range%%..*}"
    head="${range##*..}"
    git diff "$base..$head" 2>/dev/null \
      | grep -E "^[+-].*\b(def|func|function|class|fn|sub|public|private|protected|static)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[+-][a-zA-Z_][a-zA-Z0-9_]*\(\)" \
      | grep -vE "^[+-]{2}" \
      | grep -oE "(def|func|function|class|fn|sub|public|private|protected|static)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|[a-zA-Z_][a-zA-Z0-9_]*\(\)" \
      | sed -E 's/\(\)$//' \
      | grep -oE "[a-zA-Z_][a-zA-Z0-9_]*$" \
      | grep -vE "^(def|func|function|class|fn|sub|main|__init__|setup|teardown|run|start|stop|init|__main__)$" \
      | grep -vE "^(and|or|not|if|else|elif|for|while|return|import|from|class|def|with|try|except|in|is|lambda)$" \
      | sort -u
  }

  emit_result() {
    python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import json
import sys

symbol, direct_raw, transitive_raw, backend = sys.argv[1:5]
direct = [d for d in direct_raw.splitlines() if d.strip()]
transitive = [t for t in transitive_raw.splitlines() if t.strip()]
files = {}
for f in direct + transitive:
    files[f] = 1 if f in direct else 2

result = {
    "symbol": symbol or None,
    "backend": backend or "none",
    "direct": direct,
    "transitive": transitive,
    "files": files,
    "total": len(files),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
PYEOF
  }

  if [[ "$1" == "--list-backends" ]]; then
    if command -v codegraph >/dev/null 2>&1 && codegraph status >/dev/null 2>&1; then
      echo "backend=codegraph"
    else
      echo "backend=grep (codegraph no disponible o sin índice)"
    fi
    exit 0
  fi

  if [[ "$1" == "--symbol" ]]; then
    SYMBOL="${2:-}"
    [[ -z "$SYMBOL" ]] && { echo "ERROR: --symbol requiere nombre" >&2; exit 1; }
    FILE_FILTER=""
    [[ "${3:-}" == "--file" ]] && FILE_FILTER="${4:-}"
    DIRECT=$(grep_callers "$SYMBOL" "$FILE_FILTER")
    out=$(emit_result "$SYMBOL" "$DIRECT" "" "grep")
    printf '%s\n' "$out"
    # Telemetría SE-313: evento blast.radius (AC-S3.3) — nunca bloquea.
    total=$(printf '%s' "$out" | python3 -c "import sys,json;print(json.load(sys.stdin)['total'])" 2>/dev/null || echo "0")
    bash "$SCRIPT_DIR/otel-emit.sh" "blast.radius" \
      symbol="$SYMBOL" backend="grep" affected="$total" >/dev/null 2>&1 || true
    exit 0
  fi

  # --diff
  DIFF="${2:-}"
  [[ -z "$DIFF" ]] && { echo "ERROR: --diff requiere <base..head>" >&2; exit 1; }
  syms=$(diff_symbols "$DIFF")
  if [[ -z "$syms" ]]; then
    emit_result "" "" "" "none"
    exit 0
  fi
  MAX_SYMS="${BLAST_RADIUS_MAX_SYMBOLS:-40}"
  syms=$(printf '%s\n' "$syms" | head -n "$MAX_SYMS")
  TMP_RESULT="$(mktemp /tmp/blast-radius-diff-XXXXXX.jsonl)"
  trap 'rm -f "$TMP_RESULT"' EXIT
  : > "$TMP_RESULT"
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    d=$(grep_callers "$s")
    if [[ -z "$d" ]]; then
      printf '%s\t%s\n' "$s" "" >> "$TMP_RESULT"
      continue
    fi
    while IFS= read -r f; do
      printf '%s\t%s\n' "$s" "$f" >> "$TMP_RESULT"
    done <<< "$d"
  done <<< "$syms"
  python3 - "$TMP_RESULT" <<'PYEOF'
import json
import sys

result_file = sys.argv[1]
symbol_files = {}
with open(result_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t", 1)
        sym = parts[0]
        f = parts[1] if len(parts) > 1 else ""
        symbol_files.setdefault(sym, set())
        if f:
            symbol_files[sym].add(f)

files = {}
for sym, fset in symbol_files.items():
    for f in fset:
        files[f] = 1

print(json.dumps({
    "symbol": None,
    "mode": "diff",
    "symbols": sorted(symbol_files.keys()),
    "direct": sorted(files.keys()),
    "transitive": [],
    "files": files,
    "total": len(files),
}, ensure_ascii=False, indent=2))
PYEOF
  rm -f "$TMP_RESULT"
  trap - EXIT
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) ROOT="$2"; shift 2 ;;
    --depth) DEPTH="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --mcp) USE_MCP=true; shift ;;
    --grep) USE_GREP=true; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; FILES+=("$@"); break ;;
    -*) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

# ── Validate inputs ──
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "ERROR: at least one file required" >&2
  usage >&2
  exit 1
fi

if ! [[ "$DEPTH" =~ ^[1-5]$ ]]; then
  echo "ERROR: depth must be 1-5, got '$DEPTH'" >&2
  exit 1
fi

if [[ "$FORMAT" != "table" && "$FORMAT" != "json" ]]; then
  echo "ERROR: format must be table or json, got '$FORMAT'" >&2
  exit 1
fi

# ── Risk classification ──
risk_level() {
  local d=$1
  if [[ "$d" -eq 1 ]]; then echo "HIGH"
  elif [[ "$d" -eq 2 ]]; then echo "MEDIUM"
  else echo "LOW"
  fi
}

risk_weight() {
  local d=$1
  if [[ "$d" -eq 1 ]]; then echo 10
  elif [[ "$d" -eq 2 ]]; then echo 6
  else echo 3
  fi
}

# ── Grep-based dependency scanner ──
scan_deps() {
  local target="$1" max_depth="$2"
  local -A seen
  seen["$target"]=1
  local queue=("$target:1")
  local results=()

  while [[ ${#queue[@]} -gt 0 ]]; do
    local entry="${queue[0]}"
    queue=("${queue[@]:1}")
    local current="${entry%%:*}"
    local cdepth="${entry##*:}"

    [[ "$cdepth" -gt "$max_depth" ]] && continue

    local basename
    basename=$(basename "$current" | sed 's/\.[^.]*$//')

    # Search for references to this file's basename in other files
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      # Skip self-reference and already seen
      local ref_clean="${ref#./}"
      [[ "$ref_clean" == "$current" ]] && continue
      [[ -n "${seen[$ref_clean]:-}" ]] && continue

      seen["$ref_clean"]=1

      # Determine relation type
      local rel="imports"
      local content
      content=$(cat "$ROOT/$ref_clean" 2>/dev/null || true)
      if echo "$content" | grep -qE "(^|[;&|[:space:]])(source|\.)[[:space:]]+[^[:space:]]*${basename}"; then
        rel="imports"
      elif echo "$content" | grep -qE "(require|import).*${basename}"; then
        rel="imports"
      else
        rel="references"
      fi

      results+=("$ref_clean|$cdepth|$(risk_level "$cdepth")|$rel")
      queue+=("$ref_clean:$((cdepth + 1))")
    done < <(grep -rl "$basename" "$ROOT" \
      --include="*.sh" --include="*.ts" --include="*.js" --include="*.py" \
      --include="*.go" --include="*.rb" --include="*.rs" --include="*.cs" \
      --include="*.md" --include="*.yml" --include="*.yaml" \
      2>/dev/null | grep -v "^$ROOT/$current$" | sed "s|^$ROOT/||")

    [[ ${#queue[@]} -gt 50 ]] && break
  done

  [[ ${#results[@]} -gt 0 ]] && printf '%s\n' "${results[@]}"
  return 0
}

# ── Calculate risk score ──
calc_risk_score() {
  local results=("$@")
  local score=0 max_score=0
  for r in "${results[@]}"; do
    [[ -z "$r" ]] && continue
    local depth="${r#*|}"; depth="${depth%%|*}"
    score=$((score + $(risk_weight "$depth")))
    max_score=$((max_score + 10))
  done
  if [[ "$max_score" -eq 0 ]]; then echo 0; return; fi
  echo $(( (score * 100) / max_score ))
  [[ $(( (score * 100) / max_score )) -gt 100 ]] && echo 100
}

risk_grade() {
  local s=$1
  if [[ "$s" -le 20 ]]; then echo "LOW"
  elif [[ "$s" -le 50 ]]; then echo "MEDIUM"
  elif [[ "$s" -le 80 ]]; then echo "HIGH"
  else echo "CRITICAL"
  fi
}

# ── Main ──
all_results=()
exit_code=0

for target_file in "${FILES[@]}"; do
  # Normalize path
  target_file="${target_file#./}"
  [[ "$target_file" == /* ]] || target_file="$ROOT/$target_file"
  target_file="${target_file#$ROOT/}"

  if [[ ! -f "$ROOT/$target_file" ]]; then
    echo "ERROR: file not found: $target_file" >&2
    exit_code=1
    continue
  fi

  # Scan dependencies
  mapfile -t results < <(scan_deps "$target_file" "$DEPTH")

  if [[ "$FORMAT" == "json" ]]; then
    direct=0 transitive=0
    for r in "${results[@]}"; do
      [[ -z "$r" ]] && continue
      d="${r#*|}"; d="${d%%|*}"
      [[ "$d" -eq 1 ]] && direct=$((direct + 1))
      [[ "$d" -gt 1 ]] && transitive=$((transitive + 1))
    done
    rscore=$(calc_risk_score "${results[@]}")

    impacted_json="["
    first=true
    for r in "${results[@]}"; do
      [[ -z "$r" ]] && continue
      IFS='|' read -r file depth risk rel <<< "$r"
      $first || impacted_json+=","
      first=false
      impacted_json+="{\"file\":\"$file\",\"depth\":$depth,\"risk\":\"$risk\",\"relation\":\"$rel\"}"
    done
    impacted_json+="]"

    cat <<JSON
{
  "file": "$target_file",
  "depth": $DEPTH,
  "total_impacted": ${#results[@]},
  "direct": $direct,
  "transitive": $transitive,
  "risk_score": $rscore,
  "risk_level": "$(risk_grade $rscore)",
  "impacted": $impacted_json
}
JSON
  else
    # Table format
    echo "╔══════════════════════════════════════════════════════════════════╗"
    printf "║  Blast Radius: %-50s ║\n" "$target_file"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    printf "║  %-4s  %-42s %-6s  %-10s ║\n" "D=N" "File" "Risk" "Relation"
    echo "╠══════════════════════════════════════════════════════════════════╣"

    if [[ ${#results[@]} -eq 0 ]]; then
      echo "║  No dependents found                                           ║"
    else
      for r in "${results[@]}"; do
        [[ -z "$r" ]] && continue
        IFS='|' read -r file depth risk rel <<< "$r"
        printf "║  D=%-2s  %-42s %-6s  %-10s ║\n" "$depth" "${file:0:42}" "$risk" "$rel"
      done
    fi

    rscore=$(calc_risk_score "${results[@]}")
    direct=0 transitive=0
    for r in "${results[@]}"; do
      [[ -z "$r" ]] && continue
      d="${r#*|}"; d="${d%%|*}"
      [[ "$d" -eq 1 ]] && direct=$((direct + 1))
      [[ "$d" -gt 1 ]] && transitive=$((transitive + 1))
    done

    echo "╠══════════════════════════════════════════════════════════════════╣"
    printf "║  Summary: %d files impacted, %d direct, %d transitive             ║\n" \
      "${#results[@]}" "$direct" "$transitive"
    printf "║  Risk score: %s/100 (%-8s)                              ║\n" \
      "$rscore" "$(risk_grade "$rscore")"
    echo "╚══════════════════════════════════════════════════════════════════╝"
  fi

  all_results+=("${results[@]}")
done

exit $exit_code
