---
version_bump: patch
section: Added
---

### Added

- SE-537: los tests de Savia Sonora corren en el CI raíz (`.github/workflows/sonora-tests.yml`, jobs de backend pytest con Python 3.12 y de frontend vitest y tsc) y en local con `scripts/sonora-tests.sh [backend|frontend|all]`. Dependencias solo desde lockfile (`uv sync --frozen`, `pnpm@10.34.9 install --frozen-lockfile`), acciones fijadas por SHA y sin descargas de modelos: los tests que cargan pesos se saltan uno a uno con motivo (`scripts/sonora-tests-weights.txt`, plugin `scripts/lib/sonora_weights_skip.py`, que falla cerrado si la lista queda obsoleta).

### Fixed

- `projects/savia-sonora/app/uv.lock`: la raíz del lock se llamaba `voiceflow` tras el cambio de nombre a `savia-transcriptor` en `pyproject.toml`, y `uv sync --frozen` fallaba con «Missing workspace member».
