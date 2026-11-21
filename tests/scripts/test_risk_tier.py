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
    assert rt.classify(["scripts/validate-ci-local.sh", "README.md"])["tier"] == 2
    assert rt.classify(["README.md", "scripts/validate-ci-local.sh"])["tier"] == 2
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


# SE-510 D1: el corpus de órdenes legítimas es una lista de exenciones de guardas. Cambiarlo
# exige revisión humana explícita (tier 3), solo o junto a cambios de bajo riesgo. Antes: tier 2
# (".json" casaba con ".js" en la lista de conocidos y nada lo elevaba).
GUARD_CORPUS = "config/guard-allow-corpus.json"


def test_corpus_de_ordenes_legitimas_es_tier_3(rt):
    assert rt.classify([GUARD_CORPUS])["tier"] == 3
    res = rt.classify(["docs/guide.md", GUARD_CORPUS, "tests/test-x.bats"])
    assert res["tier"] == 3
    assert "SE-510" in res["rationale"]


def test_vecinos_del_corpus_no_suben_a_tier_3(rt):
    # Caso negativo: solo el nombre exacto; otro corpus de config sigue en tier 2.
    assert rt.classify(["config/kernel-corpus.json"])["tier"] == 2
    assert rt.classify(["config/guard-allow-corpus.json.bak"])["tier"] == 2


# SE-511 S2 (revisión de seguridad de #1527, P1-1): savia-core.md es el texto de autonomía y
# honestidad que se carga en cada turno y generate-savia-core.py decide qué regiones entran.
# Antes: tier 1 (prefijo docs/) y tier 2; una PR podía quitar la región de autonomía sin humano.
SAVIA_CORE_FILES = ["docs/rules/domain/savia-core.md", "scripts/generate-savia-core.py"]


@pytest.mark.parametrize("path", SAVIA_CORE_FILES)
def test_nucleo_por_turno_y_su_generador_son_tier_4(rt, path):
    assert rt.is_governance(path)
    res = rt.classify(["docs/guide.md", path, "tests/test-x.bats"])
    assert res["tier"] == 4
    assert "gobernanza" in res["rationale"]


def test_vecinos_del_nucleo_no_son_gobernanza(rt):
    # Caso negativo: solo el nombre exacto.
    assert not rt.is_governance("docs/rules/domain/savia-core-notes.md")
    assert not rt.is_governance("scripts/generate-savia-core-helper.py")
    assert rt.classify(["docs/rules/domain/savia-core-notes.md"])["tier"] == 1


# SE-498 F0 (R6.1): todo config/control/** es gobernanza en tier 4 (aprobaciones de resume,
# operator.json, executors-remote.json, REVOCATION_EPOCH, gate.json). El merge-sprint nunca
# fusiona tier 4, así que esos ficheros solo llegan a main por fusión manual de la operadora.
# Antes: tier 3 (fail-closed por extensión desconocida) o 2 (.json).
CONTROL_FILES = [
    "config/control/resume/3-7-0123456789abcdef.json",
    "config/control/operator.json",
    "config/control/executors-remote.json",
    "config/control/REVOCATION_EPOCH",
    "config/control/gate.json",
]


@pytest.mark.parametrize("path", CONTROL_FILES)
def test_plano_de_control_es_tier_4(rt, path):
    assert rt.is_governance(path)
    assert rt.classify([path])["tier"] == 4
    res = rt.classify(["docs/guide.md", path, "tests/test-x.bats"])
    assert res["tier"] == 4
    assert "gobernanza" in res["rationale"]


def test_vecinos_del_plano_de_control_no_son_gobernanza(rt):
    # Caso negativo: el prefijo es el directorio, no un nombre que empiece igual.
    assert not rt.is_governance("config/control-notes.json")
    assert not rt.is_governance("docs/config/control/operator.json")
    assert rt.classify(["config/control-notes.json"])["tier"] == 2


# Decisión 2026-11-18: guardas, CLAUDE.md, freno de emergencia y puente son gobernanza (tier 4).
@pytest.mark.parametrize("path", [
    ".claude/hooks/validate-bash-global.sh", ".claude/hooks/lib/dome_guard.py", ".claude/hooks/_legacy/x.sh",
    ".claude/enterprise/hooks/network-egress-guard.sh",
    ".opencode/plugins/guards/block-force-push.ts", ".opencode/plugins/savia-foundation.ts",
    "CLAUDE.md", "projects/demo/CLAUDE.md", ".opencode/CLAUDE.md",
    "scripts/savia-control.py", "config/control/REVOCATION_EPOCH",
    "scripts/savia-bridge.py", "scripts/bridge_auth.py", "scripts/savia-bridge.service",
    "scripts/install-savia-bridge-system.sh",
    "scripts/repeat-tool-guard.py", "scripts/budget-guard.sh",
])
def test_ejecucion_y_guardas_son_gobernanza_tier_4(rt, path):
    res = rt.classify([path])
    assert res["tier"] == 4 and res["requires_human"] is True
    assert "gobernanza" in res["rationale"]


def test_claude_md_junto_a_codigo_sube_el_lote(rt):
    assert rt.classify(["scripts/validate-ci-local.sh", "CLAUDE.md"])["tier"] == 4


@pytest.mark.parametrize("path", [
    "tests/fixtures/sam/valid/CLAUDE.md", "scripts/guardrail-audit.sh", "scripts/test-wellbeing-guardian.sh",
    "scripts/bridge_auth_notes.py", ".claude/hooksmore/x.sh", "docs/hooks/readme.md",
])
def test_vecinos_no_suben_a_tier_4(rt, path):
    # Casos límite: el prefijo/nombre debe ser exacto, no una coincidencia parcial.
    assert rt.classify([path])["tier"] < 4
