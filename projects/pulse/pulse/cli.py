"""CLI de Pulse. Salidas: 0 bien, 1 rechazado por el estado, 2 entrada inválida.

Excepción: `pulse run` devuelve el código de la orden que lanza (su 1 o su 2 no se
distinguen de los de Pulse por el código). Si Pulse rechaza antes de lanzar, no
lanza nada y no hay `job_started` en el ledger: el ledger es lo que distingue.
"""
import argparse
import json
import os
import signal
import subprocess
import sys

from . import backup, events, schema, status, store
from .store import EntradaInvalida, PulseError


def _p():
    ap = argparse.ArgumentParser(prog="pulse", description="Pulse: el latido de la planta de trabajo (SE-518 S1).")
    sub = ap.add_subparsers(dest="cmd", required=True)
    nivel = {"default": "N4", "choices": events.NIVELES, "help": "nivel de clasificación (sin nivel = N4)"}

    s = sub.add_parser("run", help="lanza una orden y emite inicio y fin con código y clase")
    s.add_argument("--job-id", required=True)
    s.add_argument("--intento", type=int, default=1)
    s.add_argument("--ttl", type=int, help="segundos entre latidos que el trabajo declara")
    s.add_argument("--propuesta")
    s.add_argument("--modelo")
    s.add_argument("--nivel", **nivel)
    s.add_argument("argv", nargs=argparse.REMAINDER, help="-- orden y argumentos")

    s = sub.add_parser("job-start")
    s.add_argument("--job-id", required=True)
    s.add_argument("--intento", type=int, default=1)
    s.add_argument("--ttl", type=int)
    s.add_argument("--propuesta")
    s.add_argument("--modelo")
    s.add_argument("--nivel", **nivel)

    s = sub.add_parser("job-beat")
    s.add_argument("--job-id", required=True)
    s.add_argument("--fase", required=True)
    s.add_argument("--nivel", **nivel)

    s = sub.add_parser("job-finish")
    s.add_argument("--job-id", required=True)
    s.add_argument("--rc", type=int, required=True)
    s.add_argument("--clase", help="señal tipada del lanzador (nunca texto libre)")
    s.add_argument("--nivel", **nivel)

    s = sub.add_parser("pr-event")
    s.add_argument("--tipo", required=True, choices=["pr_created", "pr_merged"])
    s.add_argument("--propuesta", required=True)
    s.add_argument("--nivel", **nivel)

    s = sub.add_parser("latido", help="publica el latido de Pulse")
    s.add_argument("--pasada", type=int, required=True)
    s.add_argument("--ttl", type=int, default=180)
    s.add_argument("--duracion", type=float)
    s.add_argument("--fuente-vencida", action="append", default=[])

    s = sub.add_parser("deliver", help="una pasada del canal de respaldo (solo actúa si Soul no está)")
    s.add_argument("--max-validez", type=int, default=backup.MAX_VALIDEZ_DEFECTO)

    sub.add_parser("inbox", help="lo pendiente de ti, en llano")
    s = sub.add_parser("status", help="estado de la planta, en llano")
    s.add_argument("--json", action="store_true")

    s = sub.add_parser("validate", help="valida un fichero contra un contrato")
    s.add_argument("contrato", choices=["evento", "peticiones", "latido", "presencia", "acuse"])
    s.add_argument("fichero")
    return ap


def _lanzar(cmd, env, estado, forward):
    """Lanza la orden y espera. Devuelve el código (128+n si murió por la señal n)."""
    try:
        proc = subprocess.Popen(cmd, env=env)
    except OSError as exc:
        print("no se pudo lanzar la orden: %s" % (exc.strerror or exc), file=sys.stderr)
        return 127 if isinstance(exc, FileNotFoundError) else 126
    estado["proc"] = proc
    for signum in estado["pendientes"]:  # llegadas entre Popen y aquí
        forward(signum, None)
    code = proc.wait()
    return 128 + (-code) if code < 0 else code


def _terminal_ya_entrega_sigint():
    """True si Pulse está en el grupo de primer plano de su terminal: entonces Ctrl-C ya
    llega al hijo (mismo grupo) y reenviarlo sería un segundo SIGINT («salida forzada»)."""
    for fd in (0, 1, 2):
        try:
            if os.isatty(fd):
                return os.tcgetpgrp(fd) == os.getpgrp()
        except OSError:
            continue
    return False


