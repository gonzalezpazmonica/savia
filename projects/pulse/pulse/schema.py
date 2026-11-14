"""Validador mínimo de un subconjunto de JSON Schema, sin dependencias.

Los esquemas de `schemas/` son la única fuente de verdad del contrato: los lee
este validador y puede leerlos Soul. Fail-closed: una palabra clave que el
validador no soporta lanza `SchemaNoSoportado`; nunca se ignora en silencio.
"""
import datetime as dt
import json
import math
import os
import re

SCHEMAS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "schemas")

_ANNOTATIONS = {"title", "description"}
_SUPPORTED = _ANNOTATIONS | {
    "type", "required", "properties", "enum", "const", "pattern", "minLength",
    "maxLength", "minimum", "maximum", "items", "maxItems", "allOf", "if", "then", "format",
}
_FORMATS = {"date-time": "%Y-%m-%dT%H:%M:%SZ"}  # UTC con segundos: la única forma del contrato


class SchemaNoSoportado(Exception):
    pass


def load_schema(name):
    with open(os.path.join(SCHEMAS_DIR, name + ".schema.json"), encoding="utf-8") as fh:
        sch = json.load(fh)
    check_supported(sch)  # fail-closed al cargar, no solo en las ramas que visite un documento
    return sch


_TYPES = {"object", "array", "string", "boolean", "integer", "number"}


def check_supported(schema, path="$"):
    """Recorre TODO el esquema (también `then`, `properties` e `items` anidados) y lanza
    `SchemaNoSoportado` ante una palabra clave, tipo o formato que el validador no soporta.
    `validate` solo lo descubre en las ramas que un documento concreto visita."""
    if not isinstance(schema, dict):
        raise SchemaNoSoportado(path + ": un esquema debe ser un objeto")
    unknown = set(schema) - _SUPPORTED
    if unknown:
        raise SchemaNoSoportado(path + ": palabras clave no soportadas: " + ", ".join(sorted(unknown)))
    if "type" in schema and schema["type"] not in _TYPES:
        raise SchemaNoSoportado(path + ": tipo " + repr(schema["type"]))
    if "format" in schema and schema["format"] not in _FORMATS:
        raise SchemaNoSoportado(path + ": formato " + repr(schema["format"]))
    for key, sub in schema.get("properties", {}).items():
        check_supported(sub, path + ".properties." + key)
    if "items" in schema:
        check_supported(schema["items"], path + ".items")
    for i, sub in enumerate(schema.get("allOf", [])):
        check_supported(sub, "%s.allOf[%d]" % (path, i))
    for key in ("if", "then"):
        if key in schema:
            check_supported(schema[key], path + "." + key)


def _type_ok(value, tname):
    if tname == "object":
        return isinstance(value, dict)
    if tname == "array":
        return isinstance(value, list)
    if tname == "string":
        return isinstance(value, str)
    if tname == "boolean":
        return isinstance(value, bool)
    if tname == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if tname == "number":  # NaN e infinito no son números del contrato
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
    raise SchemaNoSoportado("tipo " + repr(tname))


def validate(value, schema, path="$"):
    """Devuelve la lista de errores (vacía = válido)."""
    unknown = set(schema) - _SUPPORTED
    if unknown:
        raise SchemaNoSoportado("palabras clave no soportadas: " + ", ".join(sorted(unknown)))
    errors = []
    if "format" in schema and schema["format"] not in _FORMATS:
        raise SchemaNoSoportado("formato " + repr(schema["format"]))
    if "type" in schema and not _type_ok(value, schema["type"]):
        return [path + ": se esperaba " + schema["type"]]
    if "const" in schema and (value != schema["const"] or type(value) is not type(schema["const"])):
        errors.append(path + ": debe valer " + json.dumps(schema["const"]))
    if "enum" in schema and not any(value == e and type(value) is type(e) for e in schema["enum"]):
        errors.append(path + ": fuera del conjunto cerrado " + json.dumps(schema["enum"]))
    if isinstance(value, str):
        if "pattern" in schema and re.fullmatch(schema["pattern"], value) is None:
            errors.append(path + ": no cumple el patrón")
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(path + ": demasiado corto")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(path + ": demasiado largo")
        if "format" in schema:
            try:  # la forma la mira el patrón; aquí, que la fecha exista (no 2026-02-30)
                dt.datetime.strptime(value, _FORMATS[schema["format"]])
            except ValueError:
                errors.append(path + ": fecha imposible")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(path + ": por debajo del mínimo")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(path + ": por encima del máximo")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(path + ": falta " + key)
        for key, sub in schema.get("properties", {}).items():
            if key in value:
                errors.extend(validate(value[key], sub, path + "." + key))
    if isinstance(value, list):
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(path + ": demasiados elementos")
        if "items" in schema:
            for i, item in enumerate(value):
                errors.extend(validate(item, schema["items"], "%s[%d]" % (path, i)))
    for sub in schema.get("allOf", []):
        if "if" in sub:
            if not validate(value, sub["if"], path):
                errors.extend(validate(value, sub.get("then", {}), path))
        else:
            errors.extend(validate(value, sub, path))
    return errors
