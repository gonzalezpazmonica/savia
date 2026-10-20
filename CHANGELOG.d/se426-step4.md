---
version_bump: patch
section: Security
---

### Security

- SE-426 paso 4: nueva acción `confidentiality-sign.sh resign` (firma, exige clave real y verifica la firma escrita). `resolve-pr-conflicts.sh` (auto-rebase) y `changelog-consolidate.yml` la usan y ya no empujan en silencio una firma obsoleta si falta el secreto; el secreto de CI con salto de línea final se trata como el fichero local.
