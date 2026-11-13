#!/usr/bin/env python3
"""SE-531 S1 — ficha de runtime de harness: esquema, validador (fail-closed) y lectores.

Uso:
  python3 scripts/harness_ficha.py check [DIR]   # DIR por defecto: contracts/runtime
Salida 0 = todas las fichas válidas; 1 = algún error (nombra ficha y campo);
2 = uso incorrecto o directorio ilegible.

Una ficha es un YAML con: `ficha` (id), `usa` (lista opcional de runtimes que
usa) y `runtime` (bloque con los campos de D1). `no_medido` es válido pero los
lectores (`effective`, `accept_exit`, ...) lo leen como la opción desconfiada.
`rc_deteccion` es un dato (literal o patrón acotado): este módulo nunca lo
ejecuta ni lo pasa a un shell. La lista de bloqueo de metacaracteres es una
defensa en profundidad, NO sustituye a pasar el valor entre comillas si un
invocador futuro lo usara en una orden. Un `patron` es un subconjunto lineal de
regex (literales, `.`, clases `[...]`, ancla `^`): sin grupos ni cuantificadores,
para que ningún dato pueda colgar al invocador (ReDoS). Los valores `si`/`no`
van entre comillas en YAML 1.1; se acepta también el booleano que PyYAML produce.
"""
import re
import sys
from pathlib import Path

import yaml

NM = "no_medido"
# campo -> (valores permitidos, lectura desconfiada de no_medido)
FIELDS = {
    "aislamiento": (("ninguno", "sandbox_de_ordenes", "proceso_confinado", NM), "ninguno"),
    "rc_en_error": (("fiable", "no_fiable", NM), "no_fiable"),
    "senal_cuota": (("codigo_de_salida", "campo_del_flujo", "ninguna", NM), "ninguna"),
    "informa_uso": (("si", "no", NM), "no"),
    "reanudacion": (("por_sesion", "no_soportada", NM), "no_soportada"),
    "limpieza": (("grupo_de_procesos", "ninguna", NM), "ninguna"),
    "flujo_llamadas": (("json", "ninguno", NM), "ninguno"),
}
ALLOWED_KEYS = set(FIELDS) | {"rc_deteccion", "fuente", "version_cli", "notas"}
DET_MAX_LEN = 200
DET_KINDS = ("literal", "patron")
SCAN_MAX = 64_000_000  # tope duro: por encima la regla es inaplicable (rechazo), nunca se trunca
TOP_KEYS = {"ficha", "usa", "runtime"}
# metacaracteres de shell/sustitución: se rechazan en rc_deteccion (AC-S1i)
SHELL_META = re.compile(r"[;$`'\"|&<>\n\r\\]")
# patrón acotado: solo literales, `.`, clases y ancla inicial; sin grupos ni cuantificadores
PATRON_PROHIBIDO = re.compile(r"[(){}*+?]")


def _err(ficha, campo, msg):
    return f"{ficha}: {campo}: {msg}"


def _check_deteccion(ficha, det):
    out = []
    if not isinstance(det, dict) or set(det) != {"tipo", "valor"}:
        return [_err(ficha, "rc_deteccion", "debe ser {tipo, valor}")]
    if det["tipo"] not in DET_KINDS:
        out.append(_err(ficha, "rc_deteccion.tipo", f"valor no permitido {det['tipo']!r}"))
    val = det["valor"]
    if not isinstance(val, str) or not val:
        return out + [_err(ficha, "rc_deteccion.valor", "texto no vacío obligatorio")]
    if len(val) > DET_MAX_LEN:
        out.append(_err(ficha, "rc_deteccion.valor", f"supera {DET_MAX_LEN} caracteres"))
    if SHELL_META.search(val):
        out.append(_err(ficha, "rc_deteccion.valor", "contiene metacaracteres de shell"))
    elif det["tipo"] == "patron":
        if PATRON_PROHIBIDO.search(val):
            return out + [_err(ficha, "rc_deteccion.valor", "patrón con grupos o cuantificadores no permitido (solo literales, '.', clases, '^')")]
        try:
            re.compile(val)
        except re.error as e:
            out.append(_err(ficha, "rc_deteccion.valor", f"patrón inválido: {e}"))
    return out


