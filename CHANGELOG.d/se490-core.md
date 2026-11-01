---
version_bump: minor
section: Added
---

### Added

- Soul Continuidad v1 (SE-490), núcleo, en `projects/soul-continuity` (TypeScript sobre Node.js oficial, sin dependencias de ejecución ni módulos nativos):
  - contrato de afirmaciones, adaptadores y API móvil, y banco de continuidad portados de Labs;
  - núcleo con instantánea Q1–Q4, TTL, libro de correcciones por operador, almacén atómico en el directorio de datos del usuario y STOP que sobrevive a reinicios; el banco pasa el gate con el 100 % por pregunta;
  - el núcleo descarta la lectura de un adaptador que devuelve una credencial en cualquier campo, así no llega a disco;
  - CLI `soul`; por un frontend de agente solo salen recuentos salvo un proveedor aprobado para N4 (AC-4d), y cada llamada suya queda auditada, también los rechazos y los errores;
  - API local por HTTPS con certificado propio de la instalación, dispositivos emparejados y revocables, escucha solo en las direcciones configuradas (ninguna forma de comodín ni de IPv4 mapeada) y límite de peticiones por dirección de origen; los 27 tests de contrato de Labs pasan contra ella;
  - transporte de solo lectura con loopback solo por literal y límite de cuerpo aplicado mientras se recibe;
  - almacén de credenciales del sistema en Windows, macOS y Linux, con el secreto solo por stdin;
  - arranque sin administrador (`systemd --user`, `LaunchAgent`, tarea de inicio de sesión) y CI en los tres sistemas.
