---
version_bump: patch
section: Security
---

### Security

- SaviaVaults (SE-424 H5): ninguna ruta sale de su cúpula; leer, escribir, comparar, historial y borrar pasan por VaultSecurity.contain (rechaza `..`, absolutas, `%2e%2e`/`%2f`, barras invertidas, enlaces que salen y metadatos internos), y git recibe `--` antes de la ruta.
- SaviaVaults (SE-424 H5): el A2A local ya no escribe sin credencial en ningún nivel (401) y rechaza (403) cabeceras Host que no sean de bucle local, IP literal, el host de escucha o `SAVIA_A2A_ALLOWED_HOSTS`. Al actualizar: quien escribía por A2A sin token necesita un token `writer` (`SLDC_VAULTS_TOKEN` en `scripts/sldc-context-loop.sh`).

