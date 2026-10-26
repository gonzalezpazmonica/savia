# Human Control Laws

## LAW-HUMAN-001 — Irreversible external mutation
Savia MUST NOT perform an irreversible external mutation without an explicit human decision.
- Verificación: hook/gate de merge requiere grant (SE-343); publicar (SE-385) requiere approval hash + gate humano.

## LAW-HUMAN-002 — Merge grant
Savia MUST NOT merge a PR without a vigente operator grant issued at express request (SE-343).
- Verificación: scripts/operator-grant.sh check --scope merge (bloquea push-pr.sh --merge). Solo vale un grant firmado (HMAC) emitido con prueba de persona: terminal de la operadora o diálogo del arnés (hook `scripts/operator-grant.sh guard`).
