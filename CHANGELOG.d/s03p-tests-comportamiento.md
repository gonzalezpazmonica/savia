---
version_bump: patch
section: Security
---

### Security

- S03p: savia-shield-check.sh daba «shield active» si dataSovereigntyGate o blockCredentialLeak seguían importados pero retirados (o comentados) de la lista de guards; ahora exige el guard registrado como elemento de lista, block-credential-leak-wired es crítico, con cero componentes el JSON da [] y no [""], y un workspace inexistente sale 2
- S03p: changelog-spec-field-check.sh busca specs también en docs/propuestas y archivos, con nombre exacto (SE-25 ya no casa con SE-253-*), valida el id y normaliza comillas/CRLF
- S03p: agents-size-checker.sh falla cerrado (exit 2) sin directorio de agentes en vez de «Total: 0 agents», y escapa comillas y barras en JSON
- S03p: plan-diff-check.sh funciona fuera de la raíz del repo (antes salía 0 en --mode block), --strict y --diff funcionan y rechaza argumentos desconocidos; plan-validate.py entiende la lista de ficheros con comas de la spec
- S03p: pruebas de comportamiento para 4 ficheros de test (rescate del worker s03p)
