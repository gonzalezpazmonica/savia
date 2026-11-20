---
version_bump: patch
section: Removed
---

### Removed

- SaviaVaults: se retira el hash de 32 bits de la federación (hash-verify.ts y su test) y el AC-4.5 de SE-287; no protegía nada y nadie lo usaba (K6-c).

- SaviaVaults: `FEDERATION.md` dejaba de ser cierto al decir que los resultados federados manipulados se descartan y que eso evita MITM. Ahora dice que no se verifica la integridad de los resultados remotos y que la protección depende de TLS y del token. Un test impide que la promesa vuelva.
