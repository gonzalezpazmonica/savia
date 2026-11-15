#!/usr/bin/env python3
"""telemetry-fingerprint.py — SE-534 S1: fingerprint determinista de errores.

Computa una huella normalizada de un evento de telemetría JSON para agrupar
errores repetidos ("este error apareció 47 veces").

Normalización (message_bucket):
  URLs -> <url> · emails -> <email> · UUIDs -> <uuid> · timestamps -> <ts>
  IPs -> <ip> · hex (0x.. o >=20 chars) -> <hex> · números -> <n>
  strings entre comillas -> <str> · IDs largos (>=20 chars) -> <id>
  request paths con / inicial -> <path> (colapso anti-scan)
  desenvuelve errores wrapper-style ("message": "...") para no hashear el JSON
  colapsa whitespace, lowercase.

Output: {hash, exception_type, top_frame, normalized_frames}
Solo texto local; sin LLM, sin red (CRIT-001 / ADR-012).
"""
import hashlib
import json
import re
import sys

URL_RE = re.compile(r'https?://[^\s"\'\],]+')
EMAIL_RE = re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')
UUID_RE = re.compile(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
TS_RE = re.compile(r'\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?')
IP_RE = re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b|\b(?:[0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{0,4}\b')
HEX_RE = re.compile(r'\b0x[0-9a-fA-F]+\b|\b[0-9a-fA-F]{20,}\b')
ID_LONG_RE = re.compile(r'\b[A-Za-z0-9_-]{20,}\b')
QUOTED_RE = re.compile(r'"([^"]{4,})"')
PATH_RE = re.compile(r'/(?:api|v\d+|[a-z][a-z0-9_-]*/)+[a-z0-9._-]*')
STR_RE = re.compile(r'\b[a-z][a-z0-9_-]{7,}\b')
NUM_RE = re.compile(r'\b\d+\b')


def _unwrap_wrapper_frames(error_obj):
    """Si error_obj tiene estructura wrapper-style, extrae las frames lógicas
    (exc_chain) en vez de hashear el wrapper con request_id per-request."""
    frames = []
    if isinstance(error_obj, dict):
        chain = error_obj.get('exc_chain') or []
        for item in chain:
            loc = item.get('loc') if isinstance(item, dict) else None
            exc = item.get('exc_type') if isinstance(item, dict) else None
            msg = item.get('message') if isinstance(item, dict) else None
            if loc is not None:
                frames.append(f"{loc}:{exc}:{msg}")
        if frames:
            return frames
        # audio_event_* style
        for k in ('error', 'exception', 'message'):
            m = error_obj.get(k)
            if isinstance(m, str) and m:
                return [f"{k}:{m}"]
    return None


def normalize(text):
    """Aplica las reglas de redacción en orden (colapso anti-scan)."""
    text = URL_RE.sub('<url>', text)
    text = EMAIL_RE.sub('<email>', text)
    text = UUID_RE.sub('<uuid>', text)
    text = TS_RE.sub('<ts>', text)
    text = IP_RE.sub('<ip>', text)
    text = HEX_RE.sub('<hex>', text)
    text = ID_LONG_RE.sub('<id>', text)
    text = QUOTED_RE.sub('<str>', text)
    text = PATH_RE.sub('<path>', text)
    text = STR_RE.sub('<str>', text)
    text = NUM_RE.sub('<n>', text)
    # colapso whitespace + lowercase
    text = re.sub(r'\s+', ' ', text).strip().lower()
    return text


def fingerprint(event):
    """event: dict de telemetría (ya parseado) → {hash, exception_type,
    top_frame, normalized_frames}."""
    if not isinstance(event, dict):
        raise ValueError('event debe ser un dict')

    exc_type = str(event.get('exception_type') or event.get('error_type') or 'unknown')
    msg_raw = ''
    for key in ('message', 'error', 'error_message', 'exception', 'stderr'):
        v = event.get(key)
        if isinstance(v, str):
            msg_raw = v
            break
        if isinstance(v, dict):
            msg_raw = json.dumps(v, sort_keys=True)
            break

    raw_frames = str(event.get('frames') or event.get('stack') or '')
    if isinstance(raw_frames, list):
        raw_frames = '\n'.join(str(f) for f in raw_frames)

    # wrapper-style unwrap
    unwrapped = _unwrap_wrapper_frames(event.get('error')) if isinstance(event.get('error'), dict) else None

    if unwrapped:
        frames_norm = [normalize(f) for f in unwrapped]
    else:
        combined = f"{msg_raw}\n{raw_frames}"
        frames_norm = [normalize(combined)]

    bucket_parts = [exc_type] + frames_norm
    bucket = ' :: '.join(p for p in bucket_parts if p)
    canonical = f"{exc_type} :: {bucket}"
    h = hashlib.sha256(canonical.encode('utf-8')).hexdigest()[:16]

    top_frame = frames_norm[0] if frames_norm else ''
    return {
        'hash': h,
        'exception_type': exc_type,
        'top_frame': top_frame,
        'normalized_frames': frames_norm,
        'bucket': bucket,
    }


def main():
    if len(sys.argv) != 2:
        sys.stderr.write('usage: telemetry-fingerprint.py <event.json | ->\n')
        sys.exit(2)
    src = sys.argv[1]
    raw = sys.stdin.read() if src == '-' else open(src).read()
    event = json.loads(raw)
    result = fingerprint(event)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()