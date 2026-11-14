"""Raíz de datos del usuario y E/S segura de los contratos.

Estado del operador: siempre fuera del repo, bajo la raíz de datos del usuario.
Semántica de lectura (SE-518, «Reglas comunes»): fichero ausente = SIN_CONECTAR,
corrupto o inseguro = FALLIDA, y nunca «vacío».
"""
import contextlib
import datetime as dt
import json
import os
import stat
import sys
import tempfile
import time

from . import schema

OK = "OK"
SIN_CONECTAR = "SIN_CONECTAR"
FALLIDA = "FALLIDA"

MAX_JSON_BYTES = 8 * 1024 * 1024
MAX_LINE_BYTES = 64 * 1024
TS_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


class PulseError(Exception):
    """Estado o E/S que impide la operación (salida 1)."""


class EntradaInvalida(PulseError):
    """Argumento fuera de contrato (salida 2)."""


def now():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def fmt(t):
    return t.astimezone(dt.timezone.utc).strftime(TS_FORMAT)


def parse_ts(text):
    return dt.datetime.strptime(text, TS_FORMAT).replace(tzinfo=dt.timezone.utc)


def data_dir():
    """`PULSE_DATA_DIR` o `<datos de usuario>/savia/pulse`."""
    override = os.environ.get("PULSE_DATA_DIR")
    if override:
        return override
    home = os.path.expanduser("~")
    if sys.platform == "darwin":
        base = os.path.join(home, "Library", "Application Support")
    else:
        base = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    return os.path.join(base, "savia", "pulse")


def _posix_or_fail():
    if not hasattr(os, "getuid"):
        raise PulseError("plataforma sin comprobación de propietario (solo macOS y Linux en S1)")


def _unsafe_mode(st):
    return bool(st.st_mode & (stat.S_IWGRP | stat.S_IWOTH))


def ensure_dir(path):
    """Crea la raíz con permisos 0700 o rechaza una existente insegura."""
    _posix_or_fail()
    try:
        os.makedirs(path, mode=0o700, exist_ok=True)
        st = os.lstat(path)
    except OSError as exc:
        raise PulseError("no se puede preparar " + path + ": " + exc.strerror)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or _unsafe_mode(st):
        raise PulseError("la raíz de datos no es del usuario o es escribible por otros")
    return path


def _read_bytes_checked(path, limit):
    """(estado, bytes|motivo). Abre sin seguir enlaces y comprueba sobre el mismo descriptor."""
    try:
        _posix_or_fail()
    except PulseError as exc:
        return FALLIDA, str(exc)
    try:
        dst = os.lstat(os.path.dirname(path) or ".")
        if dst.st_uid != os.getuid() or _unsafe_mode(dst):
            return FALLIDA, "el directorio no es del usuario o es escribible por otros"
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except FileNotFoundError:
        return SIN_CONECTAR, "no existe"
    except OSError as exc:
        return FALLIDA, "no se puede abrir: " + (exc.strerror or "error")
    with os.fdopen(fd, "rb") as fh:
        st = os.fstat(fh.fileno())
        if not stat.S_ISREG(st.st_mode):
            return FALLIDA, "no es un fichero normal"
        if st.st_uid != os.getuid() or _unsafe_mode(st):
            return FALLIDA, "no es del usuario o es escribible por otros"
        if st.st_size > limit:
            return FALLIDA, "demasiado grande"
        return OK, fh.read(limit + 1)


def read_json(path, schema_name):
    """(estado, dato|motivo) validando contra el esquema del contrato."""
    estado, raw = _read_bytes_checked(path, MAX_JSON_BYTES)
    if estado != OK:
        return estado, raw
    try:
        data = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return FALLIDA, "no es JSON válido"
    errors = schema.validate(data, schema.load_schema(schema_name))
    if errors:
        return FALLIDA, errors[0]
    return OK, data


def read_jsonl(path, schema_name):
    """(estado, [registros válidos], [motivos de líneas rechazadas]).

    Las líneas ilegibles no se descartan en silencio: se devuelven sus motivos.
    """
    estado, raw = _read_bytes_checked(path, 256 * 1024 * 1024)
    if estado != OK:
        return estado, [], ([raw] if estado == FALLIDA else [])
    sch = schema.load_schema(schema_name)
    records, rejected = [], []
    for n, line in enumerate(raw.split(b"\n"), 1):
        if not line.strip():
            continue
        if len(line) > MAX_LINE_BYTES:
            rejected.append("línea %d: demasiado larga" % n)
            continue
        try:
            rec = json.loads(line.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            rejected.append("línea %d: no es JSON válido" % n)
            continue
        errors = schema.validate(rec, sch)
        if errors:
            rejected.append("línea %d: %s" % (n, errors[0]))
            continue
        records.append(rec)
    return OK, records, rejected


def _lock(root, timeout=10.0):
    """Cerrojo exclusivo de escritor en `<root>/.lock` (fcntl; el SO lo libera si el proceso muere)."""
    import fcntl
    ensure_dir(root)
    fd = os.open(os.path.join(root, ".lock"), os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise PulseError("otro proceso de Pulse tiene el cerrojo; no se ha escrito nada")
                time.sleep(0.05)
        yield
    finally:
        os.close(fd)


lock = contextlib.contextmanager(_lock)


def write_json_atomic(root, name, data, schema_name):
    """Valida y sustituye el fichero de forma atómica (0600). Un dato inválido no se escribe."""
    errors = schema.validate(data, schema.load_schema(schema_name))
    if errors:
        raise PulseError("contrato inválido, no se escribe: " + errors[0])
    ensure_dir(root)
    fd, tmp = tempfile.mkstemp(prefix="." + name + ".", dir=root)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, sort_keys=True)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, os.path.join(root, name))
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def append_jsonl(root, name, record, schema_name):
    """Valida y añade una línea (solo añadir, 0600). Un registro inválido no se escribe."""
    errors = schema.validate(record, schema.load_schema(schema_name))
    if errors:
        raise PulseError("contrato inválido, no se escribe: " + errors[0])
    ensure_dir(root)
    line = (json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")
    if len(line) > MAX_LINE_BYTES:
        raise PulseError("registro demasiado grande")
    fd = os.open(os.path.join(root, name),
                 os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or _unsafe_mode(st):
            raise PulseError(name + " no es del usuario o es escribible por otros; no se escribe")
        os.write(fd, line)
        os.fsync(fd)
    finally:
        os.close(fd)
