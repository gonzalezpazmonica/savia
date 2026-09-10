---
id: SE-399
status: APPROVED
priority: P0
developer_type: agent-team
created: 2026-09-09
approved: 2026-09-10
approved_by: human-operator
author: agent-team
parent: [SE-397, SE-398]
related_specs: [SE-037, SE-391, SE-393, SE-394, SE-395, SE-396, SE-397, SE-398]
risk: L2
type: distribution-bootstrap-experience
working_title: Savia Visual Installer & Environment Bootstrap
execution_scope: F0_ONLY_PENDING_REVIEW
---

# SE-399 — Savia Visual Installer & Environment Bootstrap

## 1. Problema y objetivo

Crear una experiencia visual Windows/Linux que convierta una máquina en un
entorno Savia instalado, configurado, verificable, actualizable, reparable,
desinstalable y reproducible. El happy path no exigirá terminal, pero siempre
mostrará detalles, logs sanitizados, sources, privilegios, cambios, verificación
y rollback.

```text
SAVIA → SAM → INSTALLATION PLAN → PROVISIONING CORE
                                  ├─ Windows adapter
                                  └─ Linux adapter
```

La GUI proyecta un plan declarativo; no contiene lógica canónica ni posee
policy. SE-398 decide si Savia funciona correctamente en un runtime/surface;
SE-399 decide cómo instalarlo/configurarlo.

## 2. Invariantes y no objetivos

- `INSTALLABLE != INSTALLED != CONFIGURED != VERIFIED != SUPPORTED`.
- Installer, GUI, package manager, runtime, IDE, modelo y provider no son Savia
  ni poseen authority.
- Detección o credencial presente no implica trust/authorization.
- No crear package manager, almacenar secretos en texto plano, asumir admin,
  modificar PATH/config global sin consentimiento, ocultar instalaciones,
  descargar sin provenance, desactivar TLS/antivirus/firewall/sandbox, exigir
  cloud/model/runtime/IDE concreto ni borrar datos de usuario por defecto.
- Nunca sobrescribir configuración o instrucciones existentes sin diff,
  reconciliation, preview y backup seguro.
- Estado de seguridad desconocido falla de forma segura.

## 3. Alcance inicial

MVP: Windows x64 y ARM64 donde exista soporte; Linux x64/ARM64, inicialmente
Ubuntu/Debian. Evaluar Fedora/RHEL y Arch después. Componentes: Savia core,
adapters, manifests, agents/skills/hooks/scripts/doctor/receipts; runtimes
OpenCode, Claude Code y Codex; surfaces disponibles CLI/TUI/Desktop; VS Code y
VSCodium opcionales; providers cloud/local/custom endpoint; MCP e integraciones
seleccionadas; toolchains solo por necesidad del proyecto.

Modos Windows a decidir en F0: native, WSL o hybrid. Hybrid debe distinguir
host path, guest path, mount path y execution context.

## 4. Solución: Provisioning Core y manifests

Separar GUI, engine, platform adapters, package managers, manifests y receipts.
Cada component manifest versionado declara ID/category, OS/arch, detection,
dependencies, install/verify/uninstall/rollback, source/integrity/license,
optional/restart/privilege/conflicts/capabilities y compatibility versions.
Nunca hardcodear URLs o versiones en botones.

El resolver produce un preview determinista de componentes/versiones/sources,
download/disk impact, privilegios, PATH/files/services/config/project changes y
restarts. Preferencia de supply chain: package manager oficial → instalador
oficial firmado → release oficial → descarga manual autorizada.

Acciones usan structured process invocation (`executable`, `args[]`, env
allowlist y cwd); shell solo cuando sea imprescindible. HTTPS, checksum y firma
se validan cuando existan; checksum/firma inválidos bloquean el componente.

## 5. Estado transaccional

Workflow: `PLAN → CHECKPOINT → EXECUTE → VERIFY → COMMIT`; rollback donde sea
viable. Acciones se clasifican reversibles, parcialmente reversibles o no
reversibles y estas últimas se muestran antes de ejecutar.

Estados persistentes: discovery, planning, ready, installing, verifying,
completed, completed-with-warnings, failed, rolling-back, rolled-back,
partially-rolled-back y repair-required. Tras crash: resume, rollback o inspect;
nunca asumir completion. Reaplicar un plan no duplica PATH, config, hooks,
agents, MCP, profile ni project bootstrap.

