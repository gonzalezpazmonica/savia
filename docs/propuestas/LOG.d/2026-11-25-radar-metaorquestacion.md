## 2026-11-25 Radar de metaorquestación: tres enmiendas y congelación de autoridad

La operadora entregó un radar con 15 líneas (M01–M15) sobre metaorquestación de harnesses y factorías. Una analista
independiente las cruzó con el código: ninguna justifica una spec nueva. Decisión de la operadora por pregunta
interactiva: «Ampliar las tres specs». Tres enmiendas en PROPOSED: SE-495 (configuración como factor y brazo de un solo
ejecutor), SE-515 P10 (brazo de paquete mínimo y estados recordar, aplicar y mejorar) y SE-482 F2 (medir escrituras
perdidas antes de añadir concurrencia). Descartadas con su motivo: factorías por eventos (M08, contradice la retirada
de SE-493 y SE-513 del 14-11), manifiesto de factoría (M09, duplica SE-531 S3 y SE-496), adaptación de modelos con
LoRA (M11), routing sensible a caché (M12) y compilación de skills (M06). Ya cubiertas: M01 en parte (SE-531), M05
(SE-497), M14 (SE-489) y M15 (SE-461, SE-462, SE-465, SE-466).

Decisión del mismo día, «Congelar y conectar»: no se abre ninguna fase nueva de autoridad hasta que cada pieza ya
fusionada tenga un consumidor real o se retire (#1593, #1597, #1611, #1612, #1615, #1616, #1617). Primer consumidor
previsto: que el guion de fusiones obedezca el freno de emergencia. Sigue vigente la excepción del 14-11 sobre AEK
(SE-496), que se conserva como línea de futuro.
