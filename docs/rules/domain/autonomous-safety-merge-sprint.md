---
context_tier: L3
token_budget: 1600
spec: SE-433
status: APPROVED
---

# merge-sprint — merges autónomos bajo autorización humana previa (SE-433)

> Apéndice de `autonomous-safety.md`. SE-433 está **APPROVED** por la operadora (2026-10-04). Mientras
> `scripts/merge-sprint.sh` no esté mergeado, ningún merge en serie es válido y rige el merge uno a uno
> (`autonomous-safety-merge-grant.md`).

## Principio

La autorización solo nace de la respuesta expresa de la operadora (el grant). Ninguna salida de un agente puede añadir un PR, subir
un tier, prorrogar el sprint ni sustituir una revisión. Las revisiones, el juez, la CI y el
clasificador de riesgo solo pueden **mantener o restar**: dejar seguir un PR ya autorizado, aparcarlo o
parar el sprint. Lo irreversible se decide con confirmación humana (`savia-ethical-principles.md`).
Lo que se afirma es «lo autorizó un humano, de forma expresa, sobre una lista concreta y tras ver las
revisiones de agentes». No se afirma que un humano haya leído el diff.

## Ciclo

1. `review-register`: cada revisión y cada veredicto de juez se registra en un registro encadenado,
   con espejo como comentario del PR.
2. `plan`: un agente prepara un borrador de manifiesto. No es de confianza.
3. `render-question` y luego `grant`. `render-question` recalcula todo desde GitHub y `origin/main` y
   emite la pregunta con el manifiesto completo y su digest. La sesión orquestadora la formula con
   AskUserQuestion, y justo después de la respuesta ejecuta `grant`, que registra la pregunta y la
   respuesta literales, la sesión, la hora y el hash.
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

Límite: el grant es un fichero que escribe un agente. Su autenticidad depende del harness de Claude
Code y del clasificador, no de criptografía. Mitigaciones: ledger encadenado, coincidencia exacta con
el manifiesto, informe a la operadora, `ask` en el permiso de `grant`, hook contra la emisión desde
un subagente y contraste con el transcript (si son viables) y revocación inmediata.

## Revisión

- Primera línea: `VERDICT: APPROVE|HOLD pr= sha= role=correctness|security tier= reviewer= author=
  p0= p1= p2= p2_blocking=`. Cualquier otra forma equivale a HOLD.
- `APPROVE` exige `p0=p1=p2_blocking=0`. El SHA es el del head autorizado. El revisor es distinto del
  autor y del orquestador.
- Se recogen **todas** las revisiones registradas de cada PR y SHA: un solo HOLD lo excluye.
- Tier 1/2 necesita una APPROVE `correctness`. Tier 3 necesita además una APPROVE `security` y el
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

- Se admiten sin juez:
  - un merge de `main`;
  - la regeneración de los artefactos SAM generados;
  - `.confidentiality-signature`, solo si la auditoría repetida sobre el nuevo head da PASSED.
- Cualquier otro cambio va al juez.

## Juez de cambios posteriores al grant

- **Prefiltro determinista.** Antes de consultar al juez, provoca STOP cualquier delta que toque
  ficheros fuera de los autorizados o paths de tier 3 o gobernanza, suba el tier, añada o borre
  ficheros, elimine tests o aserciones, debilite un test (`skip`, `|| true`, `xfail`), cambie
  binarios o modos, o supere 200 líneas.
- **Solicitud.** Acotada al grant y al head: `judge/<grant>/<pr>-<head>.request.json`. Un commit
  nuevo la deja obsoleta y el head nuevo se evalúa de cero.
- **Veredicto.** Primera línea: `JUDGE: SAFE|STOP pr= from= to= judge= fix_author= scope= security=
  reason=`. `fix_author` es el email del autor del commit o su trailer `Fix-Author:`. El juez es
  distinto del autor del fix, del autor original y del orquestador. Ante la duda, STOP.
- **Pausa.** Mientras un PR espera al juez conserva la etiqueta `merge-sprint:<id>`. `plan` borra
  las etiquetas de sprints muertos.
