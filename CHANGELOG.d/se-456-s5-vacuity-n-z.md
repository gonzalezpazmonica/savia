---
version_bump: patch
section: Fixed
---

### Fixed

- SE-456 S5: 37 aserciones anuladas o sin efecto reparadas en tests (n-z y carpetas), con 8 defectos destapados corregidos (token-estimator, pipeline-engine, rule-usage-analyzer, adapter-interface, exchange-ledger, federation-drill, prompt-suggestion-engine, agent-trace-log). Línea base de vacuidad 49 -> 21 tras fusionar #1351 (antes de fusionar, 58 -> 21). `federation-drill.sh compromised <id>` ahora revoca de verdad la tarjeta (documentado en `--help`; `FEDERATION_ROOT` para ensayar), valida el id (`[A-Za-z0-9._-]`, sin `..`) y pasa las rutas a Python por `argv`; `rule-usage-analyzer.sh` valida `--root`/`--output`; `pipeline-engine.sh` no crea directorio de salida si no hay etapas.

