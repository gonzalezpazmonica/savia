#!/usr/bin/env python3
"""
bus-factor-scan.py -- Motor CST(change-size-ratio) para deteccion de Bus Factor.
SE-252 -- Bus Factor Shield
Solo usa stdlib. Compatible con Python 3.8+.
"""

import argparse
import datetime
import fnmatch
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from typing import Dict, List, Optional, Tuple

# -- Configuracion desde entorno ----------------------------------------------

def _env_float(key, default):
    try:
        return float(os.environ.get(key, default))
    except (ValueError, TypeError):
        return default

def _env_int(key, default):
    try:
        return int(os.environ.get(key, default))
    except (ValueError, TypeError):
        return default

def _env_list(key, default):
    raw = os.environ.get(key, default)
    return [p.strip() for p in raw.split(",") if p.strip()]

BF_OWNERSHIP_THRESHOLD        = _env_float("BF_OWNERSHIP_THRESHOLD", 0.50)
BF_RISK_CRITICAL              = _env_int("BF_RISK_CRITICAL", 1)
BF_RISK_HIGH                  = _env_int("BF_RISK_HIGH", 2)
BF_RISK_MEDIUM                = _env_int("BF_RISK_MEDIUM", 3)
BF_MAX_HISTORY_DEPTH          = _env_int("BF_MAX_HISTORY_DEPTH", 0)
BF_MODULE_DEPTH               = _env_int("BF_MODULE_DEPTH", 2)
BF_EXCLUDE_PATTERNS           = _env_list("BF_EXCLUDE_PATTERNS", "vendor/,node_modules/,*.lock")
BF_EXCLUDE_BINARY             = os.environ.get("BF_EXCLUDE_BINARY", "1") not in ("0", "false", "no")
BF_EXCLUDE_GENERATED_PATTERNS = _env_list(
    "BF_EXCLUDE_GENERATED_PATTERNS",
    "*.pb.go,*_generated*,*auto_generated*,*.min.js,*.min.css"
)

# Patrones de bots, evaluados sobre "nombre <email>" del autor (tras mailmap).
# ci@ y noreply@ van anclados a un segmento de la parte local: al inicio o
# tras -, _, . o + ("gitlab-ci@", "build-noreply@" son bots; "marci@",
# "marcinoreply@" son humanos). *@users.noreply.github.com NO es bot.
BOT_PATTERNS_LIST = [
    r"\[bot\]",
    r"(<|[-_.+])no-?reply@",
    r"(<|[-_.+])ci@",
    r"<action@github\.com>",
    r"dependabot",
    r"github-actions",
    r"renovate",
    r"snyk-bot",
    r"automated",
]
_BOT_RE = re.compile("|".join(BOT_PATTERNS_LIST), re.IGNORECASE)


# -- Utilidades git ------------------------------------------------------------

