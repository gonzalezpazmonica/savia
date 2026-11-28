"""Plugin de pytest (SE-537): salta los tests de Sonora que necesitan pesos de modelo.

En CI no se descargan modelos. En lugar de ignorar ficheros enteros, cada test
que carga pesos se nombra en una lista (``nodeid | motivo``) y se marca como
skip con su motivo, de modo que aparece en el resumen ``-rs``.

Falla cerrado:
- si falta el fichero de la lista;
- si la lista nombra un test que la colección no encuentra (lista obsoleta).

``SONORA_WITH_WEIGHTS=1`` desactiva los saltos (máquina con los pesos en caché).
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

ENV_FILE = "SONORA_WEIGHTS_SKIP_FILE"
ENV_WITH = "SONORA_WITH_WEIGHTS"


def _load(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        nodeid, sep, reason = line.partition(" | ")
        if not sep or not nodeid.strip() or not reason.strip():
            raise pytest.UsageError(f"{path}: entrada sin «nodeid | motivo»: {raw!r}")
        entries[nodeid.strip()] = reason.strip()
    return entries


def _matches(item_nodeid: str, listed: str) -> bool:
    # La lista usa rutas relativas a la app; pytest puede anteponer directorios
    # según el rootdir, así que se compara por sufijo de segmento completo.
    return item_nodeid == listed or item_nodeid.endswith("/" + listed)


def pytest_collection_modifyitems(config, items):
    if os.environ.get(ENV_WITH) == "1":
        return
    raw = os.environ.get(ENV_FILE)
    if not raw:
        raise pytest.UsageError(f"{ENV_FILE} no está definido")
    path = Path(raw)
    if not path.is_file():
        raise pytest.UsageError(f"{ENV_FILE}={raw} no existe")
    entries = _load(path)
    seen: set[str] = set()
    for item in items:
        for listed, reason in entries.items():
            if _matches(item.nodeid, listed):
                item.add_marker(pytest.mark.skip(reason=f"necesita pesos de modelo: {reason}"))
                seen.add(listed)
                break
    missing = sorted(set(entries) - seen)
    if missing:
        raise pytest.UsageError(
            "la lista de pesos nombra tests que no existen: " + ", ".join(missing)
        )
