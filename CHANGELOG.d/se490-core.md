---
version_bump: minor
section: Added
---

### Added

- Soul Continuidad v1 (SE-490), núcleo, en `projects/soul-continuity` (TypeScript sobre Node.js oficial, sin dependencias de ejecución ni módulos nativos):
  - contrato de afirmaciones, adaptadores y API móvil, y banco de continuidad portados de Labs;
  - núcleo con instantánea Q1–Q4, TTL, libro de correcciones por operador, almacén atómico en el directorio de datos del usuario y STOP que sobrevive a reinicios; el banco pasa el gate con el 100 % por pregunta;
  - CLI `soul`; por un frontend de agente solo salen recuentos salvo un proveedor aprobado para N4 (AC-4d);
  - API local por HTTPS con certificado propio de la instalación, dispositivos emparejados y revocables, y escucha solo en las direcciones configuradas; los 27 tests de contrato de Labs pasan contra ella;
  - almacén de credenciales del sistema en Windows, macOS y Linux, con el secreto solo por stdin;
  - arranque sin administrador (`systemd --user`, `LaunchAgent`, tarea de inicio de sesión) y CI en los tres sistemas.
