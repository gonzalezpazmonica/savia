#!/usr/bin/env python3
"""repeat-tool-guard.py — SE-326 S1: detecta llamadas de tool repetidas idénticas.

Inspirado en deepseek-harness packages/guard/repeat-tool-reminder (SE-326).

Chain key = (tool_name, canonicalized args). Una llamada idéntica a la anterior
incrementa el contador consecutivo de esa (sesion, turno); una llamada distinta
lo resetea a 1. Al cruzar un threshold se imprime un recordatorio a stderr
(jamas bloquea). Las llamadas excluidas (bookkeeping) no incrementan ni resetean
la cadena.

Modo post (SE-326, por defecto): NUNCA bloquea, exit 0 siempre. Estado persistido por (sesion, turno) en
output/loop-guard/{session}.json — cada PostToolUse es un proceso nuevo, por lo
que la persistencia es obligatoria para que el guard funcione.

Modo pre (SE-445 S1, --mode pre): hook PreToolUse de agentes autonomos. La llamada
identica numero --block-at (3) sale con 2 y un mensaje que ordena escalar al padre
(Handback, SE-332); la numero --remind-at (2) solo emite un recordatorio. Una llamada
distinta, otro agente/sesion, o una pausa mayor que --window segundos reinician la
cadena. Estado en {session}.pre.json (separado del modo post: no hay doble conteo).

Uso:
  repeat-tool-guard.py --session <id> [--turn <turn_id>] --tool <name> \\
      --args '<json args>' [--exclude 'tool_a,tool_b'] [--thresholds 3,5,8] \\
      [--preview 500] [--state-dir output/loop-guard] [--no-persist]
"""

import argparse
import json
import os
import re
import sys
import time

DEFAULT_THRESHOLDS = [3, 5, 8]
DEFAULT_EXCLUDE = {"todo_write", "todowrite"}
DEFAULT_PREVIEW = 500
PRE_REMIND_AT = 2
PRE_BLOCK_AT = 3
PRE_WINDOW_SECONDS = 600


def safe_name(raw: str) -> str:
    """Nombre de fichero seguro derivado del id de sesion (nunca una ruta)."""
    return re.sub(r"[^A-Za-z0-9._-]", "_", raw)[:96] or "default"


def build_block_message(tool: str, count: int, preview: int, canonical: str) -> str:
    snippet = canonical if len(canonical) <= preview else canonical[:preview] + "\u2026"
    return (
        "\n[loop-guard] BLOQUEADO: misma llamada identica por "
        f"{count} veces consecutivas (autonomous-safety: misma accion 3+ veces).\n"
        f"- tool: {tool}\n"
        f"- arguments: {snippet}\n"
        "No repitas la llamada. Handback (SE-332): escala al padre inmediato con lo que "
        "intentaste y por que no avanza; si no hay padre, termina en manual. "
        "Una llamada distinta reinicia la cadena. Si esperabas un cambio externo, "
        "varia la espera o usa Monitor en vez de repetir el sondeo.\n"
    )


