#!/usr/bin/env python3
"""guard_blocks.py — registro local de bloqueos de guardas y tasa de falsos positivos (SE-510 D2).

Subcomandos:
  record --guard G --reason R [--event E] [--tool T] [--engine bash|ts|dispatcher]
         La orden llega por stdin (JSON del hook o texto). Añade una línea a
         output/guard-blocks.jsonl con ``cmd_hmac`` (HMAC-SHA256 con clave local).
         La orden en claro solo se guarda con SAVIA_GUARD_LOG_INPUT=1, y redactada.
  mark <id> false-positive|true-positive
         Etiqueta un bloqueo (línea de etiqueta aparte: el registro es de solo añadir).
  report [--since AAAA-MM-DD] [--json]
         Por guarda: bloqueos, etiquetados, FP, tasa FP = FP/etiquetados (UNKNOWN con 0
         etiquetados, nunca 0 %) y sin etiquetar.
  (wrap: en scripts/guard-blocks.sh, en bash, para no lanzar Python cuando el hook pasa.)

Rutas: SAVIA_GUARD_BLOCKS_LOG (por defecto $CLAUDE_PROJECT_DIR/output/guard-blocks.jsonl)
y SAVIA_GUARD_BLOCKS_KEY (por defecto ~/.savia/guard-blocks.key, 0600, creada al primer
uso). Sin clave legible, ``cmd_hmac`` queda vacío y ``hmac`` dice ``no-key``: nunca se cae
a un hash sin clave, que con órdenes de baja entropía se confirma por diccionario.
Nada sale de la máquina.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import hmac
import json
import os
import re
import secrets
import stat
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LABELS = ("false-positive", "true-positive")
ID_RE = re.compile(r"^[0-9a-f]{12}$")
# Redacción del opt-in (docs/rules/domain/secret-redaction-policy.md): ante la duda, se tapa.
SECRET_RES = [
    re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}"),
    re.compile(r"sk-[A-Za-z0-9]{32,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"(?:ghp|ghs|ghu|ghr|gho)_[A-Za-z0-9]{20,}"),
    re.compile(r"xox[abprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"(?i)(authorization:\s*(?:bearer|basic|token)\s+)\S+"),
    re.compile(r"(?i)((?:password|passwd|pwd|token|secret|api[_-]?key|pat)\s*[=:]\s*)(?:\"[^\"]*\"|'[^']*'|[^\s'\";&|]+)"),
    # Opciones de línea de órdenes: `--password x`, `--token=x`, `-p x` (valor con o sin comillas).
    re.compile(r"(?i)(\s--?(?:password|passwd|pwd|token|secret|api[_-]?key|pat|p)(?:=|\s+))(?:\"[^\"]*\"|'[^']*'|[^\s'\";&|]+)"),
    re.compile(r"(?i)(://[^/\s:@]+:)[^@\s]+(?=@)"),
    # Lo que reconoce el guard de credenciales (.opencode/plugins/lib/credential-patterns.ts)
    # y el genérico de abajo no tapa porque un punto o un `;` parte el token.
    re.compile(r"(?:hvs\.[A-Za-z0-9_-]{24,}|\bs\.[A-Za-z0-9]{24,})"),  # HashiCorp Vault
    re.compile(r"AIza[0-9A-Za-z_-]{35}"),  # Google API
    re.compile(r"(?i)((?:AccountKey|SharedAccessKey|sig)=)[^;&\s'\"]+"),  # Azure y SAS
    re.compile(r"eyJ[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_-]+){0,2}"),  # JWT / token de k8s
    # Bloque de clave privada PEM (la clase [E] evita que los escáneres tomen la regex por una clave).
    re.compile(r"-----BEGIN[^-\n]*PRIVAT[E] KEY-----[\s\S]*?(?:-----END[^-\n]*PRIVAT[E] KEY-----|$)"),
    re.compile(r"(?i)((?:bearer|auth[_-]?token|privat[e][_-]?key|connection[_-]?string|client[_-]?secret)"
               r"\s*[=:]\s*)(?:\"[^\"]*\"|'[^']*'|[^\s'\";&|]+)"),
    re.compile(r"[A-Za-z0-9+/_=-]{32,}"),  # tokens largos (también los PAT de grano fino)
]


def log_path() -> Path:
    env = os.environ.get("SAVIA_GUARD_BLOCKS_LOG")
    if env:
        return Path(env)
    base = os.environ.get("CLAUDE_PROJECT_DIR") or str(ROOT)
    return Path(base) / "output/guard-blocks.jsonl"


def key_path() -> Path:
    env = os.environ.get("SAVIA_GUARD_BLOCKS_KEY")
    return Path(env) if env else Path.home() / ".savia/guard-blocks.key"


def load_key() -> bytes | None:
    """Clave local; se crea (0600) si no existe. Ilegible, vacía, con permisos abiertos, enlace
    simbólico o de otra dueña → None."""
    path = key_path()
    try:
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            try:
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "w") as fh:
                    fh.write(secrets.token_hex(32))
            except FileExistsError:
                pass  # otro hook concurrente la está creando: se lee abajo
        # Sin seguir enlaces y solo si es un fichero normal de esta usuaria (no una clave ajena).
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            st = os.fstat(fd)
            if (not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid()
                    or stat.S_IMODE(st.st_mode) & 0o077):
                return None
            for _ in range(10):  # la creadora puede no haber escrito aún
                key = os.pread(fd, 4096, 0).decode("utf-8").strip()
                if len(key) >= 32:
                    return key.encode()
                time.sleep(0.05)
            return None
        finally:
            os.close(fd)
    except (OSError, UnicodeDecodeError):
        return None


def redact(text: str) -> str:
    for rx in SECRET_RES:
        text = rx.sub(lambda m: (m.group(1) if m.groups() else "") + "[REDACTED]", text)
    return text


def command_of(raw: str) -> str:
    text = raw.strip()
    if text.startswith("{"):
        try:
            doc = json.loads(text)
            ti = doc.get("tool_input") if isinstance(doc, dict) else None
            if isinstance(ti, dict):
                return str(ti.get("command") or ti.get("file_path") or json.dumps(ti, sort_keys=True))
        except json.JSONDecodeError:
            pass
    return raw


def record(guard: str, reason: str, raw: str, event: str, tool: str, engine: str) -> dict:
    cmd = command_of(raw)
    key = load_key()
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    entry = {"ts": now, "event": event, "tool": tool, "guard": guard, "engine": engine,
             # El motivo lo escribe el hook y puede repetir rutas o el fragmento detectado.
             "reason": redact((reason.strip().splitlines() or [""])[0])[:300],
             "cmd_hmac": hmac.new(key, cmd.encode(), hashlib.sha256).hexdigest() if key else "",
             "hmac": "ok" if key else "no-key"}
    if os.environ.get("SAVIA_GUARD_LOG_INPUT") == "1":
        entry["input"] = redact(cmd)[:2000]
    entry["id"] = hashlib.sha256(f"{now}{guard}{entry['cmd_hmac']}{secrets.token_hex(8)}".encode()
                                 ).hexdigest()[:12]
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    append_private(path, json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")
    return entry


def append_private(path: Path, line: str) -> None:
    """Añade al log creándolo 0600 (no con el umask): solo la persona dueña lo lee."""
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as fh:
        fh.write(line)


def read_log() -> tuple[list[dict], dict[str, str]]:
    blocks, labels = [], {}
    path = log_path()
    if not path.exists():
        return blocks, labels
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            print(f"AVISO: línea {n} ilegible en {path}; se ignora", file=sys.stderr)
            continue
        if row.get("type") == "label":
            labels[row.get("id", "")] = row.get("label", "")
        elif row.get("guard"):
            blocks.append(row)
    return blocks, labels


def mark(block_id: str, label: str) -> int:
    if label not in LABELS or not ID_RE.match(block_id):
        print(f"uso: mark <id de 12 hex> {'|'.join(LABELS)}", file=sys.stderr)
        return 2
    blocks, _ = read_log()
    if not any(b.get("id") == block_id for b in blocks):
        print(f"no existe el bloqueo {block_id} en {log_path()}", file=sys.stderr)
        return 1
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    append_private(log_path(), json.dumps({"type": "label", "id": block_id, "label": label,
                                           "ts": now}) + "\n")
    print(f"{block_id} → {label}")
    return 0


def summarize(since: str | None) -> dict:
    blocks, labels = read_log()
    if since:
        blocks = [b for b in blocks if b.get("ts", "") >= since]
    per: dict[str, dict] = {}
    for b in blocks:
        g = per.setdefault(b["guard"], {"blocks": 0, "labeled": 0, "fp": 0, "unlabeled": 0})
        g["blocks"] += 1
        lab = labels.get(b.get("id", ""))
        if lab in LABELS:
            g["labeled"] += 1
            g["fp"] += lab == "false-positive"
        else:
            g["unlabeled"] += 1
    for g in per.values():
        g["fp_rate"] = f"{100 * g['fp'] / g['labeled']:.1f}%" if g["labeled"] else "UNKNOWN"
    tot = {k: sum(g[k] for g in per.values()) for k in ("blocks", "labeled", "fp", "unlabeled")}
    tot["fp_rate"] = f"{100 * tot['fp'] / tot['labeled']:.1f}%" if tot["labeled"] else "UNKNOWN"
    return {"log": str(log_path()), "since": since, "guards": per, "total": tot}


def report(since: str | None, as_json: bool) -> int:
    if since and not re.match(r"^\d{4}-\d{2}-\d{2}", since):
        print("--since espera AAAA-MM-DD", file=sys.stderr)
        return 2
    s = summarize(since)
    if as_json:
        print(json.dumps(s, ensure_ascii=False, sort_keys=True))
        return 0
    print(f"Bloqueos de guardas — {s['log']}" + (f" desde {since}" if since else ""))
    print(f"{'guarda':<32} {'bloqueos':>8} {'etiq.':>6} {'FP':>4} {'tasa FP':>8} {'sin etiq.':>9}")
    for name, g in sorted(s["guards"].items(), key=lambda kv: -kv[1]["blocks"]):
        print(f"{name:<32} {g['blocks']:>8} {g['labeled']:>6} {g['fp']:>4} {g['fp_rate']:>8} "
              f"{g['unlabeled']:>9}")
    t = s["total"]
    print(f"{'TOTAL':<32} {t['blocks']:>8} {t['labeled']:>6} {t['fp']:>4} {t['fp_rate']:>8} "
          f"{t['unlabeled']:>9}")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="guard-blocks", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("record")
    r.add_argument("--guard", required=True)
    r.add_argument("--event", default="PreToolUse")
    r.add_argument("--tool", default="Bash")
    r.add_argument("--reason", default="")
    r.add_argument("--engine", default="bash", choices=("bash", "ts", "dispatcher"))
    m = sub.add_parser("mark")
    m.add_argument("id")
    m.add_argument("label")
    rp = sub.add_parser("report")
    rp.add_argument("--since", default=None)
    rp.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if args.cmd == "record":
        raw = "" if sys.stdin.isatty() else sys.stdin.read()
        # El motivo puede citar el fragmento detectado: los llamadores lo pasan por el entorno
        # (SAVIA_GUARD_BLOCK_REASON), que solo lee la dueña del proceso, y no por argv (/proc).
        reason = args.reason or os.environ.get("SAVIA_GUARD_BLOCK_REASON", "")
        print(record(args.guard, reason, raw, args.event, args.tool, args.engine)["id"])
        return 0
    if args.cmd == "mark":
        return mark(args.id, args.label)
    return report(args.since, args.json)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
