#!/usr/bin/env python3
"""memory-store-write.py — escritura íntegra del almacén JSONL de memoria.

Lo invoca memory-save.sh. Reúne en una sola sección crítica, bajo un cerrojo
exclusivo, lo que antes eran pasos sueltos de shell sin cerrojo:

  save         serializa la entrada con json.dumps (nunca por concatenación),
               aplica upsert por topic_key, deduplica sin borrar nada antes de
               decidir, marca la entrada sustituida (supersedes_key), escribe de
               forma atómica (temporal en el mismo directorio + fsync + rename) y
               relee el almacén para comprobar que la entrada quedó recuperable.
  consolidate  separa las entradas untrusted/system (o sin origin) del almacén
               hacia un fichero de cuarentena en lugar de borrarlas.

Contrato de salida: código 0 solo si el dato quedó íntegro y recuperable; ante
cualquier duda, código != 0, mensaje en stderr y el almacén intacto.
"""
import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import sys
import tempfile

MAX_CONTENT_CHARS = 2000
DEDUP_WINDOW_S = 15 * 60


class StoreError(Exception):
    pass


def _strict(value, name):
    """Texto utf-8 válido o error: no se escribe nada a medias."""
    if value is None:
        return ""
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        raise StoreError(f"{name} no es utf-8 válido; no se guarda nada")
    return value


@contextlib.contextmanager
def locked(store):
    os.makedirs(os.path.dirname(os.path.abspath(store)), exist_ok=True)
    fd = os.open(store + ".lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)  # cerrar libera el cerrojo


def read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, "rb") as fh:
        raw = fh.read()
    # Se conservan tal cual, también las líneas que no se pueden parsear.
    return [ln for ln in raw.decode("utf-8", errors="surrogateescape").split("\n") if ln != ""]


def parse(line):
    try:
        obj = json.loads(line)
    except (ValueError, UnicodeError):
        return None
    return obj if isinstance(obj, dict) else None


def atomic_write(path, lines):
    directory = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(prefix=".memory-store.", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "wb") as fh:
            data = "".join(ln + "\n" for ln in lines)
            fh.write(data.encode("utf-8", errors="surrogateescape"))
            fh.flush()
            os.fsync(fh.fileno())
        if os.path.exists(path):
            os.chmod(tmp, os.stat(path).st_mode & 0o777)
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def epoch(ts):
    try:
        return dt.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=dt.timezone.utc).timestamp()
    except (TypeError, ValueError):
        return 0.0


