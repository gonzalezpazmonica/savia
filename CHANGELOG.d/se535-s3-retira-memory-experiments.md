---
version_bump: patch
section: Removed
---

### Removed

- SE-535 S3: se retira `scripts/memory-experiments.py` (tres experimentos de memoria de marzo) y su suite `tests/evals/test-memory-experiments.bats`. Ningún otro guion, orden ni test lo invocaba. El fixture `tests/evals/memory-benchmark-store.jsonl` se conserva: lo usan otras suites. Se recupera del historial de git.
