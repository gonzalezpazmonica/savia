"""SE-466 S1: pruebas de scripts/osv-lockfile-audit.py (offline, respuestas OSV sintéticas)."""
import importlib.util
import json
import subprocess
import sys
import urllib.error
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "osv-lockfile-audit.py"
spec = importlib.util.spec_from_file_location("osv_audit", SCRIPT)
osv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(osv)

V3_CRITICAL = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"  # 9.8


def vuln(vid, aliases=(), score=None, label=None):
    v = {"id": vid, "aliases": list(aliases)}
    if score:
        v["severity"] = [{"type": "CVSS_V3", "score": score}]
    if label:
        v["database_specific"] = {"severity": label}
    return v


def write_offline(path, queries_results, vulns):
    path.write_text(json.dumps({
        "batch": {"results": [{"vulns": [{"id": i} for i in ids]} for ids in queries_results]},
        "vulns": vulns}))


@pytest.fixture
def repo(tmp_path):
    (tmp_path / "requirements.txt").write_text("# c\nPillow==9.0.0\nflask>=2\n-r other.txt\n")
    return tmp_path


def run(repo, offline, *extra):
    return osv.main(["--root", str(repo), "--lockfile", "requirements.txt",
                     "--offline", str(offline), "--format", "json", *extra])


def test_ac2_alias_cuenta_uno(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [["GHSA-aaaa-bbbb-cccc", "PYSEC-2022-1"]], {
        "GHSA-aaaa-bbbb-cccc": vuln("GHSA-aaaa-bbbb-cccc", ["PYSEC-2022-1", "CVE-2022-1"], V3_CRITICAL),
        "PYSEC-2022-1": vuln("PYSEC-2022-1", ["GHSA-aaaa-bbbb-cccc", "CVE-2022-1"]),
    })
    assert run(repo, off) == 0
    rep = json.loads(capsys.readouterr().out)
    assert rep["summary"]["unique_advisories"] == 1
    assert rep["advisories"][0]["ids"] == ["GHSA-aaaa-bbbb-cccc", "PYSEC-2022-1"]
    assert rep["advisories"][0]["severity"] == "critical"
    assert rep["advisories"][0]["cvss"] == 9.8


def test_dos_ghsa_distintos_con_cve_comun_no_se_fusionan(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [["GHSA-1111-1111-1111", "GHSA-2222-2222-2222"]], {
        "GHSA-1111-1111-1111": vuln("GHSA-1111-1111-1111", ["CVE-1"], label="LOW"),
        "GHSA-2222-2222-2222": vuln("GHSA-2222-2222-2222", ["CVE-1"], label="LOW"),
    })
    assert run(repo, off) == 0
    assert json.loads(capsys.readouterr().out)["summary"]["unique_advisories"] == 2


def test_sin_severidad_se_reporta_y_cuenta_como_alto(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [["RUSTSEC-2024-0001"]], {"RUSTSEC-2024-0001": vuln("RUSTSEC-2024-0001")})
    assert run(repo, off) == 0
    s = json.loads(capsys.readouterr().out)["summary"]
    assert s["by_severity"] == {"sin severidad": 1}
    assert s["high_or_above"] == 1


def test_severidad_baja_no_cuenta_como_alto(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [["GHSA-3333-3333-3333"]],
                  {"GHSA-3333-3333-3333": vuln("GHSA-3333-3333-3333", label="LOW")})
    assert run(repo, off) == 0
    assert json.loads(capsys.readouterr().out)["summary"]["high_or_above"] == 0


def test_umbral_cvss():
    assert osv._label_from_score(7.0) == "high"
    assert osv._label_from_score(6.9) == "moderate"
    assert osv._label_from_score(9.0) == "critical"
    assert osv._label_from_score(3.9) == "low"
    assert osv.cvss3_score(V3_CRITICAL) == 9.8
    assert osv.cvss3_score("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N") == 0.0
    assert osv.cvss3_score("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N") is None
    assert osv.cvss3_score("basura") is None


def test_respuesta_vacia_son_cero_avisos_sin_error(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [[]], {})
    assert run(repo, off) == 0
    assert json.loads(capsys.readouterr().out)["summary"]["unique_advisories"] == 0


