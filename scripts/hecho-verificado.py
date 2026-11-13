#!/usr/bin/env python3
"""hecho-verificado.py — SE-530 S1: declarado / verificado / refutado, solo lectura.

  classify <marca-de-fin> [--evidence F]... [--reviews F]... [--orchestrator IDS]
  measure --done-dir DIR [--window 14] [--until YYYY-MM-DD] [--evidence F]... [--reviews F]...

Salida de classify (el estado va siempre en la primera línea de stdout):
  0 verificado, o declarado con marca legible · 1 refutado · 2 marca ilegible, vacía o sin ESTADO:
Estado derivado en lectura (D1); nada se escribe. Ante dato ausente o ambiguo: declarado.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys

ORCH_DEFAULT = "savia-orchestrator savia-orquestadora"  # misma lista que merge-sprint.sh
MECANICAS = {"ci_base", "postcondicion"}
CLASES = ("revision", "persona", "ci_base", "ci_propio", "postcondicion")
CAMPOS_ESTADO = ("estado", "verificado")
N_MIN, UMBRAL_PCT = 200, 10
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def orch_ids(arg):
    return set((arg or os.environ.get("HECHO_VERIFICADO_ORCH") or ORCH_DEFAULT).split())


def parse_done(path):
    """→ (estado, pr, motivo_error). estado None si la marca es ilegible."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            txt = f.read()
    except (OSError, UnicodeDecodeError) as e:
        return None, None, "marca ilegible (%s)" % type(e).__name__
    if not txt.strip():
        return None, None, "marca vacía"
    m = re.search(r"^ESTADO:\s*(OK|PARCIAL|FALLO)\b", txt, re.M)
    if not m:
        return None, None, "marca sin línea ESTADO: válida"
    pr = re.search(r"github\.com/[^/\s]+/([^/\s]+)/pull/(\d+)", txt) or re.search(r"()/pull/(\d+)", txt)
    return m.group(1), ((int(pr.group(2)), pr.group(1)) if pr else (None, "")), None


def load_jsonl(path, anomalias):
    out = []
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError):
        anomalias.append("evidencia ilegible: %s" % os.path.basename(path))
        return out
    for i, l in enumerate(lines, 1):
        if not l.strip():
            continue
        try:
            d = json.loads(l)
            assert isinstance(d, dict)
            out.append(d)
        except (ValueError, AssertionError):
            anomalias.append("línea %d inválida en %s" % (i, os.path.basename(path)))
    return out


def review_to_record(d):
    """Adapta una línea del registro de revisiones de merge-sprint."""
    if not all(k in d for k in ("pr", "sha", "reviewer", "author", "verdict")):
        return None
    return {"pr": d["pr"], "sha": d["sha"], "clase": "revision", "verificador": d["reviewer"],
            "ejecutor": d["author"], "resultado": "superada" if d["verdict"] == "APPROVE" else "fallida"}


class Evidencia:
    def __init__(self, evidence, reviews):
        self.anom = []
        self.heads, self.checks = {}, []
        for p in evidence:
            for d in load_jsonl(p, self.anom):
                if "head" in d:
                    k = self._key(d)
                    if k and isinstance(d["head"], str) and SHA_RE.match(d["head"]):
                        self.heads[k] = d["head"]  # el último registro manda
                    else:
                        self.anom.append("head inválido")
                else:
                    self.checks.append(d)
        for p in reviews:
            for d in load_jsonl(p, self.anom):
                r = review_to_record(d)
                if r:
                    self.checks.append(r)

    @staticmethod
    def _key(d):
        if isinstance(d.get("pr"), int):
            return ("pr", d["pr"])
        if isinstance(d.get("job"), str):
            return ("job", d["job"])
        return None

    def para(self, pr, job):
        keys = [k for k in (("pr", pr) if pr is not None else None, ("job", job)) if k]
        head = next((self.heads[k] for k in keys if k in self.heads), None)
        recs = [c for c in self.checks if self._key(c) in keys]
        return head, recs


def evaluar(estado, prr, job, ev, orch, repo=None):
    """Deriva (estado_hv, motivo, clases_vistas, anomalias, propia_falla)."""
    anom = list(ev.anom)
    pr, repo_pr = prr
    if repo and pr is not None and repo_pr != repo:  # los números de PR de otro repo no son los nuestros
        return "declarado", "PR de otro repositorio (%s): sin evidencia comparable" % (repo_pr or "desconocido"), set(), anom, False
    head, recs = ev.para(pr, job)
    if estado != "OK":
        return "declarado", "el trabajador no declara OK (ESTADO: %s)" % estado, set(), anom, False
    if head is None:
        return "declarado", "SHA vigente desconocido: ninguna comprobación cuenta", set(), anom, False
    vistas, pasan, fallan, propia_falla, viejas = set(), [], [], False, 0
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
        if indep and r.get("propuesta_por") == ejec:  # D3
            ap, h = r.get("aprobada_por"), r.get("contenido_hash")
            indep = bool(ap) and ap != ejec and ap not in orch and bool(h) and r.get("aprobada_hash") == h
        if not indep:
            if res == "fallida" and ver == ejec:
                propia_falla = True
            continue
        (pasan if res == "superada" else fallan).append((clase, ver))
    if fallan:
        c, v = fallan[0]
        return "refutado", "falla %s de %s sobre %s" % (c, v, head[:8]), vistas, anom, propia_falla
    if pasan:
        c, v = pasan[0]
        return "verificado", "%s de %s sobre %s" % (c, v, head[:8]), vistas, anom, propia_falla
    motivo = "sin comprobación independiente sobre %s" % head[:8]
    if viejas:
        motivo += "; %d de un SHA anterior" % viejas
    if propia_falla:
        motivo += "; la comprobación propia del ejecutor falla"
    return "declarado", motivo, vistas, anom, propia_falla


def job_de(path):
    return os.path.basename(os.path.dirname(os.path.abspath(path)))


def cmd_classify(a):
    estado, pr, err = parse_done(a.done)
    if estado is None:
        print("declarado: %s" % err)
        return 2
    ev = Evidencia(a.evidence, a.reviews)
    st, motivo, vistas, anom, _ = evaluar(estado, pr, job_de(a.done), ev, orch_ids(a.orchestrator), a.repo)
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
        st, _, vistas, _, _ = evaluar(estado, pr, job_de(p), ev, orch, a.repo)
        por_estado[st] += 1
        for c in vistas:
            por_clase[c] = por_clase.get(c, 0) + 1
    sin = por_estado["declarado"]
    print("ventana: %s .. %s (%d días)" % (desde, hasta, a.window))
    print("n_ok: %d" % n_ok)
    print("no_ok: %d" % no_ok)
    print("ilegibles: %d" % ilegibles)
    for s in ("verificado", "declarado", "refutado"):
        print("estado.%s: %d" % (s, por_estado[s]))
    print("clase.autodeclaracion: %d" % n_ok)
    for c in CLASES:
        print("clase.%s: %d" % (c, por_clase.get(c, 0)))
    print("sin_evidencia_independiente: %d" % sin)
    print("porcentaje: %s" % ("%d.%d" % divmod(sin * 1000 // n_ok, 10) if n_ok else "n/a"))
    print("H9: %s" % veredicto(n_ok, sin))
    return 0


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
    a = ap.parse_args(argv)
    return cmd_classify(a) if a.cmd == "classify" else cmd_measure(a)


if __name__ == "__main__":
    sys.exit(main())
