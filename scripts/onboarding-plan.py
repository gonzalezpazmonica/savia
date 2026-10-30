#!/usr/bin/env python3
"""SE-484 — motor determinista del onboarding adaptativo.

El modelo interpreta la respuesta libre de la persona y propone ids de capacidades;
este script decide, a partir de docs/onboarding/capabilities.yaml, qué se pregunta,
qué se escribe y cuáles son los tres primeros pasos. Nada se escribe sin --confirm.

Subcomandos:
  validate   valida el catálogo contra su esquema y sus reglas semánticas
  refs       comprueba que todo lo que el catálogo configura existe en el repo
  present    presentación: frase corta de la fuente única (SE-483) + pregunta abierta
  questions  preguntas pendientes (--render askuser|text) para un input
  plan       plan completo (JSON) para un input, con diff si el perfil ya existe
  apply      aplica el plan: sin --confirm no escribe nada (simulación)

Input (JSON): {"name", "slug"?, "role_text", "proposed": [{"id", "reason", "hints"?}],
               "answers": {"<capacidad>": {"<pregunta>": "<opción>" | ["<opción>", ...]}},
               "skipped": ["<capacidad>.<pregunta>", ...]}
Una pregunta sin respuesta y sin saltar queda pendiente y el plan no se puede aplicar.
Códigos de salida: 0 ok · 1 validación · 2 uso o input mal formado · 3 fuente de identidad ·
4 destino no permitido · 5 plan no aplicable (aclaración, preguntas pendientes, respuestas
inválidas o perfil existente sin frontmatter).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
CATALOG = "docs/onboarding/capabilities.yaml"
SCHEMA = "docs/onboarding/capabilities.schema.json"
IDENTITY_SOURCE = ".claude/profiles/savia.md"
USERS_DIR = ".claude/profiles/users"
REQUIRED_CAPS = ("harness-orchestration", "research", "knowledge", "sdd-development", "project-management",
                 "teaching-learning", "vertical", "professional-domain", "accessibility", "tone")
FORBIDDEN_FIRST_STEPS = ("sprint-status",)
MAX_BUTTONS = 4
LEVELS = ("N1", "N2", "N3", "N4", "N4b")
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️]")


def fail(code: int, msg: str):
    print(msg, file=sys.stderr)
    sys.exit(code)


# ── Esquema (subconjunto de draft-07, sin dependencias externas) ─────────────
def _resolve(schema, root):
    while "$ref" in schema:
        node = root
        for part in schema["$ref"].lstrip("#/").split("/"):
            node = node[part]
        schema = node
    return schema


def schema_errors(value, schema, root, path="$"):
    schema = _resolve(schema, root)
    errs = []
    kind = schema.get("type")
    checks = {"object": dict, "array": list, "string": str, "boolean": bool}
    if kind == "integer" and (not isinstance(value, int) or isinstance(value, bool)):
        return [f"{path}: se esperaba integer"]
    if kind in checks and not isinstance(value, checks[kind]):
        return [f"{path}: se esperaba {kind}, hay {type(value).__name__}"]
    if "enum" in schema and value not in schema["enum"]:
        errs.append(f"{path}: {value!r} no está en {schema['enum']}")
    if isinstance(value, str):
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errs.append(f"{path}: {value!r} no cumple {schema['pattern']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errs.append(f"{path}: más de {schema['maxLength']} caracteres")
    if isinstance(value, dict):
        for req in schema.get("required", []):
            if req not in value:
                errs.append(f"{path}: falta '{req}'")
        props = schema.get("properties", {})
        for k, v in value.items():
            if k in props:
                errs += schema_errors(v, props[k], root, f"{path}.{k}")
            elif schema.get("additionalProperties") is False:
                errs.append(f"{path}: clave no permitida '{k}'")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errs.append(f"{path}: menos de {schema['minItems']} elementos")
        if "items" in schema:
            for i, item in enumerate(value):
                errs += schema_errors(item, schema["items"], root, f"{path}[{i}]")
    return errs


def load_catalog(root: Path, catalog: str | None):
    path = Path(catalog) if catalog else root / CATALOG
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        fail(1, f"ERROR catálogo ilegible: {exc}")
    return data


def _configures_blocks(cap):
    yield f"{cap['id']}", cap.get("configures", {})
    for ask in cap.get("asks", []):
        for opt in ask["options"]:
            yield f"{cap['id']}.{ask['id']}.{opt['id']}", opt.get("configures", {})


def semantic_errors(cat) -> list[str]:
    errs, ids = [], [c["id"] for c in cat["capabilities"]]
    errs += [f"capacidad duplicada: {i}" for i in sorted({i for i in ids if ids.count(i) > 1})]
    errs += [f"falta la capacidad mínima: {i}" for i in REQUIRED_CAPS if i not in ids]
    for cap in cat["capabilities"]:
        ask_ids = [a["id"] for a in cap["asks"]]
        errs += [f"{cap['id']}: pregunta duplicada {a}" for a in sorted({a for a in ask_ids if ask_ids.count(a) > 1})]
        for ask in cap["asks"]:
            where = f"{cap['id']}.{ask['id']}"
            opt_ids = [o["id"] for o in ask["options"]]
            if len(set(opt_ids)) != len(opt_ids):
                errs.append(f"{where}: opciones duplicadas")
            if ask["recommended"] not in opt_ids:
                errs.append(f"{where}: la recomendada '{ask['recommended']}' no es una opción")
            if len(opt_ids) > MAX_BUTTONS:
                n = sum(1 for o in ask["options"] if o.get("featured"))
                if not 1 <= n <= MAX_BUTTONS:
                    errs.append(f"{where}: con más de {MAX_BUTTONS} opciones hacen falta 1..{MAX_BUTTONS} 'featured' (hay {n})")
        for where, conf in _configures_blocks(cap):
            for fname, keys in conf.get("sets", {}).items():
                if not re.fullmatch(r"[a-z][a-z0-9-]*\.md", str(fname)):
                    errs.append(f"{where}: sets.{fname}: nombre de fichero de perfil no válido")
                if not isinstance(keys, dict) or not keys:
                    errs.append(f"{where}: sets.{fname} debe ser un mapa clave → valor")
                    continue
                errs += [f"{where}: sets.{fname}.{k}: clave no válida" for k in keys if not re.fullmatch(r"[a-z][a-z0-9_]*", str(k))]
    steps = list(cat["general_first_steps"])
    for cap in cat["capabilities"]:
        steps += cap.get("first_steps", [])
        steps += [s for a in cap["asks"] for o in a["options"] for s in o.get("first_steps", [])]
    errs += [f"primer paso prohibido (genérico): /{s['command']}" for s in steps if s["command"] in FORBIDDEN_FIRST_STEPS]
    return errs


def validate_catalog(root: Path, catalog: str | None, schema_path: str | None = None) -> list[str]:
    cat = load_catalog(root, catalog)
    # El esquema va con el motor (mismo repo que este script), no con el --root de destino.
    schema = json.loads((Path(schema_path) if schema_path else ROOT / SCHEMA).read_text(encoding="utf-8"))
    errs = schema_errors(cat, schema, schema)
    return errs or semantic_errors(cat)


# ── Referencias ──────────────────────────────────────────────────────────────
def frontmatter(text: str):
    """Devuelve (dict, líneas de cabecera, índice de cierre) o (None, ...) si no hay frontmatter."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, lines, -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            try:
                data = yaml.safe_load("\n".join(lines[1:i])) or {}
            except yaml.YAMLError:
                return None, lines, -1
            return (data, lines, i) if isinstance(data, dict) else (None, lines, -1)
    return None, lines, -1


