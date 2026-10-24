"""Stdlib validator for the JSON Schema subset used by schemas/installer/ (CI has no jsonschema)."""
from __future__ import annotations

import json
import re

_TYPES = {"object": dict, "array": list, "string": str, "boolean": bool, "null": type(None)}
_DATETIME = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$")


SUPPORTED = {"$defs", "$id", "$ref", "$schema", "additionalProperties", "const", "default", "description", "enum",
             "format", "items", "minItems", "minLength", "minimum", "pattern", "properties", "required", "title",
             "type", "uniqueItems"}


def _canon(x):
    return json.dumps(x, sort_keys=True)


def check_schema(node, path="#") -> list:
    """Unsupported keywords anywhere in the schema, including unreferenced $defs and absent properties."""
    if not isinstance(node, dict):
        return []
    errs = [f"{path}: unsupported schema keyword {k!r}" for k in sorted(set(node) - SUPPORTED)]
    for key in ("properties", "$defs"):
        for k, v in node.get(key, {}).items():
            errs += check_schema(v, f"{path}/{key}/{k}")
    for key in ("items", "additionalProperties"):
        errs += check_schema(node.get(key), f"{path}/{key}")
    return errs


def _same(a, b):
    """Equality that does not conflate True with 1 or False with 0."""
    return type(a) is type(b) and a == b


def _is(v, t):
    if t == "integer":
        return isinstance(v, int) and not isinstance(v, bool)
    if t not in _TYPES:
        raise ValueError(f"unsupported schema type {t!r}")
    return isinstance(v, _TYPES[t]) and not (t != "boolean" and isinstance(v, bool))


def validate(doc, schema, root=None, path="") -> list:
    errs = []
    if root is None:
        root = schema
        errs = check_schema(schema)
    if "$ref" in schema:
        node = root
        for part in schema["$ref"].lstrip("#/").split("/"):
            node = node[part]
        return errs + validate(doc, node, root, path)
    if "const" in schema and not _same(doc, schema["const"]):
        errs.append(f"{path}: expected {schema['const']!r}")
    if "enum" in schema and not any(_same(doc, e) for e in schema["enum"]):
        errs.append(f"{path}: {doc!r} not in {schema['enum']}")
    if "type" in schema:
        ts = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_is(doc, t) for t in ts):
            return errs + [f"{path}: expected {'|'.join(ts)}"]
    if isinstance(doc, str):
        if len(doc) < schema.get("minLength", 0):
            errs.append(f"{path}: too short")
        if "pattern" in schema and not re.search(schema["pattern"], doc):
            errs.append(f"{path}: {doc!r} does not match {schema['pattern']}")
        if schema.get("format") == "date-time" and not _DATETIME.match(doc):
            errs.append(f"{path}: not a date-time")
    if isinstance(doc, int) and not isinstance(doc, bool) and doc < schema.get("minimum", doc):
        errs.append(f"{path}: below minimum")
    if isinstance(doc, list):
        if len(doc) < schema.get("minItems", 0):
            errs.append(f"{path}: too few items")
        if schema.get("uniqueItems") and len({_canon(x) for x in doc}) != len(doc):
            errs.append(f"{path}: duplicate items")
        for i, x in enumerate(doc):
            if "items" in schema:
                errs += validate(x, schema["items"], root, f"{path}/{i}")
    if isinstance(doc, dict):
        props = schema.get("properties", {})
        errs += [f"{path}/{r}: required" for r in schema.get("required", []) if r not in doc]
        for k, v in doc.items():
            if k in props:
                errs += validate(v, props[k], root, f"{path}/{k}")
            elif schema.get("additionalProperties") is False:
                errs.append(f"{path}/{k}: unexpected property")
            elif isinstance(schema.get("additionalProperties"), dict):
                errs += validate(v, schema["additionalProperties"], root, f"{path}/{k}")
    return sorted(errs)
