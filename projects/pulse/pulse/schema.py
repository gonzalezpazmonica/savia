"""Validador mínimo de un subconjunto de JSON Schema, sin dependencias.

Los esquemas de `schemas/` son la única fuente de verdad del contrato: los lee
este validador y puede leerlos Soul. Fail-closed: una palabra clave que el
validador no soporta lanza `SchemaNoSoportado`; nunca se ignora en silencio.
"""
import json
import os
import re

SCHEMAS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "schemas")

_ANNOTATIONS = {"title", "description"}
_SUPPORTED = _ANNOTATIONS | {
    "type", "required", "properties", "enum", "const", "pattern", "minLength",
    "maxLength", "minimum", "maximum", "items", "maxItems", "allOf", "if", "then",
}


class SchemaNoSoportado(Exception):
    pass


def load_schema(name):
    with open(os.path.join(SCHEMAS_DIR, name + ".schema.json"), encoding="utf-8") as fh:
        return json.load(fh)


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
    if tname == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    raise SchemaNoSoportado("tipo " + repr(tname))


def validate(value, schema, path="$"):
    """Devuelve la lista de errores (vacía = válido)."""
    unknown = set(schema) - _SUPPORTED
    if unknown:
        raise SchemaNoSoportado("palabras clave no soportadas: " + ", ".join(sorted(unknown)))
    errors = []
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