def template_keys(root: Path, cat) -> dict[str, dict]:
    out = {}
    for f in sorted((root / cat["profile_template"]).glob("*.md")):
        data, _, _ = frontmatter(f.read_text(encoding="utf-8"))
        out[f.name] = data or {}
    return out


def reference_errors(root: Path, cat) -> list[str]:
    errs, tpl = [], template_keys(root, cat)
    for rel in (cat["profile_template"], cat["vertical_detection"]):
        if not (root / rel).exists():
            errs.append(f"no existe: {rel}")
    if not (root / ".claude/skills" / cat["interview_skill"] / "SKILL.md").is_file():
        errs.append(f"no existe la skill de entrevista: {cat['interview_skill']}")
    steps = [("general", s) for s in cat["general_first_steps"]]
    for cap in cat["capabilities"]:
        steps += [(cap["id"], s) for s in cap.get("first_steps", [])]
        steps += [(cap["id"], s) for a in cap["asks"] for o in a["options"] for s in o.get("first_steps", [])]
        for where, conf in _configures_blocks(cap):
            for fname, keys in conf.get("sets", {}).items():
                if fname not in tpl:
                    errs.append(f"{where}: el fichero de perfil {fname} no está en la plantilla")
                    continue
                errs += [f"{where}: la clave {fname}:{k} no está en la plantilla" for k in keys if k not in tpl[fname]]
            errs += [f"{where}: no existe el comando /{c}" for c in conf.get("commands", [])
                     if not (root / ".claude/commands" / f"{c}.md").is_file()]
            errs += [f"{where}: no existe la skill {s}" for s in conf.get("skills", [])
                     if not (root / ".claude/skills" / s / "SKILL.md").is_file()]
            errs += [f"{where}: no existe el pack {p}" for p in conf.get("packs", []) if not (root / p).exists()]
    errs += [f"{w}: no existe el comando del primer paso /{s['command']}" for w, s in steps
             if not (root / ".claude/commands" / f"{s['command']}.md").is_file()]
    return errs


