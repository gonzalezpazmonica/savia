---
version_bump: patch
section: Changed
---

### Changed

- SE-477: la enmienda de empate total define non_inferiority_margin, alinea AC1/AC3 con los campos nuevos, usa 0 tareas con pérdida como disparador (Clopper-Pearson con k>0) y declara el supuesto de independencia.

- SE-477: el contrato de la enmienda exige `worst_loss_95` y `evidence` siempre que se afirme no inferioridad (cualquier k), define «pérdida» y ámbito (binario por tarea, pareado), rechaza `sufficient` con corpus reutilizado o cota > δ y pide `preregistration` verificable.

- SE-477: el test de la enmienda ancla cada aserción a texto que cambia (probado con mutación), usa ruta fija y declara δ como tasa de pérdidas.
