#!/usr/bin/env python3
"""SE-529 S3 — fixtures sintéticos de cargas de compactación, con la forma medida en S0.1.

Ningún texto es de una conversación real: todo sale de un generador determinista a partir
de una semilla. Subcomandos (todos escriben a stdout, JSON o JSONL):

  payload <evento> <frontend> [--session ID] [--summary-bytes N] [--seed S]
      evento: PreCompact | PostCompact | SessionStart
      frontend: claude-code | opencode
  transcript [--turns N] [--decisions K] [--seed S]
      transcript sintético de Claude Code: un JSON por línea, tipos user/assistant/system/…

Forma (docs/evidence/SE-529-S0-forma-y-linea-base.md): Claude Code entrega session_id,
transcript_path, cwd, hook_event_name, trigger (+ compact_summary en PostCompact; source y
model en SessionStart); OpenCode no entrega transcript_path ni resumen.
"""
import argparse
import json
import random
import sys

WORDS = ("alfa beta gamma delta sigma kappa omega nodo ruta cola lote tabla clave turno "
         "paso fase banco muelle sonda marco regla nube").split()


def words(rng, n):
    return " ".join(rng.choice(WORDS) for _ in range(n))


def sentence_of_bytes(rng, size):
    out = []
    n = 0
    while n < size:
        w = rng.choice(WORDS)
        out.append(w)
        n += len(w) + 1
    return " ".join(out)[:size]


def payload(event, frontend, session, summary_bytes, seed):
    rng = random.Random(seed)
    if frontend == "claude-code":
        base = {"session_id": session, "transcript_path": "/tmp/sint/%s.jsonl" % session,
                "cwd": "/tmp/sint/work", "hook_event_name": event}
        if event == "PreCompact":
            base.update({"trigger": "auto", "prompt_id": "p-%s" % session[:8],
                         "custom_instructions": None})
        elif event == "PostCompact":
            base.update({"trigger": "auto", "prompt_id": "p-%s" % session[:8],
                         "compact_summary": sentence_of_bytes(rng, summary_bytes)})
        elif event == "SessionStart":
            base.pop("trigger", None)
            base.update({"source": "compact", "model": "modelo-sintetico",
                         "prompt_id": "p-%s" % session[:8]})
        return base
    if frontend == "opencode":
        if event == "PreCompact":
            return {"input": {"sessionID": session}, "output": {"context": []}}
        if event == "PostCompact":
            return {"id": "ev-%s" % session[:8], "type": "session.compacted",
                    "properties": {"sessionID": session}}
    raise SystemExit("combinación no entregada por el frontend: %s/%s" % (event, frontend))


def transcript(turns, decisions, seed):
    rng = random.Random(seed)
    marks = set(rng.sample(range(turns), min(decisions, turns))) if turns else set()
    lines = [{"type": "mode", "mode": "default"}]
    for i in range(turns):
        who = "user" if i % 2 == 0 else "assistant"
        text = words(rng, 12)
        if i in marks:
            text = "Decisión: usamos %s con %s." % (rng.choice(WORDS), rng.choice(WORDS))
        lines.append({"type": who, "message": {"role": who, "content":
                      [{"type": "text", "text": text}]}, "uuid": "u-%04d" % i})
    return lines


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("payload")
    p.add_argument("event", choices=["PreCompact", "PostCompact", "SessionStart"])
    p.add_argument("frontend", choices=["claude-code", "opencode"])
    p.add_argument("--session", default="00000000-0000-4000-8000-000000000001")
    p.add_argument("--summary-bytes", type=int, default=1736)
    p.add_argument("--seed", type=int, default=1)
    t = sub.add_parser("transcript")
    t.add_argument("--turns", type=int, default=30)
    t.add_argument("--decisions", type=int, default=2)
    t.add_argument("--seed", type=int, default=1)
    a = ap.parse_args(argv)
    if a.cmd == "payload":
        print(json.dumps(payload(a.event, a.frontend, a.session, a.summary_bytes, a.seed)))
    else:
        for line in transcript(a.turns, a.decisions, a.seed):
            print(json.dumps(line, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
