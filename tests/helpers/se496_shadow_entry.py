#!/usr/bin/env python3
"""Punto de entrada del adaptador en sombra SE-343 SOLO para tests (SE-496 F1).

Como `se496_kernel_entry.py`: traduce `SAVIA_AUTHORITY_*` del entorno a la inyección en proceso del
kernel (raíz del mundo hermético, reloj, perfil y herramientas falsas). Ningún hook ni script de
producción lo invoca; el adaptador real no lee variables de entorno para redirigirse.
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import authority_kernel as k  # noqa: E402
import authority_shadow_se343 as shadow  # noqa: E402
from se496_kernel_entry import overrides_from  # noqa: E402

if __name__ == "__main__":
    k.OVERRIDES.clear()
    k.OVERRIDES.update(overrides_from(os.environ))
    shadow.cli()