def cmd_save(a):
    content = sys.stdin.buffer.read()
    try:
        content = content.decode("utf-8")
    except UnicodeDecodeError:
        raise StoreError("el contenido no es utf-8 válido; no se guarda nada")
    content = content.rstrip("\n")[:MAX_CONTENT_CHARS]  # por caracteres, nunca a mitad de uno
    if not content:
        raise StoreError("contenido vacío tras redactar; no se guarda nada")

    concepts = [c.replace(" ", "") for c in a.concepts.split(",")] if a.concepts else []
    entities = [e.replace(" ", "") for e in a.entities.split(",")] if a.entities else []
    entities = [e for e in entities if e]
    digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
    entry = {
        "ts": a.now, "type": a.type, "sector": a.sector, "domain": a.domain,
        "title": _strict(a.title, "title"), "content": content,
        "concepts": [_strict(c, "concepts") for c in concepts],
        "tokens_est": len(content) // 4,
        "topic_key": _strict(a.topic, "topic"), "project": _strict(a.project or "null", "project"),
        "hash": digest, "rev": 1, "valid_from": a.valid_from or a.now,
        "importance_tier": a.tier, "quality": a.quality, "memory_type": a.memory_type,
        "origin": a.origin, "questions": [],
    }

    with locked(a.store):
        lines = read_lines(a.store)
        parsed = [(ln, parse(ln)) for ln in lines]

        old_objs = [o for _, o in parsed if o is not None and o.get("topic_key") == a.topic]
        if old_objs:
            old = old_objs[-1]
            try:
                entry["rev"] = int(old.get("rev", 0)) + 1
            except (TypeError, ValueError):
                entry["rev"] = 1
            old_content = old.get("content")
            if isinstance(old_content, str) and old_content and old_content != content:
                entry["supersedes"] = old_content[:200]

        # Deduplicación ANTES de tocar nada. Solo aplica a un tema nuevo: si el tema
        # ya existe, es una actualización y el valor nuevo se guarda aunque otro tema
        # tenga el mismo contenido (si no, la entrada del tema se perdía).
        if not old_objs:
            cutoff = dt.datetime.now(dt.timezone.utc).timestamp() - DEDUP_WINDOW_S
            for _, o in parsed:
                if o is not None and o.get("hash") == digest and epoch(o.get("ts")) > cutoff:
                    print(f"⊘ Duplicado omitido (idéntico a {o.get('topic_key')})")
                    return 3

        if a.expires_at:
            entry["expires_at"] = a.expires_at
        if a.supersedes_key:
            entry["supersedes_key"] = _strict(a.supersedes_key, "supersedes")
        if a.source:
            entry["source"] = _strict(a.source, "source")
        if entities:
            entry["entities"] = [_strict(e, "entities") for e in entities]
        if a.valid_to:
            entry["valid_to"] = a.valid_to

        try:
            new_line = json.dumps(entry, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            if json.loads(new_line) != entry:
                raise ValueError("ida y vuelta distinta")
            new_line.encode("utf-8")
        except (ValueError, UnicodeEncodeError) as exc:
            raise StoreError(f"la entrada no se puede serializar ({exc}); no se guarda nada")

        out = []
        for ln, obj in parsed:
            if obj is not None and obj.get("topic_key") == a.topic:
                continue  # sustituida por la nueva (upsert)
            if (obj is not None and a.supersedes_key
                    and obj.get("topic_key") == a.supersedes_key):
                obj["valid_to"] = a.now
                obj["superseded_by"] = a.topic
                ln = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
            out.append(ln)
        out.append(new_line)
        atomic_write(a.store, out)

        # Relectura: la entrada tiene que estar y ser JSON válido.
        back = [parse(ln) for ln in read_lines(a.store)]
        if not any(o is not None and o.get("hash") == digest and o.get("topic_key") == a.topic
                   and o.get("title") == entry["title"] and o.get("content") == content
                   for o in back):
            raise StoreError("la comprobación posterior no encuentra la entrada guardada")
    print(f"✓ Guardado: {a.title} (topic: {a.topic}, rev: {entry['rev']})")
    return 0


def cmd_consolidate(a):
    quarantine = a.store[:-len(".jsonl")] + "-quarantine.jsonl" if a.store.endswith(".jsonl") \
        else a.store + ".quarantine"
    with locked(a.store):
        lines = read_lines(a.store)
        keep, moved, legacy = [], [], 0
        for ln in lines:
            obj = parse(ln)
            origin = obj.get("origin") if obj is not None else None
            if obj is not None and not origin:
                legacy += 1  # sin origin = untrusted (SE-352), pero queda a salvo
            if obj is None:
                keep.append(ln)  # lo que no se entiende no se mueve ni se borra
            elif origin in ("owner", "agent"):
                keep.append(ln)
            else:
                moved.append(ln)
        print(f"{len(moved)} {len(keep)} {legacy} {quarantine}")
        if a.dry_run or not moved:
            return 0
        # Primero la cuarentena (con fsync), después el almacén: un fallo entre
        # medias deja duplicados, nunca pérdidas.
        previous = read_lines(quarantine)
        atomic_write(quarantine, previous + moved)
        back = read_lines(quarantine)
        if back[len(back) - len(moved):] != moved:
            raise StoreError("la cuarentena no quedó íntegra; el almacén no se toca")
        atomic_write(a.store, keep)
    return 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("save")
    s.add_argument("--store", required=True)
    for name in ("type", "title", "topic", "now", "sector", "domain", "tier", "quality",
                 "memory-type", "origin"):
        s.add_argument("--" + name, required=True)
    for name in ("project", "concepts", "entities", "valid-from", "valid-to", "supersedes-key",
                 "source", "expires-at"):
        s.add_argument("--" + name, default="")
    c = sub.add_parser("consolidate")
    c.add_argument("--store", required=True)
    c.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    try:
        return cmd_save(args) if args.cmd == "save" else cmd_consolidate(args)
    except StoreError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"Error: no se pudo escribir el almacén ({exc}); no se guarda nada", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
