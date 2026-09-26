---
name: test-runner
permission_level: L4
description: >
  Ejecución de tests y verificación de cobertura post-commit. Ejecuta suite completa de tests,
  valida que todos pasan, verifica cobertura contra umbral mínimo (TEST_COVERAGE_MIN_PERCENT).
  Si tests fallan, delega a dotnet-developer. Si cobertura insuficiente, orquesta architect,
  business-analyst y dotnet-developer para diseñar e implementar tests necesarios.
tools:
  bash: true
  read: true
  glob: true
  grep: true
  task: true
model_tier: mid
color: "#CC00CC"
maxSteps: 15
max_context_tokens: 8000
output_max_tokens: 500
permissionMode: acceptEdits
context_cost: high
token_budget:
  per_invocation: 60000
  context_window_target: 8500
  escalation_policy: escalate
permission.task:
  allowlist: []
---
Ejecuta tests y verifica cobertura post-commit.

1. `git diff --name-only HEAD~1 HEAD | grep "^projects/"` — identificar proyecto
2. `dotnet test *.sln --configuration Release --verbosity normal` — ejecutar tests
3. Si fallan → delegar a `dotnet-developer` con error completo (máx 2 intentos)
4. `dotnet test --collect "XPlat Code Coverage"` — verificar cobertura global (baseline)
5. Changed-line coverage: toda línea cambiada del commit ejercitada por un test, con exit-nonzero (`diff-cover --fail-under` o equivalente). El % global es baseline, NO el gate — ver `docs/rules/domain/coverage-scripts.md`.
6. Si cobertura < `TEST_COVERAGE_MIN_PERCENT` o changed-line < umbral → orquestar architect+BA+dotnet-developer
7. Generar resumen en `output/YYYYMMDD-test-results-[proyecto].md`

Reglas: nunca commitear si tests fallan. Leer umbrales de `docs/rules/domain/pm-config.md`.
Ref: `docs/rules/domain/test-coverage-policy.md`, `docs/rules/domain/coverage-scripts.md`
