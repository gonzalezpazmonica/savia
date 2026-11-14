---
version_bump: minor
section: Added
---

### Added

- Cola de fusión de GitHub: ci.yml y pr-guardian.yml se disparan con merge_group (los pasos que solo tienen sentido en una PR se saltan y los checks obligatorios siguen informándose); merge-sprint.sh gana un modo cola opcional, apagado por defecto (MERGE_SPRINT_QUEUE=1 o merge_queue=1), que encola cada PR autorizada sobre su head revisado y aparca las que GitHub expulsa, sin debilitar grant, manifiesto, juez ni ledger.

