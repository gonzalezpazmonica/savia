#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SE-345 — Mind Virus Defense: detect persistence/propagation instructions.

Reads text from stdin or a file and scores signs of a *mind virus* (Anthropic
× EPFL, 2026-08): malicious instructions designed to persist into an agent's
memory, rewrite its identity, or propagate to other agents.

Output (JSON, one object):
  {"score": int, "verdict": "clean"|"suspect"|"malicious", "signals": [...]}

Deterministic, no network, no LLM (CRIT-001: everything local).
Exit codes: 0 clean/suspect, 1 malicious (useful for hooks with --exit-verdict), 2 unreadable file.
"""

import json
import re
import sys
import unicodedata

# ── Configuration ────────────────────────────────────────────────────────────
VERDICT_THRESHOLD_CLEAN = 15    # below this → clean
VERDICT_THRESHOLD_MALICIOUS = 70  # at/above → malicious; in-between → suspect

# ── Signal patterns (from the study's three payload classes) ────────────────
# Normalize: lower-case, collapse whitespace, strip punctuation for matching.
def _norm(text: str) -> str:
    # Sin caracteres de formato invisibles (U+200B, U+00AD...) y NFKD sin marcas combinantes (ancho
    # completo → ASCII, sin tildes): "ig\u200bnora", "ｉｇｎｏｒａ" u "olvídate" no esquivan los patrones.
    text = "".join(c for c in text if unicodedata.category(c) != "Cf")
    text = "".join(c for c in unicodedata.normalize("NFKD", text.lower()) if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", text).strip(" .!¡¿?;:,")

PERSISTENCE_PATTERNS = [
    (r"(?:guarda|guardar|escribe|write|save|a[ñni]?ade|añade|add|inserta|insert|inyecta|inject).{0,60}(?:memoria|memory|historial|en (?:tu )?(?:memoria|memory|historial)|a (?:tu )?(?:memoria|memory))", 70, "persistencia"),
    (r"(?:recuerda|remember).{0,40}(?:siempre|always|para siempre|forever).{0,60}(?:añade|guarda|memoriza|write|save|add|memorize)?", 70, "persistencia-deber-remember"),
    (r"(?:actualiza|update|edi[ta]?a|modifica|modify|reescribe|rewrite|escribe).{0,30}(?:memor[a-zí]{2,}|memory).{0,30}(?:file|archivo|md)", 35, "persistencia-memfile"),
    (r"(?:archivo de memoria|memory file|historial persistente|persistent history)", 35, "persistencia-memfile-ref"),
    (r"(?:al|en|when).{0,20}(?:inicio|start).{0,20}(?:sesi[oó]n|session).{0,40}(?:carga|cargar|load)", 35, "persistencia-carga-auto"),
]

IDENTITY_PATTERNS = [
    (r"(?:ignora|ignorar|ignore|olvida|forget).{0,30}(?:instrucciones|prompt|pnjs|restricciones)|(?:desde ahora|from now on).{0,20}(?:ser[aá]s|actuar[aá]s|eres)", 70, "identidad-reescritura"),
    (r"(?:tu|new|your).{0,15}(?:prop[oó]sito|misi[oó]n|mission|objetivo real|purpose).{0,40}(?:es|s[eé]r[aá]|now|\bis\b)", 70, "identidad-nuevo-proposito"),
    (r"(?:eres realmente|you are really|en realidad eres).{0,40}", 70, "identidad-falsa"),
    (r"(?:desactiva|desactivar|disable|quita|remove|olvida).{0,30}(?:reglas|constituci[oó]n|filtros|guards|seguridad|restricciones)", 70, "identidad-desactivar-guardas"),
]

PROPAGATION_PATTERNS = [
    (r"(?:transmite|propaga|propagate|spread|pasa|pass).{0,40}(?:al (?:siguiente|otro)|al agente|a (?:este|otro) (?:agente|worker|bot)|next agent|this instruction)", 70, "propagacion"),
    (r"(?:aseg[uú]ra|ensure|make sure).{0,45}(?:tambi[eé]n|also|otro agente).{0,35}(?:lo reciba|recibe|conozca|knows|adopte)", 70, "propagacion-multi-hop"),
    (r"(?:incluye|include|incorpora).{0,30}(?:esto|this).{0,40}(?:handoff|entrega|transferencia)", 70, "propagacion-handoff"),
    (r"(?:comparte|compartir|comp[aá]rtelo|share).{0,40}(?:con otros|con (?:el|un|otro) agente|with (?:the )?next|with other)", 70, "propagacion-share"),
]

PERSUASIVE_PATTERNS = [
    (r"(?:reflexiona sobre|considera incorporar|ponder|think about).{0,40}(?:prop[oó]sito|mis[ió]on|mission|objetivos reales|objetivo|purpose)", 20, "persuasivo-reflexion"),
    (r"(?:esto encaja|this fits|aligns with).{0,30}(?:con tus|with your|your true)", 20, "persuasivo-encaje"),
    (r"(?:te ayudar[aá] a|will help you).{0,30}(?:ser mejor|become better|mejor agente)", 15, "persuasivo-mejora"),
    (r"(?:en confianza|entre nosotros|trust me).{0,30}(?:s[ií]gue|follow|haz)", 15, "persuasivo-confianza"),
]

ALL_PATTERNS = [
    *PERSISTENCE_PATTERNS,
    *IDENTITY_PATTERNS,
    *PROPAGATION_PATTERNS,
    *PERSUASIVE_PATTERNS,
]


def detect(text: str) -> dict:
    norm = _norm(text)
    signals: list[str] = []
    score = 0
    for pattern, weight, name in ALL_PATTERNS:
        if re.search(pattern, norm):
            score += weight
            signals.append(name)
    if score >= VERDICT_THRESHOLD_MALICIOUS:
        verdict = "malicious"
    elif score >= VERDICT_THRESHOLD_CLEAN:
        verdict = "suspect"
    else:
        verdict = "clean"
    return {"score": score, "verdict": verdict, "signals": sorted(set(signals))}


def main(argv: list[str]) -> int:
    exit_verdict = False
    batch = False
    args = [a for a in argv if not a.startswith("--")]
    if "--exit-verdict" in argv:
        exit_verdict = True
    if "--batch" in argv:
        batch = True

    if batch:
        # Read lines "<path>|<label>" from stdin, one detect call per file,
        # emit "label|verdict|score|signals" per line (fast single-process batch).
        import os
        for line in sys.stdin:
            line = line.rstrip("\n")
            if not line:
                continue
            path, sep, label = line.rpartition("|")
            if not sep:
                continue
            path = os.path.expanduser(path)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    content = fh.read()
            except OSError:
                # Una superficie que no se puede leer no es «limpia»: se informa para que cuente.
                print(f"{label}|error|0|unreadable")
                continue
            r = detect(content)
            print(f"{label}|{r['verdict']}|{r['score']}|{','.join(r['signals'])}")
        return 0

    if args:
        try:
            with open(args[0], encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            # exit 2: no confundir un fichero ilegible con el exit 1 de «malicious».
            print(f"ERROR: no se puede leer {args[0]}: {exc.strerror}", file=sys.stderr)
            return 2
    else:
        text = sys.stdin.read()

    result = detect(text)
    print(json.dumps(result, ensure_ascii=False))
    if exit_verdict and result["verdict"] == "malicious":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))