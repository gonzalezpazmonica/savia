---
layer: peripheral
name: agent-messaging
description: Usar cuando un agente debe enviar un mensaje a otro agente con roles y receipts, sin pasar por el usuario. Triggers: mensaje a otro agente, agent-message, notify agent, inbox.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: orchestration
  savia.maturity: stable
  savia.context: standalone
  savia.context_cost: low
  savia.maturity: beta
  savia.priority: medium
  savia.tags: "messaging, agent-to-agent, a2a, receipts, orchestration"
  savia.trigger_keywords: "mensaje a agente, notify, inbox, agent-message"
---

# Skill: Agent Messaging (bus local A2A)

Patrón extraído de Prime Agent (SE-347): `agent_message.send(...)` con roles
(parent/child/steer/follow_up) y receipts (delivered/queued), broadcast y ack.
Savia lo implementa sobre ficheros JSONL en `~/.savia/msg` (CRIT-001: sin red,
sin proveedor cloud).

## Authoritative Paths

> Lee estos paths antes de actuar.

| Para | Lee este path |
|---|---|
| Script del bus | `scripts/agent-messaging.sh` |
| Colas (runtime) | `~/.savia/msg/` |
| Protocolo handoff existente | `docs/agent-notes-protocol.md` |
| Lección origen | `output/research/prime-agent-eval/lecciones-prime-agent-20260827.md` |

## Modelo

- **inbox por receptor**: `~/.savia/msg/inbox/<agente>.jsonl`
- **ledger global**: `~/.savia/msg/ledger.jsonl`
- Mensaje: `{id, ts, from, to, role, message, status, ack_at}`
- Receipts: `queued` (ledger) → `delivered` (en inbox) → `read` (ack)
- Roles: `parent` (de orquestador a subagente), `child` (de subagente a
  orquestador), `steer` (redirección), `follow_up` (default)

## Cuándo usar

- Un orquestador quiere delegar a N subagentes y recoger respuestas después
  (complementa `parallel-dispatch`, que recoge por fichero).
- Un agente quiere notificar a otro sin esperar su turno ni pasar por el user.
- Sustituye al handoff por notas cuando necesitas *estado* (leído/entregado).

## Uso

```bash
# enviar (stdout = id; estado en stderr)
bash scripts/agent-messaging.sh send --to dev --role child --message "revisa la API" --from orchestrator
# broadcast a todas las inbox conocidas
bash scripts/agent-messaging.sh send --to all --broadcast --message "standup" --role steer
# listar inbox (--unread)
bash scripts/agent-messaging.sh list --inbox dev --unread
# acusar recibo (receipt -> read)
bash scripts/agent-messaging.sh ack --id <msgid> --as dev
# estado
bash scripts/agent-messaging.sh status --id <msgid>
```

## Reglas

- CRIT-001: las colas viven en `~/.savia/msg` (disco propio). Nunca en el repo.
- Un agente NO debe leer el inbox de otro (solo el suyo o el que le corresponda).
- No uses el bus para datos N3+ fuera de disco propio — el bus es local, pero el
  contenido sigue sujeto a confidencialidad por nivel.
- Compatible con `agent-notes-protocol.md` para handoff formal (el bus es el
  canal, las notas el contenido estructurado).

## Related

- `scripts/agent-messaging.sh` · `parallel-dispatch` (recoger por fichero) ·
  `agent-notes-protocol.md` (handoff formal)
