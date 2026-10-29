#!/usr/bin/env python3
"""
risk-tier.py — SE-362: clasifica un cambio por tier de riesgo (1-4).

Tiers:
  T1 — Reversible mínimo: docs/typos/chore, auto-merge si delegado
  T2 — Reversible módulo: refactor con tests, auto-merge + 1 review
  T3 — Irreversible/datos: migración, secrets, N3+, requiere humano
  T4 — Crítico: infra prod, auth, PII, doble humano

Fail-closed: un path no clasificable → tier 3 (humano, no asume bajo riesgo).

Uso:
  risk-tier.py --diff "path1 path2" [--json]

Ref: SE-362 — gradación de riesgo para auto-merge (gobernanza ejecutable)
"""
from __future__ import annotations

import argparse
import json
import sys

# Paths que elevan el tier
TIER_3_PATHS = (
    "secret", "credential", "migration", "db/migrate", "data/",
    "auth", "token", "vault", "key.",
    "push", "merge", "deploy", "release",
)
TIER_4_PATHS = (
    "infra/", ".github/workflows", "prod.", "terraform", "bicep", "docker-compose",
    "production", "deploy/", "pii",
)
# SE-433 §2.8: paths de gobernanza → tier 4. Un merge-sprint no puede mergear el
# debilitamiento de sus propias reglas, permisos ni de este clasificador.
GOVERNANCE_EXACT = (
    "scripts/merge-sprint.sh", "scripts/risk-tier.py",
    "docs/rules/domain/savia-ethical-principles.md", "docs/rules/domain/radical-honesty.md",
    # SE-343: raíz de confianza del grant de merge y quien lo verifica y lo usa.
    # Un PR que los cambie no se mergea sin la operadora (merge-sprint excluye tier 4).
    "config/operator-grant-signers", "scripts/operator-grant.sh", "scripts/push-pr.sh",
)
GOVERNANCE_PREFIXES = ("config/merge-sprint", ".opencode/", ".github/workflows/")


def is_governance(path: str) -> bool:
    """True si el path pertenece a la gobernanza del workspace (SE-433 §2.8)."""
    p = path.lower()
    if p in GOVERNANCE_EXACT or p.startswith(GOVERNANCE_PREFIXES):
        return True
    if p.startswith(".claude/settings") and p.endswith(".json") and "/" not in p[len(".claude/"):]:
        return True
    name = p.rsplit("/", 1)[-1]
    return p.startswith("docs/rules/domain/") and "/" not in p[len("docs/rules/domain/"):] \
        and name.startswith("autonomous-safety") and name.endswith(".md")


# Artefactos regenerados por generate-capability-map.py y sam.py: reflejan cambios ya
# clasificados en sus fuentes. Las declaraciones del SAM (*-declarations.json, esquema)
# se editan a mano y siguen clasificándose.
SCM_GENERATED_FILES = (".scm/sam.json", ".scm/registry.json", ".scm/resources.json", ".scm/index.scm")
SCM_GENERATED_DIRS = (".scm/views/", ".scm/reports/", ".scm/categories/")
# Excluir paths que NO elevan (evitar falsos positivos como "docs/")
LOW_RISK_EXT = (".md", ".txt", ".json", ".yaml", ".yml", ".scm")

DOCS_PATHS = ("docs/", "README", "CHANGELOG", "REVIEW", "CLAUDE.md", "AGENTS.md", "SKILLS.md")


def classify(files: list[str]) -> dict:
    """Devuelve tier + rationale + requires_human para un set de archivos."""
    tier = 2  # default: reversible módulo
    rationale: list[str] = []
    if not files:
        # Fail-closed: sin ficheros no se puede evaluar el riesgo (p. ej. un git diff fallido).
        return {"tier": 3, "requires_human": True, "rationale": "diff vacío: no se puede evaluar → tier 3", "files": []}

    for f in files:
        fl = f.lower()
        # SE-433: gobernanza antes que cualquier exención (docs, SCM)
        if is_governance(f):
            tier = max(tier, 4)
            rationale.append(f"path de gobernanza: {f}")
            continue
        # SAM/SCM regenerado: no eleva (p. ej. views/authority.json contiene "auth")
        if fl in SCM_GENERATED_FILES or fl.startswith(SCM_GENERATED_DIRS):
            continue
        # docs puros → tier 1 (si todos son docs)
        if any(fl.startswith(d.lower()) for d in DOCS_PATHS) and fl.endswith((".md", ".txt")):
            continue
        # tier 4: infra/prod/PII
        if any(p in fl for p in TIER_4_PATHS):
            tier = max(tier, 4)
            rationale.append(f"path crítico: {f}")
            continue
        # tier 3: secrets/migrations/auth
        if any(p in fl for p in TIER_3_PATHS):
            tier = max(tier, 3)
            rationale.append(f"path sensible: {f}")
            continue

    # Si TODOS los archivos son docs → tier 1. Cada fichero con su propio nombre
    # (antes se evaluaba `fl` del bucle anterior: solo contaba el último fichero).
    all_docs = all(
        (any(name.startswith(d.lower()) for d in DOCS_PATHS) and name.endswith((".md", ".txt")))
        or (name.endswith(LOW_RISK_EXT) and "/" not in name.replace("docs/", ""))
        for name in (x.lower() for x in files)
    ) if files else False
    if all_docs and tier == 2:
        tier = 1
        rationale.append("solo documentación/artefactos de proceso")

    if not rationale:
        rationale.append("código normal con tests — riesgo reversible")

    # Fail-closed: archivo sin categoría clara → tier 3 (humano, no asume bajo riesgo)
    KNOWN = TIER_3_PATHS + TIER_4_PATHS + DOCS_PATHS + ("src/", "tests/", ".py", ".ts", ".tsx", ".js", ".go", ".rs", ".sh", ".cs", ".java", ".rb", ".php", ".md", ".scm", "docs/", "README", "CHANGELOG", "REVIEW", "CLAUDE.md", "AGENTS.md", "SKILLS.md", ".confidentiality-signature")
    unknown = [f for f in files if not any(k in f.lower() for k in KNOWN)]
    if unknown and tier < 3:
        tier = 3
        rationale.append(f"fail-closed: paths sin categoría clara → tier 3: {', '.join(unknown)}")

    return {
        "tier": tier,
        "requires_human": tier >= 3,
        "rationale": "; ".join(rationale),
        "files": files,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Clasificador de riesgo (SE-362)")
    parser.add_argument("--diff", required=True, help="archivos del diff separados por espacio")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    files = [f for f in args.diff.split() if f]
    result = classify(files)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Risk tier: {result['tier']} {'(humano requerido)' if result['requires_human'] else '(auto-merge posible)'}")
        print(f"  rationale: {result['rationale']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
