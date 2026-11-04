---
context_tier: L3
token_budget: 1044
---

# Secret Redaction Policy — SPEC-142

> **Rule** — `.opencode/plugins/guards/auto-redact-credentials.ts` mutates
> `args.command` for the `bash` tool to substitute literal credentials with
> `$(cat $ENV_FILE)` expansions BEFORE the command runs. If the env var
> is unset the command is left intact and `block-credential-leak` aborts
> in the next guard. Fail-closed by composition.

## Why mutate instead of block-only

Rule #1 ("NUNCA hardcodear PAT") was previously enforced by aborting the
tool call and letting the model retry. That penalises latency and the
re-prompt often produces a different command. The mutate-before-execute
plugin pattern (OpenCode v1.14+ `tool.execute.before`) corrects the
command in-place so the first invocation already runs against the
operator's vault.

The redactor does NOT replace the abort guard — it composes with it:

```
auto-redact-credentials    →  block-credential-leak
  (mutate if possible)     (abort if anything still looks like a secret)
```

If the redaction cannot substitute (env var missing, unknown shape),
the next guard catches the leak. The operator's vault config is the
single source of authority.

## Pattern table

| Kind | Regex (high-precision) | Env var | Example destination |
|---|---|---|---|
| `github-pat-classic`  | `ghp_[A-Za-z0-9]{36}`                          | `GITHUB_PAT_FILE`     | `~/.azure/devops-pat`  |
| `github-pat-fine`     | `github_pat_[A-Za-z0-9_]{82,}`                 | `GITHUB_PAT_FILE`     | `~/.azure/devops-pat`  |
| `azure-sas`           | `sv=20\d{2}-\d{2}-\d{2}&s[a-z]=[A-Za-z0-9%+/_-]+` | `AZURE_SAS_FILE`   | `~/.azure/sas-token`   |
| `openai-key`          | `sk-[A-Za-z0-9]{48,}`                          | `OPENAI_KEY_FILE`     | `~/.openai/key`        |
| `anthropic-key`       | `sk-ant-[A-Za-z0-9_-]{20,}`                    | `ANTHROPIC_KEY_FILE`  | `~/.anthropic/key`     |

Patterns are deliberately narrow. Fuzzy patterns (`pat = "..."`, generic
`token=`) stay in `block-credential-leak` as abort-only — too many false
positives to safely mutate.

## Operator setup

```bash
# Per-shell (or in ~/.bashrc):
export GITHUB_PAT_FILE="$HOME/.azure/devops-pat"
export AZURE_SAS_FILE="$HOME/.azure/sas-token"
# Files must be 0600, single line, no trailing newline.
```

If a kind is detected but its `*_FILE` env var is unset, the redactor
appends a JSONL `skipped_no_env` audit record and lets the next guard
abort. Configure the env var to enable redaction.

## Audit trail

Every action lands in `output/secret-redactions.jsonl` (gitignored):

```json
{"ts":"2026-05-23T10:00:00Z","kind":"github-pat-classic","action":"redacted","env_var":"GITHUB_PAT_FILE","env_file":"/home/me/.azure/devops-pat"}
{"ts":"2026-05-23T10:00:01Z","kind":"openai-key","action":"skipped_no_env","env_var":"OPENAI_KEY_FILE"}
```

Audit is best-effort: a failed audit write never blocks the tool call.

## Ordering with other plugins

`auto-redact-credentials` runs at position 2 of `BEFORE_GUARDS` in
`.opencode/plugins/savia-foundation.ts`, between `validate-bash-global`
(cheap regex sanity) and `block-credential-leak` (the abort gate). If a
third-party plugin also mutates `args.command` it MUST run AFTER
`auto-redact-credentials` so it operates on the redacted form.

## Compatibility & legacy

- **OpenCode v1.14+**: native via this plugin.
- **Claude Code**: equivalent via `hookSpecificOutput.modifiedInput` in
  `.claude/hooks/pretooluse-secret-redaction.sh` — SPEC-142 Slice 3 (not
  shipped in initial implementation; tracked as follow-up).

## What this rule does NOT do

- Does not detect every credential ever invented.
- Does not redact `write`/`edit` content — that path is owned by
  `block-credential-leak` and `data-sovereignty-gate`.
