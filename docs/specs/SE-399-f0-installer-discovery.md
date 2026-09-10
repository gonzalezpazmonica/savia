---
id: SE-399-F0
parent: SE-399
status: READY_FOR_HUMAN_REVIEW
created: 2026-09-10
evidence_type: static-and-official-documentation-reconciliation
head: 8cf6c4bf3e3c38f6902df7ad55472674d860f016
---

# SE-399 F0 — Installer Discovery

## Estado

F0 completado sin instalar paquetes, modificar configuración global ni
implementar engine/UI. ID `SE-399` libre en refs disponibles. SAM todavía no
está implementado y SE-398 se limita a su F0; ambos son dependencias reales.

| Campo | Valor |
|---|---|
| HEAD | `8cf6c4bf3e3c38f6902df7ad55472674d860f016` |
| Spec path | `docs/specs/SE-399-visual-installer-environment-bootstrap.spec.md` |
| Veredicto | `GO_WITH_CONCERNS` para F1 de diseño; instalación funcional bloqueada |

## Current installation assets

| Área | Activos | Evaluación |
|---|---|---|
| Bootstrap | `install.sh`, `install.ps1`, `.opencode/install.*`, `scripts/savia-install.sh` | funcionalidad acumulada, mezclada con UI/ejecución |
| Setup | `scripts/savia-setup.sh`, `savia-preferences.sh`, `setup-savia-dual.*` | reutilizable por partes; no engine canónico |
| Install docs | README ES/EN, ADOPTION_GUIDE ES/EN, frontend migration guide | declarados; contienen drift de URLs/claims |
| Upgrade | `scripts/update.sh` | no plan transaccional ni rollback verificable |
| Doctor | `workspace-doctor.sh`, dual-cli doctor, sandbox doctor | sin Runtime/Surface ni support graduation |
| Receipts | bootstrap log, receipt-v2, audits/thermal/context receipts | no Installation Receipt estructurado |
| Package manifests | enterprise/rule/skill/OpenCode manifests | ninguno es Component Installation Manifest |
| Profile | profile template, active-user, profile-setup y onboarding rule | schema humano fragmentado, reutilizable |
| Project | `projects/PROJECT_TEMPLATE.md`, projects README, workspace/init scripts | sin schema/merge engine installer |
| Inference | model capabilities/registry, resolver, gateway, Savia Dual scripts/docs | reutilizable; sin provider install manifests |
| Secrets | redaction policy, credential-egress/proxy, preferences reject-list | no OS keychain; requiere threat model |

`bash scripts/test-install.sh` dio **36/38** y exit 1 en F0: `install.sh`
(441 líneas) e `install.ps1` (446) incumplen el límite contractual de 250.
No se corrige aquí porque F0 prohíbe implementación; se registra como gap
reproducible.

## SAM integration

Existing nodes/relations: ninguno machine-readable para instalación; `.scm`
solo proyecta capabilities. Required nodes: Installer, ProvisioningCore,
PlatformAdapter, InstallationManifest, RuntimePackage, SurfacePackage, IDE,
InferenceProvider, ProjectBootstrap e InstallationReceipt. Required relations:
INSTALLS, CONFIGURES, VERIFIES, DEPENDS_ON, PROVIDES, PROJECTS_TO,
SUPPORTED_ON, REQUIRES_PRIVILEGE, ROLLS_BACK y PRODUCES_RECEIPT.

No añadirlos antes de reconciliar el schema común de SE-397 F1 y SE-398 F1.

## SE-398 integration

Runtime/surface manifests, version constraints, surface canaries y support
states no existen todavía. Reutilizables: adapters, dual-cli, OpenCode plugin,
AGENTS/skills generators, doctors y canaries parciales. SE-399 debe consumir
esas futuras proyecciones, nunca recrearlas.

## Windows

| Área | Estado F0 |
|---|---|
| Existing support | `install.ps1` detecta Windows/WSL y usa winget/Chocolatey |
| Architecture | detección actual reduce a x64/x86; ARM64 no está modelado |
| Package strategy | winget preferente; Chocolatey fallback existente; manifests/provenance ausentes |
| Savia prerequisites | Git/Node requeridos, Python/jq opcionales; lógica embebida |
| OpenCode | npm install en script; vendor recomienda WSL para mejor compatibilidad |
| OpenCode Desktop | vendor ofrece Windows x64; WebView2 y sidecar/WSL son deltas; no bootstrap Savia |
| Claude Code | vendor soporta Windows vía WSL o Git Bash; doctor oficial disponible |
| Claude Code Desktop | disponible como app, pero local/cloud contract Savia no verificado |
| Codex | CLI local existe en la máquina F0; installer Windows no lo gestiona |
| Codex Desktop | documentación oficial indica Windows; installer/Savia evidence ausentes |
| IDE | no flujo común; VS Code/VSCodium solo candidatos |
| Known blockers | cero Windows CI runner/smoke, ARM64, privilege plan, rollback y mode native/WSL/hybrid |