def test_json_roto_sale_distinto_de_cero(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    off.write_text("{no es json")
    assert run(repo, off) == 2
    assert "0 avisos" not in capsys.readouterr().out


def test_respuesta_desalineada_sale_distinto_de_cero(repo, tmp_path):
    off = tmp_path / "off.json"
    write_offline(off, [[], []], {})  # una consulta, dos resultados
    assert run(repo, off) == 2


def test_falta_detalle_de_aviso_sale_distinto_de_cero(repo, tmp_path):
    off = tmp_path / "off.json"
    write_offline(off, [["GHSA-4444-4444-4444"]], {})
    assert run(repo, off) == 2


def test_lockfile_ilegible_sale_distinto_de_cero(tmp_path):
    (tmp_path / "package-lock.json").write_text("{roto")
    off = tmp_path / "off.json"
    write_offline(off, [], {})
    assert osv.main(["--root", str(tmp_path), "--lockfile", "package-lock.json", "--offline", str(off)]) == 2
    assert osv.main(["--root", str(tmp_path), "--lockfile", "no-existe.lock", "--offline", str(off)]) == 2


def test_error_de_red_sale_distinto_de_cero(repo, monkeypatch, capsys):
    def boom(*a, **k):
        raise urllib.error.URLError("sin red")
    monkeypatch.setattr(osv.urllib.request, "urlopen", boom)
    monkeypatch.setattr(osv.time, "sleep", lambda s: None)
    rc = osv.main(["--root", str(repo), "--lockfile", "requirements.txt"])
    assert rc == 2
    captured = capsys.readouterr()
    assert "OSV no respondió" in captured.err
    assert captured.out == ""


def test_parsers(tmp_path):
    npm = {"packages": {"": {"name": "root"}, "node_modules/a": {"version": "1.0.0"},
                        "node_modules/a/node_modules/@s/b": {"version": "2.0.0"},
                        "node_modules/l": {"link": True}}}
    assert osv.parse_lockfile("package-lock.json", json.dumps(npm)) == {
        ("npm", "a", "1.0.0"), ("npm", "@s/b", "2.0.0")}
    pnpm = ("lockfileVersion: '9.0'\npackages:\n  '@s/c@3.0.0':\n    resolution: {}\n"
            "  d@4.1.0(peer@1.0.0):\n    resolution: {}\nsnapshots:\n  zz@9.9.9:\n    x: 1\n")
    assert osv.parse_lockfile("pnpm-lock.yaml", pnpm) == {("npm", "@s/c", "3.0.0"), ("npm", "d", "4.1.0")}
    cargo = ('[[package]]\nname = "local"\nversion = "0.1.0"\n\n[[package]]\nname = "rand"\nversion = "0.8.5"\n'
             'source = "registry+https://github.com/rust-lang/crates.io-index"\n')
    assert osv.parse_lockfile("Cargo.lock", cargo) == {("crates.io", "rand", "0.8.5")}
    uv = ('[[package]]\nname = "Pillow"\nversion = "9.0.0"\nsource = { registry = "https://pypi.org/simple" }\n\n'
          '[[package]]\nname = "app"\nversion = "0.1.0"\nsource = { editable = "." }\n')
    assert osv.parse_lockfile("uv.lock", uv) == {("PyPI", "Pillow", "9.0.0")}
    req = "Flask_Login==1.0 --hash=sha256:ab\nsin-pin>=1\n# x\nPyJWT[crypto]==2.10.1\n"
    assert osv.parse_lockfile("requirements.txt", req) == {("PyPI", "flask-login", "1.0"), ("PyPI", "pyjwt", "2.10.1")}


def test_descubrimiento_usa_git_ls_files(tmp_path):
    subprocess.run(["git", "-C", str(tmp_path), "init", "-q"], check=True)
    (tmp_path / "a").mkdir()
    for rel in ("a/package-lock.json", "Cargo.lock", "requirements-dev.txt", "README.md"):
        (tmp_path / rel).write_text("{}")
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    assert osv.discover(tmp_path) == ["Cargo.lock", "a/package-lock.json", "requirements-dev.txt"]


def _sin_git_env(tmp_path):
    # GIT_CEILING_DIRECTORIES impide que git suba a un repo padre si TMPDIR está dentro de uno
    import os
    env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(tmp_path.parent))
    env.pop("GIT_DIR", None)
    env.pop("GIT_WORK_TREE", None)
    return env


def test_cli_fuera_de_git_falla_cerrado(tmp_path):
    root = tmp_path / "nogit"
    root.mkdir()
    p = subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), "--list"],
                       capture_output=True, text=True, env=_sin_git_env(root))
    assert p.returncode == 2
    assert "no se pudo listar ficheros con git" in p.stderr
    assert p.stdout == ""


def test_cli_fuera_de_git_con_offline_valido_falla_por_git(tmp_path):
    root = tmp_path / "nogit"
    root.mkdir()
    off = tmp_path / "off.json"
    write_offline(off, [], {})
    p = subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), "--offline", str(off)],
                       capture_output=True, text=True, env=_sin_git_env(root))
    assert p.returncode == 2
    assert "no se pudo listar ficheros con git" in p.stderr


