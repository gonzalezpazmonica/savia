---
version_bump: minor
section: Added
---

### Added

- SE-515 S1: recall trazado. learning-recall.sh, el hook de Claude Code y el guard de OpenCode registran qué criterios devolvieron y emitieron y si la emisión terminó; learning-metric.sh marca «no medido» sin --measured; el orquestador usa el recall efectivo o declara shadow; arnés de ablación P10 (learning-recall.sh ablation) que cuenta los fallos del inyector como error y marca «ruido» si cambia un control negativo. Interruptor SAVIA_LEARNING_APPLIED=off.

