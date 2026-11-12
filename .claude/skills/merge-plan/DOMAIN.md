# DOMAIN — merge-plan

## Por qué existe esta skill

`merge-sprint.sh` fusionaba siempre en orden ascendente de número. Cuando una PR choca con varias, ese orden puede aparcar más PRs de las necesarias. SE-500 S3 añade un plan ordenado con los choques previstos. Esta skill explica cómo leer ese plan antes de pedir el grant y qué llevar a la pregunta de la operadora.

## Conceptos de dominio

- **Manifiesto**: la lista de PRs candidatas, con su cabeza revisada y su tier. Lo genera `plan`.
- **order**: el orden de fusión que fija `plan`. El digest lo cubre: si cambia, el grant deja de valer, y `run` no reordena nunca.
- **collisions**: los pares `{pr, with, files}` que chocarán según `git merge-tree` entre sus cabezas revisadas.
- **Derivados y registros**: ficheros que se regeneran o que se resuelven solos, como los changelogs y los recuentos. Nunca generan aviso de choque.
- **Colisión no calculable**: la cabeza de la PR no está en el repo local. No se da por independiente.

## Límites y no-objetivos

- No fusiona ni concede grants. Solo prepara y explica el plan.
- No resuelve conflictos: eso lo hace `run`, con el resync y la equivalencia de S2.
- Es una heurística por pares: no simula la secuencia real contra `main`.

## Confidencialidad

- Nivel N1 (público). Solo describe el mecanismo; no contiene datos de PRs reales ni nombres de personas.

## Referencias

- Spec: `docs/specs/SE-500-merge-sprint-sin-realineacion.spec.md` § S3.
- Reglas: `docs/rules/domain/autonomous-safety-merge-sprint.md`, `docs/rules/domain/autonomous-safety-merge-grant.md`.
