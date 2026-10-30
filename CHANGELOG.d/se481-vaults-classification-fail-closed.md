---
version_bump: minor
section: Security
---

### Security

- SE-481 Savia Vaults: una clasificación `confidentiality` explícita que no se puede interpretar (YAML roto, valor no textual, nivel desconocido, caracteres invisibles) deja la nota en cuarentena en todas las vistas, el indexador y vault_write; vault_health la cuenta por código y `savia-vaults dome quarantine` lista las rutas en local.
- SE-481 vault_rag revalida cada hit de nota contra su estado actual en disco (borrada, fuera de nivel o en cuarentena) sin esperar al siguiente sync; el descarte se cuenta en `degradation`.
- SE-481 BM25 v2: las negaciones (no, not, ni, sin, nada) dejan de ser stopwords y los identificadores con guiones y dígitos se indexan también como término completo; `Confidentiality` incluye N4B.

