"""
tests/scripts/test_risk_tier.py — pytest para SE-362 risk-tier.

Cubre: clasificación por tier, paths de secrets/infra → tier alto, docs-only → tier 1,
fail-closed con path desconocido, rationale presente.

Ref: SE-362 — gradación de riesgo para auto-merge
"""
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "risk-tier.py"


def _load():
    spec = importlib.util.spec_from_file_location("risk_tier", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def rt():
    return _load()


def test_docs_only_tier_1(rt):
    res = rt.classify(["README.md", "docs/guide.md"])
    assert res["tier"] == 1
    assert res["requires_human"] is False


def test_secrets_tier_3(rt):
    res = rt.classify(["scripts/push-pr.sh"])
    assert res["tier"] >= 3
    assert res["requires_human"] is True


def test_infra_tier_4(rt):
    res = rt.classify(["infra/main.tf", ".github/workflows/prod.yml"])
    assert res["tier"] == 4
    assert res["requires_human"] is True


def test_migration_tier_3(rt):
    res = rt.classify(["db/migrations/001_add_users.py"])
    assert res["tier"] >= 3


def test_code_normal_tier_2(rt):
    res = rt.classify(["src/service.py", "tests/test_service.py"])
    assert res["tier"] == 2


def test_fail_closed_unknown(rt):
    res = rt.classify(["weird/path/file.bin"])
    assert res["tier"] == 3  # fail-closed: no asume bajo riesgo


def test_rationale_presente(rt):
    res = rt.classify(["src/x.py"])
    assert "rationale" in res and res["rationale"]


def test_codigo_mas_doc_es_tier_2_en_cualquier_orden(rt):
    # Regresión: all_docs miraba solo el último fichero del bucle (variable `fl` filtrada),
    # así que un script seguido de un .md salía tier 1.
    assert rt.classify(["scripts/validate-ci-local.sh", "CLAUDE.md"])["tier"] == 2
    assert rt.classify(["CLAUDE.md", "scripts/validate-ci-local.sh"])["tier"] == 2
    assert rt.classify(["src/x.py", "docs/guide.md", "README.md"])["tier"] == 2


def test_tier_independiente_del_orden(rt):
    import itertools
    files = ["docs/a.md", "scripts/tool.sh", "README.md", "tests/test_x.py"]
    tiers = {rt.classify(list(p))["tier"] for p in itertools.permutations(files)}
    assert tiers == {2}


def test_diff_vacio_fail_closed(rt):
    res = rt.classify([])
    assert res["tier"] == 3
    assert res["requires_human"] is True


def test_scm_generado_no_eleva(rt):
    res = rt.classify([".scm/sam.json", ".scm/views/authority.json", "docs/guide.md"])
    assert res["tier"] <= 2
    assert ".scm/views/authority.json" not in res["rationale"]


def test_scm_declaraciones_siguen_contando(rt):
    assert rt.classify([".scm/sam-authority-declarations.json"])["tier"] >= 3


# SE-343 (revisión de seguridad de #1401, P1-1): la raíz de confianza del grant de
# merge, su verificador y quien mergea con él son gobernanza → tier 4, solos o
# mezclados con cambios de bajo riesgo. Antes: 3 (fail-closed), 2 y 3.
GRANT_TRUST_FILES = ["config/operator-grant-" + "signers", "scripts/operator-grant.sh", "scripts/push-pr.sh"]


@pytest.mark.parametrize("path", GRANT_TRUST_FILES)
def test_raiz_de_confianza_del_grant_es_tier_4(rt, path):
    assert rt.classify([path])["tier"] == 4
    res = rt.classify(["docs/guide.md", path, "tests/test-x.bats"])
    assert res["tier"] == 4
    assert "gobernanza" in res["rationale"]


def test_vecinos_del_grant_no_son_gobernanza(rt):
    # Caso negativo: el nombre exacto, no uno parecido.
    assert not rt.is_governance("docs/operator-grant-" + "signers-notes.md")
    assert not rt.is_governance("scripts/operator-grant-helper.sh")
    assert rt.classify(["scripts/operator-grant-helper.sh"])["tier"] == 2
