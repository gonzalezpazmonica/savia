#!/usr/bin/env bash
# mcp-audit.sh — audit MCP server token overhead across configs
# Ref: docs/rules/domain/mcp-overhead.md
# Origin: MindStudio blog 2026 on MCP token overhead (per-turn cost, not per-session).
#
# Scans known MCP config locations, counts tools per server, estimates tokens
# per turn using the heuristic: tokens ≈ (tools × 200) + (char_count ÷ 4).
# Emits a PASS/WARN/FAIL verdict against a budget.
#
# Usage:
#   bash scripts/mcp-audit.sh [--budget N] [--json] [--quiet]
#   bash scripts/mcp-audit.sh --schemas (--catalog F | -- CMD...) [--expected F]
#        [--expected-from-source F] [--timeout S] [--json]
#
# --schemas (SE-443 S1, docs/rules/domain/mcp-tool-design.md): lint del catálogo
# que sirve un MCP. Con `-- CMD` arranca el servidor por stdio y pide tools/list
# (con paginación); con --catalog lee un tools/list guardado. Exige nombre,
# descripción, inputSchema objeto y válido (jsonschema), required ⊆ properties
# y catálogo completo frente a --expected (un nombre por línea) o a los
# `case '<tool>'` de --expected-from-source. Sin efectos declarados: aviso.
#
# Exit codes:
#   0 = under budget · --schemas: clean
#   1 = over budget (WARN or FAIL) · --schemas: findings
#   2 = input error · --schemas: unknown (sin jsonschema, servidor sin respuesta)

set -uo pipefail

if [[ "${1:-}" == "--schemas" ]]; then
  shift
  exec python3 - "$@" <<'PY'
import json, os, re, select, subprocess, sys, time

def usage(msg):
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(2)

args = sys.argv[1:]
catalog = expected = source = None
timeout = 30.0
as_json = False
cmd = []
i = 0
while i < len(args):
    a = args[i]
    if a == "--":
        cmd = args[i + 1:]
        break
    if a in ("--catalog", "--expected", "--expected-from-source", "--timeout"):
        if i + 1 >= len(args):
            usage(f"{a} necesita valor")
        v = args[i + 1]
        if a == "--catalog": catalog = v
        elif a == "--expected": expected = v
        elif a == "--expected-from-source": source = v
        else:
            try: timeout = float(v)
            except ValueError: usage("--timeout necesita segundos")
        i += 2
        continue
    if a == "--json":
        as_json = True; i += 1; continue
    usage(f"opción desconocida {a}")
if bool(catalog) == bool(cmd):
    usage("indica --catalog F o -- CMD (uno de los dos)")

findings, warnings, gaps = [], [], []

def finish(tools_seen):
    result = "unknown" if gaps and not findings else ("findings" if findings else "clean")
    if as_json:
        print(json.dumps({"result": result, "gaps": gaps, "tools": tools_seen,
                          "findings": findings, "warnings": warnings}, ensure_ascii=False, indent=2))
    else:
        print(f"=== MCP tool schema lint === herramientas: {len(tools_seen)}")
        for f in findings: print(f"  FAIL {f}")
        for w in warnings: print(f"  WARN {w}")
        for g in gaps: print(f"  UNKNOWN {g['check']}: {g['reason']}")
        print("gate-result: " + json.dumps({"result": result, "gaps": gaps} if gaps else {"result": result}, separators=(",", ":")))
    sys.exit(1 if findings else (2 if gaps else 0))

try:
    from jsonschema.validators import validator_for
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import SchemaError
except Exception:
    gaps.append({"check": "jsonschema", "reason": "missing_tool"})
    finish([])

def serve(cmd):
    """Cliente MCP mínimo por stdio: initialize, initialized, tools/list paginado."""
    try:
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, bufsize=1)
    except OSError:
        gaps.append({"check": "server", "reason": "not_executed"}); return None
    deadline = time.monotonic() + timeout
    def send(obj):
        p.stdin.write(json.dumps(obj) + "\n"); p.stdin.flush()
    def recv(want_id):
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError
            ready, _, _ = select.select([p.stdout], [], [], left)
            if not ready:
                raise TimeoutError
            line = p.stdout.readline()
            if not line:
                raise EOFError
            try: msg = json.loads(line)
            except ValueError: continue
            if isinstance(msg, dict) and msg.get("id") == want_id:
                return msg
    tools = []
    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "savia-mcp-tool-lint", "version": "1"}}})
        recv(1)
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        cursor, n = None, 2
        while True:
            params = {"cursor": cursor} if cursor else {}
            send({"jsonrpc": "2.0", "id": n, "method": "tools/list", "params": params})
            msg = recv(n)
            res = msg.get("result")
            if not isinstance(res, dict) or not isinstance(res.get("tools"), list):
                gaps.append({"check": "tools/list", "reason": "unreadable"}); return None
            tools += res["tools"]
            cursor = res.get("nextCursor")
            if not cursor:
                return tools
            n += 1
            if n > 1000:
                gaps.append({"check": "tools/list", "reason": "limit"}); return None
    except TimeoutError:
        gaps.append({"check": "server", "reason": "timeout"}); return None
    except (EOFError, BrokenPipeError, OSError):
        gaps.append({"check": "server", "reason": "not_executed"}); return None
    finally:
        try: p.kill()
        except OSError: pass

