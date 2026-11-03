---
version_bump: patch
section: Security
---

### Security

- merge-sprint (SE-500 S2, revisión #1469): los derivados se comparan contra su contenido en merge(H0, main) antes de regenerar, de modo que un fichero de .scm/ añadido tras la revisión ya no es equivalente; la raíz congelada sirve también .claude/hooks/lib de main, es única por llamada y falla cerrada si un generador escribe fuera del árbol; plan usa el resolutor de main; la cola del juez integra registros desde la cabeza SAFE sin perder el arreglo juzgado.

