---
version_bump: patch
section: Added
---

### Added

- SE-535 (PROPOSED): entrada de skills externas. El instalador de la integración externa enlaza skills de terceros sin leerlas y sin versión fijada, y las tres órdenes de marketplace no tienen implementación. Por decisión de la operadora se retiran ambos caminos en dos slices; el diseño de una puerta de entrada (origen fijado, copia defensiva, cabecera reducida, recibo y fallo en cerrado) queda en reserva y no se construye mientras no haya nada que entre por ella. Solo spec; ningún script ni orden cambia todavía.
