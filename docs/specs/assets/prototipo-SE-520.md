# Prototipo SE-520 — Reglas de guarda en texto

> Slice S0 de `docs/specs/SE-520-reglas-de-guarda-en-texto.spec.md`. Muestra lo que escribe y lo que ve la persona. No es código: las salidas son las que dará el motor si la spec se aprueba tal cual. Pendiente de confirmar por la operadora.

## 1. Una guarda de hoy, escrita como regla (escena 1)

`.claude/guard-rules/infra-terraform-destroy.md`:

```markdown
---
id: infra-terraform-destroy
version: 1
event: PreToolUse
tools: [Bash]
action: block
class: POLITICA
enabled: true
profile: security
when:
  - field: tool_input.command
    op: regex
    pattern: 'terraform\s+destroy'
    flags: [i]
cases:
  block:
    - {tool: Bash, input: {command: "terraform destroy -auto-approve"}}
    - {tool: Bash, input: {command: "cd infra && TERRAFORM destroy"}}
  allow:
    - {tool: Bash, input: {command: "terraform plan -out p.tfplan"}}
replaces: ".claude/hooks/block-infra-destructive.sh:32"
---
Terraform destroy bloqueado: destruye infraestructura.
Usa `terraform plan -destroy` y pide la ejecución a una persona.
```

Lo que ve la persona (o el agente) al intentarlo:

```
BLOQUEADO [POLITICA] guard-rules:infra-terraform-destroy
Terraform destroy bloqueado: destruye infraestructura.
Usa `terraform plan -destroy` y pide la ejecución a una persona.
```

Línea en `output/guard-blocks.jsonl` (SE-510 D2; la orden no se guarda en claro):

```json
{"ts":"2026-12-01T10:12:03Z","event":"PreToolUse","tool":"Bash","guard":"guard-rules:infra-terraform-destroy","class":"POLITICA","reason":"Terraform destroy bloqueado: destruye infraestructura.","cmd_hmac":"9c1e…"}
```

## 2. Una regla nueva (escena 2)

`.claude/guard-rules/token-slack-en-orden.md`:

```markdown
---
id: token-slack-en-orden
version: 1
event: PreToolUse
tools: [Bash]
action: block
class: POLITICA
enabled: true
when:
  - field: tool_input.command
    op: regex
    pattern: 'xox[abposr]-[A-Za-z0-9-]{10,}'
cases:
  block:
    - {tool: Bash, input: {command: "curl -H 'Authorization: Bearer xoxb-EJEMPLOFALSO' https://slack.com/api/x"}}
  allow:
    - {tool: Bash, input: {command: "curl -H \"Authorization: Bearer $(cat \"$SLACK_TOKEN_FILE\")\" https://slack.com/api/x"}}
    - {tool: Bash, input: {command: "grep -n 'xoxb-' docs/rules/domain/secret-redaction-policy.md"}}
---
Token de Slack en claro en la orden.
Léelo de un fichero fuera del repo: `$(cat "$SLACK_TOKEN_FILE")`.
```

Lo que pasa después: la persona abre una PR. `scripts/risk-tier.py` la marca **tier 3** porque toca `.claude/guard-rules/`. No hay hook nuevo ni cambio en `settings.json`.

## 3. Una regla con excepción y su par (escena 3)

```markdown
---
id: git-push-main
version: 1
event: PreToolUse
tools: [Bash]
action: block
class: POLITICA
enabled: true
when:
  - field: tool_input.command
    op: regex
    pattern: 'git\s+push\b[^;&|\n]*\s(\+|HEAD:|refs/heads/)?main\b'
unless:
  - field: tool_input.command
    op: fullmatch                      # la orden entera; la clase excluye ; & | < > $ ` \n \r
    pattern: 'git\s+push\s+--dry-run\s[^;&|<>$`\n\r]*'
