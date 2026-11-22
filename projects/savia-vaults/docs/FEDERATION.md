# Savia Federate — Federation Guide

> **How to connect multiple context domes for unified search across your knowledge.**

Savia Federate lets you register remote vaults as federated domes. Once connected, searching your local vault automatically includes results from all healthy federated domes — merged, deduplicated, and ranked as if they were part of your own vault.

## Quick Start

```bash
# 1. Start vault A (with auth)
savia-vaults serve --transport a2a --port 8923 --name alpha

# 2. Start vault B (no auth)
savia-vaults serve --transport a2a --port 8924 --name beta

# 3. Register B as federated dome in A
savia-vaults federate add beta http://localhost:8924

# 4. Search across both vaults
savia-vaults search "architecture" --federated
# Returns results from alpha (local) + beta (federated)
```

## Commands

| Command | Description |
|---|---|
| `savia-vaults federate add <id> <url>` | Register a remote dome |
| `savia-vaults federate add <id> <url> --token <t>` | Register with auth token |
| `savia-vaults federate add <id> <url> --weight 2.0` | Register with higher priority |
| `savia-vaults federate list` | List all federated domes |
| `savia-vaults federate remove <id>` | Remove a federated dome |
| `savia-vaults federate health` | Check health of all federated domes |
| `savia-vaults search "q" --federated` | Search local + all federated |

## Configuration

Federation settings live in `savia-vaults.config.json`:

```json
{
  "federation": {
    "enabled": true,
    "domes": [
      {
        "id": "team-docs",
        "name": "Team Documentation",
        "url": "http://192.168.1.50:8923",
        "authToken": "${SAVIA_TEAM_DOCS_TOKEN}",
        "timeout": 5000,
        "weight": 1.5,
        "tags": ["docs", "team"]
      },
      {
        "id": "specs-vault",
        "name": "Specifications",
        "url": "http://localhost:8924",
        "weight": 1.0,
        "tags": ["specs", "technical"]
      }
    ]
  }
}
```

| Field | Default | Description |
|---|---|---|
| `id` | required | Unique identifier for the dome |
| `url` | required | A2A server URL (http://host:port) |
| `authToken` | — | Bearer token for authenticated domes |
| `timeout` | 5000 | Max milliseconds per remote query |
| `weight` | 1.0 | Priority weight (0.1-2.0), higher = more results |
| `enabled` | true | Enable/disable without removing |
| `tags` | [] | Metadata tags for filtering |

## How Federation Works

```
1. User searches "microservices"
       │
2. Local BM25 search runs immediately (< 10ms)
       │
3. Parallel A2A queries sent to all healthy federated domes
   ├── GET http://team-docs:8923/search?q=microservices (timeout 5s)
   └── GET http://specs-vault:8924/search?q=microservices (timeout 5s)
       │
4. Results merged:
   ├── Deduplicate by content hash (same content → one result)
   ├── Interleave: round-robin from each source, weighted
   └── Cap at maxResults × (1 + federated domes)
       │
5. Results cached (5 min TTL), returned with source attribution
```

## Security

- **Read-only**: Federated domes receive only GET requests (never writes)
- **1-hop only**: Remote domes do NOT propagate searches further
- **Auth per dome**: Each dome can require its own Bearer token
- **Timeout**: 5s per remote dome (configurable)
- **Graceful degradation**: Offline domes are skipped, local results always returned
- **Health tracking**: Domes auto-transition healthy → degraded → unhealthy

## Best Practices

- Use `https://` URLs in production
- Store auth tokens in environment variables, not config files
- Set weight=2.0 for high-priority domes, weight=0.5 for auxiliary ones
- Monitor health: `savia-vaults federate health` periodically
- Cache TTL of 5 min balances freshness vs performance
- Federate domes on the same machine or local network for low latency

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Federated results not appearing | Dome offline or auth wrong | `savia-vaults federate health` |
| Slow searches | Remote dome latency | Reduce timeout, increase cache TTL |
| Duplicate results | Same content in multiple domes | Normal — dedup by content hash |
| 401 errors | Wrong or missing auth token | Check `authToken` in config |
| Timeout errors | Dome unreachable | Check network, increase timeout |

## Production Hardening

### TLS Encryption

Always use HTTPS in production. A2A has no built-in TLS: put a TLS-terminating
reverse proxy in front of it and always set `SAVIA_VAULTS_TOKEN` (without it, A2A
refuses to listen outside loopback).

Register federated domes with `https://` URLs:

```bash
savia-vaults federate add prod https://vault.example.com:8923 --token "$TOKEN"
```

### Token Rotation

Rotate auth tokens periodically:

```bash
savia-vaults federate rotate-token specs
```

### Audit Logging

All federated queries are logged to `output/federation-audit.jsonl`:

```jsonl
{"ts":"2026-07-30T22:00:00Z","event":"federated_query","dome":"specs","query":"architecture","status":"ok","results":3,"latency_ms":45}
{"ts":"2026-07-30T22:00:05Z","event":"federated_query","dome":"team-docs","query":"architecture","status":"timeout","results":0,"latency_ms":5001}
```

### Circuit Breaker

Domes that fail repeatedly are automatically disabled:

- **5 consecutive failures** → dome enters OPEN state (no requests)
- **5 minute cooldown** → dome enters HALF_OPEN (single probe allowed)
- **Probe succeeds** → dome returns to CLOSED (normal operation)
- **Probe fails** → dome returns to OPEN

No manual intervention needed for recovery.

### Content Integrity

Federated results are **not** verified for content integrity. Remote results are not
signed, and `contentHash` is computed locally by the client from the received snippet:
it is only a deduplication key, not an integrity check. Protection of results in transit
depends on TLS (see "TLS Encryption") and on the per-dome Bearer token. Only federate
domes you trust: a remote dome can return any content it wants.