if cmd:
    tools = serve(cmd)
else:
    try:
        with open(catalog, encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict) and isinstance(data.get("result"), dict):
            data = data["result"]
        tools = data.get("tools") if isinstance(data, dict) else None
        if not isinstance(tools, list):
            raise ValueError
    except (OSError, ValueError):
        gaps.append({"check": "catalog", "reason": "unreadable"}); tools = None
if tools is None:
    finish([])

NAME_RE = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")
names = []
for idx, t in enumerate(tools):
    if not isinstance(t, dict):
        findings.append(f"#{idx}: la entrada no es un objeto"); continue
    name = t.get("name")
    label = name if isinstance(name, str) and name else f"#{idx}"
    if not isinstance(name, str) or not NAME_RE.match(name):
        findings.append(f"{label}: nombre ausente o inválido")
    else:
        if name in names: findings.append(f"{name}: nombre duplicado")
        names.append(name)
    if not isinstance(t.get("description"), str) or not t["description"].strip():
        findings.append(f"{label}: sin descripción")
    schema = t.get("inputSchema")
    if schema is None:
        findings.append(f"{label}: sin inputSchema"); continue
    if not isinstance(schema, dict):
        findings.append(f"{label}: inputSchema no es un objeto"); continue
    if schema.get("type") != "object":
        findings.append(f"{label}: inputSchema.type debe ser \"object\"")
    try:
        validator_for(schema, default=Draft202012Validator).check_schema(schema)
    except SchemaError as e:
        findings.append(f"{label}: esquema inválido ({e.message[:120]})"); continue
    props = schema.get("properties") or {}
    for r in schema.get("required") or []:
        if r not in props:
            findings.append(f"{label}: required '{r}' no está en properties")
    ann = t.get("annotations")
    if not isinstance(ann, dict) or not any(k in ann for k in ("readOnlyHint", "destructiveHint")):
        warnings.append(f"{label}: sin efectos declarados (annotations.readOnlyHint/destructiveHint)")

want = None
try:
    if expected:
        with open(expected, encoding="utf-8") as fh:
            want = {l.strip() for l in fh if l.strip() and not l.lstrip().startswith("#")}
    elif source:
        with open(source, encoding="utf-8") as fh:
            want = set(re.findall(r"case\s+'([A-Za-z0-9_.-]+)'\s*:", fh.read()))
        if not want:
            gaps.append({"check": "expected", "reason": "unreadable"})
except OSError:
    gaps.append({"check": "expected", "reason": "unreadable"})
if want is None and not gaps:
    gaps.append({"check": "expected", "reason": "no_baseline"})
if want:
    have = set(names)
    for m in sorted(want - have): findings.append(f"{m}: falta en el catálogo (catálogo incompleto)")
    for x in sorted(have - want): findings.append(f"{x}: servida pero no esperada (sin manejador)")
finish(sorted(names))
PY
fi

BUDGET_TOKENS=3000
OUT_JSON=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget) BUDGET_TOKENS="$2"; shift 2 ;;
    --json)   OUT_JSON=true; shift ;;
    --quiet)  QUIET=true; shift ;;
    --help|-h)
      sed -n '2,27p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Error: unknown flag $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}" || REPO_ROOT="."

# ── Discover config files ───────────────────────────────────────────────────
declare -a CONFIG_PATHS=()
# Workspace-level
[[ -f "$REPO_ROOT/.claude/mcp.json" ]] && CONFIG_PATHS+=("$REPO_ROOT/.claude/mcp.json")
# User-level Claude Code config
[[ -f "$HOME/.claude.json" ]] && CONFIG_PATHS+=("$HOME/.claude.json")
# Per-project .mcp.json files in the workspace (non-node_modules)
while IFS= read -r p; do
  CONFIG_PATHS+=("$p")
done < <(find "$REPO_ROOT/projects" -maxdepth 3 -name "mcp.json" -o -name ".mcp.json" 2>/dev/null \
          | grep -v node_modules 2>/dev/null || true)

# ── Extract servers + tools + descriptions ─────────────────────────────────
export CONFIG_PATHS_JOINED="${CONFIG_PATHS[*]:-}"
export BUDGET_TOKENS OUT_JSON QUIET

python3 <<'PY'
import json
import os
import sys

TOKENS_PER_TOOL_BASE = 200  # From MindStudio blog heuristic: 100-500 tokens/tool
CHARS_PER_TOKEN = 4

paths = os.environ.get("CONFIG_PATHS_JOINED", "").split()
budget = int(os.environ.get("BUDGET_TOKENS", "3000"))
out_json = os.environ.get("OUT_JSON", "false") == "true"
quiet = os.environ.get("QUIET", "false") == "true"

