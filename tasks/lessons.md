# Lessons Learned

- Un runner agregado debe decidir por fallos, no por éxitos: `PASS > 0` sólo
  demuestra que algún componente funcionó. El contrato sistémico correcto es
  `FAIL == 0 && PASS > 0`, con corpus vacío tratado como fallo de evidencia.
- Un registro canónico no es completo sólo porque sus entradas sean válidas:
  debe declarar el universo que pretende cubrir y fallar cuando una fuente de
  ese universo queda omitida. El suelo de cobertura evita confundir legacy no
  migrado con iniciativas actuales desaparecidas.
- Nunca neutralizar el exit code de `timeout` antes de clasificarlo. Un runner
  que expira sin imprimir marcadores de fallo no ha pasado: los gates deben
  exigir exit 0 y una señal positiva de finalización, y mantener acotada la
  selección local cuando el corpus completo excede su presupuesto.
- Un benchmark de inventario debe afirmar su cardinalidad mínima y probar la
  topología real del repositorio. `find` no sigue por defecto un directorio que
  es enlace simbólico; sin `-L`, “cero elementos, cero fallos” puede producir un
  PASS vacío y ocultar que no se midió nada.
- Con `set -o pipefail`, `producer | grep -q` puede fallar cuando `grep` encuentra
  pronto una coincidencia y cierra el pipe. En validadores, consultar el fichero
  directamente evita que un SIGPIPE convierta coincidencias reales en falsos
  negativos silenciosos.
- Los IDs de spec históricos no son necesariamente únicos: un resolver de
  gobernanza debe fallar ante ambigüedad y aceptar una ruta explícita validada;
  elegir el primer resultado convierte el orden del filesystem en autoridad.

Persistent log of corrections and patterns discovered during sessions.
Reviewed at session start to prevent recurrence. Newest entries first.

| 2026-09-08 | MCP | Medir por separado llamada, arranque y cierre antes de atribuir latencia al handler. El incidente de SaviaLabs fue `tsx`/sandbox (`EPERM`); `vault_read` respondió en 5–93 ms. | Diagnóstico de transporte MCP |
| 2026-09-08 | Skills | Frontmatter migrations must parse every `SKILL.md` as YAML after rewriting it. Grep-only checks missed invalid nesting below scalar metadata and unquoted colons in descriptions. Keep a repository-wide YAML regression test. | Codex skipped invalid skills at startup |
| 2026-03-28 | Git | ALWAYS run /pr-plan before creating any PR. NEVER call push-pr.sh directly — it bypasses 10 pre-flight gates and the confidentiality signing protocol, causing CI failures (diff hash mismatch). Structural guard: push-pr.sh now requires .pr-plan-ok sentinel or exits with error. Rule #25. | CI failure PR #441 + user correction |
| 2026-03-25 | Comms | When told to improve a response, ACTUALLY improve it. Don't resend the same quality. Re-read the original feedback, address every point, improve depth and tone. | User correction |
| 2026-03-25 | Comms | Follow directives precisely. If user says "improve the email", the next version MUST be measurably better. Track directives as checklist, verify before executing. | User correction |
| 2026-03-24 | Docs | Ellipsis (...) is rhetorical, NOT truncation. Never say "message seems cut" based on `...` alone. Rule: ellipsis-guardrail.md | User correction |
| 2026-03-24 | PII | Wrote user's real name in CHANGELOG (public file). Rule #20 violation. ALWAYS use "user" or generic terms in any versioned file. No exceptions, even when referring to ideas or contributions. | User correction |
| 2026-03-24 | Git | ALWAYS use scripts/push-pr.sh for PRs. Never manual curl to GitHub API. Corrected 3+ times. | User correction |

Format: `| date | category | lesson | source |`

---

| Date | Category | Lesson | Source |
|---|---|---|---|
| 2026-03-24 | CHANGELOG | Always include `Era N` reference in CHANGELOG entry description. BATS test `recent versions (>=2.20) have an Era reference` fails without it. Format: `Era 138. Description here.` | CI BATS failure — test-changelog-integrity |
| 2026-03-23 | Git | Always use `scripts/push-pr.sh` for commit+sign+push+PR. Manual flow causes signature mismatch (sign before commit = diff changes after). The script handles the correct order: CI → sign → commit → push → PR. | CI failure — Confidentiality Gate hash mismatch |
| 2026-03-23 | Git | GitHub PAT is at `~/.github-pat`. Use it for API calls when `gh` CLI is not installed. | Session discovery |
| 2026-03-04 | Reasoning | Out-of-scope answers must identify the REAL objective before responding. "Lavar el coche a 100m → ¿andando o en coche?" requires the car there, so: drive. Proxy optimization of "desplazamiento" instead of "lavado". Added to adaptive-output.md. | User correction — car wash example |
| 2026-03-04 | CHANGELOG | Always add versión link reference `[X.Y.Z]: URL` at bottom of CHANGELOG.md when creating a new `## [X.Y.Z]` header. Validated by `scripts/validate-changelog-links.sh` and `prompt-hook-commit.sh`. | User correction — v1.9.0 |
| 2026-03-03 | PII | Never include real company names, personal names, or handles in CHANGELOG, releases, commits, or PR descriptions. Use generic placeholders (test-org, alice, test company). | User correction — Era 21 |
| 2026-03-03 | Git | `git fetch origin --all` is invalid. Use `git fetch --all` or `git fetch origin` (without --all). | Test failure — Era 22 |
| 2026-03-03 | Testing | `assert_ok` checking `$?` after `TOTAL=$((TOTAL+1))` always returns 0. Pass the command as arguments to the assert function instead. | Test failure — Era 22 |
| 2026-03-03 | Git | savia-branch.sh dispatcher uses short names (read, write, exists) not function names (do_read, do_write, do_exists). | Test failure — Era 22 |
| 2026-03-03 | Bash | `!` negation doesn't work inside `"$@"` expansion. Use a separate `assert_fail` helper instead. | Test failure — Era 22 |
| 2026-03-03 | Git | Default branch is `master` unless `init.defaultBranch` is configured. Always set `git config --global init.defaultBranch main` in test setup. | Test failure — Era 22 |

| 2026-03-21 | Security | SIEMPRE firmar .confidentiality-signature como ULTIMO paso antes de push. El diff hash debe calcularse con merge-base, no three-dot diff, para compatibilidad con CI merge commits. HMAC solo sobre diff_hash, nunca sobre commit hash (cambia con squash). | Bug en pipeline de firma tras PRs #364-#365 |