def _run(cmd, cwd, timeout=60):
    """Ejecuta un comando y devuelve (returncode, stdout, stderr)."""
    try:
        r = subprocess.run(
            cmd, cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
        stdout = r.stdout.decode("utf-8", errors="replace") if r.stdout else ""
        stderr = r.stderr.decode("utf-8", errors="replace") if r.stderr else ""
        return r.returncode, stdout, stderr
    except subprocess.TimeoutExpired:
        return 1, "", "timeout"
    except FileNotFoundError as e:
        return 1, "", str(e)


def is_shallow_clone(repo):
    rc, out, _ = _run(["git", "rev-parse", "--is-shallow-repository"], repo)
    return rc == 0 and out.strip() == "true"


def is_binary_file(repo, path):
    """Detecta si un archivo es binario via git check-attr."""
    rc, out, _ = _run(["git", "check-attr", "diff", "--", path], repo)
    if rc != 0:
        return False
    return "unset" in out or "-text" in out


def get_tracked_files(repo):
    """Devuelve los archivos versionados bajo `repo`, relativos a `repo`.

    -z evita el quoting de git en rutas no ASCII; sin --full-name las rutas
    son relativas al directorio escaneado, el mismo cwd que usa git log.
    """
    rc, out, _ = _run(["git", "ls-files", "-z"], repo)
    if rc != 0:
        return []
    return [f for f in out.split("\0") if f]


def should_exclude(path):
    """Retorna True si el path debe excluirse segun los patrones configurados."""
    for pat in BF_EXCLUDE_PATTERNS:
        # Un patrón "dir/" excluye ese directorio, no cualquier ruta que
        # empiece por las mismas letras (vendor_client.py, vendored/...).
        if fnmatch.fnmatch(path, pat) or (pat.endswith("/") and path.startswith(pat)):
            return True
    for pat in BF_EXCLUDE_GENERATED_PATTERNS:
        basename = os.path.basename(path)
        if fnmatch.fnmatch(basename, pat) or fnmatch.fnmatch(path, pat):
            return True
    return False


def is_bot_author(author_field):
    """Retorna True si el campo de autor corresponde a un bot."""
    return bool(_BOT_RE.search(author_field))


# -- Algoritmo CST -------------------------------------------------------------

AUTHOR_MARK = "@@BF-AUTHOR@@"


def get_file_stats(repo, path):
    """
    Devuelve {author_email: total_changes} para un archivo usando git log --numstat.
    %aN/%aE aplican .mailmap: varios emails de una persona cuentan como uno.
    """
    cmd = ["git", "log"]
    if BF_MAX_HISTORY_DEPTH > 0:
        cmd.append(f"-{BF_MAX_HISTORY_DEPTH}")
    cmd += ["--use-mailmap", "--follow", "-C", "-M", "--numstat",
            f"--format={AUTHOR_MARK}%aN <%aE>", "--", path]

    rc, out, _ = _run(cmd, repo, timeout=120)
    if rc != 0 or not out.strip():
        return {}

    stats = defaultdict(int)
    current_author = None

    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        # Linea de autor: "@@BF-AUTHOR@@Nombre <email>"
        if line.startswith(AUTHOR_MARK):
            ident = line[len(AUTHOR_MARK):]
            if is_bot_author(ident):
                current_author = None
            else:
                current_author = ident[ident.rfind("<") + 1:].rstrip(">")
            continue
        # Linea numstat: "added\tdeleted\tfilename"
        parts = line.split("\t")
        if len(parts) >= 3 and current_author:
            added_s, deleted_s = parts[0], parts[1]
            # Archivos binarios tienen "-" en numstat
            if added_s == "-" or deleted_s == "-":
                continue
            try:
                stats[current_author] += int(added_s) + int(deleted_s)
            except ValueError:
                pass

    return dict(stats)


def compute_file_bus_factor(stats):
    """
    Calcula BF de un archivo a partir de {author: total_changes}.
    Retorna (bus_factor, owners_list, warnings).
    """
    warnings = []
    total = sum(stats.values())

    if total == 0:
        warnings.append("no_history")
        return 0, [], warnings

    scores = {e: v / total for e, v in stats.items()}
    owners = [
        {"dev": e, "score": round(s, 4), "files_owned": 0}
        for e, s in sorted(scores.items(), key=lambda x: -x[1])
        if s >= BF_OWNERSHIP_THRESHOLD
    ]

    if not owners:
        # Si nadie alcanza el umbral, el mayor contribuidor es owner
        top = max(scores, key=lambda e: scores[e])
        owners = [{"dev": top, "score": round(scores[top], 4), "files_owned": 0}]
        warnings.append("no_clear_owner")

    return len(owners), owners, warnings


def risk_level(bf):
    # BF=0 significa sin historial atribuible: no hay datos, no es CRITICAL.
    if bf <= 0:
        return "UNKNOWN"
    if bf <= BF_RISK_CRITICAL:
        return "CRITICAL"
    if bf <= BF_RISK_HIGH:
        return "HIGH"
    if bf <= BF_RISK_MEDIUM:
        return "MEDIUM"
    return "LOW"


# -- Agrupacion en modulos ----------------------------------------------------

def module_path_for(file_path, depth):
    """Agrupa por los primeros `depth` componentes del path."""
    parts = file_path.replace("\\", "/").split("/")
    if len(parts) <= depth:
        return os.path.dirname(file_path) or "."
    return "/".join(parts[:depth])


# -- Bus factor de modulo (greedy set cover) -----------------------------------

def compute_module_bus_factor(files_data):
    """
    Calcula BF del modulo como el menor conjunto de autores C que cubren
    al menos el 50% de archivos del modulo. Greedy set cover.
    """
    total_files = len(files_data)
    if total_files == 0:
        return 0, []

    dev_files = defaultdict(set)
    for fd in files_data:
        for owner in fd.get("owners", []):
            dev_files[owner["dev"]].add(fd["path"])

    if not dev_files:
        return 0, []

    covered = set()
    selected = []
    target = total_files * 0.5

    remaining = dict(dev_files)
    while len(covered) < target and remaining:
        best = max(remaining, key=lambda d: len(remaining[d] - covered))
        new_files = remaining[best] - covered
        if not new_files:
            break
        covered |= new_files
        selected.append(best)
        del remaining[best]

    # Scores aggregados
    all_scores = defaultdict(list)
    for fd in files_data:
        for owner in fd.get("owners", []):
            all_scores[owner["dev"]].append(owner["score"])

    owners_list = []
    for dev in selected:
        s_list = all_scores.get(dev, [0.0])
        avg = sum(s_list) / len(s_list)
        owners_list.append({
            "dev": dev,
            "score": round(avg, 4),
            "files_owned": len(dev_files[dev]),
        })

    return len(selected), owners_list


# -- Escaneo principal ---------------------------------------------------------

def _utc_now_iso():
    """Fecha UTC ISO-8601 con sufijo Z (sin utcnow, obsoleto en 3.12)."""
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    return now.isoformat() + "Z"


def scan_repo(repo, project_name):
    """Escanea un repositorio y devuelve el JSON de bus factor."""
    warnings_global = []

    if is_shallow_clone(repo):
        warnings_global.append("shallow_clone_detected:results_may_be_incomplete")

    all_files = get_tracked_files(repo)
    if not all_files:
        return {
            "generated_at": _utc_now_iso(),
            "project": project_name,
            "modules": [],
            "summary": {"total_modules": 0, "critical": 0, "high": 0,
                        "medium": 0, "low": 0, "unknown": 0},
            "warnings": ["no_tracked_files"],
        }

    # Agrupar archivos por modulo
    module_files = defaultdict(list)
    for f in all_files:
        if should_exclude(f):
            continue
        if BF_EXCLUDE_BINARY and is_binary_file(repo, f):
            continue
        mod = module_path_for(f, BF_MODULE_DEPTH)
        module_files[mod].append(f)

    modules_output = []

    for mod_name, files in sorted(module_files.items()):
        files_data = []
        module_warnings = []

        for fpath in files:
            stats = get_file_stats(repo, fpath)
            bf, owners, file_warnings = compute_file_bus_factor(stats)
            files_data.append({
                "path": fpath,
                "bus_factor": bf,
                "owners": owners,
                "warnings": file_warnings,
            })

        if not files_data:
            continue

        mod_bf, mod_owners = compute_module_bus_factor(files_data)
        if mod_bf == 0:
            mod_bf = max((fd["bus_factor"] for fd in files_data if fd["bus_factor"] > 0), default=0)
            if mod_bf == 0:
                module_warnings.append("no_history_in_module")

        rl = risk_level(mod_bf)

        modules_output.append({
            "name": mod_name,
            "path": mod_name,
            "bus_factor": mod_bf,
            "risk_level": rl,
            "owners": mod_owners,
            "files": files_data,
            "warnings": module_warnings,
        })

    summary = {
        "total_modules": len(modules_output),
        "critical": sum(1 for m in modules_output if m["risk_level"] == "CRITICAL"),
        "high":     sum(1 for m in modules_output if m["risk_level"] == "HIGH"),
        "medium":   sum(1 for m in modules_output if m["risk_level"] == "MEDIUM"),
        "low":      sum(1 for m in modules_output if m["risk_level"] == "LOW"),
        "unknown":  sum(1 for m in modules_output if m["risk_level"] == "UNKNOWN"),
    }

    return {
        "generated_at": _utc_now_iso(),
        "project": project_name,
        "modules": modules_output,
        "summary": summary,
        "warnings": warnings_global,
    }


# -- CLI -----------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Bus Factor Scan -- CST algorithm. SE-252."
    )
    parser.add_argument("repo", nargs="?", default=".",
                        help="Path al repositorio git (default: .)")
    parser.add_argument("--project", default=None,
                        help="Nombre del proyecto")
    parser.add_argument("--output", default=None,
                        help="Fichero JSON de salida (default: stdout)")
    args = parser.parse_args()

    repo = os.path.abspath(args.repo)
    if not os.path.isdir(repo):
        print(f"ERROR: directorio no existe: {repo}", file=sys.stderr)
        sys.exit(1)

    rc, _, _ = _run(["git", "rev-parse", "--git-dir"], repo)
    if rc != 0:
        print(f"ERROR: no es un repositorio git: {repo}", file=sys.stderr)
        sys.exit(1)

    project_name = args.project or os.path.basename(repo)
    result = scan_repo(repo, project_name)
    output_json = json.dumps(result, indent=2, ensure_ascii=False)

    if args.output:
        out_dir = os.path.dirname(os.path.abspath(args.output))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_json)
            f.write("\n")
    else:
        print(output_json)


if __name__ == "__main__":
    main()
