"""Skill python-backed de ejemplo (template)."""


def run(query: str, limit: int = 5) -> str:
    """Contrato mínimo: función `run` invocable con kwargs tipados.

    Sustituye esta implementación por la lógica real del skill. Todo local
    (CRIT-001): no llamadas de red a proveedores cloud.
    """
    return f"example_skill.run(query={query!r}, limit={limit}) OK"