def _norm(v):
    """YAML 1.1 lee `si`/`no` sin comillas como booleano: se normaliza a texto."""
    if v is True:
        return "si"
    if v is False:
        return "no"
    return v


def validate_runtime(ficha, rt):
    """Errores (lista de str) de un bloque runtime. Vacía = válido."""
    if not isinstance(rt, dict):
        return [_err(ficha, "runtime", "bloque ausente o no es un mapa")]
    rt = {k: (_norm(v) if k in FIELDS else v) for k, v in rt.items()}
    errs = [_err(ficha, k, "campo desconocido") for k in rt if k not in ALLOWED_KEYS]
    measured = []
    for campo, (allowed, _) in FIELDS.items():
        if campo not in rt:
            errs.append(_err(ficha, campo, "campo obligatorio ausente"))
        elif rt[campo] not in allowed:
            errs.append(_err(ficha, campo, f"valor no permitido {rt[campo]!r}"))
        elif rt[campo] != NM:
            measured.append(campo)
    rc = rt.get("rc_en_error")
    if "rc_deteccion" in rt:
        if rc == "fiable":
            errs.append(_err(ficha, "rc_deteccion", "prohibido con rc_en_error: fiable"))
        errs += _check_deteccion(ficha, rt["rc_deteccion"])
        measured.append("rc_deteccion")
    elif rc == "no_fiable":
        errs.append(_err(ficha, "rc_deteccion", "obligatorio con rc_en_error: no_fiable"))
    for meta in ("fuente", "version_cli"):
        m = rt.get(meta, {})
        if not isinstance(m, dict):
            errs.append(_err(ficha, meta, "debe ser un mapa campo -> texto"))
            continue
        for k in m:
            if k not in set(FIELDS) | {"rc_deteccion"}:
                errs.append(_err(ficha, f"{meta}.{k}", "dato desconocido"))
        for campo in measured:
            v = m.get(campo)
            if not isinstance(v, str) or not v.strip():
                errs.append(_err(ficha, f"{meta}.{campo}", "obligatorio para un dato medido"))
    return errs


class _UniqueLoader(yaml.SafeLoader):
    """safe_load que rechaza claves duplicadas (la última ganaría en silencio)."""


def _no_dup_mapping(loader, node, deep=False):
    seen = set()
    for k, _ in node.value:
        key = loader.construct_object(k, deep=True)
        if key in seen:
            raise yaml.YAMLError(f"clave duplicada {key!r}")
        seen.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)


_UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_dup_mapping)


def load_fichas(directory):
    fichas, errs = {}, []
    files = sorted(Path(directory).glob("*.yaml"))
    for extra in sorted(Path(directory).glob("*.yml")):
        errs.append(f"{extra.name}: extensión .yml no admitida, usa .yaml")
    if not files:
        errs.append(f"{directory}: sin fichas (*.yaml)")
    for f in files:
        try:
            doc = yaml.load(f.read_text(encoding="utf-8"), Loader=_UniqueLoader)  # noqa: S506 (SafeLoader)
        except (yaml.YAMLError, OSError, UnicodeError) as e:
            errs.append(f"{f.name}: ilegible: {e}")
            continue
        if not isinstance(doc, dict) or not isinstance(doc.get("ficha"), str) or not doc["ficha"]:
            errs.append(f"{f.name}: ficha: id obligatorio")
            continue
        unknown = sorted(str(k) for k in doc if k not in TOP_KEYS)
        if unknown:
            errs.append(f"{f.name}: clave de primer nivel desconocida {unknown} (permitidas: {sorted(TOP_KEYS)})")
            continue
        if doc["ficha"] != f.stem:
            errs.append(f"{f.name}: ficha: el id {doc['ficha']!r} no coincide con el nombre del fichero")
            continue
        if doc["ficha"] in fichas:
            errs.append(f"{f.name}: ficha: id duplicado {doc['ficha']!r}")
            continue
        fichas[doc["ficha"]] = doc
    return fichas, errs