# ── Presentación (frase de la fuente única SE-483) ───────────────────────────
class IdentityError(Exception):
    """La fuente única de identidad no da una frase utilizable (código 3)."""


def identity_short(source: Path) -> str:
    try:
        text = source.read_text(encoding="utf-8")
    except OSError as exc:
        raise IdentityError(f"ERROR fuente de identidad ilegible: {exc}") from exc
    m = re.search(r"<!--\s*identity:short\s*-->(.*?)(?:<!--|\n\s*\n|\Z)", text, re.S)
    phrase = " ".join(l.strip().lstrip(">").strip() for l in (m.group(1) if m else "").strip().splitlines()).strip()
    if not phrase:
        raise IdentityError(f"ERROR {source}: sin marcador <!-- identity:short --> con texto (fuente única de SE-483)")
    if EMOJI.search(phrase):
        raise IdentityError("ERROR la frase de identidad contiene emojis")
    return phrase


# ── Plan ─────────────────────────────────────────────────────────────────────
def input_errors(data) -> list[str]:
    """Forma del input que produce el modelo; cualquier desviación es un error de uso (código 2)."""
    if not isinstance(data, dict):
        return ["el input debe ser un objeto JSON"]
    errs = [f"'{k}' debe ser texto" for k in ("name", "slug", "role_text") if k in data and not isinstance(data[k], str)]
    props = data.get("proposed", [])
    if not isinstance(props, list):
        errs.append("'proposed' debe ser una lista")
    else:
        for i, p in enumerate(props):
            if not isinstance(p, dict) or not isinstance(p.get("id"), str):
                errs.append(f"proposed[{i}] debe ser un objeto con 'id' de texto")
            elif not isinstance(p.get("hints", {}), dict) or not all(
                    isinstance(v, list) and all(isinstance(x, str) for x in v) for v in p.get("hints", {}).values()):
                errs.append(f"proposed[{i}].hints debe ser un mapa pregunta → lista de opciones")
    answers = data.get("answers", {})
    if not isinstance(answers, dict):
        errs.append("'answers' debe ser un objeto")
    else:
        for cid, per in answers.items():
            if not isinstance(per, dict):
                errs.append(f"answers.{cid} debe ser un objeto pregunta → respuesta")
                continue
            for aid, v in per.items():
                if not (isinstance(v, str) or (isinstance(v, list) and all(isinstance(x, str) for x in v))):
                    errs.append(f"answers.{cid}.{aid} debe ser texto o lista de textos")
    skipped = data.get("skipped", [])
    if not isinstance(skipped, list) or not all(isinstance(x, str) for x in skipped):
        errs.append("'skipped' debe ser una lista de 'capacidad.pregunta'")
    return errs


