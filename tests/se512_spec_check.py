#!/usr/bin/env python3
"""SE-512: comprobador de coherencia interna de la spec (revisiones de la PR #1485).

Uso: python3 -I tests/se512_spec_check.py <spec.md>
Exit 0 si la spec es coherente; 1 con un motivo por línea en stderr;
2 si no se puede leer (uso, fichero ausente o no UTF-8).

Reglas (cada una cierra un hallazgo de la tercera ronda de revisión):
  R-FORCED    (correctness P1-1) la exclusión forzosa (b)+(c) la aplica el
              ejecutor en S2 con su propia lista, sin depender de S3; AC-11 no
              llama «ya existente» a rutas que `risk-tier.py` no excluye.
  R-ACDEF     (correctness P2-1) cada AC citado tiene su propia viñeta.
  R-PLAN      cada AC definido está en el plan por slices, y viceversa.
  R-RUNAC     (correctness P2-2) hay AC de `run` para topes, universo y revocación.
  R-PENDING   (correctness P2-3) `main_pending_timeout` por defecto cuadra con
              el sondeo actual y `action_required`/`stale` no cuentan como `pass`.
  R-NOCHECKS  (correctness P2-4) «ningún check-run en main» tiene motivo y AC.
  R-GLOB      (security P2-1) los globs no se evalúan con fnmatch sobre la
              ruta entera y hay negativo `docs/*` frente a `docs/x/y`.
  R-KEY       (security P2-2 y revisión de a6ca4322) la clave privada vive en el
              móvil o en Savia Space, nunca en el equipo de los agentes
              (LAW-HUMAN-002), y la spec no enmienda esa ley.
  R-ACTIVATION (revisión de a6ca4322) `run --policy` no se activa antes de la
              enmienda humana de S4.
  R-WFEXEC    (security P1-1 sobre 9f88dd10) la exclusión forzosa incluye (d),
              el código que ejecutan los workflows, derivado de `origin/main` con
              cierre transitivo, con STOP fail-closed si la derivación falla, y
              AC-11 lo prueba con un caso directo y uno solo transitivo.
  R-WFIMPORT  (security P1-1 sobre 66ee1659) el cierre de (d) sigue imports de
              Python, source/. de bash y rutas relativas; lo no resoluble excluye
              el directorio; semillas sin lista de prefijos y con normalización.
  R-GUARDVIAS (security P2-2 sobre 66ee1659) el guard niega gh api .../merge y
              git push a main.
  R-AUTHOR    (correctness P2-5 sobre 9f88dd10) identidad de la autora definida.
  R-C3WIN     (correctness P2-2/P2-3 sobre 9f88dd10) C3 cuenta solo la ventana;
              R2.5 no dice «sin cambios»; límite del orquestador comprometido.
  R-GUARD     (security P2-3) el guard se activa con OR y el rollback lo respeta.
  R-HOLDEQ    (nota) la equivalencia por re-sync hereda también los HOLD.

Límite: es un comprobador **léxico**. Verifica que frases concretas del
contrato siguen en su sección y que el texto no retrocede; no demuestra que
la spec sea segura ni completa. Su verde no es una prueba de seguridad.
"""
import re
import sys


