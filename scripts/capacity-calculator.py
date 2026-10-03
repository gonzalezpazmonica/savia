#!/usr/bin/env python3
"""
capacity-calculator.py — Cálculo de capacidades del equipo
===========================================================
Calcula horas disponibles reales por persona, cruza con la carga asignada
y genera alertas de sobre/sub-asignación.

Fórmula (skill capacity-planning):
  horas_disponibles = (dias_habiles - dias_off) * horas_dia * factor_foco
  dias_off = unión de días off personales y de equipo que caen en día hábil

Uso:
  python3 scripts/capacity-calculator.py --items /tmp/sprint-items.json
  python3 scripts/capacity-calculator.py --items items.json --capacities caps.json \\
      --team-days-off teamdaysoff.json --sprint-start 2026-09-07 --sprint-end 2026-09-18

Entradas aceptadas:
  --items         lista JSON, objeto API {"value": [...]} o stream de objetos
                  (salida de `azdevops-queries.sh items`).
  --capacities    salida de `azdevops-queries.sh capacities` (stream de
                  {persona, actividades, dias_off}), respuesta API cruda
                  {"value": [{teamMember, activities, daysOff}]} o mapa
                  {persona: {"horas_disponibles": N}}.
  --team-days-off respuesta API teamdaysoff {"daysOff": [{start, end}]} o
                  lista de fechas YYYY-MM-DD.
Los números admiten coma decimal (locale es_ES): "4,5".

Exit codes: 0 ok · 1 error de entrada (fichero, JSON, valor) · 2 argumento inválido.
Requiere: Python 3.8+
"""

import json
import argparse
import sys
from datetime import datetime, date, timedelta
from typing import Optional


# ── CONSTANTES (editar según tu entorno) ──────────────────────────────────────
TEAM_HOURS_PER_DAY: float = float(8)           # horas laborables por día
FOCUS_FACTOR: float = float(0.75)              # factor de foco (75% productivo)
OVERLOAD_THRESHOLD: float = float(1.0)         # > 100% = sobre-cargado
WARNING_THRESHOLD: float = float(0.85)         # 85-100% = al límite
DEFAULT_SPRINT_DAYS: int = 10                  # sin fechas: sprint de 2 semanas
SIN_ASIGNAR = "Sin asignar"

# Festivos de la Comunidad de Madrid (actualizar anualmente)
FESTIVOS_2026: list = [
    date(2026, 1, 1),   # Año Nuevo
    date(2026, 1, 6),   # Reyes
    date(2026, 4, 2),   # Jueves Santo
    date(2026, 4, 3),   # Viernes Santo
    date(2026, 5, 1),   # Día del Trabajo
    date(2026, 5, 2),   # Comunidad de Madrid
    date(2026, 10, 12), # Día de la Hispanidad
    date(2026, 11, 1),  # Todos los Santos
    date(2026, 11, 9),  # Almudena
    date(2026, 12, 6),  # Constitución
    date(2026, 12, 8),  # Inmaculada
    date(2026, 12, 25), # Navidad
]
FESTIVOS_YEARS = {d.year for d in FESTIVOS_2026}


class InputError(Exception):
    """Entrada inválida (fichero, JSON o valor); se reporta sin traceback."""


# ── HELPERS ────────────────────────────────────────────────────────────────────
def parse_num(valor, campo: str = "valor") -> float:
    """Convierte a float admitiendo coma decimal ("4,5"). None/"" cuentan como 0."""
    if valor is None or valor == "":
        return 0.0
    if isinstance(valor, bool):
        raise InputError(f"valor no numérico en {campo}: {valor!r}")
    if isinstance(valor, (int, float)):
        return float(valor)
    s = str(valor).strip()
    if "," in s:
        s = s.replace(".", "").replace(",", ".")
    try:
        return float(s)
    except ValueError:
        raise InputError(f"valor no numérico en {campo}: {valor!r}") from None


