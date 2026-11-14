#!/usr/bin/env bash
# telemetry-issues.sh — SE-534 S2: agrupa eventos por fingerprint en issues.
#
# Lee telemetry-events.jsonl (eventos con fingerprint.hash adjunto vía
# telemetry-fingerprint.py), agrupa y escribe/actualiza
# output/telemetry-issues.jsonl.
#
# Usage: telemetry-issues.sh [--events FILE] [--issues FILE] [--window N]
#   --window N  solo eventos de los últimos N eventos (default: todos)
# Exit: 0 siempre (reporte) · 2 input inválido
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVENTS="${TEL_FP_EVENTS:-$ROOT/output/telemetry-events.jsonl}"
ISSUES="${TEL_FP_ISSUES:-$ROOT/output/telemetry-issues.jsonl}"
WINDOW="${TEL_FP_WINDOW:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --events) EVENTS="$2"; shift 2 ;;
    --issues) ISSUES="$2"; shift 2 ;;
    --window) WINDOW="$2"; shift 2 ;;
    *) echo "usage: $0 [--events F] [--issues F] [--window N]" >&2; exit 2 ;;
  esac
done

[[ -f "$EVENTS" ]] || { echo "no events file: $EVENTS" >&2; exit 0; }

mkdir -p "$(dirname "$ISSUES")"
python3 - "$EVENTS" "$ISSUES" "$WINDOW" <<'PYEOF'
import json, sys, time
events_file, issues_file, window = sys.argv[1], sys.argv[2], int(sys.argv[3])

groups = {}  # hash -> {count, first_seen, last_seen, severity, sample}
lines = []
with open(events_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            lines.append(json.loads(line))
        except json.JSONDecodeError:
            continue

if window > 0:
    lines = lines[-window:]

sev_rank = {'error': 3, 'warn': 2, 'info': 1}
for ev in lines:
    fp = ev.get('fingerprint') or {}
    h = fp.get('hash') or ev.get('fingerprint_hash')
    if not h:
        continue
    sev = str(ev.get('severity') or 'error').lower()
    ts = ev.get('ts') or ''
    g = groups.setdefault(h, {
        'issue_id': h[:12], 'hash': h, 'count': 0,
        'first_seen': ts, 'last_seen': ts, 'severity': sev, 'sample_event': None})
    g['count'] += 1
    if not g['first_seen'] or (ts and ts < g['first_seen']):
        g['first_seen'] = ts
    if ts and ts > g['last_seen']:
        g['last_seen'] = ts
    if sev_rank.get(sev, 0) > sev_rank.get(g['severity'], 0):
        g['severity'] = sev
    if g['sample_event'] is None:
        g['sample_event'] = ev

ordered = sorted(groups.values(), key=lambda g: -g['count'])
with open(issues_file, 'w') as f:
    for g in ordered:
        f.write(json.dumps(g, ensure_ascii=False) + '\n')

print(f"issues={len(ordered)} events={sum(g['count'] for g in ordered)}")
PYEOF