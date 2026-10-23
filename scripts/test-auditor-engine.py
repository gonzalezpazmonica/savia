#!/usr/bin/env python3
"""test-auditor-engine.py — Deterministic 9-criteria scorer for BATS tests.
SPEC-055: regex/pattern matching only, zero LLM calls.
Usage: python3 test-auditor-engine.py <test-file.bats> <project-root>
"""
import hashlib, json, os, re, sys
from datetime import date

def read_file(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        return ""

def find_target(test_file, root):
    content = read_file(test_file)
    m = re.search(r'(?:SCRIPT|HOOK)\s*=\s*["\']([^"\']+)["\']', content)
    if m:
        c = os.path.join(root, m.group(1))
        if os.path.isfile(c): return c
    base = os.path.basename(test_file).replace("test-","").replace("test_","").replace(".bats",".sh")
    for d in ["scripts", ".claude/hooks"]:
        c = os.path.join(root, d, base)
        if os.path.isfile(c): return c
    return None

def get_tests(content):
    return re.findall(r'@test\s+"([^"]*)"', content)

NEG_PAT = r'(error|fail|missing|invalid|bad|block|reject|skip|disabled|no.arg|graceful|empty)'
EDGE_PAT = [r'empty', r'nonexistent', r'large', r'boundary', r'max.*depth',
    r'cap.*at', r'overflow', r'zero', r'null', r'no.*arg', r'timeout']

def c1_exists(f):
    pts = 5 if os.path.isfile(f) else 0
    if read_file(f).startswith("#!/"): pts += 3
    if os.access(f, os.X_OK): pts += 2
    return min(pts, 10)

def c2_safety(c):
    if re.search(r'set -[eu]*o pipefail|grep.*set.*pipefail|head.*grep.*pipefail', c): return 10
    if re.search(r'grep.*set -\[?[euo]', c): return 10
    if re.search(r'set -uo pipefail', c): return 8
    return 0

def c3_positive(c):
    tests = get_tests(c)
    pos = [t for t in tests if not re.search(NEG_PAT, t, re.I)]
    n = len(pos)
    return 15 if n >= 5 else 10 if n >= 3 else 5 if n >= 1 else 0

def c4_negative(c):
    tests = get_tests(c)
    neg = [t for t in tests if re.search(NEG_PAT, t, re.I)]
    ne = len(re.findall(r'\[\s*"\$status"\s*-ne\s*0\s*\]', c))
    n = max(len(neg), ne)
    return 15 if n >= 4 else 10 if n >= 2 else 5 if n >= 1 else 0

def c5_edge(c):
    tests = get_tests(c)
    n = sum(1 for t in tests if any(re.search(p, t, re.I) for p in EDGE_PAT))
    return 10 if n >= 3 else 5 if n >= 1 else 0

def c6_isolation(c):
    pts = 0
    if re.search(r'setup\s*\(\)', c): pts += 4
    if re.search(r'teardown\s*\(\)', c): pts += 3
    if re.search(r'mktemp|TMPDIR|tmp_dir', c, re.I): pts += 3
    return min(pts, 10)

def c7_coverage(c, target):
    if not target: return 3
    tc = read_file(target)
    funcs = set(re.findall(r'(?:^|\s)(\w+)\s*\(\)\s*\{', tc))
    funcs |= set(re.findall(r'^def\s+(\w+)', tc, re.MULTILINE))
    if not funcs: return 5
    tested = sum(1 for fn in funcs if fn in c)
    r = tested / len(funcs)
    return 10 if r >= 0.8 else 7 if r >= 0.6 else 4 if r >= 0.3 else 2

def c8_spec(c):
    if re.search(r'SPEC-\d+', c): return 10
    if re.search(r'docs/propuestas/', c): return 10
    if re.search(r'#\s*[Rr]ef:', c): return 8
    if re.search(r'\docs/rules/', c): return 8
    if re.search(r'\.opencode/skills/', c): return 7
    return 5 if re.search(r'\[\s*-f.*\.md.*\]', c) else 0

def c9_assertions(c):
    pts = 0
    if re.search(r'\[\[.*\$output.*\]\]', c): pts += 3
    if re.search(r'\[\[.*\*.*\*', c): pts += 2
    if re.search(r'python3.*json\.load', c): pts += 3
    if re.search(r'grep -q', c): pts += 2
    if re.search(r'assert\s+', c): pts += 3
    if re.search(r'\[\s*"\$\w+".*-(?:gt|lt|ge|le|eq|ne)\s', c): pts += 2
    if re.search(r'\[\s*"\$status"', c): pts += 2
    return min(pts, 10)

# SE-456: tests que no pueden fallar. V1 = aserción anulada con `|| true`/`|| :`;
# V2 = `run` sin ninguna aserción detrás (ni $status, ni $output, ni nada que pueda fallar);
# V3 = `run` cuyo estado se ignora pero con otras aserciones detrás: débil, no vacío.
ASSERT_LINE = re.compile(r'(?:^|;\s*)(?:\[\[?\s|test\s|(?:assert|refute)_\w+|grep\s+(?:-\S+\s+)*(?:-\w*q\w*|--quiet)\b)')
NEUTRALIZED = re.compile(r'\|\|\s*(?:true|:|/bin/true|exit\s+0|return\s+0|echo\b[^|&;()\[\]]*)\s*;?\s*(?:#.*)?$')
RUN_LINE = re.compile(r'^run(\s|$)')
RUN_SELF_CHECKED = re.compile(r'^run\s+(-\d+|!)\s')
# Líneas que no pueden hacer fallar el test por sí mismas.
NON_ASSERT = re.compile(r'^(run\s|true|:|local\s|export\s|echo\s|printf\s|[A-Za-z_]\w*=(?!.*\$\()|cd\s|\}|\)|\'|")')
RESULT_CHECK = re.compile(r'\$status|\$\{status|\$output|\$\{output|\$\{lines|\$lines|\blines\[|assert_|refute_')

def test_blocks(c):
    """(nombre, [(nº de línea, línea sin espacios)]) por cada @test."""
    lines = c.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r'^@test\s+(?:"((?:[^"\\]|\\.)*)"|\'([^\']*)\')\s*\{\s*$', lines[i])
        if not m:
            i += 1
            continue
        body, j = [], i + 1
        while j < len(lines) and lines[j].rstrip() != "}":
            s = lines[j].strip()
            if s and not s.startswith("#"):
                body.append((j + 1, s))
            j += 1
        yield m.group(1) or m.group(2) or "", body
        i = j + 1

