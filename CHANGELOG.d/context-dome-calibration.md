---
version_bump: patch
section: Fixed
---

### Fixed

- context-dome-generate: solo acepta <proyecto>.json o <proyecto>-<timestamp>.json con project coincidente, sin fallback a otro proyecto (aislamiento N4, mismo criterio que #1248), extrae de verdad las decisiones (grep -E, solo HEAD), no pisa cúpulas editadas a mano ni reescribe sin cambios (tampoco tras commitear la cúpula; huella en python3, portable a macOS), frontmatter YAML válido con owners/rutas arbitrarios, --module sin inyección de código, rutas inseguras y symlinks rechazados, exit 2 ante scan ilegible, exit 1 ante --min-risk inválido o proyecto inexistente; nuevo --redact-owners y --force