def run_pre(args, exclude: set) -> int:
    """SE-445 S1: cuenta llamadas identicas consecutivas antes de ejecutarlas; bloquea en --block-at."""
    if args.tool.casefold() in exclude:
        return 0
    try:
        import fcntl
    except ImportError:  # sin flock el modo bloqueante no es fiable: no bloquear
        return 0
    os.makedirs(args.state_dir, exist_ok=True)
    base = os.path.join(args.state_dir, f"{safe_name(args.session)}.pre")
    canonical = canonicalize_args(normalize_bash_args(args.tool, args.args))
    key = args.agent or "-"
    now = time.time()
    with open(base + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load_state(base + ".json")
        chain = state.get(key) or {}
        same = (
            chain.get("tool") == args.tool
            and chain.get("canonical") == canonical
            and now - chain.get("ts", 0) <= args.window
        )
        count = chain.get("count", 0) + 1 if same else 1
        state[key] = {"tool": args.tool, "canonical": canonical, "count": count, "ts": now}
        save_state(base + ".json", state)
    if count >= args.block_at:
        print(build_block_message(args.tool, count, args.preview, canonical), file=sys.stderr)
        return 2
    if count >= args.remind_at:
        print(
            "\n[loop-guard] Llamada identica repetida "
            f"({count}/{args.block_at} antes de bloqueo). Analiza el resultado anterior y "
            "cambia de enfoque o de argumentos en lugar de repetirla.\n",
            file=sys.stderr,
        )
    return 0


def normalize_bash_args(tool: str, raw: str) -> str:
    """Bash: la clave ignora description/timeout/run_in_background y los espacios del comando."""
    if tool.casefold() != "bash":
        return raw
    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return raw
    if not isinstance(parsed, dict) or not isinstance(parsed.get("command"), str):
        return raw
    return json.dumps({"command": " ".join(parsed["command"].split())})


def canonicalize_args(raw: str) -> str:
    """Canonicaliza args: deep key-sort + json.dumps. Args en distinto orden = iguales."""
    if not raw or raw.strip() == "":
        return ""
    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return raw.strip()
    return json.dumps(parsed, sort_keys=True, separators=(",", ":"))


def load_state(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(path: str, state: dict) -> None:
    tmp = f"{path}.tmp"
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(state, fh, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass


def build_reminder(tool: str, count: int, preview: int, canonical: str) -> str:
    snippet = canonical
    if len(snippet) > preview:
        snippet = snippet[:preview] + f"\u2026 (+{len(canonical) - preview} more chars)"
    return (
        "\n[loop-guard] Repeated tool call detected:\n"
        f"- tool: {tool}\n"
        f"- consecutive_calls: {count}\n"
        f"- arguments: {snippet}\n"
        "Carefully analyze the previous result before calling again: "
        "if the task is not complete, try a different approach or different "
        "arguments instead of repeating the call.\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True, help="session id (CLAUDE_SESSION_ID)")
    parser.add_argument("--turn", default="", help="turn id (CLAUDE_TURN_ID) — resets chain on change")
    parser.add_argument("--tool", required=True, help="tool name")
    parser.add_argument("--args", default="", help="tool args as JSON string")
    parser.add_argument("--exclude", default="", help="comma-separated tool names excluded from chain")
    parser.add_argument("--thresholds", default="", help="comma-separated ascending thresholds")
    parser.add_argument("--preview", type=int, default=DEFAULT_PREVIEW, help="args preview cap")
    parser.add_argument("--state-dir", default="output/loop-guard")
    parser.add_argument("--no-persist", action="store_true",
                        help="NO persistir estado (cada PostToolUse es un proceso nuevo; el guard exige persistencia)")
    parser.add_argument("--mode", choices=("post", "pre"), default="post",
                        help="post: recordatorios, nunca bloquea (SE-326). pre: bloquea en --block-at (SE-445 S1)")
    parser.add_argument("--agent", default="", help="id de subagente: cadenas separadas por agente (modo pre)")
    parser.add_argument("--remind-at", type=int, default=PRE_REMIND_AT)
    parser.add_argument("--block-at", type=int, default=PRE_BLOCK_AT)
    parser.add_argument("--window", type=int, default=PRE_WINDOW_SECONDS,
                        help="segundos; una pausa mayor reinicia la cadena (modo pre)")
    parser.add_argument("--emit-telemetry", default="", help="path to otel-emit.sh (optional)")
    args = parser.parse_args()

    thresholds = sorted(set(DEFAULT_THRESHOLDS))
    if args.thresholds.strip():
        try:
            parsed = [int(t) for t in args.thresholds.split(",") if t.strip()]
            if parsed and all(t >= 2 for t in parsed) and len(parsed) == len(set(parsed)):
                thresholds = sorted(parsed)
        except ValueError:
            pass

    exclude = set(DEFAULT_EXCLUDE)
    if args.exclude.strip():
        exclude |= {t.strip().casefold() for t in args.exclude.split(",") if t.strip()}

    if args.mode == "pre":
        return run_pre(args, exclude)

    # bookkeeping tools are transparent to the chain
    if args.tool.casefold() in exclude:
        return 0

    key = f"{args.session}:::{args.turn or 'default'}"

    # estado por (sesion, turno); persistido SIEMPRE (cada PostToolUse es proceso nuevo)
    state_path = os.path.join(args.state_dir, f"{args.session}.json")
    state = load_state(state_path) if not args.no_persist else {}

    chain = state.get(key)
    if chain is None or chain.get("turn") != args.turn:
        chain = {"turn": args.turn, "tool": None, "canonical": None, "count": 0}

    canonical = canonicalize_args(args.args)

    if chain["tool"] == args.tool and chain["canonical"] == canonical:
        chain["count"] += 1
    else:
        chain["tool"] = args.tool
        chain["canonical"] = canonical
        chain["count"] = 1

    state[key] = chain

    hit_threshold = chain["count"] in thresholds
    if not args.no_persist:
        save_state(state_path, state)

    if hit_threshold:
        first = chain["count"] == thresholds[0]
        if first:
            print(
                "\n[loop-guard] You are repeating the exact same tool call with identical "
                "arguments. Carefully analyze the previous result before calling again: "
                "if the task is not complete, try a different approach or different "
                "arguments instead of repeating the call.\n",
                file=sys.stderr,
            )
        else:
            print(build_reminder(args.tool, chain["count"], args.preview, canonical), file=sys.stderr)

        if args.emit_telemetry and os.path.exists(args.emit_telemetry):
            try:
                import subprocess

                subprocess.run(
                    [
                        "bash",
                        args.emit_telemetry,
                        "savia.loop-guard",
                        f"tool={args.tool}",
                        f"run_length={chain['count']}",
                        f"threshold={chain['count']}",
                    ],
                    capture_output=True,
                    check=False,
                )
            except Exception:
                pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