def section(text, title_re, level="###"):
    m = re.search(rf"^{level} {title_re}.*$", text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    end = re.search(rf"^#{{1,{len(level)}}} ", rest, re.M)
    return rest[: end.start()] if end else rest


def ac_bullet(text, ac):
    """Texto de la viñeta `- **AC-x ...` hasta la siguiente viñeta de AC o sección."""
    m = re.search(rf"^- \*\*{re.escape(ac)}\b.*$", text, re.M)
    if not m:
        return ""
    rest = text[m.start():]
    end = re.search(r"^(- \*\*AC-|#)", rest[1:], re.M)
    return rest[: end.start() + 1] if end else rest


def plan_row(plan, slice_id):
    m = re.search(rf"^\| {slice_id} \|.*$", plan, re.M)
    return m.group(0) if m else ""


AC_ID = r"AC-\d+[a-z]?"


def check(text):
    errs = []
    r1 = section(text, r"R1\b")
    r2 = section(text, r"R2\b")
    plan = section(text, r"Plan por slices", "##")
    s2 = plan_row(plan, "S2")

    # R-FORCED
    if "POLICY_FORCED_EXCLUDE" not in r1 or not re.search(r"desde S2", r1):
        errs.append("R-FORCED: R1 no dice que el ejecutor aplica (b)+(c) desde S2 con lista propia")
    if "POLICY_FORCED_EXCLUDE" not in r2:
        errs.append("R-FORCED: R2.3 no usa la lista propia del ejecutor")
    if "POLICY_FORCED_EXCLUDE" not in s2:
        errs.append("R-FORCED: el slice S2 no incluye la exclusión forzosa propia")
    ac11 = ac_bullet(text, "AC-11")
    if "ya existente" in ac11:
        errs.append("R-FORCED: AC-11 llama «ya existente» a rutas que risk-tier.py no excluye")
    for path in (".claude/hooks/", ".claude/agents/", "scripts/confidentiality-scan.sh",
                 "night-mode-guard.sh"):
        if path not in ac11:
            errs.append(f"R-FORCED: AC-11 no prueba la ruta {path}")

    # R-WFEXEC
    r3 = section(text, r"R3\b")
    if "WORKFLOW_EXEC_PATHS" not in r1 or "(a), (b), (c) y (d)" not in r1:
        errs.append("R-WFEXEC: R1 no aplica (d), el código que ejecutan los workflows")
    if "WORKFLOW_EXEC_PATHS" not in r2 or "cierre transitivo" not in r2 or "origin/main" not in r2:
        errs.append("R-WFEXEC: R2.3 no deriva (d) de origin/main con cierre transitivo")
    if "forced_exclude_error" not in r2:
        errs.append("R-WFEXEC: un error al derivar (d) no es STOP en R2.3")
    if "forced_exclude_error" not in r3:
        errs.append("R-WFEXEC: un error al derivar (d) no es STOP en R3")
    for path in ("scripts/changelog-consolidate.sh", "scripts/generate-capability-map.py",
                 "forced_exclude_error"):
        if path not in ac11:
            errs.append(f"R-WFEXEC: AC-11 no prueba {path}")
    if "WORKFLOW_EXEC_PATHS" not in s2:
        errs.append("R-WFEXEC: el slice S2 no incluye (d)")

    # R-WFIMPORT (security P1-1 sobre 66ee1659 y correctness P2-1/P2-2)
    if "`from x import ...`" not in r2:
        errs.append("R-WFIMPORT: el cierre de (d) no sigue los imports de Python")
    if "`source` y `.`" not in r2:
        errs.append("R-WFIMPORT: el cierre de (d) no sigue source/. de bash")
    if not re.search(r"\*\*Fail-closed ante lo que no se resuelve\*\*.*?todo el\s+directorio\*\*", r2, re.S):
        errs.append("R-WFIMPORT: lo que no se resuelve no excluye el directorio entero")
    if "**sin lista de prefijos**" not in r2:
        errs.append("R-WFIMPORT: las semillas de (d) dependen de una lista de prefijos")
    if "filtros `paths`/`paths-ignore` disparan, no ejecutan" not in r2:
        errs.append("R-WFIMPORT: no se define qué pasa con los filtros on.paths")
    if "un token con comodín" not in r2 or "se corta en el primer" not in r2:
        errs.append("R-WFIMPORT: falta la normalización de comodines y variables")
    for path in ("scripts/sam_model.py", "`mcp.json`", "on.push.paths", 'source "$VAR"'):
        if path not in ac11:
            errs.append(f"R-WFIMPORT: AC-11 no prueba {path}")
    if "manifiestos de dependencias" not in r1:
        errs.append("R-WFIMPORT: (b) no excluye los manifiestos de dependencias")
    if "los tests de los gates" not in r1:
        errs.append("R-WFIMPORT: (b) no excluye los tests de los gates")

    # R-ACDEF
    defined = set(re.findall(rf"^- \*\*({AC_ID})\b", text, re.M))
    cited = set(re.findall(rf"\b({AC_ID})\b", text))
    for ac in sorted(cited - defined):
        errs.append(f"R-ACDEF: {ac} se cita pero no tiene viñeta propia")

    # R-PLAN
    in_plan = set(re.findall(rf"\b({AC_ID})\b", plan))
    for ac in sorted(defined - in_plan):
        errs.append(f"R-PLAN: {ac} no aparece en el plan por slices")
    for ac in sorted(in_plan - defined):
        errs.append(f"R-PLAN: {ac} está en el plan pero no está definido")

    # R-RUNAC
    run_acs = sorted(defined & set(re.findall(rf"\b({AC_ID})\b", s2)))
    run_text = "\n".join(ac_bullet(text, ac) for ac in run_acs)
    for needle in ("max_merges", "max_parks_in_row", "universe: frozen", "revoke"):
        if needle not in run_text:
            errs.append(f"R-RUNAC: ningún AC de S2 prueba `{needle}` en run")

    # R-PENDING
    if re.search(r"hasta 30 min", text):
        errs.append("R-PENDING: queda un plazo de 30 min que no cuadra con el sondeo actual")
    if not re.search(r"`main_pending_timeout`.*\|\s*20 por defecto", r1):
        errs.append("R-PENDING: R1 no fija main_pending_timeout = 20 min por defecto")
    if "main_ci_strict" not in r2 or "action_required" not in r2:
        errs.append("R-PENDING: R2.2 no excluye action_required/stale del pass")
    if "action_required" not in ac_bullet(text, "AC-6"):
        errs.append("R-PENDING: AC-6 no prueba action_required")
    if "ceil(main_pending_timeout * 60 / MERGE_SPRINT_POLL_S)" not in r2:
        errs.append("R-PENDING: el sondeo no convierte minutos a segundos (20 min / 30 s debe dar 40)")

    # R-NOCHECKS
    if "main_sin_checks" not in r2:
        errs.append("R-NOCHECKS: R2 no define el caso sin check-runs")
    if "main_sin_checks" not in ac_bullet(text, "AC-6"):
        errs.append("R-NOCHECKS: AC-6 no prueba main_sin_checks")

    # R-GLOB
    if re.search(r"fnmatchcase` sobre la ruta relativa", text):
        errs.append("R-GLOB: los globs se evalúan con fnmatch sobre la ruta entera (`*` cruza `/`)")
    if "por segmentos" not in r2:
        errs.append("R-GLOB: R2.3 no define el matcher por segmentos")
    ac11c = ac_bullet(text, "AC-11c")
    if 'include: ["docs/*"]' not in ac11c or "toca `docs/x/y.md`" not in ac11c:
        errs.append("R-GLOB: AC-11c no tiene el negativo docs/* frente a docs/x/y")

    # R-KEY
    if not re.search(r"\*\*Requisito de la clave ed25519\.\*\*", r1):
        errs.append("R-KEY: R1 no exige que la clave ed25519 quede fuera del alcance del agente")
    if "La clave privada nunca reside en el equipo de los agentes" not in r1:
        errs.append("R-KEY: la clave privada debe quedar fuera del equipo de los agentes")
    if "Esta spec no enmienda LAW-HUMAN-002" not in r1:
        errs.append("R-KEY: R1 no declara que la spec no enmienda LAW-HUMAN-002")
    deps = section(text, r"Dependencias", "##")
    if "Activación bloqueada hasta la enmienda humana de S4" not in deps:
        errs.append("R-ACTIVATION: falta bloquear la activación hasta la enmienda humana de S4")

    # R-GUARDVIAS (security P2-2 sobre 66ee1659)
    r6 = section(text, r"R6\b")
    if "`/pulls/<n>/merge`" not in r6 or "un `git push` cuyo destino sea la rama `main`" not in r6:
        errs.append("R-GUARDVIAS: R6 no niega gh api .../merge ni git push a main")
    ac13 = ac_bullet(text, "AC-13")
    if "pulls/12/merge" not in ac13 or "refspec `HEAD:`" not in ac13:
        errs.append("R-GUARDVIAS: AC-13 no prueba gh api .../merge ni git push a main")

    # R-AUTHOR (correctness P2-5 sobre 9f88dd10)
    if "**Identidad de la autora.**" not in r2:
        errs.append("R-AUTHOR: R2.5 no define con qué se compara la autora")
    if "el `author` del registro" not in ac_bullet(text, "AC-9"):
        errs.append("R-AUTHOR: AC-9 no prueba el campo author del registro")

    # R-C3WIN (correctness P2-2 sobre 9f88dd10)
    contra = section(text, r"Contrapesos", "##")
    if "dentro de `[not_before, not_after)`" not in contra:
        errs.append("R-C3WIN: C3 no dice qué filas cuenta")
    if "dentro de la ventana" not in ac_bullet(text, "AC-4e"):
        errs.append("R-C3WIN: AC-4e no fija que sus revisiones están en la ventana")
    if "reutiliza sin cambios" in r2:
        errs.append("R-C3WIN: R2.5 dice «sin cambios» y a la vez cambia head_equivalent")
    if "no protegen frente a un orquestador comprometido" not in contra:
        errs.append("R-C3WIN: no se declara que C1-C3 no protegen frente al orquestador")

    # R-GUARD
    rollback = section(text, r"Rollback", "##")
    if re.search(r"se desactiva quitando `SAVIA_NIGHT_MODE`; sin grant", rollback):
        errs.append("R-GUARD: el rollback contradice la condición OR de R6")
    if "SAVIA_NIGHT_MODE" not in rollback or "revoke" not in rollback:
        errs.append("R-GUARD: el rollback no pide revoke y quitar SAVIA_NIGHT_MODE")
    if "OR" not in ac_bullet(text, "AC-13"):
        errs.append("R-GUARD: AC-13 no prueba el guard con grant vigente y sin SAVIA_NIGHT_MODE")

    # R-HOLDEQ
    if not re.search(r"hereda \*\*todas\*\* las revisiones.*también los HOLD", r2, re.S):
        errs.append("R-HOLDEQ: la equivalencia por re-sync no dice que hereda los HOLD")

    return errs


def main(argv):
    if len(argv) != 2:
        print("uso: se512_spec_check.py <spec.md>", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        print(f"no se puede leer: {exc}", file=sys.stderr)
        return 2
    errs = check(text)
    for e in errs:
        print(e, file=sys.stderr)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
