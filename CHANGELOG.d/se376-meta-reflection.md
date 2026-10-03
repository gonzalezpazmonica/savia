---
version_bump: patch
section: Fixed
---

### Fixed

- meta-reflection: historical-priors.py no compilaba (SyntaxError) y trigger-evaluator nunca cargaba operator-state ni priors (import con guion); override_rate contaba los reframes, la franja de fatiga no cruzaba medianoche, deadline_proximity rechazaba coma decimal y reaffirm aceptaba razones de solo espacios. Una tarea sin tags ya no suma precedentes de cualquier tema; deadline_proximity nan/inf o con clave prefijo ya no cuenta como presion maxima; los fallos de senal quedan en signals_degraded y en la telemetria del hook (priors_source). Tests de score exacto que matan los mutantes de pesos y de priors. Test bats certificado.

