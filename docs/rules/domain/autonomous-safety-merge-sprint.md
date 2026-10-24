---
context_tier: L3
token_budget: 1600
spec: SE-433
status: APPROVED
---

# merge-sprint — merges autónomos bajo autorización humana previa (SE-433)

> Apéndice de `autonomous-safety.md`. SE-433 **APPROVED** por la operadora (2026-10-04). Sin
> `scripts/merge-sprint.sh` mergeado rige el merge uno a uno (`autonomous-safety-merge-grant.md`).

## Principio

La autorización solo nace de la respuesta expresa de la operadora (el grant). Ninguna salida de un agente puede añadir un PR, subir
un tier, prorrogar el sprint ni sustituir una revisión. Las revisiones, el juez, la CI y el
clasificador de riesgo solo pueden **mantener o restar**: dejar seguir un PR ya autorizado, aparcarlo o
parar el sprint. Lo irreversible se decide con confirmación humana (`savia-ethical-principles.md`).
Se afirma «lo autorizó un humano, expresamente, sobre una lista concreta y tras ver las revisiones de
agentes», no que haya leído el diff.

## Ciclo

1. `review-register`: cada revisión y cada veredicto de juez se registra en un registro encadenado,
   con espejo como comentario del PR.
2. `plan`: un agente prepara un borrador de manifiesto. No es de confianza.
3. `render-question` y luego `grant`. `render-question` recalcula todo desde GitHub y `origin/main` y
   emite la pregunta con el manifiesto y su digest. La orquestadora la formula con AskUserQuestion y,
   tras la respuesta, ejecuta `grant`: registra pregunta y respuesta literales, sesión, hora y hash.
4. `run`: un ejecutor determinista mergea en serie, del PR más antiguo al más nuevo.
5. `report`: genera un informe local.

## Grant

```text
NUNCA   un grant sin respuesta literal de la operadora a la pregunta generada por render-question
NUNCA   un subagente emite un grant; nadie lo amplía, prorroga ni reutiliza para otro manifiesto
NUNCA   tier 4 · consulta sin resolver · grant sin TTL, máximo ni tiers enumerados
SIEMPRE manifiesto congelado: PR, head SHA, ficheros, tier, todas las revisiones, blobs del
        ejecutor y del clasificador, checks obligatorios y workflows de main
SIEMPRE el ejecutor exige grant con manifest_digest idéntico y respuesta = opción de aprobación
SIEMPRE por defecto TTL 12 h, 40 merges, ≤ 50 PRs; topes absolutos TTL ≤ 24 h, parks ≤ 3
SIEMPRE acuse e informe enviados a la operadora; revoke/stop invalidan el grant al instante
```

Límite: el grant es un fichero que escribe un agente; su autenticidad depende del harness y del
clasificador, no de criptografía. Mitigaciones: ledger encadenado, coincidencia exacta con el
manifiesto, informe a la operadora, `ask` en `grant`, hook contra la emisión desde un subagente,
contraste con el transcript (si son viables) y revocación inmediata.

## Revisión

- Primera línea: `VERDICT: APPROVE|HOLD pr= sha= role=correctness|security tier= reviewer= author=
  p0= p1= p2= p2_blocking=`. Cualquier otra forma equivale a HOLD.
- `APPROVE` exige `p0=p1=p2_blocking=0`. El SHA es el del head autorizado. El revisor es distinto del
  autor y del orquestador.
- Se recogen **todas** las revisiones registradas de cada PR y SHA: un solo HOLD lo excluye.
- Tier 1/2 necesita una APPROVE `correctness`. Tier 3 necesita además una APPROVE `security` y la
  selección explícita del PR en la pregunta de autorización (`ack`).
- Basta con revisores independientes del autor; no hace falta que sean de otro modelo.

## Ejecución

```text
SIEMPRE ejecutor determinista; el LLM no decide un merge
SIEMPRE en serie; re-sync con main por merge (nunca rebase); auto-rebase pausado (etiqueta)
SIEMPRE checks obligatorios en verde sobre el SHA S; merge con --match-head-commit S
SIEMPRE tras cada merge, todos los workflows de main en success sobre ese SHA
NUNCA   force-push · revert automático · reintento de CI · PRs fuera del manifiesto
NUNCA   bajar un tier; los paths de gobernanza son tier 4
```

Equivalencia del head, comparando árboles (blob y modo):

- Sin juez: un merge de `main`, la regeneración de los artefactos SAM y `.confidentiality-signature`
  (solo si la auditoría repetida sobre el nuevo head da PASSED). Cualquier otro cambio va al juez.

## Juez de cambios posteriores al grant