def arg_float(lo: float, hi: float):
    """Tipo argparse: float en (lo, hi], con coma decimal."""
    def _tipo(s: str) -> float:
        try:
            v = parse_num(s, "argumento")
        except InputError as e:
            raise argparse.ArgumentTypeError(str(e))
        if not lo < v <= hi:
            raise argparse.ArgumentTypeError(f"{s} fuera de rango ({lo}, {hi}]")
        return v
    return _tipo


def dias_habiles_entre(inicio: date, fin: date, festivos: Optional[list] = None) -> list:
    """Devuelve la lista de días hábiles entre inicio y fin (ambos incluidos)."""
    festivos = FESTIVOS_2026 if festivos is None else festivos
    dias = []
    actual = inicio
    while actual <= fin:
        if actual.weekday() < 5 and actual not in festivos:  # L-V, no festivo
            dias.append(actual)
        actual += timedelta(days=1)
    return dias


def parse_date(s: str) -> date:
    """Parsea fecha en formato YYYY-MM-DD o YYYY-MM-DDTHH:MM:SSZ."""
    try:
        return datetime.fromisoformat(str(s)[:10]).date()
    except ValueError:
        raise InputError(f"fecha inválida: {s!r} (esperado YYYY-MM-DD)") from None


def expandir_rangos(rangos) -> set:
    """[{start, end}] o ["YYYY-MM-DD"] -> conjunto de fechas (extremos incluidos)."""
    dias: set = set()
    for r in rangos or []:
        if isinstance(r, dict):
            ini, fin = parse_date(r.get("start")), parse_date(r.get("end") or r.get("start"))
        else:
            ini = fin = parse_date(r)
        if fin < ini:
            raise InputError(f"rango de días off invertido: {r!r}")
        while ini <= fin:
            dias.add(ini)
            ini += timedelta(days=1)
    return dias


def semaforo(ratio: Optional[float]) -> str:
    """Devuelve el semáforo según el ratio de utilización (umbrales de SKILL.md)."""
    if ratio is None:
        return "⚪ SIN DATOS"
    if ratio > OVERLOAD_THRESHOLD:
        return "🔴 SOBRE-CARGADO"
    if ratio >= WARNING_THRESHOLD:
        return "🟡 AL LÍMITE"
    return "🟢 OK"


# ── CARGA DE FICHEROS ──────────────────────────────────────────────────────────
def load_json_values(path: str) -> list:
    """Lee uno o varios valores JSON concatenados (stream de `jq '.value[]'`)."""
    with open(path, encoding="utf-8") as f:
        texto = f.read()
    dec = json.JSONDecoder()
    valores, i = [], 0
    while True:
        while i < len(texto) and texto[i].isspace():
            i += 1
        if i >= len(texto):
            return valores
        try:
            valor, i = dec.raw_decode(texto, i)
        except json.JSONDecodeError as e:
            raise InputError(f"JSON inválido en {path}: {e}") from None
        valores.append(valor)


def _aplanar(valores: list, path: str) -> list:
    registros = []
    for v in valores:
        if isinstance(v, dict) and isinstance(v.get("value"), list):
            registros.extend(v["value"])
        elif isinstance(v, list):
            registros.extend(v)
        else:
            registros.append(v)
    for r in registros:
        if not isinstance(r, dict):
            raise InputError(f"registro no es un objeto JSON en {path}: {r!r}")
    return registros


def load_items(path: str) -> list:
    return _aplanar(load_json_values(path), path)


def load_capacities(path: str) -> dict:
    """persona -> {"horas_disponibles": N} (mapa) o {"horas_dia": h, "dias_off": set}."""
    valores = load_json_values(path)
    if len(valores) == 1 and isinstance(valores[0], dict) and "value" not in valores[0] \
            and "persona" not in valores[0] and "teamMember" not in valores[0]:
        mapa = {}
        for persona, datos in valores[0].items():
            if not isinstance(datos, dict) or "horas_disponibles" not in datos:
                raise InputError(f"capacidad sin horas_disponibles para {persona!r} en {path}")
            mapa[persona] = {"horas_disponibles": parse_num(datos["horas_disponibles"], persona)}
        return mapa
    caps = {}
    for rec in _aplanar(valores, path):
        persona = rec.get("persona") or (rec.get("teamMember") or {}).get("displayName")
        if not persona:
            raise InputError(f"registro de capacidad sin persona en {path}: {rec!r}")
        actividades = rec.get("actividades", rec.get("activities")) or []
        horas_dia = sum(parse_num(a.get("capacityPerDay"), persona) for a in actividades)
        caps[persona] = {
            "horas_dia": horas_dia,
            "dias_off": expandir_rangos(rec.get("dias_off", rec.get("daysOff"))),
        }
    return caps


