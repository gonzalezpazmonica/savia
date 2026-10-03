# Regla: guards de seguridad con `blocking: true` (D23-5)

> Decisión de la operadora D-T2 (2026-10-03). Fuente de verdad de la lista:
> `config/hooks-blocking-policy.txt`. Auditor: `scripts/hooks-integrity-check.sh --blocking`.
> Test: `tests/test-hooks-blocking-audit.bats`.

## Qué significa `blocking: true`

Es una clave opcional de cada hook en `.claude/settings.json`. Solo la interpreta
Savia Space en **modo mediado** (D23-5, fail-closed): si un hook marcado sale con un
código distinto de 0 o 2, muere por señal, agota su `timeout` o no se puede lanzar,
Space **bloquea** la herramienta con la causa. Sin la marca, ese mismo fallo es un
error no bloqueante que solo queda en la traza (contrato de Claude Code).

- Claude Code tolera la clave (ya la llevaba `android-adb-validate`) y no cambia su comportamiento.
- OpenCode (`scripts/opencode-plugin/savia-gates`) solo copia `type`, `command`, `matcher`,
  `timeout` y `async`: ignora la clave sin fallar.
- La salida 2 de cualquier hook bloquea siempre, con o sin la marca.

## Guards marcados

| Hook | Evento / matcher |
|---|---|
| `block-credential-leak` | PreToolUse `Bash` |
| `block-force-push` | PreToolUse `Bash` |
| `agent-git-discipline` (dos entradas) | PreToolUse `Bash` |
| `block-infra-destructive` | PreToolUse `Bash` |
| `validate-bash-global` | PreToolUse `Bash` |
| `android-adb-validate` | PreToolUse `Bash` |

`agent-git-discipline` aparece dos veces con el mismo comando. Space ejecuta una sola
vez cada comando repetido de un evento y conserva la primera aparición, así que
**todas** las apariciones de un guard deben llevar la marca.

## Exclusión: `data-sovereignty-gate`

Queda **sin** `blocking` hasta acotar su latencia. Llama a `curl` contra el shield
(2 s de health y hasta 10 s de escaneo) y a `sovereignty-classify.sh`, que no tiene
timeout propio. Medido el 2026-10-03 con carga ~10: 5,6 s y 3,8 s en frío para un
Write o un Edit de `docs/` y `scripts/`, ~0,3 s en caliente, con `timeout: 15`. Con más
carga podría superar los 15 s y, en fail-closed, bloquear Edit/Write legítimos.
Condición para marcarlo: timeout propio en el clasificador y margen medido bajo carga.

## Requisitos para marcar un hook

1. Sale **solo** con 0 o 2 en cualquier entrada: vacía, JSON inválido, `tool_input`
   ausente o de otro tipo, entrada grande, sin `jq` en el PATH. Los seis guards se
   verificaron con esas entradas el 2026-10-03.
2. Su latencia en frío y bajo carga deja margen frente a su `timeout`.
3. Es un guard de seguridad: su fallo silencioso permitiría una acción irreversible.

## Política de regresión

`scripts/hooks-integrity-check.sh --blocking` falla (exit 1) si:

- un guard declarado `blocking` tiene alguna aparición sin `blocking: true` (booleano);
- un hook lleva `blocking: true` sin estar declarado en la política;
- un hook `excluded` o `reviewed` lleva `blocking: true`;
- un guard declarado ya no está registrado;
- aparece un hook cuyo script empieza por `block-` sin clasificar como `blocking`,
  `excluded` o `reviewed` (estos dos con motivo).

Un guard de seguridad nuevo obliga a decidir: se añade a la política o el test falla.
Los `block-*` marcados `reviewed` (`block-commit-to-main`, `block-pat-file-write`, etc.)
quedan fuera de D-T2; pasarlos a `blocking` requiere decisión de la operadora y medir
los requisitos de arriba.
