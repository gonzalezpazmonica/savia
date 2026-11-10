---
version_bump: patch
section: Security
---

### Security

- Seguridad: `exit-purge-verify.sh` daba CLEAN con referencias vivas a un engagement olvidado en ficheros `exit-*` o con `audit-trail` en la ruta, ignoraba `--exclude-dir`, daba CLEAN si una carpeta no se podía leer, marcaba el tombstone como `verified` aunque la verificación encontrara referencias y ejecutaba código Python inyectado en el nombre del engagement. Ahora: rutas permitidas exactas, `UNKNOWN`/exit 2 si la búsqueda falla, nombre validado y pasado por argv, estado `dirty`/`unknown` en el tombstone.
- Seguridad: `mobile-security-scan.sh` descartaba los hallazgos de `android-manifest-audit.sh`; un APK `debuggable` con código inocuo salía `clean`. Los hallazgos del manifiesto cuentan como `findings`; manifiesto o auditor ausentes quedan como hueco.
- Fix: `compliance-eval.py` reventaba con traceback sin PyYAML (el parser de reserva perdía la estructura), con YAML malformado o con un unknown que no es objeto. Ahora el resultado es `UNKNOWN` (fail-safe).
- Calidad S03u: pruebas de comportamiento validadas por mutación para exit-purge-verify, mobile-security-scan, compliance-eval y egress-gate; medición previa de 14 candidatos en `docs/evidence/s03u-medicion-previa.md`.

