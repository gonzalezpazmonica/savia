#!/usr/bin/env python3
"""compliance-eval.py — SE-389: evaluador determinista de políticas regulatorias.

Uso: compliance-eval.py --policy <yaml> --context <json> [--json]
Estados: ALLOW | ALLOW_WITH_DISCLOSURE | REQUIRE_HUMAN_REVIEW |
         REQUIRE_HUMAN_APPROVAL | BLOCK | UNKNOWN | NOT_APPLICABLE.

Reglas (deterministas, sin LLM):
  - status != EXECUTABLE  -> UNKNOWN ("policy_not_executable", fail-safe §18)
  - trigger no aplica      -> NOT_APPLICABLE
  - unknowns críticos      -> UNKNOWN (fail-safe §20)
  - disclosure requerida y ausente -> BLOCK (§19 ejemplo Art.50)
  - disclosure presente            -> ALLOW_WITH_DISCLOSURE + receipt
Monotonía (§10): el resultado nunca rebaja restricciones Savia previas
(esta herramienta no devuelve ALLOW si el caller ya tenía BLOCK).
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import sys

try:
    import yaml  # opcional; fallback a parser mínimo
    HAVE_YAML = True
except ImportError:
    HAVE_YAML = False


def load_policy(path: str) -> dict:
    if HAVE_YAML:
        return __import__("yaml").safe_load(open(path, encoding="utf-8"))
    # fallback mínimo: extraer claves escalares top-level
    out, cur_list = {}, None
    for line in open(path, encoding="utf-8"):
        if ":" in line and not line.startswith(" "):
            k, _, v = line.partition(":")
            cur_list = None
            out[k.strip()] = v.strip()
        elif line.startswith("  - ") and cur_list is not None:
            cur_list.append(line.strip()[2:])
    return out


def evaluate(policy: dict, ctx: dict) -> dict:
    pid = policy.get("policy_id", "unknown")
    version = policy.get("version", "?")
    status = policy.get("status", "DRAFT")
    unknowns = list(ctx.get("unknowns", []))

    base = {
        "policy": {"id": pid, "version": version},
        "source": {"regulation": policy.get("legal_source", {}).get("regulation", ""),
                    "article": policy.get("legal_source", {}).get("article", "")},
        "context_used": sorted(ctx.keys()),
        "unknowns": unknowns,
    }

    # §18: sólo políticas EXECUTABLE enforzan (fail-safe)
    if status != "EXECUTABLE":
        r = dict(base, result="UNKNOWN",
                 reason=f"policy status={status} — requiere validación humana antes de enforzar (SE-389 §18)")
        r["unknowns"] = unknowns + [{"type": "LEGAL_UNKNOWN", "field": "policy_status",
                                     "impact": "no_enforceable", "action": "HUMAN_VALIDATION"}]
        return r

    # NOT_APPLICABLE: trigger por rol no cubierto
    trig = policy.get("trigger", {})
    role = (ctx.get("actor") or {}).get("role", "unknown")
    roles = trig.get("actor_role", [])
    if role not in roles and role != "unknown":
        return dict(base, result="NOT_APPLICABLE", reason=f"actor_role={role} fuera del trigger")

    # UNKNOWN fail-safe (§20): unknowns críticos no resuelven silenciosamente
    critical = [u for u in unknowns if u.get("action") in ("REQUIRE_HUMAN_REVIEW", "BLOCK")]
    if critical:
        return dict(base, result="UNKNOWN",
                    reason="unknowns críticos sin resolver", unknowns=unknowns)

    # Art.50 slice: human_facing + disclosure_required -> disclosure obligatoria
    inter = ctx.get("interaction") or {}
    hf = inter.get("human_facing")
    if hf is None:
        u = {"type": "CONTEXT_UNKNOWN", "field": "human_facing",
             "impact": "determina_obligacion", "action": "REQUIRE_HUMAN_REVIEW"}
        return dict(base, result="UNKNOWN", reason="human_facing desconocido",
                    unknowns=unknowns + [u])
    if not hf:
        return dict(base, result="NOT_APPLICABLE", reason="no human-facing")

    disclosure_required = True  # interpretación humana validada (policy §obligations)
    performed = bool((ctx.get("human_oversight") or {}).get("disclosure_performed", False))
    if disclosure_required and not performed:
        return dict(base, result="BLOCK",
                    reason="transparency disclosure requerida y no realizada (EU AI Act Art.50)",
                    evidence_required=["disclosure_receipt"])
    return dict(base, result="ALLOW_WITH_DISCLOSURE",
                reason="disclosure realizada", evidence_required=["disclosure_receipt"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy", required=True)
    ap.add_argument("--context", required=True)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--receipt-out", default=None)
    args = ap.parse_args()

    policy = load_policy(args.policy)
    ctx = json.load(open(args.context, encoding="utf-8"))
    decision = evaluate(policy, ctx)
    decision["timestamp"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    decision["context_hash"] = hashlib.sha256(
        json.dumps(ctx, sort_keys=True, ensure_ascii=False).encode()).hexdigest()

    if args.json or args.receipt_out:
        out = json.dumps(decision, indent=2, ensure_ascii=False)
    else:
        out = f"{decision['result']}: {decision.get('reason','')} [{decision['policy']['id']} v{decision['policy']['version']}]"
    print(out)

    if args.receipt_out:
        receipt = {
            "receipt_type": "compliance_receipt",
            "policy_versions": [decision["policy"]],
            "context_hash": decision["context_hash"],
            "decision": {"result": decision["result"], "reason": decision.get("reason", "")},
            "unknowns": decision.get("unknowns", []),
            "timestamp": decision["timestamp"],
        }
        with open(args.receipt_out, "w", encoding="utf-8") as f:
            json.dump(receipt, f, indent=2, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