# --------------------------------------------------- fix-1612 (revisión independiente)
def test_alias_sin_severidad_primero_y_critico_despues_sube(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [["PYSEC-2022-1", "GHSA-aaaa-bbbb-cccc"]], {
        "GHSA-aaaa-bbbb-cccc": vuln("GHSA-aaaa-bbbb-cccc", ["PYSEC-2022-1"], V3_CRITICAL),
        "PYSEC-2022-1": vuln("PYSEC-2022-1", ["GHSA-aaaa-bbbb-cccc"]),
    })
    assert run(repo, off) == 0
    rep = json.loads(capsys.readouterr().out)
    adv = rep["advisories"][0]
    assert rep["summary"]["unique_advisories"] == 1
    assert (adv["severity"], adv["cvss"]) == ("critical", 9.8)
    # la tabla por hallazgo cuadra con el aviso fusionado
    assert {f["severity"] for f in rep["lockfiles"][0]["findings"]} == {"critical"}


def test_alias_sin_severidad_primero_y_etiqueta_despues_sube(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [["PYSEC-2022-2", "GHSA-dddd-eeee-ffff"]], {
        "GHSA-dddd-eeee-ffff": vuln("GHSA-dddd-eeee-ffff", ["PYSEC-2022-2"], label="MODERATE"),
        "PYSEC-2022-2": vuln("PYSEC-2022-2", ["GHSA-dddd-eeee-ffff"]),
    })
    assert run(repo, off) == 0
    s = json.loads(capsys.readouterr().out)["summary"]
    assert s["by_severity"] == {"moderate": 1}
    assert s["high_or_above"] == 0


def test_mismo_rango_completa_cvss_ausente(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [["PYSEC-2022-3", "GHSA-gggg-hhhh-iiii"]], {
        "PYSEC-2022-3": vuln("PYSEC-2022-3", ["GHSA-gggg-hhhh-iiii"], label="CRITICAL"),
        "GHSA-gggg-hhhh-iiii": vuln("GHSA-gggg-hhhh-iiii", ["PYSEC-2022-3"], V3_CRITICAL),
    })
    assert run(repo, off) == 0
    adv = json.loads(capsys.readouterr().out)["advisories"][0]
    assert (adv["severity"], adv["cvss"]) == ("critical", 9.8)


def test_cvss_cero_es_none_no_low():
    v = vuln("GHSA-0", score="CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N")
    assert osv.severity_of(v) == ("none", 0.0)
    assert osv._label_from_score(0.1) == "low"


def test_aviso_retirado_no_cuenta(repo, tmp_path, capsys):
    off = tmp_path / "off.json"
    w = vuln("GHSA-wwww-wwww-wwww", score=V3_CRITICAL)
    w["withdrawn"] = "2024-01-01T00:00:00Z"
    write_offline(off, [["GHSA-wwww-wwww-wwww"]], {"GHSA-wwww-wwww-wwww": w})
    assert run(repo, off) == 0
    s = json.loads(capsys.readouterr().out)["summary"]
    assert s["unique_advisories"] == 0
    assert s["withdrawn_ignored"] == 1


@pytest.mark.parametrize("batch", [
    {"results": [{"vulns": [{"sin": "id"}]}]},
    {"results": [{"vulns": None}]},
    {"results": [{"vulns": ["no-es-dict"]}]},
])
def test_forma_inesperada_sale_2_no_traceback(repo, tmp_path, capsys, batch):
    off = tmp_path / "off.json"
    off.write_text(json.dumps({"batch": batch, "vulns": {}}))
    assert run(repo, off) == 2
    assert "ERROR:" in capsys.readouterr().err


def test_error_inesperado_sale_2(repo, tmp_path, monkeypatch, capsys):
    off = tmp_path / "off.json"
    write_offline(off, [[]], {})
    monkeypatch.setattr(osv, "build_report", lambda *a, **k: 1 / 0)
    assert run(repo, off) == 2
    assert "error inesperado" in capsys.readouterr().err