def slugify(text: str) -> str:
    s = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def _match_option(ask, raw):
    key = str(raw).strip().lower().removesuffix(" (recomendada)")
    for o in ask["options"]:
        if key in (o["id"], o["label"].lower()):
            return o
    return None


def _merge_set(writes, fname, key, value, origin, errors):
    cur = writes.setdefault(fname, {})
    if key not in cur:
        cur[key] = list(value) if isinstance(value, list) else value
    elif isinstance(cur[key], list) and isinstance(value, list):
        cur[key] += [v for v in value if v not in cur[key]]
    elif cur[key] != value:
        errors.append(f"{origin}: {fname}:{key} recibe dos valores ({cur[key]!r} y {value!r})")


def build_plan(cat, data: dict, root: Path, profile_dir: Path | None = None) -> dict:
    caps = {c["id"]: c for c in cat["capabilities"]}
    accepted, rejected, seen = [], [], set()
    for prop in data.get("proposed", []):
        cid = prop.get("id") if isinstance(prop, dict) else None
        if cid not in caps:
            rejected.append({"id": cid, "reason": "no existe en el catálogo; no se inventa"})
        elif cid not in seen:
            seen.add(cid)
            accepted.append({"id": cid, "title": caps[cid]["title"], "reason": prop.get("reason", ""),
                             "source": "proposed", "hints": prop.get("hints", {})})
    real = [a for a in accepted if not caps[a["id"]].get("always")]
    for c in cat["capabilities"]:
        if c.get("always") and c["id"] not in seen:
            accepted.append({"id": c["id"], "title": c["title"], "reason": "siempre", "source": "always", "hints": {}})
    name = str(data.get("name", "")).strip()
    slug = data.get("slug") or slugify(name)
    plan = {"status": "ready", "profile": {"name": name, "slug": slug, "role": str(data.get("role_text", "")).strip()},
            "capabilities": accepted, "rejected": rejected, "pending": [], "skipped": [], "invalid_answers": [],
            "commands": [], "skills": [], "packs": [], "requires": [], "first_steps": [], "notes": [],
            "sensitivity": {"level": "N1", "special_categories": []}, "vertical": {"status": "none", "message": cat["no_vertical_message"]}}
    if not real:
        plan["status"] = "needs_clarification"
        plan["clarify"] = {"question": cat["clarify_question"], "interview_skill": cat["interview_skill"],
                           "options": [c["id"] for c in cat["capabilities"] if not c.get("always")]}
    if not name or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", slug or "") or slug == "template":
        plan["invalid_answers"].append("nombre o slug vacío o no válido")
    sets, errors = {}, []
    _merge_set(sets, "identity.md", "name", name, "identidad", errors)
    _merge_set(sets, "identity.md", "slug", slug, "identidad", errors)
    if plan["profile"]["role"]:
        _merge_set(sets, "identity.md", "role", plan["profile"]["role"], "identidad", errors)
    _merge_set(sets, "preferences.md", "onboarding_capabilities", [a["id"] for a in accepted], "onboarding", errors)
    answers, skipped, per_cap_steps = data.get("answers", {}), set(data.get("skipped", [])), []
    known = {f"{c['id']}.{a['id']}" for c in cat["capabilities"] for a in c["asks"]}
    plan["invalid_answers"] += [f"skipped: pregunta desconocida {k!r}" for k in sorted(skipped - known)]
    for cid, per in answers.items():
        plan["invalid_answers"] += [f"answers: pregunta desconocida '{cid}.{aid}'" for aid in per if f"{cid}.{aid}" not in known]
    for acc in accepted:
        cap = caps[acc["id"]]
        blocks, steps = [("capacidad", cap.get("configures", {}))], []
        for ask in cap["asks"]:
            raw = answers.get(cap["id"], {}).get(ask["id"])
            if raw is None:
                key = "skipped" if f"{cap['id']}.{ask['id']}" in skipped else "pending"
                plan[key].append({"capability": cap["id"], "ask": ask["id"]})
                continue
            raws = raw if isinstance(raw, list) else [raw]
            if not raws:
                plan["invalid_answers"].append(f"{cap['id']}.{ask['id']}: elige al menos una opción o sáltala")
                continue
            if not ask["multi"] and len(raws) != 1:
                plan["invalid_answers"].append(f"{cap['id']}.{ask['id']}: admite una sola opción")
                continue
            for r in raws:
                opt = _match_option(ask, r)
                if opt is None:
                    plan["invalid_answers"].append(f"{cap['id']}.{ask['id']}: opción desconocida {r!r}")
                    continue
                blocks.append((f"{cap['id']}.{ask['id']}.{opt['id']}", opt.get("configures", {})))
                steps += opt.get("first_steps", [])
                entry = {"capability": cap["id"], "why": opt.get("sensitive", "")}
                if opt.get("sensitive") and entry not in plan["sensitivity"]["special_categories"]:
                    plan["sensitivity"]["special_categories"].append(entry)
                if cap["id"] == "vertical" and opt["id"] != "none":
                    plan["vertical"] = {"status": "selected", "id": opt["id"]}
        plan["sensitivity"]["level"] = max(plan["sensitivity"]["level"], cap["sensitivity"]["level"], key=LEVELS.index)
        if cap["sensitivity"]["special_category"]:  # cada capacidad se procesa una vez: sin duplicados
            plan["sensitivity"]["special_categories"].append({"capability": cap["id"], "why": cap["sensitivity"].get("why", "")})
        for origin, conf in blocks:
            for fname, keys in conf.get("sets", {}).items():
                for k, v in keys.items():
                    _merge_set(sets, fname, k, v, origin, errors)
            for field in ("commands", "skills", "packs"):
                plan[field] += [x for x in conf.get(field, []) if x not in plan[field]]
            plan["requires"] += [r for r in conf.get("requires", []) if r not in plan["requires"]]
        per_cap_steps.append(steps + cap.get("first_steps", []))
    if any(a["id"] == "vertical" for a in accepted) and plan["vertical"]["status"] == "none" \
            and {"capability": "vertical", "ask": "which"} in plan["pending"]:
        plan["vertical"] = {"status": "pending"}
    plan["invalid_answers"] += errors
    plan["first_steps"] = pick_first_steps(per_cap_steps, cat["general_first_steps"])
    plan["writes"], plan["unchanged"] = diff_writes(sets, root, cat, profile_dir)
    if plan["invalid_answers"] and plan["status"] == "ready":
        plan["status"] = "invalid_answers"
    elif plan["pending"] and plan["status"] == "ready":
        plan["status"] = "pending_questions"
    return plan


