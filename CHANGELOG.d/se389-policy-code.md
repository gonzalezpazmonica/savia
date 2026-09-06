---
version_bump: patch
section: Added
---
- **SE-389 Regulatory Policy-as-Code (MVP EU AI Act Art.50)**: registry regulatorio con ciclo de vida DRAFT→LEGAL_REVIEW_PENDING→HUMAN_VALIDATED→EXECUTABLE (fail-safe: no-EXECUTABLE nunca enforza), ComplianceContext schema (origen EXPLICIT/DERIVED/INFERRED/UNKNOWN), evaluador determinista sin LLM (ALLOW/ALLOW_WITH_DISCLOSURE/BLOCK/UNKNOWN/NOT_APPLICABLE), receipt compliance con policy_version+context_hash, monotonía §31. Policy Art50 en LEGAL_REVIEW_PENDING — requiere validación humana para EXECUTABLE. Bats 7/7.