def vacuity_all(c):
    found = []
    for name, body in test_blocks(c):
        for idx, (n, s) in enumerate(body):
            if ASSERT_LINE.search(s) and NEUTRALIZED.search(s) and "&&" not in s:
                found.append({"test": name, "line": n, "kind": "V1", "text": s[:120]})
            elif RUN_LINE.match(s) and not RUN_SELF_CHECKED.match(s):
                same_line = re.split(r';\s*|\s&&\s', s, maxsplit=1)[1:]
                rest = body[idx + 1:]
                stop = next((k for k, (_, x) in enumerate(rest) if RUN_LINE.match(x)), len(rest))
                # el run siguiente (con su argumento multilínea) cuenta si consume $output del anterior
                nxt = next((k for k, (_, x) in enumerate(rest[stop + 1:], stop + 1) if RUN_LINE.match(x)), len(rest))
                consumed = any("$output" in x or "${output" in x for _, x in rest[stop:nxt])
                checked = [x for _, x in rest[:stop + 1]] + same_line + (["$output"] if consumed else [])
                if not any(RESULT_CHECK.search(x) for x in checked):
                    can_fail = any(not NON_ASSERT.match(x) for x in checked)
                    kind = "V3" if can_fail else "V2"
                    found.append({"test": name, "line": n, "kind": kind, "text": s[:120]})
    return found

def vacuity(c):
    """Solo lo que no puede fallar (V1, V2); V3 es débil y se informa aparte."""
    return [v for v in vacuity_all(c) if v["kind"] != "V3"]

def weak(c):
    return [v for v in vacuity_all(c) if v["kind"] == "V3"]

def vacuity_scan(root):
    findings = []
    if not os.path.isdir(os.path.join(root, "tests")):
        raise FileNotFoundError(f"sin directorio tests/ en {root}")
    for dirpath, _, files in os.walk(os.path.join(root, "tests")):
        for f in sorted(files):
            if f.endswith(".bats"):
                p = os.path.join(dirpath, f)
                for v in vacuity(read_file(p)):
                    findings.append({"file": os.path.relpath(p, root), **v})
    findings.sort(key=lambda v: (v["file"], v["line"]))
    return {"count": len(findings), "findings": findings}

def audit(test_file, root):
    c = read_file(test_file)
    target = find_target(test_file, root)
    today = date.today().isoformat()
    criteria = {
        "exists_executable": c1_exists(test_file), "safety_verification": c2_safety(c),
        "positive_cases": c3_positive(c), "negative_cases": c4_negative(c),
        "edge_cases": c5_edge(c), "isolation": c6_isolation(c),
        "coverage_breadth": c7_coverage(c, target), "spec_reference": c8_spec(c),
        "assertion_quality": c9_assertions(c),
    }
    total = sum(criteria.values())
    vac = vacuity(c)
    h = hashlib.sha256(f"{os.path.basename(test_file)}{total}{today}".encode()).hexdigest()[:8]
    return {
        "file": os.path.relpath(test_file, root),
        "target": os.path.relpath(target, root) if target else None,
        "test_count": len(get_tests(c)), "criteria": criteria,
        "total": total, "certified": total >= 80 and not vac, "vacuity": vac, "weak": weak(c),
        "hash": h, "date": today,
    }

if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--vacuity-scan":
        try:
            print(json.dumps(vacuity_scan(sys.argv[2]), indent=2, ensure_ascii=False))
        except FileNotFoundError as e:
            print(json.dumps({"error": str(e)}))
            sys.exit(2)
        sys.exit(0)
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: test-auditor-engine.py <file> <root>"}))
        sys.exit(1)
    print(json.dumps(audit(sys.argv[1], sys.argv[2]), indent=2))