def load_team_days_off(path: str) -> set:
    valores = load_json_values(path)
    rangos = []
    for v in valores:
        if isinstance(v, dict):
            rangos.extend(v.get("daysOff") or [])
        elif isinstance(v, list):
            rangos.extend(v)
        else:
            rangos.append(v)
    return expandir_rangos(rangos)


# ── CÁLCULO DE CAPACITY ────────────────────────────────────────────────────────
def calcular_capacity_persona(
    inicio_sprint: date,
    fin_sprint: date,
    horas_dia: float = TEAM_HOURS_PER_DAY,
    factor_foco: float = FOCUS_FACTOR,
    dias_off_persona: Optional[set] = None,
) -> dict:
    """Calcula la capacity real de una persona para el sprint."""
    dias_habiles = dias_habiles_entre(inicio_sprint, fin_sprint)
    off = set(dias_off_persona or [])
    dias_disponibles = [d for d in dias_habiles if d not in off]

    horas_disponibles = len(dias_disponibles) * horas_dia * factor_foco

    return {
        "dias_habiles_sprint": len(dias_habiles),
        "dias_off": len(dias_habiles) - len(dias_disponibles),
        "dias_disponibles": len(dias_disponibles),
        "horas_por_dia": horas_dia,
        "factor_foco": factor_foco,
        "horas_disponibles": round(horas_disponibles, 1),
    }


def _campo(item: dict, clave: str, campo_api: str):
    valor = item.get(clave)
    return valor if valor is not None else item.get("fields", {}).get(campo_api)


def calcular_carga_por_persona(items: list) -> dict:
    """Agrupa el RemainingWork por persona desde los work items del sprint."""
    carga: dict = {}
    for item in items:
        persona = _campo(item, "asignado", "System.AssignedTo")
        if isinstance(persona, dict):
            persona = persona.get("displayName")
        persona = persona or SIN_ASIGNAR

        remaining = parse_num(_campo(item, "restante_h", "Microsoft.VSTS.Scheduling.RemainingWork"),
                              f"restante_h de {persona}")
        completed = parse_num(_campo(item, "completado_h", "Microsoft.VSTS.Scheduling.CompletedWork"),
                              f"completado_h de {persona}")

        if persona not in carga:
            carga[persona] = {"remaining_h": 0.0, "completed_h": 0.0, "items": 0}
        carga[persona]["remaining_h"] += remaining
        carga[persona]["completed_h"] += completed
        carga[persona]["items"] += 1

    return carga


def analizar(items: list, capacities: Optional[dict] = None, team_off: Optional[set] = None,
             inicio: Optional[date] = None, fin: Optional[date] = None,
             horas_dia: float = TEAM_HOURS_PER_DAY, foco: float = FOCUS_FACTOR) -> dict:
    """Carga + capacidad + utilización + semáforo por persona (tabla y JSON comparten esto)."""
    carga = calcular_carga_por_persona(items)
    capacities, team_off = capacities or {}, team_off or set()
    # Sprint planning: los miembros con capacidad configurada aparecen aunque no tengan items
    for persona in capacities:
        carga.setdefault(persona, {"remaining_h": 0.0, "completed_h": 0.0, "items": 0})
    for persona, datos in carga.items():
        datos["remaining_h"] = round(datos["remaining_h"], 2)
        datos["completed_h"] = round(datos["completed_h"], 2)
        if persona == SIN_ASIGNAR:
            datos.update(horas_disponibles=None, utilizacion_pct=None, estado="— SIN ASIGNAR")
            continue
        cfg = capacities.get(persona, {})
        if "horas_disponibles" in cfg:
            disponible = cfg["horas_disponibles"]
        elif inicio and fin:
            off = set(cfg.get("dias_off", set())) | team_off
            disponible = calcular_capacity_persona(
                inicio, fin, cfg.get("horas_dia", horas_dia), foco, off)["horas_disponibles"]
        else:
            disponible = round(DEFAULT_SPRINT_DAYS * cfg.get("horas_dia", horas_dia) * foco, 1)
        asignado = datos["remaining_h"] + datos["completed_h"]
        ratio = asignado / disponible if disponible > 0 else None
        datos["horas_disponibles"] = disponible
        datos["utilizacion_pct"] = round(ratio * 100, 1) if ratio is not None else None
        datos["estado"] = semaforo(ratio)
    return carga