def validate_all(fichas):
    """(errores, nº de datos no_medido). Cobertura: todo runtime usado tiene bloque."""
    errs, nm = [], 0
    for fid, doc in fichas.items():
        errs += validate_runtime(fid, doc.get("runtime"))
        if isinstance(doc.get("runtime"), dict):
            nm += sum(1 for c in FIELDS if doc["runtime"].get(c) == NM)
        usa = doc.get("usa", [])
        if not isinstance(usa, list) or not all(isinstance(u, str) for u in usa):
            errs.append(_err(fid, "usa", "debe ser lista de ids de runtime"))
            continue
        for u in usa:
            if u not in fichas or not isinstance(fichas[u].get("runtime"), dict):
                errs.append(_err(fid, "usa", f"runtime {u!r} sin ficha con bloque runtime"))
    return errs, nm


# --- lectores: aplican D1 (no_medido = opción desconfiada) -------------------

def effective(rt, campo):
    v = _norm(rt.get(campo, NM))
    return FIELDS[campo][1] if v == NM or v not in FIELDS[campo][0] else v


def _scan(det, output):
    """True = fallo encontrado, False = limpio, None = la regla no se pudo aplicar."""
    if _check_deteccion("x", det) or not isinstance(output, str):
        return None
    if len(output) > SCAN_MAX:
        return None  # no se trunca (un error en el tramo omitido pasaría): se rechaza
    try:
        if det["tipo"] == "literal":
            return det["valor"] in output
        return re.search(det["valor"], output) is not None
    except re.error:
        return None


def detect_failure(det, output):
    """True si `output` cumple la regla. Dato puro: no ejecuta nada.
    Una regla inaplicable cuenta como no cumplida aquí; `accept_exit` la rechaza."""
    return _scan(det, output) is True


def accept_exit(rt, rc, postcondition_ok, output=""):
    """(aceptado, motivo). Fail-closed: un 0 solo se acepta con ficha `fiable`
    o con la postcondición del trabajo cumplida (True explícito) y sin que una
    regla de detección presente la contradiga ni deje de poder aplicarse."""
    if type(rc) is not int or rc != 0:
        return False, "rc distinto de 0 (o no entero)"
    if "rc_deteccion" in rt and effective(rt, "rc_en_error") == "fiable":
        return False, "ficha incoherente: rc_deteccion con rc_en_error fiable"
    if effective(rt, "rc_en_error") == "fiable":
        return True, "rc 0 con runtime fiable"
    if "rc_deteccion" in rt:  # presente pero None/vacía también se rechaza vía _scan
        found = _scan(rt["rc_deteccion"], output)
        if found is None:
            return False, "regla de detección inaplicable (regla inválida o salida no es texto)"
        if found:
            return False, "rc 0 pero la regla de detección encontró fallo"
    if postcondition_ok is True:
        return True, "rc 0 no fiable, postcondición cumplida"
    return False, "rc 0 no fiable sin postcondición cumplida"


def confined(rt):
    return effective(rt, "aislamiento") != "ninguno"


def quota_channel(rt):
    return effective(rt, "senal_cuota")


def reports_usage(rt):
    return effective(rt, "informa_uso") == "si"


def can_resume(rt):
    return effective(rt, "reanudacion") == "por_sesion"


def cleanup_guaranteed(rt):
    return effective(rt, "limpieza") == "grupo_de_procesos"


def watches_calls(rt):
    return effective(rt, "flujo_llamadas") == "json"


def main(argv):
    if len(argv) < 2 or argv[1] != "check" or len(argv) > 3:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    directory = Path(argv[2]) if len(argv) == 3 else Path(__file__).resolve().parent.parent / "contracts" / "runtime"
    if not directory.is_dir():
        print(f"{directory}: no es un directorio", file=sys.stderr)
        return 2
    fichas, load_errs = load_fichas(directory)
    errs, nm = validate_all(fichas)
    errs = load_errs + errs
    for e in errs:
        print(f"ERROR {e}")
    print(f"fichas={len(fichas)} errores={len(errs)} no_medido={nm}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