def test_record_a_ruta_inexistente_sale_2(repo, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(osv, "query_online", lambda q: ({"results": [{"vulns": []}]}, {}))
    rc = osv.main(["--root", str(repo), "--lockfile", "requirements.txt",
                   "--record", str(tmp_path / "no" / "existe" / "r.json")])
    assert rc == 2
    assert "no se pudo guardar" in capsys.readouterr().err


@pytest.mark.parametrize("name,text", [
    ("Cargo.lock", "basura truncada\n"),
    ("uv.lock", "version = 1\n[[pack"),
    ("package-lock.json", '{"name": "x", "lockfileVersion": 3}'),
    ("pnpm-lock.yaml", "packages:\n  formato-raro:\n    x: 1\n"),
])
def test_lockfile_reconocido_sin_estructura_sale_2(tmp_path, name, text):
    (tmp_path / name).write_text(text)
    off = tmp_path / "off.json"
    write_offline(off, [], {})
    assert osv.main(["--root", str(tmp_path), "--lockfile", name, "--offline", str(off)]) == 2


def test_lockfiles_legitimos_vacios_no_fallan(tmp_path):
    # Cargo.lock con solo crates locales y package-lock solo con la raíz: 0 paquetes es correcto
    assert osv.parse_lockfile("Cargo.lock", '[[package]]\nname = "local"\nversion = "0.1.0"\n') == set()
    assert osv.parse_lockfile("package-lock.json", '{"packages": {"": {"name": "r"}}}') == set()


def test_requirements_sin_pins_se_avisa(tmp_path, capsys):
    (tmp_path / "requirements.txt").write_text("flask>=2\nrequests\n")
    off = tmp_path / "off.json"
    write_offline(off, [], {})
    assert osv.main(["--root", str(tmp_path), "--lockfile", "requirements.txt",
                     "--offline", str(off), "--format", "json"]) == 0
    rep = json.loads(capsys.readouterr().out)
    assert rep["lockfiles"][0]["unpinned"] == ["flask>=2", "requests"]
    assert rep["summary"]["unpinned"] == 2


def test_sin_lockfiles_descubiertos_sale_2(tmp_path, capsys):
    subprocess.run(["git", "-C", str(tmp_path), "init", "-q"], check=True)
    (tmp_path / "README.md").write_text("x")
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    off = tmp_path / "off.json"
    write_offline(off, [], {})
    assert osv.main(["--root", str(tmp_path), "--offline", str(off)]) == 2
    assert "ningún lockfile" in capsys.readouterr().err


def test_descubrimiento_con_nombres_no_ascii(tmp_path):
    subprocess.run(["git", "-C", str(tmp_path), "init", "-q"], check=True)
    d = tmp_path / "módulo"
    d.mkdir()
    (d / "Cargo.lock").write_text("x")
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    assert osv.discover(tmp_path) == ["módulo/Cargo.lock"]


def test_parsers_casos_borde():
    pnpm5 = ("lockfileVersion: 5.4\npackages:\n  /foo/1.0.0_@babel+core@7.0.0:\n    resolution: {}\n"
             "  /@s/bar/2.0.0:\n    resolution: {}\n")
    assert osv.parse_lockfile("pnpm-lock.yaml", pnpm5) == {("npm", "foo", "1.0.0"), ("npm", "@s/bar", "2.0.0")}
    npm = {"packages": {"": {"name": "root"}, "packages/ws": {"version": "0.0.1", "name": "ws-local"},
                        "node_modules/ws-local": {"link": True},
                        "node_modules/alias": {"version": "1.2.3", "name": "real-pkg"}}}
    assert osv.parse_lockfile("package-lock.json", json.dumps(npm)) == {("npm", "real-pkg", "1.2.3")}
    cargo = ('[[package]]\nname = "priv"\nversion = "1.0.0"\n'
             'source = "registry+https://my.registry.example/index"\n\n'
             '[[package]]\nname = "serde"\nversion = "1.0.0"\nsource = "sparse+https://index.crates.io/"\n')
    assert osv.parse_lockfile("Cargo.lock", cargo) == {("crates.io", "serde", "1.0.0")}


def test_paginacion_con_token_repetido_sale_2(monkeypatch):
    def fake(url, payload):
        return {"results": [{"vulns": [], "next_page_token": "T"}] * len((payload or {}).get("queries", []))}
    monkeypatch.setattr(osv, "_http_json", fake)
    with pytest.raises(osv.AuditError, match="paginación"):
        osv.query_online([("PyPI", "x", "1")])


def test_id_de_aviso_se_escapa_en_la_url(monkeypatch):
    urls = []

    def fake(url, payload):
        if payload is not None:
            return {"results": [{"vulns": [{"id": "../x?y=1"}]}]}
        urls.append(url)
        return {"id": "../x?y=1"}
    monkeypatch.setattr(osv, "_http_json", fake)
    osv.query_online([("PyPI", "x", "1")])
    assert urls == [osv.OSV_VULN_URL + "..%2Fx%3Fy%3D1"]


@pytest.mark.parametrize("src", [
    "sparse+https://evil.example/index.crates.io/",
    "registry+https://evil.example/github.com/rust-lang/crates.io-index",
    "registry+https://github.com/rust-lang/crates.io-index.evil.example",
    "sparse+https://index.crates.io.evil.example/",
])
def test_cargo_registro_alternativo_con_subcadena_no_es_crates_io(src):
    # CodeQL py/incomplete-url-substring-sanitization: la subcadena no basta
    assert osv._cargo_registry(src) is False


@pytest.mark.parametrize("src", [
    "registry+https://github.com/rust-lang/crates.io-index",
    "sparse+https://index.crates.io/",
])
def test_cargo_crates_io_legitimo(src):
    assert osv._cargo_registry(src) is True