- **Prefiltro determinista.** Antes de consultar al juez, provoca STOP cualquier delta que toque
  ficheros fuera de los autorizados o paths de tier 3 o gobernanza, suba el tier, añada o borre
  ficheros, elimine tests o aserciones, debilite un test (`skip`, `|| true`, `xfail`), cambie
  binarios o modos, o supere 200 líneas.
- **Solicitud.** Acotada al grant y al head: `judge/<grant>/<pr>-<head>.request.json`. Un commit
  nuevo la deja obsoleta y el head nuevo se evalúa de cero.
- **Veredicto.** Primera línea: `JUDGE: SAFE|STOP pr= from= to= judge= fix_author= scope= security=
  reason=`. `fix_author`: email del autor del commit o trailer `Fix-Author:`. El juez es distinto del
  autor del fix, del original y del orquestador. Ante la duda, STOP.
- **Pausa.** Mientras un PR espera al juez conserva la etiqueta `merge-sprint:<id>`. `plan` borra
  las etiquetas de sprints muertos.
- **Comprobación del ejecutor.** Verifica formato, SHA, independencia y unicidad. `SAFE` solo deja
  seguir al PR, con CI nueva. `STOP` detiene el sprint para revisión humana.

| Evento | Acción |
|---|---|
| CI roja del PR (con tarea de causa raíz), conflicto real, revisión cambiada o HOLD nuevo, tier elevado, merge rechazado | Aparcar (vuelve a Draft si el ejecutor lo sacó de Draft) y seguir |
| CI de `main` no verde tras un merge (rojo, pending, ausente, cancelled, skipped) | Parar |
| Grant inválido o revocado, manifiesto o blobs alterados, merge externo (sin reserva propia, o de otro SHA u otra cuenta), base cambiada, checks reducidos | Parar (anomalía) |
| Juez `STOP`, veredicto inválido o fuera de plazo | Parar |
| Máximo de merges, TTL, fichero STOP, 3 aparcamientos seguidos | Parar |

Parar siempre es seguro. Un sprint parado por una condición de parada no se reanuda sin grant nuevo.

## Tier 3/4

- **Tier 3.** Por decisión de la operadora, aprobar el manifiesto que lista el PR por número es la
  revisión humana del PR concreto (SE-362), junto con una revisión de seguridad de un agente
  independiente. Modifica la lectura de SE-362 y Rule 8 E1 para tier 3: ningún humano lee el diff.
- **Tier 4.** Nunca entra. Incluye el ejecutor, `risk-tier.py`, la
  configuración de permisos de Claude Code y OpenCode, las reglas `autonomous-safety*`, `CLAUDE.md`,
  `AGENTS.md`, los principios éticos, la honestidad radical y `.github/workflows/`.

## Auditoría

El ledger local es append-only, encadenado por hash (`verify-ledger`). Cada merge registra grant y
digest, tier, SHA autorizado y mergeado, tipo de equivalencia, juez, hashes de revisiones, ids de CI,
checks obligatorios, commit de merge, CI de `main` y horas. Al final, informe para la operadora. Nada
se versiona.

## Permiso en el frontend

Lo concede la operadora en sus settings, nunca un agente:

- **Allow**: `run|status|stop|revoke|report|plan|render-question|review-register|verify-ledger`.
- **Ask**: `grant`. **Deny**: `gh pr merge`, la edición del ejecutor y de `risk-tier.py`, y la
  escritura en `~/.savia/merge-sprints/`.

Sin grant vigente para el manifiesto exacto, `run` termina con error. No elude el clasificador: es un
único camino, acotado y auditable, que concede la operadora.

## Límite declarado

Un agente con shell arbitraria del mismo usuario puede saltarse cualquier script; lo contienen los
permisos del frontend, no esta regla. Revisor, revisor de seguridad y juez son del mismo modelo y
comparten sesgos. Las identidades son autodeclaradas: el registro encadenado detecta la compra de
veredictos antes de `plan`, pero no la impide.

- La independencia del juez compara su id declarado con emails git y trailers `Fix-Author:`, que son
  espacios de nombres distintos: un agente que firma con email y juzga con su id no se detecta.
- Las reservas F5 van por manifiesto (digest), no por grant: un merge reservado bajo un grant
  anterior del mismo manifiesto cuenta como propio.
- La re-sincronización ejecuta generadores de la rama del PR (`sam.py`, escáner y firma) antes de
  que el prefiltro y el juez vean el delta.

## Referencias

- Spec: `docs/specs/SE-433-merge-sprint.spec.md` · reglas: `autonomous-safety.md`,
  `autonomous-safety-merge-grant.md` (SE-343), `maker-checker-protocol.md`
- Scripts: `scripts/risk-tier.py` (SE-362) · reservas F5 (SE-387)