## 6. Modos y experiencia

Welcome ofrece instalar, actualizar, reparar, importar workspace, crear
proyecto, configurar, desinstalar y avanzado/offline. Flujo principal:
Welcome → Detect → Choose → Configure → Review → Install → Verify → Finish.
Siempre: Back, Cancel, Details y Logs.

Presets: minimal, developer, agentic-engineering, full-desktop, local-AI y
custom. Son defaults, nunca authority profiles. Selección granular muestra
installed/available/recommended/required/optional/unsupported y estrategia
recommended/latest-compatible/pinned/existing.

UI preparada para español/inglés, teclado, screen reader, alto contraste,
texto escalable y estados no dependientes solo del color. Progreso basado en
stages reales. Errores indican qué falló, causa, cambios, rollback, remanente y
acción recomendada.

## 7. Discovery y preflight

Detectar de forma sanitizada OS/arch/user, capacidad de elevación, HOME/shell/
PATH, git, package managers, WSL, Savia/runtimes/Desktop/IDEs/inference
existentes, provider metadata y project roots. No leer secretos.

Preflight: ready, warnings o blockers para disco, arquitectura/versión,
conflictos, permisos, package manager, proxy, red y certificados. Agrupar
elevaciones USER/ELEVATED/ROOT-ADMIN y usar mecanismos OS nativos.

## 8. Profile, project, IDE e inference

Reutilizar schemas canónicos. Profile wizard solo usa campos soportados y
explica qué queda local, entra en contexto o puede llegar al provider. Project
wizard crea/importa/clona/adjunta; detecta git, stack, tests, CI, containers,
docs e instrucciones AI; muestra antes todos los ficheros/projections/hooks/
config que cambiará.

GitHub no es obligatorio. SSH keys no se crean sin consentimiento. IDE y
extensions son opcionales. Toolchains/containers se sugieren por necesidad;
Docker/Podman/WSL requieren consentimiento explícito cuando su instalación
tiene impacto.

Inference ofrece cloud/local/custom endpoint mediante provider manifests sin
secretos. Preferir login oficial/device/browser/runtime secure store. Mostrar
data boundary, availability vs verification y modelos/routing ya soportados por
Savia. Connectivity canary usa datos no sensibles y no envía el proyecto.

## 9. Runtime/surface y doctor

Consumir manifests, version constraints, support states y canaries de SE-398;
no duplicarlos. Por runtime: install/detect, project projection, instructions,
agents, skills, hooks/equivalent, permissions y smoke canary. Desktop bootstrap
es una proyección SE-398.

Después de instalar: doctor devuelve `INSTALLED_NOT_VERIFIED`,
`DEGRADED_SAFE`, `SUPPORTED`, `BLOCKED` o `UNKNOWN`. El installer nunca eleva
el support state. Actualizar runtime invalida solo evidencia relevante y lanza
smoke corpus.

## 10. Receipts, repair, upgrade y uninstall

Installation Receipt sin secretos: ID/timestamp, versiones Savia/installer,
OS/arch, componentes/versiones/sources/checksums, acciones y elevaciones,
config changes, verification, rollback, warnings y failures.

Repair detecta drift/missing files/dependencies/PATH/manifests/runtime/config y
ofrece cambios seleccionados con preview. Upgrade hace backup, resuelve
migración, preview, update, verify/canaries y rollback o degraded-safe.
Uninstall separa app, adapters, generated config, projects, profile, cache y
receipts; preserva datos de usuario por defecto.

## 11. Reproducibilidad, offline y seguridad

Export/import de installation plan sin secretos; revalidar plataforma,
versiones, firmas y preview antes de aplicar. El mismo engine permitirá futuro
headless mode. Offline bundle solo redistribuye terceros cuando su licencia lo
permite; en caso contrario declara external prerequisite.

Threat model: package substitution, manifest tampering, privilege escalation,
command injection, path traversal, malicious config, secret leakage, unsafe
shell, rollback corruption y plugin substitution. Manifests críticos quedan
versionados y ligados a release/hash/firma cuando la arquitectura lo permita.
Telemetría no obligatoria; cualquier futura telemetría será opt-in.

## 12. SAM Installation View

