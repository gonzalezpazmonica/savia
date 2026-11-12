#!/usr/bin/env python3
"""Punto de entrada del kernel SOLO para tests (SE-496 F0).

El kernel real (`scripts/lib/authority_kernel.py`) no lee variables de entorno para redirigirse.
Este envoltorio vive en tests/ y es el único que traduce `SAVIA_AUTHORITY_*` del entorno a la
inyección en proceso (`authority_kernel.OVERRIDES`): raíz del mundo hermético, reloj fijo, perfil y
herramientas falsas. Ningún hook ni script de producción lo invoca.
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
import authority_kernel as k  # noqa: E402

PREFIX = "SAVIA_AUTHORITY_"


def overrides_from(environ):
    """Solo con SAVIA_AUTHORITY_TEST=1; el marcador no se copia (test_mode = hay inyección)."""
    if environ.get(PREFIX + "TEST") != "1":
        return {}
    return {n: v for n, v in environ.items() if n.startswith(PREFIX) and n != PREFIX + "TEST"} or {"_": "1"}


if __name__ == "__main__":
    k.OVERRIDES.clear()
    k.OVERRIDES.update(overrides_from(os.environ))
    k.cli()
