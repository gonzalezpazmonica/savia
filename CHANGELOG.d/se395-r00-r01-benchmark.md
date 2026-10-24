---
version_bump: minor
section: Added
---

### Added

- **SE-395 R00+R01**: protocolo preregistrado (`projects/savia-vaults/docs/SE-395-adaptive-connectivity-protocol.md`), dataset congelado de 180 consultas (9 estratos × 20) y baseline reproducible sin red en `eval/adaptive/`, generados por `src/federation/benchmark/`; `FederatedSearchEngine` acepta `opts.client` inyectable. Ningún flag adaptativo activado. Tests `tests/unit/federation/benchmark.test.ts`.

- **SE-395 R00+R01 (correcciones de revisión)**: latencia warm medida, ranking y tokens sobre el mismo top-k, orden ordinal, validador ampliado, hash de umbrales fijado en test y decisión de fase NEEDS_MORE_EVIDENCE.
