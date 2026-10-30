#!/usr/bin/env python3
"""SE-489 R1 — validador del banco de evidencia.

Comprueba cada caso contra `schema.json` (motor mínimo de JSON Schema, solo
stdlib) y después contra los ficheros: cada `required_evidence` existe en su
revisión, el localizador está en la sección indicada y cada
`forbidden_evidence` existe. Reglas del banco: ≥ N casos por categoría, 70/30
dev/test por categoría, ids únicos, `as_of` en D, evidencia dentro de
`allowed_domes`.

Revisiones: blob SHA-1 de git. Cúpula `git` (savia-docs): el blob de la ruta
en `snapshot_commit`. Cúpula `worktree` (corpus sintético): el blob del
fichero en disco. Sin git o sin el commit, falla (cierre seguro).

Uso: validate.py [--cases F] [--manifest F] [--repo DIR] [--hidden]
Salida: 0 válido · 1 inválido · 2 error de entrada.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
TYPES = {"object": dict, "array": list, "string": str, "boolean": bool, "null": type(None)}


def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def _type_ok(x, t) -> bool:
    if t == "integer":
        return isinstance(x, int) and not isinstance(x, bool)
    if t == "number":
        return isinstance(x, (int, float)) and not isinstance(x, bool)
    if t in ("object", "array", "string", "null"):
        return isinstance(x, TYPES[t])
    if t == "boolean":
        return isinstance(x, bool)
    return False


def check_schema(x, s: dict, path: str = "$") -> list[str]:
    """Subconjunto de JSON Schema usado por schema.json."""
    errs: list[str] = []
    if "type" in s:
        ts = s["type"] if isinstance(s["type"], list) else [s["type"]]
        if not any(_type_ok(x, t) for t in ts):
            return [f"{path}: tipo {type(x).__name__}, se esperaba {ts}"]
    if "const" in s and x != s["const"]:
        errs.append(f"{path}: debe valer {s['const']!r}")
    if "enum" in s and x not in s["enum"]:
        errs.append(f"{path}: {x!r} fuera de {s['enum']}")
    if isinstance(x, str):
        if "minLength" in s and len(x) < s["minLength"]:
            errs.append(f"{path}: longitud < {s['minLength']}")
        if "pattern" in s and not re.search(s["pattern"], x):
            errs.append(f"{path}: no cumple {s['pattern']}")
    if isinstance(x, list):
        if "minItems" in s and len(x) < s["minItems"]:
            errs.append(f"{path}: menos de {s['minItems']} elementos")
        if "items" in s:
            for i, it in enumerate(x):
                errs += check_schema(it, s["items"], f"{path}[{i}]")
    if isinstance(x, dict):
        props = s.get("properties", {})
        for k in s.get("required", []):
            if k not in x:
                errs.append(f"{path}: falta {k}")
        for k, val in x.items():
            if k in props:
                errs += check_schema(val, props[k], f"{path}.{k}")
            elif s.get("additionalProperties") is False:
                errs.append(f"{path}: campo no permitido {k}")
    return errs


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")


def section_text(text: str, section: str | None) -> str | None:
    """Texto bajo el encabezado `section` hasta el siguiente de nivel igual o superior."""
    if section is None:
        return text
    lines = text.splitlines()
    want = norm(section.replace("**", ""))
    for i, line in enumerate(lines):
        m = HEADING.match(line)
        if m and norm(m.group(2).replace("**", "")) == want:
            level = len(m.group(1))
            body = []
            for nxt in lines[i + 1:]:
                h = HEADING.match(nxt)
                if h and len(h.group(1)) <= level:
                    break
                body.append(nxt)
            return "\n".join(body)
    return None


class Corpus:
    """Acceso a documentos por cúpula y revisión."""

    def __init__(self, manifest: dict, repo: str):
        self.m, self.repo = manifest, repo
        self.cache: dict[tuple, tuple] = {}
        self.git_error: str | None = None
        snap = manifest.get("snapshot_commit", "")
        try:
            subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{snap}^{{commit}}"], check=True, capture_output=True)
        except (OSError, subprocess.CalledProcessError):
            self.git_error = f"snapshot_commit {snap} no disponible en {repo} (hace falta el historial de git)"

    def get(self, dome: str, doc: str):
        """(revisión, texto) o (None, motivo)."""
        key = (dome, doc)
        if key in self.cache:
            return self.cache[key]
        d = self.m["domes"].get(dome)
        if d is None:
            res = (None, f"cúpula desconocida {dome}")
        elif ".." in doc.split("/") or doc.startswith("/"):
            res = (None, f"ruta no válida {doc}")
        elif d["source"] == "git":
            if self.git_error:
                res = (None, self.git_error)
            else:
                rel = os.path.join(d["root"], doc) if d["root"] else doc
                spec = f"{self.m['snapshot_commit']}:{rel}"
                p = subprocess.run(["git", "-C", self.repo, "rev-parse", "--verify", "-q", spec], capture_output=True, text=True)
                if p.returncode != 0:
                    res = (None, f"{dome}:{doc} no existe en {self.m['snapshot_commit'][:9]}")
                else:
                    rev = p.stdout.strip()
                    data = subprocess.run(["git", "-C", self.repo, "cat-file", "blob", rev], capture_output=True, check=True).stdout
                    res = (rev, data.decode("utf-8"))
        elif d["source"] == "worktree":
            path = os.path.join(self.repo, d["root"], doc)
            if not os.path.isfile(path):
                res = (None, f"{dome}:{doc} no existe en {d['root']}")
            else:
                with open(path, "rb") as fh:
                    data = fh.read()
                res = (blob_sha(data), data.decode("utf-8"))
        else:
            res = (None, f"source desconocido {d['source']}")
        self.cache[key] = res
        return res


def validate(cases: list, manifest: dict, repo: str, hidden: bool = False, schema: dict | None = None) -> list[str]:
    if schema is None:
        with open(os.path.join(HERE, "schema.json"), encoding="utf-8") as fh:
            schema = json.load(fh)
    corpus = Corpus(manifest, repo)
    domes = manifest["domes"]
    errs: list[str] = []
    seen: Counter = Counter()
    by_cat: dict[str, Counter] = defaultdict(Counter)
    for n, c in enumerate(cases):
        cid = c.get("id", f"#{n}") if isinstance(c, dict) else f"#{n}"
        se = check_schema(c, schema)
        if se:
            errs += [f"{cid}: {e}" for e in se]
            continue
        seen[cid] += 1
        by_cat[c["category"]][c["split"]] += 1
        if not cid.lstrip("H-").startswith(c["category"]):
            errs.append(f"{cid}: id no corresponde a la categoría {c['category']}")
        allowed = c["scope"]["allowed_domes"]
        for dname in allowed:
            if dname not in domes:
                errs.append(f"{cid}: cúpula desconocida en allowed_domes: {dname}")
        if c["category"] == "D" and not c["scope"]["as_of"]:
            errs.append(f"{cid}: la categoría D exige scope.as_of")
        exp = c["expected"]
        if not exp["must_abstain"] and not exp["required_evidence"]:
            errs.append(f"{cid}: sin must_abstain hace falta required_evidence")
        if not exp["must_abstain"] and not exp["answer_facts"]:
            errs.append(f"{cid}: sin must_abstain hace falta answer_facts")
        req_docs = set()
        for ev in exp["required_evidence"]:
            tag = f"{cid}: {ev['dome']}:{ev['document']}"
            if ev["dome"] not in allowed:
                errs.append(f"{tag}: la evidencia requerida está fuera de allowed_domes")
            rev, text = corpus.get(ev["dome"], ev["document"])
            if rev is None:
                errs.append(f"{tag}: {text}")
                continue
            req_docs.add((ev["dome"], ev["document"]))
            if rev != ev["revision"]:
                errs.append(f"{tag}: revision {ev['revision'][:12]} ≠ {rev[:12]}")
            body = section_text(text, ev["locator"]["section"])
            if body is None:
                errs.append(f"{tag}: section «{ev['locator']['section']}» no encontrada")
            elif norm(ev["locator"]["quote"]) not in norm(body):
                errs.append(f"{tag}: quote «{ev['locator']['quote'][:50]}» no está en la sección")
        for ev in exp["forbidden_evidence"]:
            tag = f"{cid}: forbidden {ev['dome']}:{ev['document']}"
            rev, text = corpus.get(ev["dome"], ev["document"])
            if rev is None:
                errs.append(f"{tag}: {text}")
                continue
            if "revision" in ev and ev["revision"] != rev:
                errs.append(f"{tag}: revision {ev['revision'][:12]} ≠ {rev[:12]}")
            if (ev["dome"], ev["document"]) in req_docs:
                errs.append(f"{tag}: documento requerida y prohibida a la vez")
    errs += [f"{cid}: id duplicado" for cid, k in seen.items() if k > 1]
    if not hidden:
        minimum = manifest.get("min_per_category", 50)
        ratio = manifest.get("test_ratio", 0.3)
        for cat in "ABCDEF":
            cnt = by_cat[cat]
            total = cnt["dev"] + cnt["test"]
            if total < minimum:
                errs.append(f"categoría {cat}: {total} casos, mínimo {minimum}")
            elif cnt["test"] != round(total * ratio):
                errs.append(f"categoría {cat}: split test={cnt['test']} de {total}, se esperaba {round(total * ratio)}")
    return errs


def load_jsonl(path: str) -> list:
    with open(path, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--cases", default=os.path.join(HERE, "cases.jsonl"))
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.json"))
    ap.add_argument("--repo", default=None, help="raíz del repo (def. git rev-parse --show-toplevel)")
    ap.add_argument("--hidden", action="store_true", help="subconjunto oculto: sin mínimos ni split")
    a = ap.parse_args(argv)
    try:
        repo = a.repo or subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"],
                                        capture_output=True, text=True, check=True).stdout.strip()
        cases = load_jsonl(a.cases)
        with open(a.manifest, encoding="utf-8") as fh:
            manifest = json.load(fh)
    except (OSError, ValueError, subprocess.CalledProcessError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    errs = validate(cases, manifest, repo, hidden=a.hidden)
    for e in errs:
        print(f"INVALID {e}")
    cats = Counter((c.get("category"), c.get("split")) for c in cases if isinstance(c, dict))
    summary = " ".join(f"{k}={cats[(k, 'dev')]}+{cats[(k, 'test')]}" for k in "ABCDEF")
    print(f"{'FAIL' if errs else 'OK'} casos={len(cases)} errores={len(errs)} {summary}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
