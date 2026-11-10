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
  risk-tier.py --diff "path1 path2" [--json] [--base <ref>]

Ref: SE-362 — gradación de riesgo para auto-merge (gobernanza ejecutable)
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
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
# SE-510 D1: corpus de órdenes que ninguna guarda puede bloquear. Cada entrada es una exención:
# cambiarlo exige revisión humana explícita (tier 3), para que no sea una vía de exenciones sueltas.
TIER_3_EXACT = ("config/guard-allow-corpus.json",)


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
# SE-501: se leen de scripts/derived-paths.txt (fuente única de D) TAL COMO ESTÁ EN LA BASE (por defecto
# origin/main; --base <ref>), nunca del checkout: la lista viaja en la PR y una PR que se añade a sí misma
# rebajaría su propio tier (seguimiento de #1472). Sin la lista de la base no se exime nada (fail-closed:
# el riesgo solo puede subir).
DEFAULT_BASE = "origin/main"


def _base_entries(base):
    """Líneas de scripts/derived-paths.txt en <base>; None si no se puede leer (ref inválida, sin git…)."""
    if not base or base.startswith("-"):
        return None
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    try:
        r = subprocess.run(["git", "-C", root, "show", f"{base}:scripts/derived-paths.txt"],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.splitlines() if r.returncode == 0 else None


def _load_scm_generated(base=DEFAULT_BASE):
    lines = _base_entries(base)
    if lines is None:
        return (), ()
    entries = [l.strip() for l in lines if l.strip() and not l.lstrip().startswith("#")]
    # rev-1472 S-P2-2: una entrada que cubra todo .scm/ (o un fichero editado a mano) rebajaría el tier
    # de las declaraciones del SAM; esas entradas se ignoran (fail-closed), también si vienen de la base.
    scm = [e.lower() for e in entries if e.startswith(".scm/") and e != ".scm/" and not _scm_hand_edited(e)]
    return tuple(e for e in scm if not e.endswith("/")), tuple(e for e in scm if e.endswith("/"))


# Ficheros de .scm que se editan a mano: nunca son D, digan lo que digan la lista o un prefijo de ella.
def _scm_hand_edited(path):
    p = path.lower()
    return (p.startswith(".scm/runtime-surface/") or p.endswith("-declarations.json")
            or p.endswith(".schema.json") or ".scm/runtime-surface/".startswith(p))


SCM_GENERATED_FILES, SCM_GENERATED_DIRS = _load_scm_generated()
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
        if fl in TIER_3_EXACT:
            tier = max(tier, 3)
            rationale.append(f"corpus de exenciones de guardas (SE-510): {f}")
            continue
        # SAM/SCM regenerado: no eleva (p. ej. views/authority.json contiene "auth")
        if (fl in SCM_GENERATED_FILES or fl.startswith(SCM_GENERATED_DIRS)) and not _scm_hand_edited(fl):
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
    parser.add_argument("--base", default=DEFAULT_BASE,
                        help="ref de la base de la que se lee scripts/derived-paths.txt (por defecto origin/main)")
    args = parser.parse_args()
    global SCM_GENERATED_FILES, SCM_GENERATED_DIRS
    SCM_GENERATED_FILES, SCM_GENERATED_DIRS = _load_scm_generated(args.base)

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
