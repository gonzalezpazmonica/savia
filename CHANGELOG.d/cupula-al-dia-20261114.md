---
version_bump: patch
section: Fixed
---

### Fixed

- Cúpula savia-docs: index-docs.sh sincroniza solo lo versionado, retira lo borrado y deja el commit de origen (Source-Commit); vaults dome index le pasa bien los argumentos; vaults-freshness.sh deja de fallar con variable sin asignar, mide el atraso respecto a docs/ y avisa en validate-ci-local.sh --quick; vault_rag en perfil lean conserva la fecha (modified).
- index-docs.sh lee el contenido del commit de origen (no del disco) y omite symlinks; rechaza `--branch` sobre la rama del árbol vivo; `vaults dome index` solo acepta savia-docs y valida el nombre; el trailer Source-Commit solo se usa si es un SHA.

