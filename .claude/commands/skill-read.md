---
name: skill-read
description: Carga el contenido completo de un skill bajo demanda (progressive disclosure)
allowed-tools: [Read, Bash]
model_tier: fast
tier: core
---

Carga y muestra el SKILL.md completo del skill solicitado.

**Uso:** `/skill-read {nombre-skill}`

Pasos:
1. Buscar el skill en `.claude/skill-manifests.json`:
   `jq '.skills[] | select(.name=="$ARGUMENTS")' .claude/skill-manifests.json`
2. Si no existe → mostrar skills disponibles:
   `echo "Skill no encontrado: $ARGUMENTS. Skills disponibles:"; jq -r '.skills[].name' .claude/skill-manifests.json`
3. Leer el SKILL.md completo de la ruta indicada en el manifesto
4. Mostrar el contenido completo

El manifesto carga ~15 tokens/skill. Este comando carga el SKILL.md completo solo cuando es necesario.