- **Comprobación del ejecutor.** El ejecutor verifica el formato, los SHA, la independencia y la
  unicidad. Un veredicto `SAFE` solo deja seguir al PR, con CI nueva. `STOP` detiene el sprint para
  revisión humana.

| Evento | Acción |
|---|---|
| CI roja del PR (con tarea de causa raíz), conflicto real, revisión cambiada o HOLD nuevo, tier elevado, merge rechazado | Aparcar (vuelve a Draft si el ejecutor lo sacó de Draft) y seguir |
| CI de `main` no verde tras un merge (rojo, pending, ausente, cancelled, skipped) | Parar |
| Grant inválido o revocado, manifiesto o blobs alterados, merge externo (sin reserva propia, o de otro SHA u otra cuenta), base cambiada, checks reducidos | Parar (anomalía) |
| Juez `STOP`, veredicto inválido o fuera de plazo | Parar |
| Máximo de merges, TTL, fichero STOP, 3 aparcamientos seguidos | Parar |

Parar siempre es seguro. Un sprint parado por una condición de parada no se reanuda sin un grant
nuevo.

## Tier 3/4

- **Tier 3.** Por decisión de la operadora, la aprobación del manifiesto que lista el PR por número es la
  revisión humana del PR concreto (SE-362), junto con una revisión de seguridad de un agente
  independiente. Esto modifica la lectura de SE-362 y de Rule 8 E1 para tier 3. Ningún humano lee el
  diff.
- **Tier 4.** Nunca entra. Incluye el ejecutor, `risk-tier.py`, la
  configuración de permisos de Claude Code y OpenCode, las reglas `autonomous-safety*`, `CLAUDE.md`,
  `AGENTS.md`, los principios éticos, la honestidad radical y `.github/workflows/`.

## Auditoría

El ledger local es append-only y está encadenado por hash; se valida con `verify-ledger`. Cada merge
registra el grant y el digest del manifiesto, el tier, el SHA autorizado, el mergeado y el tipo de
equivalencia, la referencia al juez, los hashes de las revisiones, los ids de CI y los checks
obligatorios, el commit de merge, la CI de `main` y las horas.

Al final se genera un informe para la operadora. Nada de esto se versiona.

## Permiso en el frontend

Lo concede la operadora en sus settings, nunca un agente:

- **Allow**: `run|status|stop|revoke|report|plan|render-question|review-register|verify-ledger`.
- **Ask**: `grant`.
- **Deny**: `gh pr merge`, la edición del ejecutor y de `risk-tier.py`, y la escritura en
  `~/.savia/merge-sprints/`.

Sin un grant vigente para el manifiesto exacto, `run` termina con error. No elude el clasificador: la
operadora autoriza expresamente y concede un único camino, acotado y auditable.

## Límite declarado

Un agente con shell arbitraria del mismo usuario puede saltarse cualquier script; lo contienen los
permisos del frontend, no esta regla. El revisor, el revisor de seguridad y el juez son instancias del
mismo modelo y comparten sesgos. Las identidades de los agentes son autodeclaradas: el registro
encadenado detecta que alguien compre veredictos antes de `plan`, pero no lo impide.

- La independencia del juez compara su id declarado con emails git y trailers `Fix-Author:`, que son
  espacios de nombres distintos: un agente que firma con email y juzga con su id no se detecta.
- Las reservas F5 van por manifiesto (digest), no por grant: un merge reservado bajo un grant
  anterior del mismo manifiesto cuenta como propio.
- La re-sincronización ejecuta generadores de la rama del PR (`sam.py`, escáner y firma) antes de
  que el prefiltro y el juez vean el delta.

## Referencias

- Spec: `docs/specs/SE-433-merge-sprint.spec.md`
- Reglas: `autonomous-safety.md` · `autonomous-safety-merge-grant.md` (SE-343) ·
  `maker-checker-protocol.md`
- Scripts: `scripts/risk-tier.py` (SE-362) · reservas F5 (SE-387)
