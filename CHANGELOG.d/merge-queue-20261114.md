---
version_bump: minor
section: Added
---

### Added

- Cola de fusión de GitHub: ci.yml y pr-guardian.yml se disparan con merge_group (los pasos que solo tienen sentido en una PR se saltan y los checks obligatorios siguen informándose); merge-sprint.sh gana un modo cola opcional, apagado por defecto (MERGE_SPRINT_QUEUE=1 o merge_queue=1), que encola cada PR autorizada con enqueuePullRequest atada a su head revisado (exige que la cola fusione con squash) y aparca las que GitHub expulsa, sin debilitar grant, manifiesto, juez ni ledger. Fail-closed en la cola: un estado ilegible para el run, la salida de la cola se verifica y, si una PR no sale, el run termina con anomalía conservando su reserva. Una respuesta perdida al encolar, un auto-merge pendiente o un STOP durante cualquier espera no dejan ninguna PR en la cola sin vigilancia; en modo serie, un gh pr merge que no fusiona en el acto para el run, y uno que falla con la PR dentro de la cola también. Una PR que GitHub fusiona antes de la primera lectura cuenta contra el máximo y se registra con su CI de main; grant, TTL y método squash se revalidan justo antes de cada entrada. Una PR que GitHub fusiona mientras se retira de la cola (espera agotada, expulsión, cabeza movida) se registra y cuenta en vez de liberar su reserva; una señal (SIGTERM) tras aceptar la entrada no la deja sin vigilancia, y una sola lectura «fuera» no basta para dar una retirada por buena. Los workflows de la cola quedan auditados: solo contents: read, escritura en una lista cerrada y ningún secreto salvo GITHUB_TOKEN.