def pick_first_steps(per_cap, general, n=3):
    chosen, cmds = [], set()
    queues = [list(q) for q in per_cap]
    while len(chosen) < n and any(queues):
        for q in queues:
            while q and q[0]["command"] in cmds:
                q.pop(0)
            if q and len(chosen) < n:
                s = q.pop(0)
                chosen.append(s)
                cmds.add(s["command"])
    for s in general:
        if len(chosen) < n and s["command"] not in cmds:
            chosen.append(s)
            cmds.add(s["command"])
    return chosen


def diff_writes(sets, root: Path, cat, profile_dir: Path | None):
    tpl, writes, unchanged = template_keys(root, cat), [], 0
    for fname in sorted(sets):
        current = None
        if profile_dir and (profile_dir / fname).is_file():
            current, _, _ = frontmatter((profile_dir / fname).read_text(encoding="utf-8"))
        for key, value in sets[fname].items():
            default = tpl.get(fname, {}).get(key)
            if current is None:
                action = "create"
            else:
                # Un valor escrito en el fichero es de la persona aunque coincida con el de la plantilla:
                # solo una clave ausente o vacía se considera hueco que se rellena sin pedir permiso.
                have = current.get(key, default)
                if have == value:
                    unchanged += 1
                    continue
                action = "add" if key not in current or current[key] in (None, "", []) else "overwrite"
            entry = {"file": fname, "key": key, "value": value, "action": action}
            if action == "overwrite":
                entry["before"] = current.get(key)
            writes.append(entry)
    return writes, unchanged


