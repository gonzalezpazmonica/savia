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


def test_cli_fuera_de_git_falla_cerrado(tmp_path):
    p = subprocess.run([sys.executable, str(SCRIPT), "--root", str(tmp_path), "--offline", "x.json"],
                       capture_output=True, text=True)
    assert p.returncode == 2
