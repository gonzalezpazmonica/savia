#!/usr/bin/env python3
"""hecho-verificado.py — SE-530 S1: declarado / verificado / refutado, solo lectura.

  classify <marca-de-fin> [--evidence F]... [--reviews F]... [--orchestrator IDS]
  measure --done-dir DIR [--window 14] [--until YYYY-MM-DD] [--evidence F]... [--reviews F]...
  check-prereg <prerregistro> <medicion>   (AC-1.8: 0 coincide · 1 no coincide · 2 error)

Salida de classify (el estado va siempre en la primera línea de stdout):
  0 verificado, o declarado con marca legible · 1 refutado · 2 marca ilegible, vacía o sin ESTADO:
Estado derivado en lectura (D1); nada se escribe. Ante dato ausente o ambiguo: declarado.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
from collections import Counter

ORCH_DEFAULT = "savia-orchestrator savia-orquestadora"  # misma lista que merge-sprint.sh
MECANICAS = {"ci_base", "postcondicion"}
CLASES = ("revision", "persona", "ci_base", "ci_propio", "postcondicion")
CAMPOS_ESTADO = ("estado", "verificado")
N_MIN, UMBRAL_PCT = 200, 10
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def orch_ids(arg):
    return set((arg or os.environ.get("HECHO_VERIFICADO_ORCH") or ORCH_DEFAULT).split())


def parse_done(path):
    """→ (estado, pr, motivo_error); pr = (n, owner, repo) | 'multiple'. estado None si la marca es ilegible."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            txt = f.read()
    except (OSError, UnicodeDecodeError) as e:
        return None, None, "marca ilegible (%s)" % type(e).__name__
    if not txt.strip():
        return None, None, "marca vacía"
    m = re.search(r"^ESTADO:[ \t]*(OK|PARCIAL|FALLO)\b", txt, re.M)
    if not m:
        return None, None, "marca sin línea ESTADO: válida"
    gh = re.findall(r"github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)", txt)
    prs = {(o.lower(), r.lower(), int(n)) for o, r, n in gh}
    otras = Counter(re.findall(r"/pull/(\d+)", txt)) - Counter(n for _, _, n in gh)  # URL sin github.com
    prs |= {("", "", int(n)) for n in otras}
    if len(prs) > 1:  # la marca la escribe el ejecutor: varias PR citadas = ambiguo, no se elige la que convenga
        return m.group(1), "multiple", None
    if not prs:
        return m.group(1), (None, "", ""), None
    o, r, n = next(iter(prs))
    return m.group(1), (n, o, r), None


def load_jsonl(path, anomalias):
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except (OSError, UnicodeDecodeError):
        anomalias.append("evidencia ilegible: %s" % os.path.basename(path))
        return out
    for i, l in enumerate(lines, 1):
        if not l.strip():
            continue
        try:
            d = json.loads(l)
            if not isinstance(d, dict):
                raise ValueError("no es un objeto")
            out.append(d)
        except ValueError:
            anomalias.append("línea %d inválida en %s" % (i, os.path.basename(path)))
    return out


def review_to_record(d, anomalias):
    """Adapta una línea del registro de revisiones de merge-sprint. APPROVE→superada, HOLD→fallida;
    cualquier otro verdict es una anomalía y se ignora (un verdict basura no refuta)."""
    if not all(k in d for k in ("pr", "sha", "reviewer", "author", "verdict")):
        return None
    res = {"APPROVE": "superada", "HOLD": "fallida"}.get(d["verdict"]) if isinstance(d["verdict"], str) else None
    if res is None:
        anomalias.append("verdict desconocido %r ignorado" % (d["verdict"],))
        return None
    return {"pr": d["pr"], "sha": d["sha"], "clase": "revision", "verificador": d["reviewer"],
            "ejecutor": d["author"], "resultado": res, "propuesta_por": d["reviewer"]}


