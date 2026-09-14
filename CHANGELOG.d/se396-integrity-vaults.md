---
version_bump: minor
section: Added
---
- **SE-395 vault isolation**: `projects/savia-vaults/src/registry/domes.ts` expone
  `config` en `VaultInstance` y `projects/savia-vaults/src/server/mcp.ts` aísla
  motores por dome; test e2e `tests/e2e/mcp-dome-isolation.test.ts` verifica que
  un lector de un dome no alcanza el grafo/query/introspección de otro.
- **SE-396 integrity extensions**: `contracts.py` valida `observed_at` en RFC3339
  estricto y `verify_observation` falla cerrado (`EVIDENCE_VERIFIER_UNAVAILABLE`);
  `autonomy.py` correlaciona y firma receipts; `autonomy_doctor.py` marca
  evidencia `NOT_VERIFIED`; `codex_profile.py` separa `SYNTHETIC` de
  `OPERATIONAL_PROBE`; `config.py` cierra el hash de domain packs; `preflight.py`
  rechaza verifier no disponible. Tests `test_doctor_integrity.py`,
  `test_evidence_integrity.py`.
