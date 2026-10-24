#!/usr/bin/env python3
"""Memory consolidation — removes test entries, deduplicates, flags stale refs."""
import os, sys, re, shutil
from datetime import datetime

MEMORY_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.claude', 'external-memory', 'auto', 'MEMORY.md')
BACKUP_DIR = os.path.join(os.path.dirname(MEMORY_FILE), 'archive')
MODE = sys.argv[1] if len(sys.argv) > 1 else "--report"

TEST_PATTERNS = [
    # SE/SPEC entries are always real
    r'(OK[0-9]|Entry (one|two)|inject.test|ep-(x|\d+\b)|tiny content|dec-1|pinx)',
    r'(Test (decision|rebuild)|Dedup test|My Test Bug|dummy|fake)',
    r'(Some entry|Use (Redis|GraphQL|PostgreSQL)|Decision [AB]\b|Login broken)',
    r'(Timeout error|Redis Timeout|Null ref|Circuit Breaker|Grep assert)',
    r'(GraphQL for Frontend|Microservices|split)',
    r'(Edge|First|Second|Daily|Temp|Perm|Only entry|Bypass|WithSource|Auth|DB choice)\b.*\[',
]

def is_test(line):
    if re.search(r'(SE-\d+|SPEC-\d+)', line):
        return False
    after = re.sub(r'^- [a-z-]+: ', '', line)
    if len(after) < 25:
        return True
    for pat in TEST_PATTERNS:
        if re.search(pat, line, re.IGNORECASE):
            return True
    return False

with open(MEMORY_FILE) as f:
    lines = f.readlines()

entries = []
header = []
in_entries = False
entry_lines = []

for line in lines:
    if not in_entries:
        header.append(line)
        if 'ENTRIES_START' in line:
            in_entries = True
        continue
    if 'ENTRIES_END' in line:
        header.append(line)
        continue
    if line.startswith('- '):
        entry_lines.append(line)

test_entries = [e for e in entry_lines if is_test(e)]
real_entries = [e for e in entry_lines if not is_test(e)]

# Dedup by ref
seen_refs = set()
dedup = []
keep = []
for e in real_entries:
    m = re.findall(r'\[(.*?)\]', e)
    ref = m[-1] if m else ''
    if ref and ref in seen_refs:
        dedup.append(e)
        continue
    if ref:
        seen_refs.add(ref)
    keep.append(e)

# Stale check
stale = []
for e in keep:
    m = re.findall(r'\[(.*?)\]', e)
    ref = m[-1] if m else ''
    if ref:
        ref_path = os.path.dirname(MEMORY_FILE) + '/' + ref + '.md'
        if not os.path.exists(ref_path):
            stale.append(e)

total = len(entry_lines)
removed = len(test_entries) + len(dedup)

print(f"=== Memory Consolidation ===")
print(f"  Total:       {total} entries")
print(f"  Test:        {len(test_entries)} (will remove)")
print(f"  Duplicates:  {len(dedup)} (will dedup)")
print(f"  Stale refs:  {len(stale)}")
print(f"  Keep:        {len(keep)}")

if test_entries:
    print(f"\n--- Test entries to remove ---")
    for e in test_entries:
        print(f"  ~ {e.rstrip()}")

if MODE == '--apply':
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ts = datetime.now().strftime('%Y%m%dT%H%M%S')
    backup = f"{BACKUP_DIR}/MEMORY-{ts}.md"
    shutil.copy2(MEMORY_FILE, backup)
    print(f"\nBackup: {backup}")

    with open(MEMORY_FILE, 'w') as f:
        for line in header:
            f.write(line)
        for e in keep:
            f.write(e)

    print(f"Removed: {removed} entries")
    print(f"Remaining: {len(keep)} entries")
    print(f"=== CONSOLIDATED ===")
elif MODE == '--dry-run':
    print(f"\n=== DRY RUN: {removed} would be removed ===")
else:
    print(f"\nStatus: CLEAN — run with --apply")