# ── REPORTE ────────────────────────────────────────────────────────────────────
def generar_reporte(
    items: list,
    carga: dict,
    inicio_sprint: Optional[date] = None,
    fin_sprint: Optional[date] = None,
    sprint_days_left: int = 0,
    horas_dia: float = TEAM_HOURS_PER_DAY,
    foco: float = FOCUS_FACTOR,
) -> None:
    """Genera el reporte de capacity en terminal."""
    print("\n" + "=" * 70)
    print("  CAPACITY REPORT — SPRINT ACTUAL")
    print("=" * 70)

    if inicio_sprint and fin_sprint:
        print(f"  Período: {inicio_sprint.strftime('%d/%m/%Y')} → {fin_sprint.strftime('%d/%m/%Y')}")
        dias = dias_habiles_entre(inicio_sprint, fin_sprint)
        print(f"  Días hábiles del sprint: {len(dias)}")

    if sprint_days_left:
        capacity_restante = sprint_days_left * horas_dia * foco
        print(f"  Días restantes: {sprint_days_left} | Capacity restante por persona: {capacity_restante:.0f}h")

    print()
    print(f"  {'Persona':<22} {'Asignado':>10} {'Completado':>11} {'Disponible':>11} {'Util%':>7}  Estado")
    print("  " + "-" * 68)

    total_asignado = 0.0
    total_completado = 0.0
    alertas = []

    for persona, datos in sorted(carga.items()):
        asignado = datos["remaining_h"] + datos["completed_h"]
        completado = datos["completed_h"]
        disp = datos["horas_disponibles"]
        util = datos["utilizacion_pct"]
        disp_txt = f"{disp:>9.1f}h" if disp is not None else f"{'—':>10}"
        util_txt = f"{util:>6.0f}%" if util is not None else f"{'—':>7}"

        print(f"  {persona:<22} {asignado:>9.1f}h {completado:>9.1f}h {disp_txt} {util_txt}  {datos['estado']}")

        total_asignado += asignado
        total_completado += completado

        if "SOBRE-CARGADO" in datos["estado"]:
            alertas.append(f"⚠️  {persona}: SOBRE-CARGADO ({util:.0f}% de capacity)")
        elif "AL LÍMITE" in datos["estado"]:
            alertas.append(f"⚡ {persona}: AL LÍMITE ({util:.0f}% de capacity)")

    print("  " + "-" * 68)
    print(f"  {'TOTAL EQUIPO':<22} {total_asignado:>9.1f}h {total_completado:>9.1f}h")

    if alertas:
        print("\n  ALERTAS:")
        for alerta in alertas:
            print(f"    {alerta}")

    # Resumen de items por estado
    estados: dict = {}
    for item in items:
        estado_item = _campo(item, "estado", "System.State") or "Desconocido"
        estados[estado_item] = estados.get(estado_item, 0) + 1

    print("\n  ITEMS POR ESTADO:")
    for estado_item, count in sorted(estados.items()):
        barra = "█" * count
        print(f"    {estado_item:<15} {barra} ({count})")

    print("=" * 70 + "\n")