def estimate_tokens(server_name, server_cfg):
    """Estimate tokens/turn for a single MCP server config."""
    tools = server_cfg.get("tools", [])
    tool_count = len(tools) if isinstance(tools, list) else 0
    # If tools not enumerated in config, we only see the server entry itself —
    # we cannot count tools until the server is running. Estimate conservatively.
    if tool_count == 0:
        return {
            "tools": 0,
            "char_count": 0,
            "estimated_tokens": 0,
            "note": "tools-not-enumerated-statically",
        }
    desc_chars = sum(len(str(t.get("description", ""))) for t in tools)
    base = tool_count * TOKENS_PER_TOOL_BASE
    extra = desc_chars // CHARS_PER_TOKEN
    return {
        "tools": tool_count,
        "char_count": desc_chars,
        "estimated_tokens": base + extra,
    }

report = {
    "budget_tokens": budget,
    "configs_scanned": [],
    "servers": [],
    "total_tokens_estimated": 0,
    "verdict": "UNKNOWN",
    "recommendations": [],
}

seen_servers = set()

for path in paths:
    if not path or not os.path.isfile(path):
        continue
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception as e:
        report["configs_scanned"].append({"path": path, "error": str(e)})
        continue
    report["configs_scanned"].append({"path": path, "ok": True})

    # Top-level mcpServers
    top = data.get("mcpServers", {})
    for name, cfg in (top.items() if isinstance(top, dict) else []):
        if name in seen_servers:
            continue
        seen_servers.add(name)
        est = estimate_tokens(name, cfg if isinstance(cfg, dict) else {})
        report["servers"].append({
            "name": name,
            "origin": path,
            "scope": "global",
            **est,
        })
        report["total_tokens_estimated"] += est["estimated_tokens"]

    # Per-project mcpServers (nested under projects.{path}.mcpServers)
    projects = data.get("projects", {})
    for proj_path, proj_cfg in (projects.items() if isinstance(projects, dict) else []):
        proj_mcp = (proj_cfg or {}).get("mcpServers", {})
        if not isinstance(proj_mcp, dict):
            continue
        for name, cfg in proj_mcp.items():
            key = f"{proj_path}::{name}"
            if key in seen_servers:
                continue
            seen_servers.add(key)
            est = estimate_tokens(name, cfg if isinstance(cfg, dict) else {})
            report["servers"].append({
                "name": name,
                "origin": path,
                "scope": f"project:{proj_path}",
                **est,
            })
            report["total_tokens_estimated"] += est["estimated_tokens"]

# ── Verdict ─────────────────────────────────────────────────────────────────
total = report["total_tokens_estimated"]
if total == 0:
    report["verdict"] = "OK (no user-configured MCP servers — zero overhead)"
elif total <= budget:
    report["verdict"] = f"OK ({total} tokens/turn, under budget {budget})"
elif total <= budget * 2:
    report["verdict"] = f"WARN ({total} tokens/turn, over budget {budget} by {total-budget})"
else:
    report["verdict"] = f"FAIL ({total} tokens/turn, {total//budget}x the budget {budget})"

# ── Recommendations ────────────────────────────────────────────────────────
if total > budget:
    report["recommendations"].append("Move global mcpServers to per-project config")
    report["recommendations"].append("Compress tool descriptions to 1-2 lines (saves ~60-80 tokens/tool)")
    report["recommendations"].append("Prune servers unused for >2 weeks")
    report["recommendations"].append("Use tool filtering — expose only actively used tools")
if len(report["servers"]) == 0 and len(report["configs_scanned"]) > 0:
    report["recommendations"].append("Current design (on-demand loading) is already optimal — keep it")

# ── Output ──────────────────────────────────────────────────────────────────
if out_json:
    print(json.dumps(report, indent=2))
else:
    if not quiet:
        print("=== MCP Overhead Audit ===")
        print(f"Configs scanned: {len(report['configs_scanned'])}")
        for cfg in report["configs_scanned"]:
            mark = "OK" if cfg.get("ok") else f"ERROR ({cfg.get('error', '?')})"
            print(f"  [{mark}] {cfg['path']}")
        print()
        if report["servers"]:
            print(f"Servers configured: {len(report['servers'])}")
            for s in report["servers"]:
                note = f" ({s.get('note')})" if s.get("note") else ""
                print(f"  {s['name']} [{s['scope']}] — {s['tools']} tools, ~{s['estimated_tokens']} tokens/turn{note}")
        else:
            print("Servers configured: 0 (no MCP overhead)")
        print()
        print(f"Total estimated overhead: {total} tokens/turn")
        print(f"Budget: {budget} tokens/turn")
        print(f"Verdict: {report['verdict']}")
        if report["recommendations"]:
            print()
            print("Recommendations:")
            for r in report["recommendations"]:
                print(f"  - {r}")

# Exit code
if total > budget:
    sys.exit(1)
sys.exit(0)
PY
