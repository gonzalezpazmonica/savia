---
version_bump: patch
section: Fixed
---

### Fixed

- Savia Mobile: `gradle-wrapper.properties` fija `distributionSha256Sum` al SHA-256 oficial de Gradle 8.13 y un test bats verifica que el `gradle-wrapper.jar` versionado coincide con el checksum oficial del wrapper (alerta BinaryArtifacts #60). Añadir wrapper-validation al CI queda propuesto, por tocar `.github/`.
