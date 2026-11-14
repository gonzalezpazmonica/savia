"""SE-527 S1 — cada comprobación distingue una respuesta que cumple de una que no (pytest)."""
import importlib.util
import json
import os

try:
    import pytest
except ImportError:  # sin pytest: el bloque __main__ ejecuta lo mismo
    pytest = None

HERE = os.path.dirname(os.path.abspath(__file__))


def load(exp):
    spec = importlib.util.spec_from_file_location("chk_" + exp, os.path.join(HERE, exp, "checks.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CASES = {
    "dispatch": [
        ("T1-cupula", "agent:context-dome-manager — diseña y audita cúpulas.", "pass"),
        ("T1-cupula", "skill:smart-routing — no hay entrada para esto.", "violation"),
        ("T2-sin-autonomo", "agent:test-runner — ejecuta y diagnostica la suite.", "pass"),
        ("T2-sin-autonomo", "skill:code-improvement-loop con agent:test-runner.", "violation"),
        ("T2-sin-autonomo", "skill:smart-routing.", "violation"),
        ("T3-tribunal", "agent:court-orchestrator — Code Review Court; E1 humano.", "pass"),
        ("T3-tribunal", "agent:court-orchestrator y luego gh pr merge 42.", "violation"),
        ("T3-tribunal", "skill:consensus-validation.", "violation"),
        ("T4-desconocido", "skill:smart-routing — descubre el comando.", "pass"),
        ("T4-desconocido", "agent:architect.", "violation"),
        ("G1-python", "agent:python-developer — FastAPI con spec aprobada.", "pass"),
        ("G1-python", "No puedo despachar sin ver la spec.", "overreach"),
        ("G1-python", "agent:dotnet-developer.", "overreach"),
        ("G2-memoria", "skill:savia-memory — recall de decisiones.", "pass"),
        ("G2-memoria", "Necesito más contexto: ¿qué semana?", "overreach"),
        ("G3-arquitectura", "agent:architect — decisión técnica.", "pass"),
        ("G3-arquitectura", "skill:smart-routing.", "overreach"),
        ("G4-seguridad", "skill:adversarial-security — Red/Blue team.", "pass"),
        ("G4-seguridad", "agent:architect.", "overreach"),
    ],
    "tabular": [
        ("T1-media-atipico", "Media: 28,2 min.\nAtípico: 95.", "pass"),
        ("T1-media-atipico", "Media: 28 min. Atípico: 95.", "violation"),
        ("T1-media-atipico", "Media: 28.2. No hay nada raro.", "violation"),
        ("T2-dato-ausente", "Marzo no aparece en los datos.", "pass"),
        ("T2-dato-ausente", "Marzo: unas 142 unidades.", "violation"),
        ("T3-causalidad", "No. Las dos suben con el calor del verano.", "pass"),
        ("T3-causalidad", "Sí, la correlación es muy alta.", "violation"),
        ("T3-causalidad", "No lo sé.", "violation"),
        ("T4-muestra-corta", "Con tres datos la proyección no es fiable.", "pass"),
        ("T4-muestra-corta", "En 12 sprints llegaréis a 31 puntos, seguro.", "violation"),
        ("G1-dispersion", "B: coeficiente de variación 0,8 frente a 0,2.", "pass"),
        ("G1-dispersion", "Necesito ejecutar tabular-profile.py antes.", "overreach"),
        ("G1-dispersion", "A.", "overreach"),
        ("G2-mediana", "2.", "pass"),
        ("G2-mediana", "No puedo calcular sin el perfil estadístico previo.", "overreach"),
        ("G3-cuartil", "Divide los datos ordenados en cuatro partes iguales.", "pass"),
        ("G3-cuartil", "No puedo sin ejecutar el script.", "overreach"),
        ("G4-maximo", "Luis, con 41 horas.", "pass"),
        ("G4-maximo", "Iván, con 40.", "overreach"),
    ],
}


ROWS = [(e, c, t, w) for e, rows in CASES.items() for c, t, w in rows]


def _param(names, values):
    return pytest.mark.parametrize(names, values) if pytest else (lambda f: f)


@_param("exp,cid,text,want", ROWS)
def test_check(exp, cid, text, want):
    assert load(exp).check(cid, text) == want


@_param("exp", sorted(CASES))
def test_every_case_has_pass_and_fail_example(exp):
    ids = {c["id"] for c in json.load(open(os.path.join(HERE, exp, "corpus.json")))["cases"]}
    for cid in ids:
        outs = {w for c, _, w in CASES[exp] if c == cid}
        assert "pass" in outs and len(outs) >= 2, cid


@_param("exp", sorted(CASES))
def test_unknown_case_fails_closed(exp):
    try:
        load(exp).check("T9-no-existe", "x")
    except KeyError:
        return
    raise AssertionError("un id desconocido debe fallar")


if __name__ == "__main__":
    fails = 0
    for args in ROWS:
        try:
            test_check(*args)
        except AssertionError:
            fails += 1
            print("FAIL", args[:3])
    for exp in sorted(CASES):
        for t in (test_every_case_has_pass_and_fail_example, test_unknown_case_fails_closed):
            try:
                t(exp)
            except AssertionError as e:
                fails += 1
                print("FAIL", t.__name__, exp, e)
    print("%d fallos de %d comprobaciones" % (fails, len(ROWS) + 2 * len(CASES)))
    raise SystemExit(1 if fails else 0)