def _run(root, a):
    if not a.argv or a.argv[0] != "--" or len(a.argv) < 2:
        raise EntradaInvalida("uso: pulse run --job-id ID -- orden [args...]")
    cmd = a.argv[1:]
    env = dict(os.environ, PULSE_JOB_ID=a.job_id)
    # Los manejadores van antes del inicio y de lanzar: una señal en esa ventana no
    # mata a Pulse sin dejar el fin. Si llega antes de lanzar, no se lanza.
    estado = {"proc": None, "pendientes": []}

    def forward(signum, _frame):
        if estado["proc"] is None:
            estado["pendientes"].append(signum)
            return
        if signum == signal.SIGINT and _terminal_ya_entrega_sigint():
            return
        try:
            estado["proc"].send_signal(signum)
        except OSError:
            pass

    old = {s: signal.signal(s, forward) for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
    try:
        # Fail-closed: sin inicio registrado no se lanza nada.
        events.job_start(root, a.job_id, a.nivel, a.intento, a.ttl, a.propuesta, a.modelo)
        if estado["pendientes"]:
            print("pulse: señal recibida antes de lanzar; no se lanza la orden", file=sys.stderr)
            rc = 128 + estado["pendientes"][0]
        else:
            rc = _lanzar(cmd, env, estado, forward)
    finally:
        for s, h in old.items():
            signal.signal(s, h)
    rc = min(rc, 255)
    try:
        events.job_finish(root, a.job_id, rc)
    except PulseError as exc:
        # El trabajo queda «en marcha» en el ledger hasta que se anote su fin a mano.
        print("pulse: no se registró el fin: %s\n"
              "pulse: el trabajo consta en marcha; corrige la causa y anota el fin con:\n"
              "  pulse job-finish --job-id %s --rc %d" % (exc, a.job_id, rc), file=sys.stderr)
    return rc


def _validate(a):
    sch = schema.load_schema(a.contrato)
    try:
        with open(a.fichero, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        raise EntradaInvalida("no se puede leer el fichero: %s" % exc)
    docs = [l for l in text.split("\n") if l.strip()] if a.contrato in ("evento", "acuse") else [text]
    bad = 0
    for n, raw in enumerate(docs, 1):
        try:
            errs = schema.validate(json.loads(raw), sch)
        except (ValueError, RecursionError):
            errs = ["no es JSON válido"]
        for e in errs[:1]:
            bad += 1
            print("%s %d: %s" % (a.fichero, n, e), file=sys.stderr)
    if not docs:
        print("fichero vacío: no es un contrato válido", file=sys.stderr)
        return 1
    return 1 if bad else 0


def main(argv=None):
    a = _p().parse_args(argv)
    root = store.data_dir()
    try:
        if a.cmd == "run":
            return _run(root, a)
        if a.cmd == "job-start":
            ev = events.job_start(root, a.job_id, a.nivel, a.intento, a.ttl, a.propuesta, a.modelo)
            print("inicio registrado: %s (intento %d)" % (a.job_id, ev["intento"]))
        elif a.cmd == "job-beat":
            ev = events.job_beat(root, a.job_id, a.fase, a.nivel)
            print("latido %d registrado: %s" % (ev["seq"], a.job_id))
        elif a.cmd == "job-finish":
            ev, nuevo = events.job_finish(root, a.job_id, a.rc, a.clase, a.nivel)
            print("fin %s: %s (código %d, clase %s)" % ("registrado" if nuevo else "ya constaba", a.job_id, ev["rc"], ev["clase"]))
        elif a.cmd == "pr-event":
            events.pr_event(root, a.tipo, a.propuesta, a.nivel)
            print("%s registrado: %s" % (a.tipo, a.propuesta))
        elif a.cmd == "latido":
            events.write_latido(root, a.pasada, a.ttl, a.duracion, a.fuente_vencida)
            print("latido publicado (pasada %d)" % a.pasada)
        elif a.cmd == "deliver":
            try:
                r = backup.entregar(root, a.max_validez)
            except backup.PasadaEnCurso as exc:
                print("Otra pasada de respaldo está en curso; esta no hace nada (%s)." % exc)
                return 0
            if r["soul"]:
                print("Soul presente: no emito nada.")
            else:
                print("Soul %s. Avisos por respaldo: %d." % (r["motivo"], len(r["avisados"])))
                if r["sin_canal_so"]:
                    print("Sin notificación del sistema para %d aviso(s): el único canal es «pulse inbox»."
                          % r["sin_canal_so"])
        elif a.cmd == "inbox":
            print(backup.inbox_text(root))
        elif a.cmd == "status":
            d = status.collect(root)
            print(json.dumps(d, ensure_ascii=False, indent=1) if a.json else status.render(d))
        elif a.cmd == "validate":
            return _validate(a)
    except EntradaInvalida as exc:
        print("pulse: " + str(exc), file=sys.stderr)
        return 2
    except PulseError as exc:
        print("pulse: " + str(exc), file=sys.stderr)
        return 1
    return 0
