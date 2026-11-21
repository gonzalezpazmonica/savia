---
context_tier: L2
token_budget: 734
---

# Reglas Criticas — Referencia Extendida (9-26)

> Rules 1-8 inline in CLAUDE.md. Este fichero contiene las reglas 9-26 con detalle.

9. **Secrets**: NUNCA en repo — vault o `config.local/` · `@docs/rules/domain/context-placement-confirmation.md`
10. **Infra**: NUNCA apply PRE/PRO sin aprobacion · `@docs/rules/domain/infrastructure-as-code.md`
11. **150 lineas max.** por fichero .md del workspace (.claude/) — NO aplica a codigo fuente de aplicaciones
12. **README**: cambios en commands/agents/skills/rules → actualizar README.md + README.en.md
13. **Git**: NUNCA commit/add en `main` — hook lo bloquea. Verificar rama antes de operar
14. **CI Local**: antes de push → `bash scripts/validate-ci-local.sh`
15. **UX**: CADA comando DEBE mostrar banner, prerequisitos, progreso, resultado. **El silencio es bug.**
16. **Auto-compact**: Resultado >30 lineas → fichero + resumen. `Task` para pesados. Tras comando → ` /compact`
17. **Anti-improvisacion**: Comando SOLO ejecuta lo de su `.md`. No cubierto → error + sugerencia
18. **Serializacion**: scopes antes de Agent Teams. Solapan → serializar. Hook `scope-guard.sh`
19. **Arranque seguro**: MCP/integraciones se cargan bajo demanda, NUNCA al inicio. Savia SIEMPRE arranca.
20. **PII-Free repo**: NUNCA nombres reales, empresas, handles ni datos personales en codigo, docs, CHANGELOG, releases, commits ni PRs. Usar genericos (`test-org`, `alice`, `test company repo`). Detalle → `@docs/rules/domain/pii-sanitization.md`
20b. **Operational Privacy**: El repo publico contiene software general reutilizable. NUNCA datos operacionales privados: backups personales, cron jobs, systemd units con paths/usuarios concretos, emails, tokens, URLs de infraestructura privada, configuraciones de despliegue personal. Este tipo de artefactos va en `~/.savia/` (privado, fuera del repo). Si un PR introduce datos operacionales, CIERRALO y mueve los ficheros a `~/.savia/`.
21. **Self-Improvement Loop**: Tras correccion del usuario o bug descubierto → escribir leccion en `tasks/lessons.md`. Revisar al inicio de sesion. Detalle → `@docs/rules/domain/self-improvement.md`
22. **Verification Before Done**: NUNCA marcar tarea como completada sin prueba demostrable. Preguntarse "¿lo aprobaria un senior?" Detalle → `@docs/rules/domain/verification-before-done.md`
23. **Equality Shield**: Asignaciones, evaluaciones y comunicaciones INDEPENDIENTES de genero, raza u origen. Test contrafactual obligatorio. Detalle → `@docs/rules/domain/equality-shield.md`
24. **Radical Honesty**: Savia acts as honest advisor — growth, not comfort. Canonical → `@docs/rules/domain/radical-honesty.md` (source of truth, no duplicar aquí).
25. **PR via /pr-plan**: SIEMPRE ejecutar `/pr-plan` antes de crear un PR. NUNCA llamar `push-pr.sh` directamente. La guardia estructural: `push-pr.sh` falla sin `.pr-plan-ok`. Detalle → `@docs/rules/domain/pr-signing-protocol.md`
26. **Procedencia**: NUNCA información de entornos profesionales ajenos al proyecto en Savia, cúpulas ni Labs (ni anonimizada ni «inspirada en»); ante la duda, parar y preguntar. Detalle → `@docs/rules/domain/procedencia-entornos-profesionales.md`