Fuentes de vendor relevantes:
[OpenCode download](https://dev.opencode.ai/download),
[OpenCode WSL](https://opencode.ai/docs/de/windows-wsl/),
[Claude Code setup](https://docs.anthropic.com/en/docs/claude-code/getting-started)
y [OpenAI official docs](https://developers.openai.com/).

## Linux

| Área | Estado F0 |
|---|---|
| Supported distributions | install scripts declaran Debian/Ubuntu, Fedora/RHEL, Arch y Alpine; CI solo Ubuntu |
| Package strategy | apt/dnf/pacman/apk parcial; zypper ausente; no manifests |
| Architecture | `savia-install.sh` fija Node linux-x64; ARM64 no demostrado |
| Savia prerequisites | Git/Node + opcionales; clone/install/smoke mezclados |
| OpenCode | npm/binary/install script; Desktop oficial ofrece deb/rpm |
| OpenCode Desktop | Linux disponible oficialmente; Savia lifecycle/gates no verificados |
| Claude Code | Ubuntu/Debian documentados; local CLI no presente en F0 |
| Claude Code Desktop | documentación de app Linux existe, pero Code local contract no probado |
| Codex | CLI 0.153.4 probado solo como presencia en host |
| Codex Desktop | official evidence F0 no establece un paquete Linux confiable; `NOT_AVAILABLE/NOT_VERIFIED` |
| IDE | VS Code/VSCodium candidatos, no manifests |
| Known blockers | claims multi-distro sin matrix, ARM, signatures, package rollback y clean VMs |

## Installer engine

**Existing reusable code:** OS detection, basic package-manager invocation,
clone/update, setup scripts, smoke workflow, bootstrap logs, doctor/canaries,
profile/project/model metadata.

**New gaps:** Provisioning Core, declarative schema, dependency resolver,
deterministic preview/export/import, persistent state machine, structured
receipt, platform adapter interface, idempotency contract, backup/rollback and
crash recovery.

**Do not duplicate:** package managers, SE-398 manifests, SAM, profile/project/
model registries, doctors, receipts, security policy or runtime adapters.

## UI technology

| Candidate | Repo evidence | F0 assessment |
|---|---|---|
| Tauri 2 + web UI | `projects/savia-monitor` and `docs/savia-models/04-rust-tauri-vue-desktop.md` | strongest local reuse; small shell and explicit IPC/capabilities |
| Avalonia | none | viable .NET candidate, requires research/prototype |
| Qt | none | mature/native, larger skills/licensing/packaging evaluation |
| Flutter | language guidance only | cross-platform, no installer precedent |
| Electron | web familiarity only | widest ecosystem, larger footprint/attack surface |

**Recommendation:** time-boxed Tauri 2 feasibility probe, not final selection.
Evaluate Windows/Linux packaging, accessibility, signing/updater, secure IPC,
footprint and maintainability. ADR required before F1 closes. No dependency is
installed during F0.

## Profile

Canonical sources: `.claude/profiles/users/template/*.md`,
`.claude/profiles/active-user.md`, profile onboarding and setup command.
Installer gap: schema validation/API, privacy labels, backup/merge and
non-interactive projection. Never store credentials in general profile.

## Project

Canonical candidates: `projects/PROJECT_TEMPLATE.md`, project CLAUDE files,
workspace/init scripts. Gaps: machine-readable project schema, detection
result, config ownership, three-way reconciliation and deterministic preview.

## Inference

Canonical assets: `config/model-capabilities.yaml`,
`config/model-registry.json`, resolver/gateway and Savia Dual. Provider
adapters/local inference exist piecemeal. Gaps: provider manifest, safe model
discovery, compatibility states, OS credential-store integration and
non-sensitive connectivity canary. No provider is mandatory.

## Security

- Download provenance/checksum/signature is not consistently enforced.
- Existing installers contain remote script pipes and embedded package logic;
  these conflict with SE-399's transparent download model.
- Privilege actions are executed inline, not represented in a reviewed plan.
- Redaction/credential proxy are reusable but no OS-native secure-store
  contract exists.
- Supply-chain, command injection, path traversal, config poisoning, rollback
  corruption and plugin substitution need an explicit threat model.
- Repo URL drifts between `pm-workspace` and `savia`; source identity must
  be reconciled before generating trusted manifests.

## Licensing

Savia root license is MIT plus an enterprise policy/license. Rights to bundle
OpenCode, Claude, Codex, IDEs, inference engines and other dependencies were
not established. Default: invoke official external installers/package managers;
offline redistribution remains `UNKNOWN` until a license inventory exists.

## F1 minimum slice

Design only:

- ADR comparing UI candidates and selecting/provisionally rejecting one.
- Versioned JSON Schema for Component Manifest and Installation Plan.
- Provisioning Core interfaces for discovery/planning only.
- PlatformAdapter contract with fake Windows/Linux fixtures.
- State and Installation Receipt schemas compatible with existing receipts.
- Threat model and config ownership/rollback vocabulary.

Expected files: spec delta/ADR, schemas under a canonical config/contracts
location selected with SAM, read-only planner skeleton, fixtures and unit/BATS
tests. No package installation. Estimated complexity: high, 3–5 slices.

## Human decisions required

1. Approve F0 and whether SE-399 F1 may start before SE-397/398 F1.
2. Approve UI ADR after a feasibility probe; Tauri is only recommended.
3. Select initial execution modes: native Windows, WSL, or both; hybrid needs
   an explicit path/authority model.
4. Decide canonical distribution repository/channel after URL drift is fixed.
5. Approve any elevation, global config/PATH change, third-party redistribution
   or actual installation test.

## Verdict

`GO_WITH_CONCERNS` for architecture/design F1 only after review.
`NO_GO` for functional installer work today: SAM and SE-398 manifests are
absent, install tests are red, supply-chain integrity is incomplete and no
Windows operational evidence exists.
