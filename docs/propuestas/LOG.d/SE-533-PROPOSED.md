## 2026-11-14 SE-533 PROPOSED

Límites compartidos de delegación entre agentes, en seis slices en serie (S0 medición, S1 analizador, S2 permiso cerrado, S3 mediador en observación, S4 obligatorio con datos, S5 lanzadores). Solo spec: ningún guard, agente ni script se toca. Hallazgos verificados en main: el analizador da PASS a ciclo, autobucle y atajo (reproducido); su test está en skip y no corre en CI; seis agentes delegadores no declaran destinos; la variable de profundidad del guard no la escribe nadie. Sigue PROPOSED hasta que la operadora lo decida.