class Evidencia:
    def __init__(self, evidence, reviews):
        self.anom = []
        self.heads, self.checks, self.job_pr = {}, [], {}
        for p in evidence:
            for d in load_jsonl(p, self.anom):
                if "head" in d:
                    k = self._key(d)
                    if k and isinstance(d["head"], str) and SHA_RE.match(d["head"]):
                        self.heads[k] = d["head"]  # el último registro manda
                        if k[0] == "pr" and isinstance(d.get("job"), str):
                            self.job_pr[d["job"]] = k[1]  # la PR de un trabajo la fija el recolector, no la marca
                    else:
                        self.anom.append("head inválido")
                else:
                    self.checks.append(d)
        for p in reviews:
            for d in load_jsonl(p, self.anom):
                r = review_to_record(d, self.anom)
                if r:
                    self.checks.append(r)

    @staticmethod
    def _key(d):
        if isinstance(d.get("pr"), int) and not isinstance(d.get("pr"), bool):
            return ("pr", d["pr"])
        if isinstance(d.get("job"), str):
            return ("job", d["job"])
        return None

    def para(self, pr, job):
        keys = [k for k in (("pr", pr) if pr is not None else None, ("job", job)) if k]
        head = next((self.heads[k] for k in keys if k in self.heads), None)
        recs = [c for c in self.checks if self._key(c) in keys]
        return head, recs


def repo_ok(repo, owner, name):
    """--repo admite «repo» u «owner/repo»; GitHub no distingue mayúsculas."""
    want = repo.lower().split("/")
    return name == want[-1] and (len(want) < 2 or owner == want[0])


def evaluar(estado, prr, job, ev, orch, repo=None):
    """Deriva (estado_hv, motivo, clases_vistas, clases_independientes, anomalias, propia_falla)."""
    anom = list(ev.anom)
    if prr == "multiple":
        return "declarado", "la marca cita varias PR distintas: ambiguo, sin evidencia comparable", set(), set(), anom, False
    pr, owner_pr, repo_pr = prr
    if pr is not None and repo_pr and not repo:  # sin --repo no se sabe de qué repositorio es el número
        return "declarado", "la marca cita el repositorio %s y no se indicó --repo: sin evidencia comparable" % repo_pr, set(), set(), anom, False
    if repo and pr is not None and not repo_ok(repo, owner_pr, repo_pr):  # los números de PR de otro repo no son los nuestros
        return "declarado", "PR de otro repositorio (%s): sin evidencia comparable" % (repo_pr or "desconocido"), set(), set(), anom, False
    if pr is not None and ev.job_pr.get(job, pr) != pr:
        return "declarado", "la PR citada (#%d) no es la que la evidencia asocia al trabajo (#%d)" % (pr, ev.job_pr[job]), set(), set(), anom, False
    head, recs = ev.para(pr, job)
    if estado != "OK":
        return "declarado", "el trabajador no declara OK (ESTADO: %s)" % estado, set(), set(), anom, False
    if head is None:
        return "declarado", "SHA vigente desconocido: ninguna comprobación cuenta", set(), set(), anom, False
    vistas, indeps, pasan, fallan, propia_falla, viejas, ajena_falla = set(), set(), [], [], False, 0, None
    for r in recs:
        for c in CAMPOS_ESTADO:
            if c in r:
                anom.append("campo '%s' escrito por el ejecutor, ignorado" % c)
        clase = r.get("clase")
        if clase == "ci":
            pb = r.get("pruebas_base")
            clase = "ci_base" if isinstance(pb, int) and not isinstance(pb, bool) and pb >= 1 else "ci_propio"
        if clase not in CLASES:
            anom.append("clase desconocida %r ignorada" % (r.get("clase"),))
            continue
        if r.get("sha") != head:
            viejas += 1
            continue
        res = r.get("resultado")
        if res not in ("superada", "fallida"):
            anom.append("resultado ambiguo ignorado")
            continue
        vistas.add(clase)
        ejec, ver = r.get("ejecutor"), r.get("verificador")
        if not (isinstance(ejec, str) and ejec and isinstance(ver, str) and ver):
            anom.append("registro sin ejecutor o verificador: no cuenta")
            continue
        indep = ver != ejec and (clase in MECANICAS or ver not in orch) and clase != "ci_propio"
        # D3: si la comprobación la propuso alguien que no es el verificador, exige aprobación de la
        # persona. Sin `propuesta_por` en una clase no mecánica no se sabe quién la propuso: se trata
        # como propuesta del ejecutor (fail-closed). Las mecánicas las recoge el recolector.
        pp = r.get("propuesta_por", None if clase not in MECANICAS else ver)
        if indep and pp != ver:
            ap, h, ah = r.get("aprobada_por"), r.get("contenido_hash"), r.get("aprobada_hash")
            indep = (isinstance(ap, str) and ap != "" and ap != ejec and ap not in orch
                     and isinstance(h, str) and h != "" and ah == h)
        if not indep:
            if res == "fallida" and ver == ejec:
                propia_falla = True
            elif res == "fallida" and ajena_falla is None:
                ajena_falla = (clase, ver)
            continue
        indeps.add(clase)
        (pasan if res == "superada" else fallan).append((clase, ver))
    if fallan:
        c, v = fallan[0]
        return "refutado", "falla %s de %s sobre %s" % (c, v, head[:8]), vistas, indeps, anom, propia_falla
    if pasan and ajena_falla:  # una falla no independiente no refuta, pero tampoco se calla: no se verifica
        anom.append("falla no independiente de %s ignorada" % ajena_falla[1])
        return "declarado", "hay una comprobación fallida no independiente (%s de %s): no se verifica" % ajena_falla, vistas, indeps, anom, propia_falla
    if pasan:
        c, v = pasan[0]
        return "verificado", "%s de %s sobre %s" % (c, v, head[:8]), vistas, indeps, anom, propia_falla
    motivo = "sin comprobación independiente sobre %s" % head[:8]
    if viejas:
        motivo += "; %d de un SHA anterior" % viejas
    if propia_falla:
        motivo += "; la comprobación propia del ejecutor falla"
    return "declarado", motivo, vistas, indeps, anom, propia_falla