Entidades futuras: Installer, ProvisioningCore, PlatformAdapter,
InstallationManifest, RuntimePackage, SurfacePackage, IDE, InferenceProvider,
ProjectBootstrap e InstallationReceipt. Relaciones: `INSTALLS`, `CONFIGURES`,
`VERIFIES`, `DEPENDS_ON`, `PROVIDES`, `PROJECTS_TO`, `SUPPORTED_ON`,
`REQUIRES_PRIVILEGE`, `ROLLS_BACK`, `PRODUCES_RECEIPT`.

Debe responder qué falta, qué versión/source/privilegio aplica, qué falló o se
modificó y qué puede retirarse sin romper dependencias.

## 13. Fases

- F0: reconciliación/product discovery; sin implementación.
- F1: arquitectura engine/manifest/state/receipt/platform/UI boundary + ADR UI.
- F2: detection, dependency graph, plan y preview read-only.
- F3: instalación mínima Windows + Debian/Ubuntu con un runtime y doctor.
- F4: wizard visual MVP.
- F5: runtime/Desktop desde SE-398.
- F6: profile/project.
- F7: inference.
- F8: IDE/toolchains.
- F9: repair/upgrade/uninstall.
- F10: expansión Linux.
- F11: offline/planes/headless-ready.
- F12: hardening.
- F13: graduación humana.

Estimación inicial: esfuerzo muy alto y evolución multiphase; F1 es un slice
medio de contratos, schemas y ADR, sin instalar paquetes.

## 14. Acceptance Criteria

- AC01–AC10 core: IDs/dependencias reconciliados; core independiente de GUI;
  platform adapters; manifests; dependency resolver; preview; receipts; crash
  recovery.
- AC11–AC25 Windows: detección OS/arch/package manager/privilege, instalación de
  Savia/runtime/surface/IDE seleccionados, profile/project/inference, doctor,
  smoke, repair y uninstall que preserva datos.
- AC26–AC40 Linux: equivalentes para distribuciones soportadas.
- AC41–AC50 seguridad: cero secrets en logs/receipts/plans, provenance e
  integridad, structured invocation, TLS intacto, privilegios visibles,
  backups y no overwrite silencioso.
- AC51–AC58 runtime: consume SE-398, surfaces separadas, versiones/freshness y
  doctor fiel; installer no gradúa support.
- AC59–AC65 inference: al menos un flujo cloud y uno local/custom evaluado,
  secure credentials, canary no sensible, compatibilidad explícita y ningún
  provider obligatorio.
- AC66–AC75 UX: happy path sin terminal, details/back/cancel/progreso real,
  error accionable/rollback, español/inglés, accesibilidad y clean VM.

## 15. Test matrix y corpus

Windows/Linux clean, existing, partial y upgrade; offline, no-admin, proxy,
broken dependency y conflicting runtime. Golden corpus: fresh minimal/full,
custom runtime, existing Git/IDE/old Savia, repair/upgrade, package/network/
checksum failures, cancel/resume/rollback, existing/new project, auth failure y
runtime canary failure.

## 16. Human Gates

Fases posteriores requieren revisión de F0. Installation execution, elevación,
PATH/config global, container/WSL, project/profile destructive removal,
credential/provider activation, UI technology ADR, supported OS/component y
release channel mantienen sus gates explícitos. No auto-graduation.

## 17. Instrucción inmediata

Persistir la spec y ejecutar **solo F0**. Entregar inventario de activos,
SAM/SE-398 integration, Windows/Linux, engine/UI/profile/project/inference,
security/licensing, slice F1 y decisiones humanas. No F1 hasta revisión.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode | Codex |
|---|---|---|---|
| F0 | inventario bootstrap/proyección | inventario installer/runtime | inventario installer/runtime |
| F1+ | consume manifest canónico | consume manifest canónico | consume manifest canónico |

### Verification protocol

- [x] F0 no instala paquetes ni modifica configuración global.
- [ ] Engine futuro se prueba en Windows y Linux con fixtures/VMs.
- [ ] Runtime bootstrap futuro consume SE-398 y conserva authority.

### Portability classification

- [x] **DUAL_BINDING** ampliado a tres runtimes; el Provisioning Core será
  frontend-agnostic y las diferencias vivirán en platform/runtime projections.
