#!/usr/bin/env python3
"""SE-466 S1: audita los lockfiles del repo contra OSV (solo stdlib).

Lee los ficheros de dependencias versionados, consulta OSV en lote,
deduplica alias (un GHSA con su PYSEC cuenta 1) y emite una tabla o JSON
por fichero/paquete con severidad.

Fail-closed:
  - respuesta de red/JSON rota, lockfile ilegible, lockfile reconocido sin
    la estructura esperada, ningún lockfile descubierto, respuesta con forma
    inesperada o cualquier error imprevisto -> salida 2 (nunca «0 avisos»);
  - un aviso sin severidad se informa como «sin severidad» y el resumen
    lo cuenta como alto;
  - las líneas de requirements sin pin `==` no se pueden consultar: se
    listan por fichero en «unpinned» y se cuentan en el resumen;
  - los avisos retirados (`withdrawn`) no cuentan; se informa cuántos.

Salida: 0 = auditoría completa (haya o no avisos; este script informa, el
gate de CI es otro slice), 2 = no se pudo auditar.

Modo offline: `--offline respuesta.json` con la forma
  {"batch": <respuesta de /v1/querybatch>, "vulns": {"<id>": <vuln OSV>}}
donde batch.results se alinea por posición con las consultas ordenadas por
(ecosistema, paquete, versión). `--record fichero` guarda esa forma desde
una ejecución en línea para producir fixtures.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

OSV_BATCH_URL = "https://api.osv.dev/v1/querybatch"
OSV_VULN_URL = "https://api.osv.dev/v1/vulns/"
BATCH_SIZE = 500
TIMEOUT_S = 20
RETRIES = 3
MAX_PAGES = 100
LABEL_RANK = {"sin severidad": 5, "critical": 4, "high": 3, "moderate": 2, "low": 1, "none": 0}
HIGH_OR_ABOVE = {"critical", "high", "sin severidad"}

LOCK_NAMES = {"package-lock.json", "pnpm-lock.yaml", "Cargo.lock", "uv.lock"}
REQ_RE = re.compile(r"(^|/)requirements[^/]*\.(txt|lock)$|\.lock\.txt$|(^|/)requirements\.lock$")


class AuditError(Exception):
    """Fallo que impide una auditoría fiable (salida 2)."""


# ---------------------------------------------------------------- discovery
def discover(root: Path) -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            check=True, capture_output=True, timeout=60,
        ).stdout.decode("utf-8")
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError) as exc:
        raise AuditError(f"no se pudo listar ficheros con git: {exc}") from exc
    found = []
    for rel in out.split("\0"):
        if rel and (Path(rel).name in LOCK_NAMES or REQ_RE.search(rel)):
            found.append(rel)
    return sorted(found)


# ------------------------------------------------------------------ parsers
def _parse_package_lock(text: str) -> set[tuple[str, str, str]]:
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("package-lock no es un objeto JSON")
    pkgs: set[tuple[str, str, str]] = set()
    entries = data.get("packages")
    if isinstance(entries, dict):
        for key, meta in entries.items():
            # "" es la raíz; claves sin node_modules/ son fuentes de workspaces, no paquetes del registro
            if "node_modules/" not in key or not isinstance(meta, dict) or meta.get("link"):
                continue
            # alias npm: (node_modules/alias -> name: paquete real)
            name = meta.get("name") if isinstance(meta.get("name"), str) else key.rsplit("node_modules/", 1)[-1]
            ver = meta.get("version")
            if name and isinstance(ver, str):
                pkgs.add(("npm", name, ver))
    else:
        def walk(deps: dict) -> None:
            for name, meta in deps.items():
                if isinstance(meta, dict):
                    if isinstance(meta.get("version"), str):
                        pkgs.add(("npm", name, meta["version"]))
                    if isinstance(meta.get("dependencies"), dict):
                        walk(meta["dependencies"])
        deps = data.get("dependencies")
        if not isinstance(deps, dict):
            raise ValueError("package-lock sin «packages» ni «dependencies» (formato no reconocido)")
        walk(deps)
    return pkgs


_PNPM_KEY = re.compile(r"^/?(@?[^@(\s]+)@([^(@\s:]+)")
_PNPM_OLD = re.compile(r"^/(@[^/]+/[^/]+|[^/]+)/([^/(_\s:]+)")


def _pnpm_major(text: str) -> int | None:
    m = re.search(r"(?m)^lockfileVersion:\s*['\"]?(\d+)", text)
    return int(m.group(1)) if m else None


def _parse_pnpm(text: str) -> set[tuple[str, str, str]]:
    major = _pnpm_major(text)
    if major is None:
        raise ValueError("pnpm-lock sin lockfileVersion (formato no reconocido)")
    # v5 usa claves /nombre/versión(_peers); v6+ usa [/]nombre@versión(peers)
    key_re = _PNPM_OLD if major < 6 else _PNPM_KEY
    pkgs: set[tuple[str, str, str]] = set()
    in_packages = False
    for line in text.splitlines():
        if re.match(r"^\S", line):
            in_packages = line.strip() == "packages:"
            continue
        if not in_packages:
            continue
        m = re.match(r"^  ('([^']+)'|\"([^\"]+)\"|([^\s'\"][^:]*[^\s:]|[^\s'\":])):\s*$", line)
        if not m:
            continue
        key = m.group(2) or m.group(3) or m.group(4)
        mm = key_re.match(key)
        if not mm:
            raise ValueError(f"pnpm-lock: clave de paquete no reconocida «{key}»")
        pkgs.add(("npm", mm.group(1), mm.group(2)))
    return pkgs


def _cargo_registry(src: str) -> bool:
    # solo crates.io (índice git o sparse); un registro alternativo no es crates.io en OSV
    return "github.com/rust-lang/crates.io-index" in src or "index.crates.io" in src


def _uv_registry(src: str) -> bool:
    return "registry" in src


def _toml_packages(text: str, ecosystem: str, registry_ok) -> set[tuple[str, str, str]]:
    """registry_ok(source) -> bool decide si el paquete viene del registro público."""
    blocks = re.split(r"(?m)^\[\[package\]\]\s*$", text)[1:]
    if not blocks:
        raise ValueError("sin bloques [[package]] (truncado o formato no reconocido)")
    pkgs: set[tuple[str, str, str]] = set()
    for block in blocks:
        # solo la cabecera del bloque: hasta la siguiente tabla [..]
        head = re.split(r"(?m)^\[", block, maxsplit=1)[0]
        name = re.search(r'(?m)^name\s*=\s*"([^"]+)"', head)
        ver = re.search(r'(?m)^version\s*=\s*"([^"]+)"', head)
        src = re.search(r"(?m)^source\s*=\s*(.+)$", head)
        if not name or not ver:
            raise ValueError("bloque [[package]] sin name/version")
        if not src or not registry_ok(src.group(1)):
            continue
        pkgs.add((ecosystem, name.group(1), ver.group(1)))
    return pkgs


def _parse_requirements(text: str, unpinned: list[str] | None = None) -> set[tuple[str, str, str]]:
    pkgs: set[tuple[str, str, str]] = set()
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].split(" --", 1)[0].strip().rstrip("\\").strip()
        if not line or line.startswith("-"):
            continue
        m = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)(\[[^\]]*\])?\s*==\s*([A-Za-z0-9._+!-]+)", line)
        if m:
            name = re.sub(r"[-_.]+", "-", m.group(1)).lower()
            pkgs.add(("PyPI", name, m.group(3)))
        elif unpinned is not None:
            unpinned.append(line)
    return pkgs


def parse_lockfile(path: str, text: str, unpinned: list[str] | None = None) -> set[tuple[str, str, str]]:
    name = Path(path).name
    if name == "package-lock.json":
        return _parse_package_lock(text)
    if name == "pnpm-lock.yaml":
        return _parse_pnpm(text)
    if name == "Cargo.lock":
        return _toml_packages(text, "crates.io", _cargo_registry)
    if name == "uv.lock":
        return _toml_packages(text, "PyPI", _uv_registry)
    return _parse_requirements(text, unpinned)


def read_lockfiles(root: Path, rels: list[str]) -> tuple[dict[str, set[tuple[str, str, str]]], dict[str, list[str]]]:
    result, unpinned = {}, {}
    for rel in rels:
        try:
            text = (root / rel).read_text(encoding="utf-8")
            unpinned[rel] = []
            result[rel] = parse_lockfile(rel, text, unpinned[rel])
        except (OSError, UnicodeDecodeError, ValueError) as exc:  # JSONDecodeError es ValueError
            raise AuditError(f"lockfile ilegible {rel}: {exc}") from exc
    return result, unpinned


# --------------------------------------------------------------------- OSV
def _http_json(url: str, payload: dict | None) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json", "User-Agent": "savia-osv-lockfile-audit"})
    last: Exception | None = None
    for attempt in range(RETRIES):
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:  # noqa: S310 (https fijo)
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, OSError, ValueError) as exc:
            last = exc
            if attempt < RETRIES - 1:
                time.sleep(2 ** attempt)
    raise AuditError(f"OSV no respondió tras {RETRIES} intentos ({url}): {last}")


def _vuln_refs(item: dict) -> list[str]:
    """Ids de avisos de un resultado de querybatch; forma inesperada -> AuditError."""
    vulns = item.get("vulns", [])
    if not isinstance(vulns, list):
        raise AuditError("«vulns» de un resultado no es una lista")
    ids = []
    for v in vulns:
        if not isinstance(v, dict) or not isinstance(v.get("id"), str) or not v["id"]:
            raise AuditError("aviso sin «id» en la respuesta")
        ids.append(v["id"])
    return ids


def query_online(queries: list[tuple[str, str, str]]) -> tuple[dict, dict]:
    results: list[dict] = []
    for i in range(0, len(queries), BATCH_SIZE):
        chunk = queries[i:i + BATCH_SIZE]
        body = {"queries": [{"package": {"name": n, "ecosystem": e}, "version": v} for e, n, v in chunk]}
        resp = _http_json(OSV_BATCH_URL, body)
        res = resp.get("results") if isinstance(resp, dict) else None
        if not isinstance(res, list) or len(res) != len(chunk):
            raise AuditError("respuesta querybatch con forma inesperada")
        for (e, n, v), item in zip(chunk, res):
            if not isinstance(item, dict):
                raise AuditError("resultado querybatch no es un objeto")
            vulns = _vuln_refs(item)
            token = item.get("next_page_token")
            seen: set[str] = set()
            while token:  # paginación de un paquete con muchos avisos
                if token in seen or len(seen) >= MAX_PAGES:
                    raise AuditError(f"paginación OSV sin fin para {e}:{n}@{v}")
                seen.add(token)
                page = _http_json(OSV_BATCH_URL, {"queries": [{
                    "package": {"name": n, "ecosystem": e}, "version": v, "page_token": token}]})
                pr = page.get("results") if isinstance(page, dict) else None
                if not isinstance(pr, list) or len(pr) != 1 or not isinstance(pr[0], dict):
                    raise AuditError("página querybatch con forma inesperada")
                vulns += _vuln_refs(pr[0])
                token = pr[0].get("next_page_token")
            results.append({"vulns": [{"id": i} for i in vulns]})
    ids = sorted({v["id"] for r in results for v in r["vulns"]})
    with ThreadPoolExecutor(max_workers=8) as pool:
        details = list(pool.map(lambda i: _http_json(OSV_VULN_URL + urllib.parse.quote(i, safe=""), None), ids))
    return {"results": results}, dict(zip(ids, details))


# ---------------------------------------------------------------- severity
_W = {"AV": {"N": 0.85, "A": 0.62, "L": 0.55, "P": 0.2},
      "AC": {"L": 0.77, "H": 0.44},
      "UI": {"N": 0.85, "R": 0.62},
      "CIA": {"H": 0.56, "L": 0.22, "N": 0.0}}


def _roundup(x: float) -> float:
    i = int(round(x * 100000))
    return i / 100000.0 if i % 10000 == 0 else (i // 10000 + 1) / 10.0


def cvss3_score(vector: str) -> float | None:
    """Puntuación base CVSS v3.x; None si el vector no es v3 o es inválido."""
    if not vector.startswith("CVSS:3"):
        return None
    try:
        m = dict(p.split(":", 1) for p in vector.split("/")[1:])
        changed = m["S"] == "C"
        pr = {"N": 0.85, "L": 0.68 if changed else 0.62, "H": 0.5 if changed else 0.27}[m["PR"]]
        iss = 1 - (1 - _W["CIA"][m["C"]]) * (1 - _W["CIA"][m["I"]]) * (1 - _W["CIA"][m["A"]])
        impact = 7.52 * (iss - 0.029) - 3.25 * (iss - 0.02) ** 15 if changed else 6.42 * iss
        expl = 8.22 * _W["AV"][m["AV"]] * _W["AC"][m["AC"]] * pr * _W["UI"][m["UI"]]
        if impact <= 0:
            return 0.0
        raw = 1.08 * (impact + expl) if changed else impact + expl
        return _roundup(min(raw, 10.0))
    except (KeyError, ValueError):
        return None


def _label_from_score(score: float) -> str:
    return ("critical" if score >= 9.0 else "high" if score >= 7.0
            else "moderate" if score >= 4.0 else "low" if score > 0.0 else "none")


def severity_of(vuln: dict) -> tuple[str, float | None]:
    """(etiqueta, cvss). Sin dato utilizable -> «sin severidad»."""
    score = None
    for s in vuln.get("severity") or []:
        if isinstance(s, dict) and isinstance(s.get("score"), str):
            sc = cvss3_score(s["score"])
            if sc is not None:
                score = sc if score is None else max(score, sc)
    if score is not None:
        return _label_from_score(score), score
    db = vuln.get("database_specific")
    label = db.get("severity") if isinstance(db, dict) else None
    if isinstance(label, str) and label.strip().lower() in LABEL_RANK and label.strip().lower() != "sin severidad":
        return label.strip().lower(), None
    return "sin severidad", None


def _known_rank(label: str) -> int:
    # «sin severidad» queda por debajo de cualquier dato conocido (incluido «none»)
    return -1 if label == "sin severidad" else LABEL_RANK[label]


def canonical_id(vuln: dict) -> str:
    """GHSA si lo hay entre id/alias; si no CVE; si no el propio id."""
    ids = sorted({vuln["id"], *[a for a in vuln.get("aliases") or [] if isinstance(a, str)]})
    for prefix in ("GHSA-", "CVE-"):
        for i in ids:
            if i.startswith(prefix):
                return i
    return vuln["id"]


# ------------------------------------------------------------------ report
def build_report(locks: dict[str, set], batch: dict, vulns: dict, queries: list, source: str,
                 unpinned: dict[str, list[str]] | None = None) -> dict:
    unpinned = unpinned or {}
    results = batch.get("results") if isinstance(batch, dict) else None
    if not isinstance(results, list) or len(results) != len(queries):
        raise AuditError("la respuesta no se alinea con las consultas (¿lockfiles cambiados?)")
    by_query = {}
    for q, item in zip(queries, results):
        if not isinstance(item, dict):
            raise AuditError("resultado de consulta con forma inesperada")
        by_query[q] = _vuln_refs(item)
    advisories: dict[str, dict] = {}
    withdrawn: set[str] = set()
    files = []
    for path in sorted(locks):
        entries = []
        for eco, name, ver in sorted(locks[path]):
            for vid in by_query.get((eco, name, ver), []):
                vuln = vulns.get(vid)
                if not isinstance(vuln, dict) or vuln.get("id") != vid:
                    raise AuditError(f"falta el detalle OSV de {vid}")
                if vuln.get("withdrawn"):
                    withdrawn.add(vid)
                    continue
                canon = canonical_id(vuln)
                label, score = severity_of(vuln)
                adv = advisories.setdefault(canon, {
                    "id": canon, "ids": [], "severity": label, "cvss": score, "packages": []})
                if vid not in adv["ids"]:
                    adv["ids"].append(vid)
                # un alias con severidad conocida gana a uno sin ella (PYSEC suele no traerla)
                if _known_rank(label) > _known_rank(adv["severity"]):
                    adv["severity"], adv["cvss"] = label, score
                elif label == adv["severity"] and adv["cvss"] is None and score is not None:
                    adv["cvss"] = score
                adv["packages"].append(f"{eco}:{name}@{ver}")
                entries.append({"package": name, "version": ver, "ecosystem": eco,
                                "advisory": canon, "osv_id": vid})
        files.append({"path": path, "packages": len(locks[path]), "alerts": len(entries),
                      "findings": entries, "unpinned": unpinned.get(path, [])})
    # cada fila muestra la severidad del aviso fusionado, para que tabla y resumen cuadren
    for f in files:
        for e in f["findings"]:
            adv = advisories[e["advisory"]]
            e["severity"], e["cvss"] = adv["severity"], adv["cvss"]
    for adv in advisories.values():
        adv["ids"].sort()
        adv["packages"] = sorted(set(adv["packages"]))
    by_sev: dict[str, int] = {}
    for adv in advisories.values():
        by_sev[adv["severity"]] = by_sev.get(adv["severity"], 0) + 1
    return {
        "source": source,
        "summary": {
            "lockfiles": len(files),
            "packages": len(queries),
            "unique_advisories": len(advisories),
            "by_severity": dict(sorted(by_sev.items())),
            "high_or_above": sum(n for k, n in by_sev.items() if k in HIGH_OR_ABOVE),
            "withdrawn_ignored": len(withdrawn),
            "unpinned": sum(len(f["unpinned"]) for f in files),
            "note": "«sin severidad» se cuenta como alto (fail-closed)",
        },
        "lockfiles": files,
        "advisories": sorted(advisories.values(), key=lambda a: (-LABEL_RANK[a["severity"]], a["id"])),
    }


def render_table(rep: dict) -> str:
    lines = ["FICHERO  PAQUETE  VERSIÓN  AVISO  SEVERIDAD  CVSS"]
    for f in rep["lockfiles"]:
        lines.append(f"{f['path']}  ({f['packages']} paquetes, {f['alerts']} avisos con alias)")
        for u in f["unpinned"]:
            lines.append(f"  AVISO sin pin, no auditado: {u}")
        for e in f["findings"]:
            cv = "-" if e["cvss"] is None else f"{e['cvss']:.1f}"
            lines.append(f"  {e['package']}  {e['version']}  {e['advisory']}  {e['severity']}  {cv}")
    s = rep["summary"]
    lines.append("")
    lines.append(f"Avisos únicos: {s['unique_advisories']}  |  alto o peor (incl. sin severidad): "
                 f"{s['high_or_above']}  |  por severidad: {s['by_severity']}  |  "
                 f"lockfiles: {s['lockfiles']}  paquetes: {s['packages']}  sin pin: {s['unpinned']}  "
                 f"retirados ignorados: {s['withdrawn_ignored']}  [{rep['source']}]")
    return "\n".join(lines)


# -------------------------------------------------------------------- main
def run(args: argparse.Namespace) -> dict:
    root = Path(args.root).resolve()
    rels = args.lockfile or discover(root)
    if not rels:
        raise AuditError("no se encontró ningún lockfile versionado que auditar")
    locks, unpinned = read_lockfiles(root, rels)
    queries = sorted({q for pk in locks.values() for q in pk})
    if args.offline:
        try:
            raw = json.loads(Path(args.offline).read_text(encoding="utf-8"))
            batch, vulns = raw["batch"], raw["vulns"]
        except (OSError, ValueError, KeyError, TypeError) as exc:
            raise AuditError(f"respuesta offline ilegible: {exc}") from exc
        if not isinstance(vulns, dict):
            raise AuditError("respuesta offline: «vulns» no es un objeto")
        source = "offline"
    else:
        batch, vulns = query_online(queries)
        source = "osv.dev"
        if args.record:
            try:
                Path(args.record).write_text(json.dumps({"batch": batch, "vulns": vulns}, indent=1), encoding="utf-8")
            except OSError as exc:
                raise AuditError(f"no se pudo guardar --record {args.record}: {exc}") from exc
    return build_report(locks, batch, vulns, queries, source, unpinned)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".", help="raíz del repo (por defecto el cwd)")
    ap.add_argument("--lockfile", action="append", help="fichero relativo a --root; omite el descubrimiento (repetible)")
    ap.add_argument("--offline", metavar="RESPUESTA.json", help="usa una respuesta grabada, sin red")
    ap.add_argument("--record", metavar="FICHERO", help="guarda la respuesta de OSV (modo en línea)")
    ap.add_argument("--format", choices=("table", "json"), default="table")
    ap.add_argument("--list", action="store_true", help="solo lista los lockfiles descubiertos")
    args = ap.parse_args(argv)
    try:
        if args.list:
            print("\n".join(discover(Path(args.root).resolve())))
            return 0
        rep = run(args)
    except AuditError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001 — contrato: cualquier fallo imprevisto es «no se pudo auditar»
        print(f"ERROR: error inesperado, auditoría no fiable: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(rep, indent=2, ensure_ascii=False) if args.format == "json" else render_table(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