cases:
  block:
    - {tool: Bash, input: {command: "git push origin main"}}                 # par mínimo del unless
    - {tool: Bash, input: {command: "git push -u origin main"}}
    - {tool: Bash, input: {command: "git push -f origin main"}}
    - {tool: Bash, input: {command: "git push origin +main"}}
    - {tool: Bash, input: {command: "git push origin HEAD:main"}}
    - {tool: Bash, input: {command: "git push --dry-run origin main; git push origin main"}}   # encadenado
    - {tool: Bash, input: {command: "git push --dry-run origin main $(git push origin main)"}}   # sustitución
  allow:
    - {tool: Bash, input: {command: "git push --dry-run origin main"}}       # casa con when Y con unless
    - {tool: Bash, input: {command: "git push origin agent/x-main-fix"}}
---
Push a main bloqueado. Rama agent/* y PR en borrador.
```

Esta regla ilustra el formato; la regla real se escribe con su corpus en F1. El lint exige, por cada `unless`, un caso `allow` que case con `when` **y** con ese `unless` (aquí el primero), y un caso `block` por familia de encadenado (`<allow>; <peligroso>` y `<allow> $(<peligroso>)`, aquí el sexto y el séptimo). Quitar el `unless` hace fallar el primer `allow`: el par es efectivo.

Si una worker edita su copia local y añade `unless: git push origin main`, la versión de `origin/main` se sigue evaluando:

```
BLOQUEADO [POLITICA] guard-rules:git-push-main (versión de origin/main)
Push a main bloqueado. Rama agent/* y PR en borrador.
Nota: la copia local de esta regla difiere de origin/main; se aplican las dos.
```

## 4. Una regla rota (escena 4)

En la CI (`python3 scripts/guard_rules.py lint`):

```
FAIL .claude/guard-rules/token-slack-en-orden.md:13 pattern fuera del dialecto común: lookbehind '(?<=' no está permitido
FAIL .claude/guard-rules/git-push-main.md: unless[0] sin caso block encadenado o sin caso allow que case con when y con el unless
2 reglas no cargan. Exit 1.
```

Si llegara a la máquina, en cualquier llamada que atienda el motor:

```
BLOQUEADO [POLITICA] guard-rules: no se pueden cargar las reglas
.claude/guard-rules/token-slack-en-orden.md:13 lookbehind no permitido.
Ninguna llamada pasa hasta que la regla se corrija (fallo cerrado, SE-520 D5).
Salida de recuperación: Edit/Write sobre .claude/guard-rules/ y `python3 scripts/guard_rules.py diagnose` siguen permitidos.
```

Aviso (`action: warn`), canal de Claude Code: JSON por stdout con exit 0, no stderr:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"AVISO guard-rules:<id>: <primera línea del mensaje>"}}
```

## 5. Salida de las pruebas

`python3 scripts/guard_rules.py test`:

```
infra-terraform-destroy   block 2/2  allow 1/1  quitar-regla→cambia  OK
token-slack-en-orden      block 1/1  allow 2/2  quitar-regla→cambia  OK
git-push-main             block 2/2  allow 1/1  quitar-regla→cambia  OK
3 reglas, 0 fallos. Paridad bash/TS: 9/9 casos con el mismo veredicto.
```

## 6. Propuesta de un agente (escena 5)

```
Propuesta (borrador, no activa): ajustar token-slack-en-orden
Motivo: 3 bloqueos marcados false-positive esta semana (guard-blocks.sh report).
Cambio: añade un unless fullmatch `grep\s+-n\s+'xoxb-[^']*'\s+docs/[^;&|<>$`\n\r]*` (la orden entera, sin encadenar ni sustituir).
Pares añadidos: curl con 'xoxb-…' real → sigue bloqueando; `grep -n 'xoxb-' docs/x; curl … xoxb-<real>` (encadenado) y `grep -n 'xoxb-' docs/x $(curl … xoxb-<real>)` (sustitución) → siguen bloqueando.
Nota: en el worktree de la worker la regla de origin/main sigue aplicando; el cambio solo rige cuando la operadora fusiona (SE-520 D3).
Rama agent/guard-rule-slack-20261201, PR en borrador. La activa tu fusión (tier 3).
```