def job_de(path):
    return os.path.basename(os.path.dirname(os.path.abspath(path)))


def cmd_classify(a):
    estado, pr, err = parse_done(a.done)
    if estado is None:
        print("declarado: %s" % err)
        return 2
    ev = Evidencia(a.evidence, a.reviews)
    st, motivo, vistas, _, anom, _ = evaluar(estado, pr, job_de(a.done), ev, orch_ids(a.orchestrator), a.repo)
    print("%s: %s" % (st, motivo))
    for c in sorted(vistas):
        print("clase=%s" % c)
    for x in sorted(set(anom)):
        print("anomalia=%s" % x)
    return 1 if st == "refutado" else 0


def veredicto(n, sin):
    if n < N_MIN:
        return "no concluyente"
    return "confirmada" if sin * 100 >= n * UMBRAL_PCT else "refutada"


def cmd_measure(a):
    marcas = []
    for root, _, files in os.walk(a.done_dir):
        if "done" in files:
            marcas.append(os.path.join(root, "done"))
    marcas.sort()
    jobs = [job_de(p) for p in marcas]
    if len(set(jobs)) != len(jobs):  # el job es el nombre del directorio: anidar mezclaría evidencia
        print("measure: nombres de trabajo repetidos (--done-dir debe ser plano)", file=sys.stderr)
        return 2
    if not marcas:
        print("measure: sin marcas en el directorio", file=sys.stderr)
        return 2
    fechas = {p: dt.datetime.fromtimestamp(os.path.getmtime(p), dt.timezone.utc).date() for p in marcas}
    try:
        hasta = dt.date.fromisoformat(a.until) if a.until else max(fechas.values())
    except ValueError:
        print("measure: --until inválido", file=sys.stderr)
        return 2
    desde = hasta - dt.timedelta(days=a.window - 1)
    ev = Evidencia(a.evidence, a.reviews)
    orch = orch_ids(a.orchestrator)
    n_ok, por_estado, por_clase, ilegibles, no_ok = 0, {"verificado": 0, "declarado": 0, "refutado": 0}, {}, 0, 0
    anoms = set()
    for p in marcas:
        if not desde <= fechas[p] <= hasta:
            continue
        estado, pr, _ = parse_done(p)
        if estado is None:
            ilegibles += 1
            continue
        if estado != "OK":
            no_ok += 1
            continue
        n_ok += 1
        st, _, vistas, indep_c, an, _ = evaluar(estado, pr, job_de(p), ev, orch, a.repo)
        por_estado[st] += 1
        anoms |= set(an)
        for c in vistas:  # ci_propio se informa siempre (nunca es independiente); el resto, solo si lo es
            if c != "ci_propio" and c not in indep_c:
                continue
            por_clase[c] = por_clase.get(c, 0) + 1
    sin = por_estado["declarado"]
    print("ventana: %s .. %s (%d días)" % (desde, hasta, a.window))
    print("n_ok: %d" % n_ok)
    print("no_ok: %d" % no_ok)
    print("ilegibles: %d" % ilegibles)
    print("anomalias: %d" % len(anoms))
    for s in ("verificado", "declarado", "refutado"):
        print("estado.%s: %d" % (s, por_estado[s]))
    print("clase.autodeclaracion: %d" % n_ok)
    for c in CLASES:
        print("clase.%s: %d" % (c, por_clase.get(c, 0)))
    print("sin_evidencia_independiente: %d" % sin)
    print("porcentaje: %s" % ("%d.%d" % divmod(sin * 1000 // n_ok, 10) if n_ok else "n/a"))
    print("H9: %s" % veredicto(n_ok, sin))
    return 0


def prereg_hash(path):
    """SHA-256 del prerregistro congelado: el texto anterior a «## Desviaciones» (esa sección se escribe tras medir)."""
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    m = re.search(r"^## Desviaciones$", txt, re.M)
    return hashlib.sha256((txt[:m.start()] if m else txt).encode("utf-8")).hexdigest()


def cmd_check_prereg(a):
    try:
        got = prereg_hash(a.prereg)
        with open(a.medicion, encoding="utf-8") as f:
            m = re.search(r"^prerregistro-sha256: ([0-9a-f]{64})$", f.read(), re.M)
    except (OSError, UnicodeDecodeError) as e:
        print("error: %s" % type(e).__name__, file=sys.stderr)
        return 2
    if not m:
        print("error: el informe no declara prerregistro-sha256", file=sys.stderr)
        return 2
    print("%s: calculado %s, declarado %s" % ("coincide" if got == m.group(1) else "NO coincide", got, m.group(1)))
    return 0 if got == m.group(1) else 1


def main(argv=None):
    ap = argparse.ArgumentParser(prog="hecho-verificado")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("classify", "measure"):
        s = sub.add_parser(name)
        s.add_argument("--evidence", action="append", default=[])
        s.add_argument("--reviews", action="append", default=[])
        s.add_argument("--orchestrator")
        s.add_argument("--repo", help="solo las PR de este repositorio tienen evidencia; el resto, declarado")
        if name == "classify":
            s.add_argument("done")
        else:
            s.add_argument("--done-dir", required=True)
            s.add_argument("--window", type=int, default=14)
            s.add_argument("--until")
    s = sub.add_parser("check-prereg")
    s.add_argument("prereg")
    s.add_argument("medicion")
    a = ap.parse_args(argv)
    try:
        return {"classify": cmd_classify, "measure": cmd_measure, "check-prereg": cmd_check_prereg}[a.cmd](a)
    except Exception as e:  # fail-closed: un error interno nunca es «refutado» (1)
        print("declarado: error interno (%s)" % type(e).__name__, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