# ── Aplicación ───────────────────────────────────────────────────────────────
def _yaml_scalar(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(value, ensure_ascii=False)


def _is_continuation(lines, i, end) -> bool:
    """Línea del valor en bloque de la clave anterior: con sangría o `- `; una línea en blanco solo si
    lo que sigue también es continuación. Una clave o un comentario de primer nivel cierran el bloque."""
    line = lines[i]
    if line.startswith((" ", "\t", "- ")) or line == "-":
        return True
    if line.strip() == "":
        nxt = next((j for j in range(i + 1, end) if lines[j].strip()), None)
        return nxt is not None and lines[nxt].startswith((" ", "\t", "- "))
    return False


def render_keys(path: Path, template: Path, items: list[dict]) -> str:
    """Texto nuevo del fichero con las claves cambiadas. Un valor en bloque (líneas con sangría o
    `- ` bajo la clave) se sustituye entero; el resultado tiene que seguir siendo YAML válido."""
    text = path.read_text(encoding="utf-8") if path.is_file() else template.read_text(encoding="utf-8")
    data, lines, end = frontmatter(text)
    if data is None:
        raise ValueError(f"{path.name}: sin frontmatter; no se toca")
    for it in items:
        new = f"{it['key']}: {_yaml_scalar(it['value'])}"
        idx = next((i for i in range(1, end) if re.match(rf"^{re.escape(it['key'])}\s*:", lines[i])), None)
        if idx is None:
            lines.insert(end, new)
            end += 1
            continue
        stop = idx + 1
        while stop < end and _is_continuation(lines, stop, end):
            stop += 1
        lines[idx:stop] = [new]
        end -= stop - idx - 1
    out = "\n".join(lines)
    if frontmatter(out)[0] is None:
        raise ValueError(f"{path.name}: el resultado no sería YAML válido; no se toca")
    return out


def check_destination(root: Path, profile_dir: Path):
    users = (root / USERS_DIR).resolve()
    target = profile_dir.resolve()
    if target.parent != users or target.name == "template":
        fail(4, f"ERROR destino no permitido: el perfil va en {USERS_DIR}/<slug>/")
    probe = subprocess.run(["git", "-C", str(root), "check-ignore", "-q", str(target / "identity.md")],
                           capture_output=True, check=False)
    if probe.returncode != 0:
        fail(4, f"ERROR destino no ignorado por git: {target} (los perfiles nunca se versionan)")


def check_files(root: Path, profile_dir: Path, files: list[str]):
    """Antes de escribir nada: cada fichero queda dentro del perfil, no es un enlace, git lo ignora y,
    si ya existe, tiene frontmatter. Un fallo aborta sin escrituras parciales."""
    target = profile_dir.resolve()
    for fname in files:
        path = profile_dir / fname
        if path.is_symlink() or path.resolve().parent != target:
            fail(4, f"ERROR destino no permitido: {fname} es un enlace o sale del directorio del perfil")
        probe = subprocess.run(["git", "-C", str(root), "check-ignore", "-q", str(target / fname)],
                               capture_output=True, check=False)
        if probe.returncode != 0:
            fail(4, f"ERROR destino no ignorado por git: {target / fname}")
        if path.is_file() and frontmatter(path.read_text(encoding="utf-8"))[0] is None:
            fail(5, f"ERROR {fname} existe sin frontmatter; no se toca")


def check_input_location(root: Path, input_path: str):
    """El input lleva datos personales: dentro del repo solo se acepta si git lo ignora."""
    if input_path == "-":
        return
    resolved = Path(input_path).resolve()
    if root.resolve() not in resolved.parents:
        return
    probe = subprocess.run(["git", "-C", str(root), "check-ignore", "-q", str(resolved)], capture_output=True, check=False)
    if probe.returncode != 0:
        fail(4, f"ERROR el input está en una ruta versionada: {input_path} (guárdalo en el directorio del perfil)")


def run_checks(requires):
    out = []
    for r in requires:
        kind, value = r["check"]["type"], r["check"]["value"]
        ok = shutil.which(value) is not None if kind == "command" else Path(value).expanduser().exists()
        out.append({"id": r["id"], "ok": ok, "description": r["description"]})
    return out


def apply(cat, data, root: Path, profile_dir: Path, confirm: bool, overwrite: set[str]):
    check_destination(root, profile_dir)
    plan = build_plan(cat, data, root, profile_dir)
    if plan["status"] != "ready":
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        fail(5, f"ERROR plan no aplicable: {plan['status']}")
    if plan["profile"]["slug"] != profile_dir.name:
        fail(4, f"ERROR el slug del plan ({plan['profile']['slug']}) no coincide con el directorio ({profile_dir.name})")
    plan["applied"], plan["diagnostics"] = False, run_checks(plan["requires"])
    todo = [w for w in plan["writes"] if w["action"] != "overwrite" or f"{w['file']}:{w['key']}" in overwrite]
    plan["skipped_overwrites"] = [f"{w['file']}:{w['key']}" for w in plan["writes"] if w not in todo]
    for k in plan["skipped_overwrites"]:
        print(f"AVISO no se sobrescribe {k} sin --overwrite {k}", file=sys.stderr)
    files = sorted({w["file"] for w in todo})
    check_files(root, profile_dir, files)
    if confirm:
        # Todo el contenido se calcula antes de tocar el disco; luego cada fichero se sustituye de forma
        # atómica (temporal + os.replace) para que un fallo no deje ficheros a medio escribir.
        tpl_dir = root / cat["profile_template"]
        try:
            rendered = {f: render_keys(profile_dir / f, tpl_dir / f, [w for w in todo if w["file"] == f]) for f in files}
        except ValueError as exc:
            fail(5, f"ERROR {exc}")
        profile_dir.mkdir(parents=False, exist_ok=True)
        for fname, text in rendered.items():
            # mkstemp crea con O_EXCL un nombre nuevo (no sigue enlaces) y os.replace sustituye la entrada
            # del directorio, no el destino de un enlace.
            fd, tmp = tempfile.mkstemp(prefix=f".{fname}.", suffix=".tmp", dir=profile_dir)
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(text)
            os.replace(tmp, profile_dir / fname)
        plan["applied"], plan["written"] = True, [f"{w['file']}:{w['key']}" for w in todo]
    return plan


# ── Preguntas ────────────────────────────────────────────────────────────────
def questions(cat, plan) -> list[dict]:
    caps = {c["id"]: c for c in cat["capabilities"]}
    if plan["status"] == "needs_clarification":
        opts = [caps[i] for i in plan["clarify"]["options"]]
        return [{"capability": None, "ask": "clarify", "header": "Empezar", "question": plan["clarify"]["question"],
                 "multiSelect": True, "options": [{"id": c["id"], "label": c["title"], "description": c["description"],
                                                   "featured": i < MAX_BUTTONS} for i, c in enumerate(opts)]}]
    hints = {a["id"]: a.get("hints", {}) for a in plan["capabilities"]}
    out = []
    for p in plan["pending"]:
        ask = next(a for a in caps[p["capability"]]["asks"] if a["id"] == p["ask"])
        hinted = [h for h in hints.get(p["capability"], {}).get(ask["id"], []) if _match_option(ask, h)]
        order = sorted(ask["options"], key=lambda o: (o["id"] != ask["recommended"], o["id"] not in hinted))
        featured = [o["id"] for o in order if len(ask["options"]) <= MAX_BUTTONS or o.get("featured") or o["id"] in hinted][:MAX_BUTTONS]
        out.append({"capability": p["capability"], "ask": ask["id"], "header": ask["header"], "question": ask["question"],
                    "multiSelect": ask["multi"], "options": [
                        {"id": o["id"], "label": o["label"] + (" (recomendada)" if o["id"] == ask["recommended"] else ""),
                         "description": o["description"], "featured": o["id"] in featured} for o in order]})
    return out


def render(qs, mode: str) -> str:
    if mode == "askuser":
        return json.dumps({"questions": [{**{k: q[k] for k in ("capability", "ask", "header", "question", "multiSelect")},
                                          "options": [{"label": o["label"], "description": o["description"]}
                                                      for o in q["options"] if o["featured"]]} for q in qs]},
                          ensure_ascii=False, indent=2)
    lines = []
    for i, q in enumerate(qs, 1):
        lines.append(f"{i}. {q['question']}" + (" (puedes elegir varias)" if q["multiSelect"] else ""))
        lines += [f"   {chr(97 + j)}) {o['label']}: {o['description']}" for j, o in enumerate(q["options"])]
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cmd", choices=["validate", "refs", "present", "questions", "plan", "apply"])
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--catalog")
    ap.add_argument("--schema")
    ap.add_argument("--source", help="fuente de identidad (por defecto .claude/profiles/savia.md)")
    ap.add_argument("--fallback", action="store_true",
                    help="present: sin marcador en la fuente, «Soy Savia.» y aviso por stderr en vez de fallar")
    ap.add_argument("--input", help="fichero JSON con la interpretación y las respuestas ('-' = stdin)")
    ap.add_argument("--profile-dir")
    ap.add_argument("--render", choices=["askuser", "text"], default="text")
    ap.add_argument("--confirm", action="store_true", help="escribir de verdad (sin esto: simulación)")
    ap.add_argument("--overwrite", action="append", default=[], metavar="FICHERO:CLAVE")
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    if args.cmd == "validate":
        errs = validate_catalog(root, args.catalog, args.schema)
        print("\n".join(errs) if errs else "OK catálogo válido")
        return 1 if errs else 0
    errs = validate_catalog(root, args.catalog, args.schema)
    if errs:
        fail(1, "ERROR catálogo no válido; ejecuta validate:\n" + "\n".join(errs[:10]))
    cat = load_catalog(root, args.catalog)
    if args.cmd == "refs":
        errs = reference_errors(root, cat)
        print("\n".join(errs) if errs else "OK todas las referencias existen")
        return 1 if errs else 0
    if args.cmd == "present":
        source = Path(args.source) if args.source else root / IDENTITY_SOURCE
        try:
            phrase = identity_short(source)
        except IdentityError as exc:
            if not args.fallback:
                fail(3, str(exc))
            print(f"AVISO {exc}; presentación mínima", file=sys.stderr)
            phrase = "Soy Savia."
        print(phrase + "\n\n" + cat["open_question"])
        return 0
    if not args.input:
        fail(2, "ERROR falta --input")
    if args.cmd == "apply":
        check_input_location(root, args.input)
    try:
        data = json.loads(sys.stdin.read() if args.input == "-" else Path(args.input).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        fail(2, f"ERROR input ilegible: {exc}")
    errs = input_errors(data)
    if errs:
        fail(2, "ERROR input mal formado:\n" + "\n".join(errs))
    profile_dir = Path(args.profile_dir) if args.profile_dir else None
    if args.cmd == "apply":
        if profile_dir is None:
            fail(2, "ERROR apply necesita --profile-dir")
        plan = apply(cat, data, root, profile_dir, args.confirm, set(args.overwrite))
    else:
        plan = build_plan(cat, data, root, profile_dir)
    if args.cmd == "questions":
        print(render(questions(cat, plan), args.render))
    else:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
