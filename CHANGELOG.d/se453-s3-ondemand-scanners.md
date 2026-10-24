---
version_bump: patch
section: Changed
---

### Changed

- **SE-453 S3 por demanda**: `mobile-security-scan.sh`, `security-scan.sh` y `vuln-scan.sh` emiten la línea `gate-result` (clean/findings/unknown). En mobile, apktool ausente, descompilación vacía, modo `dynamic` (no implementado) o informe MobSF sin triaje quedan como hueco y el JSON del informe lleva `result` y `gaps`. En security-scan y vuln-scan, un grep que no puede leer el árbol (rc ≥ 2) o un directorio de hooks vacío dejan de contarse como pass: `--ci` avisa `WARN`, registra en `output/unmeasured-gates.jsonl` y con `SAVIA_GATE_UNKNOWN=block` sale 1. Códigos existentes sin renumerar.