- Does not validate the contents of the destination file (operator
  responsibility — file must hold the actual secret).

## References

- SPEC-142: `docs/propuestas/SPEC-142-pretooluse-input-modification.md`
- Implementation: `.opencode/plugins/guards/auto-redact-credentials.ts`
- Tests: `.opencode/plugins/__tests__/auto-redact-credentials.test.ts`
- Composition: `.opencode/plugins/savia-foundation.ts` (BEFORE_GUARDS)

## Sentinel credential substitution (SE-353)

Complementa la redacción con resolución **solo en egress**: el valor real de una
credencial se sustituye en el subproceso que habla con el destino autorizado, de
modo que **jamás entra en el contexto del modelo**.

- `printf '%s' "$SECRETO" | scripts/credential-egress.sh store KEY [-]` — lee el
  valor por **stdin**, lo cifra y almacena en `~/.savia/credential-store/keys.json`
  (0600, AES-256-CBC + HMAC, clave derivada de machine-id + HOME). El valor por
  argv (`store KEY VALUE`) se rechaza: quedaría en `ps` y en el historial. La
  clave del store tampoco pasa por argv: `openssl` la lee por descriptor
  (`-pass fd:3`, PBKDF2) y el HMAC lo calcula `python3` leyendo la clave por fd
  (formato `v2:`). Los blobs del formato anterior (`iv:ciph:mac`, `-K` raw) se
  leen una última vez con la clave en argv y se reescriben en `v2:`.
- `resolve KEY --dest D` — valor real solo si `D` coincide exactamente con la
  allowlist (`dev.azure.com`, `github.com`, `api.github.com`). Sin `--dest`,
  destino no autorizado o marcador no registrado → **REFUSE** (fail-closed, nada
  en stdout).
- `run [--dest D] CMD ARG...` — sustituye cada argumento `savia:cred:<key>` por
  la ruta `/dev/fd/N` de una tubería que contiene solo el valor (sin salto de
  línea final) y ejecuta en subproceso; el valor no aparece en el argv del hijo
  (`/proc/<pid>/cmdline`, `ps`). El hijo lo lee del fichero (`curl -H
  @/dev/fd/N`, `cat "$1"`); la tubería se lee una sola vez. El script no
  imprime ni persiste el valor. El destino es `--dest`
  o el host único de las URLs (`esquema://host`) que aparezcan en cualquier
  posición de los args, también dentro de `--url=...` o de un script de
  `bash -c`; sin destino, varios hosts, `--dest` distinto del host de la URL o
  una autoridad ambigua (`\`, `%`) → **REFUSE**. Sin marcadores, `run` ejecuta
  el comando sin validar hosts.
- `status` / `audit` — diagnóstico sin exponer valores.

### Límites (lo que SE-353 no garantiza)

`--dest` lo declara quien llama. La comprobación de host de `run` es una
**salvaguarda contra errores de enrutado**, no una barrera frente a un llamante
hostil:

- `resolve KEY --dest github.com` imprime el valor real por stdout a quien lo
  pida con un destino autorizado.
- `run` entrega el valor al proceso hijo, que puede imprimirlo (`bash -c 'echo
  "$1"'`) o enviarlo a un host que no aparezca como `esquema://host` en los args
  (variable de entorno, fichero, `curl host` sin esquema).
- El descriptor lo heredan el hijo y sus descendientes, y otro proceso del mismo
  usuario puede abrirlo vía `/proc/<pid>/fd/N` mientras no se haya leído.
- `store` descarta los saltos de línea finales del valor.

El aislamiento real requiere que quien invoca no controle el comando hijo (un
wrapper fijo por herramienta) o que la comprobación ocurra en el propio cliente
HTTP. Lo fija el test `G2r: LÍMITE conocido` (`test-se353-credential-egress.bats`).

CRIT-001: tienda 100% local, sin proveedor cloud. La clave de cifrado deriva del
host, así que el store no es portable a otra máquina (intencional).

## References (SE-353)

- Spec: `docs/specs/SE-353-sentinel-secrets.spec.md`
- Tests: `tests/bats/test-se353-credential-egress.bats`
- Inspiración: OpenClaw SecretRefs + egress sentinels