# ── MAIN ───────────────────────────────────────────────────────────────────────
def die(msg: str, code: int) -> None:
    print(f"[ERROR] {msg}", file=sys.stderr)
    sys.exit(code)


def main():
    parser = argparse.ArgumentParser(
        description="Calculadora de capacidades del equipo para Azure DevOps / Scrum"
    )
    parser.add_argument("--items", default="/tmp/sprint-items.json",
                        help="JSON con los work items del sprint (lista, API o stream)")
    parser.add_argument("--capacities", default=None,
                        help="JSON con las capacidades de Azure DevOps (opcional)")
    parser.add_argument("--team-days-off", default=None,
                        help="JSON teamdaysoff de Azure DevOps o lista de fechas (opcional)")
    parser.add_argument("--sprint-start", default=None,
                        help="Fecha inicio sprint (YYYY-MM-DD)")
    parser.add_argument("--sprint-end", default=None,
                        help="Fecha fin sprint (YYYY-MM-DD)")
    parser.add_argument("--sprint-days-left", type=int, default=0,
                        help="Días restantes del sprint (para alertas)")
    parser.add_argument("--team-hours-per-day", type=arg_float(0, 24), default=TEAM_HOURS_PER_DAY,
                        help="Horas de trabajo por día, (0, 24] (default: 8)")
    parser.add_argument("--focus-factor", type=arg_float(0, 1), default=FOCUS_FACTOR,
                        help="Factor de foco, (0, 1] (default: 0.75)")
    parser.add_argument("--output-json", action="store_true",
                        help="Emitir resultado en JSON en lugar de tabla legible")

    args = parser.parse_args()

    if bool(args.sprint_start) != bool(args.sprint_end):
        die("--sprint-start y --sprint-end van juntos: indica las dos fechas o ninguna", 2)
    if args.sprint_days_left < 0:
        die("--sprint-days-left no puede ser negativo", 2)
    try:
        inicio_sprint = parse_date(args.sprint_start) if args.sprint_start else None
        fin_sprint = parse_date(args.sprint_end) if args.sprint_end else None
    except InputError as e:
        die(str(e), 2)
    if inicio_sprint and fin_sprint and fin_sprint < inicio_sprint:
        die(f"--sprint-end ({fin_sprint}) es anterior a --sprint-start ({inicio_sprint})", 2)

    try:
        items = load_items(args.items)
    except FileNotFoundError:
        print(f"[ERROR] Fichero de items no encontrado: {args.items}", file=sys.stderr)
        print("Ejecuta primero: ./scripts/azdevops-queries.sh items > /tmp/sprint-items.json", file=sys.stderr)
        sys.exit(1)
    except (InputError, OSError) as e:
        die(str(e), 1)

    try:
        capacities = load_capacities(args.capacities) if args.capacities else None
        team_off = load_team_days_off(args.team_days_off) if args.team_days_off else None
        carga = analizar(items, capacities, team_off, inicio_sprint, fin_sprint,
                         args.team_hours_per_day, args.focus_factor)
    except FileNotFoundError as e:
        die(f"fichero no encontrado: {e.filename}", 1)
    except (InputError, OSError) as e:
        die(str(e), 1)

    if inicio_sprint and fin_sprint and team_off is None and \
            {inicio_sprint.year, fin_sprint.year} - FESTIVOS_YEARS:
        print("[WARN] los festivos por defecto solo cubren "
              f"{sorted(FESTIVOS_YEARS)} (Comunidad de Madrid); pasa --team-days-off "
              "para descontar los festivos de este sprint", file=sys.stderr)

    if args.output_json:
        resultado = {
            "sprint": {
                "inicio": str(inicio_sprint) if inicio_sprint else None,
                "fin": str(fin_sprint) if fin_sprint else None,
                "dias_restantes": args.sprint_days_left,
            },
            "carga_por_persona": carga,
        }
        print(json.dumps(resultado, indent=2, ensure_ascii=False))
    else:
        generar_reporte(items, carga, inicio_sprint, fin_sprint, args.sprint_days_left,
                        args.team_hours_per_day, args.focus_factor)


if __name__ == "__main__":
    main()
