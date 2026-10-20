# Spec Template — Spec-Driven Development

> Plantilla estándar para specs ejecutables por humanos o agentes Claude.
> Copiar y rellenar para cada Task. El objetivo es que no quede ningún campo ambiguo.

> **spec_kit_compatible: true** — Este template es compatible con [github/spec-kit](https://github.com/github/spec-kit) como superset. Las 4 secciones estándar de spec-kit (`What & Why`, `Requirements`, `Technical Design`, `Acceptance Criteria`) se mapean a las secciones extendidas de Savia como se indica abajo.

---

## Spec-Kit Alignment

Correspondencia entre secciones spec-kit estándar y secciones Savia extendidas:

| spec-kit (estándar) | Savia (extendido) |
|---|---|
| `## What & Why` | `## 1. Contexto y Objetivo` |
| `## Requirements` (Functional + Non-Functional) | `## 2. Contrato Técnico` + `## 3. Inputs/Outputs` + `## 3. Reglas de Negocio` + `## 4. Constraints and Limits` |
| `## Technical Design` | `## 2.3 Dependencias` + `## 7. Código de Referencia` |
| `## Acceptance Criteria` | `## Criterios de aceptación con autoridad (SE-444)

> Regla: `docs/rules/domain/ac-verifier-authority.md`. Valores: `real` | `simulada` | `estatica`.

| AC | Verificación | autoridad_requerida | autoridad_obtenida |
|---|---|---|---|
| AC1 | {comando o prueba} | {real / simulada / estatica} | {se rellena al cerrar} |

Un AC cuyo texto exige comportamiento real no se cierra con `simulada` ni `estatica`; si la autoridad no está disponible, se registra como skip con nombre y motivo.

### Autorizaciones literales (opcional; recomendable en riesgo L3+)

| Cita textual de la persona | Alcance | Fecha | Sustituida por |
|---|---|---|---|
| «{cita literal}» | {qué autoriza y qué no} | {YYYY-MM-DD} | {- o referencia} |

---

## 5. Test Scenarios` + `## 10. Checklist Pre-Entrega` |

**Secciones exclusivas Savia** (no mapeables a spec-kit):
- `Developer Type` (human | agent-single | agent-team) — para SDD agent routing
- `Effort Estimation (Dual Model)` — agent/human/review effort + context risk
- `Sección 6: Ficheros a Crear/Modificar` — precisión operativa para agentes
- `Sección 9: Estado de Implementación` — log iterativo
- `Sección 12: Iteration & Convergence Criteria` — checklist de madurez

**Uso con tooling externo**: Herramientas que consumen specs spec-kit leerán las 4 secciones estándar por sus headers canónicos. Para exportar a spec-kit puro, copiar las secciones mapeadas y omitir las exclusivas de Savia.

---

## Cabecera

```markdown
# Spec: {Tipo} — {Título descriptivo}

**Task ID:**        AB#{id}
**PBI padre:**      AB#{pbi_id} — {título del PBI}
**Sprint:**         {sprint, ej: 2026-04}
**Fecha creación:** {YYYY-MM-DD}
**Creado por:**     {PM/Tech Lead}

**Developer Type:** human | agent-single | agent-team
**Asignado a:**     {nombre_dev | claude-agent | claude-agent-team}
**Estado:**         Pendiente | En Progreso | Completado | Bloqueado

**Effort Estimation (Dual Model):**
| Dimension | Value |
|-----------|-------|
| Agent effort | {XX min} |
| Human effort | {XX h} |
| Review effort | {XX min} |
| Context risk | {low / medium / high / exceeds} |
| Agent-capable | {yes / no / partial} |
| Fallback | {Si agente falla: humano necesita Xh desde cero} |
```

---

## 1. Contexto y Objetivo

> *¿Por qué existe esta task? ¿Qué problema resuelve? 2-4 frases.*

```
Contexto del PBI:
[Describe brevemente el PBI padre y cómo encaja esta task dentro del PBI.]

Objetivo de esta task:
[Qué debe existir al finalizar esta task que no existía antes.]
```

> **Principio SDD**: Describe QUÉ hace el código (contratos, interfaces, comportamiento), NO CÓMO lo implementa. El agente decide el cómo.

**Criterios de Aceptación del PBI (extracto relevante):**
```
- [ ] {AC relevante al alcance de esta task}
- [ ] {AC relevante al alcance de esta task}
```

---

## 2. Contrato Técnico

> *El contrato define exactamente qué se debe implementar. Debe ser inequívoco.*

### 2.1 Interfaz / Firma

```csharp
// Clase / interface / método principal que debe existir al terminar la task

// Ejemplo para un Command Handler:
public class CreatePatientCommand : IRequest<Result<Guid>>
{
    public string Name { get; init; }
    public DateTime BirthDate { get; init; }
    public string NationalId { get; init; }  // DNI/NIE
}

public class CreatePatientCommandHandler : IRequestHandler<CreatePatientCommand, Result<Guid>>
{
    Task<Result<Guid>> Handle(CreatePatientCommand request, CancellationToken ct);
}

// Ejemplo para un endpoint:
// POST /api/v1/patients
// Request body: CreatePatientRequest (definida en sección 2.2)
// Response: 201 Created + { "id": "{guid}" }
// Errores: 400 (validación), 409 (DNI duplicado), 500 (error interno)
```

### 2.2 Modelos de Entrada y Salida

```csharp
// Todos los DTOs, Request y Response deben estar definidos aquí
// con sus tipos de datos y restricciones

public record CreatePatientRequest
{
    [Required]
    [MaxLength(200)]
    public string Name { get; init; }

    [Required]
    public DateTime BirthDate { get; init; }

    [Required]
    [RegularExpression(@"^[0-9]{8}[A-Z]$|^[XYZ][0-9]{7}[A-Z]$")]
    public string NationalId { get; init; }  // DNI o NIE
}

public record CreatePatientResponse
{
    public Guid Id { get; init; }
}
```

### 2.3 Dependencias e Inyección

```csharp
// Interfaces que debe recibir por inyección el componente a implementar

// Ejemplo:
public CreatePatientCommandHandler(
    IPatientRepository patientRepository,   // Repositorio de pacientes
    IUnitOfWork unitOfWork,                 // Para commit de transacción
    IMapper mapper,                          // AutoMapper para mapeos
    ILogger<CreatePatientCommandHandler> logger
)
```

---

## 3. Inputs / Outputs Contract

> *Define exactamente QUÉ datos entran y QUÉ datos salen. Tipos concretos, no vaguedades.*

### Inputs

```csharp
// Parámetros tipados que el componente acepta (entrada)

// Ejemplo — CreatePatientCommand:
public record CreatePatientCommand : IRequest<Result<Guid>>
{
    /// <summary>
    /// Nombre completo del paciente (1-200 caracteres)
    /// Ejemplo: "Juan García López"
    /// </summary>
    [Required]
    [MinLength(1)]
    [MaxLength(200)]
    public string Name { get; init; }

    /// <summary>
    /// Fecha de nacimiento (no puede ser futura)
    /// Formato: ISO 8601 (YYYY-MM-DD)
    /// Ejemplo: "1985-03-15" → 40 años
    /// </summary>
    [Required]
    public DateTime BirthDate { get; init; }

    /// <summary>
    /// DNI o NIE español (debe pasar validación de algoritmo)
    /// Formato: 8 dígitos + 1 letra (DNI) O X/Y/Z + 7 dígitos + 1 letra (NIE)
    /// Ejemplo: "12345678A" o "X1234567A"
    /// </summary>
    [Required]
    [RegularExpression(@"^[0-9]{8}[A-Z]$|^[XYZ][0-9]{7}[A-Z]$")]
    public string NationalId { get; init; }
}
```

### Outputs

```csharp
// Valores tipados que el componente retorna (salida)

// Ejemplo — Response:
public record CreatePatientResponse
{
    /// <summary>
    /// ID único del paciente creado (GUID)
    /// Formato: UUID v4
    /// Ejemplo: "550e8400-e29b-41d4-a716-446655440000"
    /// </summary>
    [Required]
    public Guid Id { get; init; }
}

// Ejemplo — HTTP Response (201 Created):
{
    "id": "550e8400-e29b-41d4-a716-446655440000"
}

// Ejemplo — Errores (4xx/5xx):
// 400 Bad Request — validación fallida
{
    "error": "ValidationException",
    "message": "El campo Name no puede estar vacío",
    "traceId": "0HN8V5EGPE72B:00000001"
}

// 409 Conflict — DNI duplicado
{
    "error": "DuplicateNationalIdException",
    "message": "El DNI 12345678A ya existe en el sistema",
    "traceId": "0HN8V5EGPE72B:00000002"
}
```

---

## 3. Reglas de Negocio

> *Cada regla debe ser verificable en tests. No usar "según corresponda" ni "a criterio del dev".*

| # | Regla | Error a lanzar | Código HTTP |
|---|-------|---------------|-------------|
| RN-01 | El DNI/NIE debe ser único en el sistema | `DuplicateNationalIdException` | 409 |
| RN-02 | El nombre no puede estar vacío ni tener solo espacios | `ValidationException` | 400 |
| RN-03 | La fecha de nacimiento no puede ser futura | `ValidationException` | 400 |
| RN-04 | La edad mínima del paciente es 0 años (recién nacidos permitidos) | - | - |
| RN-05 | El `NationalId` debe coincidir con el algoritmo de validación DNI/NIE español | `ValidationException` | 400 |

**Referencias a docs de reglas de negocio:**
```
→ projects/{proyecto}/reglas-negocio.md §{sección}
→ docs/reglas-dominio/{módulo}.md
```

---

## 4. Constraints and Limits

> *Lo que el código NO PUEDE hacer. Límites cuantificables, no suposiciones.*

### Performance Constraints

| Métrica | Límite | Crítico | Nota |
|---|---|---|---|
| Latencia de creación de paciente | ≤ 500ms | Sí | p95 latency, incluye BD |
| Memory por comando | ≤ 50 MB | No | Heap máximo durante ejecución |
| Throughput (requests/seg) | ≥ 1000 req/s | Sí | En DEV/PRE, medido con load test |
| Timeout máximo | 30s | Sí | Abrir un comando que tarde >30s debe fallar con TimeoutException |

### Security Constraints

| Aspecto | Requirement |
|---|---|
| Autenticación | Usuario DEBE estar autenticado (JWT válido) con claim `scope:patient.create` |
| Autorización | Solo Role `Doctor` o `Admin` pueden crear pacientes |
| Validación de entrada | Sanitizar campo `Name` (XSS), validar `NationalId` (no inyección SQL), rechazar campos extra |
| Encriptación | Connection string a BD DEBE usar SSL/TLS, datos sensibles (NationalId) pueden estar hasheados en logs |
| Rate Limiting | Máx 100 requests/min por usuario (DDoS mitigation) |
| GDPR | Registrar creación en audit log (quién, cuándo, qué dato) |

### Compatibility Constraints

| Elemento | Constraint |
|---|---|
| .NET Runtime | ≥ .NET 8.0 (LTS), soporte por Microsoft hasta Nov 2026 |
| Base de datos | SQL Server 2019+ ó PostgreSQL 13+ |
| API versioning | Soportar `application/json` con charset `utf-8` |
| Backwards compatibility | Si cambias la interfaz del comando, crear una V2 del endpoint (`/api/v2/patients`) |

### Scalability Limits

| Recurso | Límite | Plan de escalado |
|---|---|---|
| Usuarios concurrentes | ≤ 10,000 | Horizontal: add más instancias de API (Azure App Service scale out) |
| Registros de pacientes | ≤ 10 millones | Vertical: migrar a sharding por región, table partitioning en BD |
| Datos por request | ≤ 1 MB | Si supera, usar pagination o batch API |

---

## 5. Test Scenarios

> *Estos escenarios son los tests que DEBEN existir al finalizar la task.*
> *Si el developer_type es agent, el agente debe generar exactamente estos tests.*

### Happy Path
```
Scenario: Crear paciente con datos válidos
  Given un DNI válido "12345678A" que no existe en el sistema
  And un nombre "Juan García López"
  And una fecha de nacimiento "1985-03-15"
  When se envía el comando CreatePatientCommand
  Then el resultado es Success
  And se retorna un Guid válido (no vacío)
  And el paciente existe en la base de datos
  And se disparó el evento PatientCreatedDomainEvent
```

### Casos de Error
```
Scenario: DNI duplicado
  Given un DNI "12345678A" que YA existe en el sistema
  When se envía el comando CreatePatientCommand con ese DNI
  Then el resultado es Failure
  And el error es DuplicateNationalIdException
  And no se creó ningún paciente nuevo

Scenario: Nombre vacío
  Given un nombre ""
  When se envía el comando CreatePatientCommand
  Then el resultado es Failure (o lanza ValidationException antes de llegar al handler)
  And el mensaje de error menciona el campo "Name"

Scenario: Fecha de nacimiento futura
  Given una fecha de nacimiento DateTime.UtcNow.AddDays(1)
  When se envía el comando CreatePatientCommand
  Then el resultado es Failure
  And el mensaje de error menciona "fecha de nacimiento"

Scenario: DNI con formato inválido
  Given un DNI "AAAAAAAA1" (formato incorrecto)
  When se envía el comando CreatePatientCommand
  Then el resultado es Failure
  And el mensaje de error menciona "NationalId"
```

### Edge Cases
```
Scenario: Nombre con 200 caracteres (límite máximo)
  → Debe ser aceptado

Scenario: Nombre con 201 caracteres
  → Debe ser rechazado con ValidationException

Scenario: Recién nacido (fecha de nacimiento = hoy)
  → Debe ser aceptado

Scenario: Transacción fallida (UnitOfWork lanza excepción)
  → Debe propagar el error sin crear el paciente parcialmente
```

---

## 6. Ficheros a Crear / Modificar

> *Lista exacta de ficheros. El agente debe crear/modificar EXACTAMENTE estos, ni más ni menos.*

### Crear (nuevos)
```
src/Application/Patients/Commands/CreatePatient/
├── CreatePatientCommand.cs          # Command + Response
├── CreatePatientCommandHandler.cs   # Handler principal
└── CreatePatientCommandValidator.cs # FluentValidation rules

tests/Application.Tests/Patients/Commands/
└── CreatePatientCommandHandlerTests.cs  # Tests del handler
```

### Modificar (existentes)
```
src/Application/DependencyInjection.cs   # Registrar el handler (si no usa MediatR auto-scan)
src/API/Controllers/PatientsController.cs # Añadir endpoint POST
```

### NO tocar
```
src/Domain/Patients/              # Domain layer — solo modificación explícita por humano
src/Infrastructure/               # Infrastructure layer — según Fase 2 de descomposición del PBI
```

---

## 7. Código de Referencia

> *Ejemplos del mismo patrón en el proyecto para que el developer/agente siga la convención.*

### Ejemplo de Command Handler similar (mismo patrón):
```
→ src/Application/Appointments/Commands/CreateAppointment/CreateAppointmentCommandHandler.cs
```

```csharp
// Fragmento del handler de referencia para mostrar el patrón de Result<T>:
public async Task<Result<Guid>> Handle(CreateAppointmentCommand request, CancellationToken ct)
{
    var existingAppointment = await _appointmentRepository
        .GetByPatientAndDateAsync(request.PatientId, request.Date, ct);

    if (existingAppointment is not null)
        return Result.Failure<Guid>(AppointmentErrors.DuplicateAppointment);

    var appointment = Appointment.Create(
        request.PatientId,
        request.Date,
        request.DoctorId
    );

    _appointmentRepository.Add(appointment);
    await _unitOfWork.SaveChangesAsync(ct);

    return Result.Success(appointment.Id);
}
```

### Ejemplo de Validator similar:
```
→ src/Application/Appointments/Commands/CreateAppointment/CreateAppointmentCommandValidator.cs
```

### Ejemplo de Tests similar:
```
→ tests/Application.Tests/Appointments/Commands/CreateAppointmentCommandHandlerTests.cs
```

---

## 8. Configuración de Entorno

> *Lo que el agente necesita saber sobre el entorno de ejecución.*

```bash
# Proyecto
PROJECT_DIR="projects/{proyecto}/source"
SOLUTION_FILE="src/{Proyecto}.sln"
TEST_PROJECT="tests/Application.Tests"

# Comandos de verificación post-implementación
dotnet build $SOLUTION_FILE
dotnet test $TEST_PROJECT --filter "Category=Unit" --no-build
```

**Variables de entorno necesarias para tests:**
```
# Los tests unitarios NO deben necesitar variables de entorno externas
# Si necesitan base de datos → usar InMemory o SQLite en memoria
```

---

## 9. Estado de Implementación

> *El developer/agente actualiza esta sección durante la implementación.*

```markdown
**Estado:** Pendiente | En Progreso | Completado | Bloqueado

**Último update:** {YYYY-MM-DD HH:MM}
**Actualizado por:** {dev/agent}

### Log de implementación (si agent-single o agent-team)
- {timestamp} — [AGENT] Iniciando implementación
- {timestamp} — [AGENT] Handler creado: CreatePatientCommandHandler.cs
- {timestamp} — [AGENT] Validator creado: CreatePatientCommandValidator.cs
- {timestamp} — [AGENT] Tests creados: 7 scenarios
- {timestamp} — [AGENT] Build: ✅ OK
- {timestamp} — [AGENT] Tests: ✅ 7/7 passing
- {timestamp} — [AGENT] Implementación completada

### Blockers (si los hay)
> El agente DEBE detenerse y escribir aquí si encuentra ambigüedad o bloqueo

- [ ] {descripción del blocker} — Necesita decisión de: {PM | Tech Lead | humano}
```

---

## 10. Checklist Pre-Entrega

> *El developer (humano o agente) verifica antes de marcar la task como "In Review".*

```markdown
### Implementación
- [ ] Todos los ficheros de la sección 5 han sido creados/modificados
- [ ] Las firmas coinciden exactamente con el contrato de la sección 2
- [ ] Todas las reglas de negocio de la sección 3 están implementadas y testadas
- [ ] Todos los test scenarios de la sección 4 tienen su test correspondiente
- [ ] Los tests pasan localmente (dotnet test)
- [ ] El código sigue el patrón del ejemplo en sección 6
- [ ] Sin hardcoding de valores que deberían ser configurables
- [ ] Sin código comentado ni TODOs sin resolver

### Específico para agente
- [ ] No se tomaron decisiones de diseño fuera de la Spec
- [ ] No se crearon ficheros no listados en la sección 5
- [ ] Las dependencias inyectadas coinciden con la sección 2.3
- [ ] Los nombres siguen las convenciones del proyecto (sección 6)
```

---

## 11. Notas para el Revisor (Tech Lead)

> *Información adicional para el Code Review. No afecta la implementación.*

```
{Notas del PM/Tech Lead sobre decisiones de diseño, contexto histórico,
 riesgos identificados, o aspectos específicos a revisar con cuidado.}
```

---

## 12. Iteration & Convergence Criteria

> *¿Cuándo está la spec lista para implementar? Checklist de madurez.*

### Cuándo es la Spec "Good Enough" para implementar

Una spec está lista para que un agente (o developer humano) empiece a implementar SOLO si cumple todos los criterios siguientes. Si falta algo → iterar la spec, NO empezar a codificar.

### Checklist de Completitud

#### ✅ Inputs / Outputs Completamente Definidos (Sección 3)
- [ ] **Tipos concretos para TODOS los inputs**: Cada parámetro tiene un tipo específico (string, int, DateTime, custom object). No "información", "datos", "algo".
  - ❌ MAL: `input: información del paciente`
  - ✅ BIEN: `input: CreatePatientCommand { Name: string (1-200), BirthDate: DateTime, NationalId: string (regex) }`
- [ ] **Ejemplos reales para cada input**: Mostrar un ejemplo de valor válido. No plantillas abstractas.
  - ❌ MAL: `NationalId: {valid_dni}`
  - ✅ BIEN: `NationalId: "12345678A" (8 dígitos + letra mayúscula)`
- [ ] **Tipos concretos para TODOS los outputs**: Response, error codes, eventos generados.
  - ❌ MAL: `output: resultado de la creación`
  - ✅ BIEN: `output: { id: Guid, name: string }` + HTTP 201 + `PatientCreatedDomainEvent`
- [ ] **Ejemplos reales de outputs**: Mostrar JSON/objeto real que se devuelve.
  - ❌ MAL: `{ success: true, data: {...} }`
  - ✅ BIEN: `{ id: "550e8400-e29b-41d4-a716-446655440000" }` + HTTP 201

#### ✅ Reglas de Negocio Enumerables (Sección 4 — antes "3. Reglas de Negocio")
- [ ] **Cada regla es una fila en tabla**: No párrafos sueltos. Formato: ID | Descripción | Error | HTTP Code.
- [ ] **Cada regla es testeable**: Puedo escribir un test unitario para ella sin ambigüedad.
  - ❌ MAL: `El DNI debe ser válido según corresponda`
  - ✅ BIEN: `RN-05: El NationalId debe pasar validación de algoritmo DNI/NIE español (mod 23). Error: ValidationException (400)`
- [ ] **Sin "según corresponda", "a criterio del", "si procede"**: Reglas concretas y cuantificables.
- [ ] **Máximo 10-15 reglas**: Si hay más, están mal agrupadas. Consolidar.

#### ✅ Test Scenarios Cubren Happy + Error + Edge (Sección 5 — antes "4")
- [ ] **Happy path**: Al menos 1 scenario donde TODO funciona bien.
- [ ] **Error cases**: Cada regla de negocio tiene al menos 1 scenario de error asociado.
- [ ] **Edge cases**: Límites (máximo/mínimo valores), casos frontera.
  - Ejemplo: nombre de 200 caracteres (límite máximo) vs 201 (debe fallar)
- [ ] **Cada scenario es ejecutable**: Doy Given/When/Then concretos, no vagos.
  - ❌ MAL: `Given un paciente When creamos Then se crea bien`
  - ✅ BIEN: `Given DNI "12345678A" (no existe) AND nombre "Juan" AND BirthDate "1985-03-15" When POST /api/v1/patients Then HTTP 201 AND response.id es Guid válido`

#### ✅ Constraints Están Cuantificados (Sección 4 — nuevo)
- [ ] **Performance**: Latencia máxima en ms, throughput en req/s, memory limit en MB. No "rápido" o "eficiente".
  - ❌ MAL: `Debe ser eficiente`
  - ✅ BIEN: `Latencia ≤ 500ms (p95), throughput ≥ 1000 req/s`
- [ ] **Security**: Autenticación y autorización especificadas. Qué datos se sanitizan. Rate limits.
  - ❌ MAL: `Debe ser seguro`
  - ✅ BIEN: `Requiere JWT válido con scope:patient.create. Solo Role Doctor|Admin. Rate limit: 100 req/min/user`
- [ ] **Compatibility**: Qué versiones de BD, framework, navegadores. Backwards compatibility.
  - ❌ MAL: `Compatible con versiones recientes`
  - ✅ BIEN: `.NET 8.0+ (LTS). SQL Server 2019+ o PostgreSQL 13+`
- [ ] **Scalability**: Límites de usuarios, volumen de datos, plan de escalado.
  - ❌ MAL: `Escalable horizontalmente`
  - ✅ BIEN: `≤ 10,000 usuarios concurrentes. Plan: App Service scale-out. ≤ 10M registros. Plan: sharding por región`

#### ✅ Archivos a Crear/Modificar Están Listados (Sección 6 — antes "5")
- [ ] **Crear (nuevos)**: Ruta exacta + nombre de fichero + propósito en 1 línea.
  - ❌ MAL: `src/Application/Commands/` (ruta incompleta)
  - ✅ BIEN: `src/Application/Patients/Commands/CreatePatient/CreatePatientCommand.cs # Command + Response`
- [ ] **Modificar (existentes)**: Ruta exacta + qué cambios concretos (añadir método, registrar handler, etc.)
  - ❌ MAL: `Actualizar DependencyInjection.cs`
  - ✅ BIEN: `src/Application/DependencyInjection.cs # Registrar CreatePatientCommandHandler en MediatR`
- [ ] **NO tocar**: Listar ficheros que el agente NUNCA debe tocar.

### Flujo de Iteración

```
PM escribe spec (inicial, probablemente incompleta)
    ↓
Para cada sección:
  ¿Inputs/Outputs son concretos o vagos?
    → Vagos → Iterar spec (pedir detalles al analista/PM)
  ¿Reglas de negocio enumerables o texto libre?
    → Texto libre → Iterar (extraer reglas en tabla)
  ¿Test scenarios tienen Given/When/Then concretos?
    → Abstactos → Iterar (pedir ejemplos reales)
  ¿Constraints cuantificados o sólo descripciones?
    → Descripciones → Iterar (definir límites numéricos)
    ↓
  Spec madura → READY FOR IMPLEMENTATION
    ↓
  Agente lee spec → Implementa exactamente lo pedido → Tests pasan
```

### Condiciones de Parada (cuándo dejar de iterar)

**Parar de iterar (spec lista para implementar) si:**
- Inputs/Outputs: tipos concretos + ejemplos para todos
- Reglas: tabla con ID, descripción, error, HTTP code (máx 15 reglas)
- Tests: happy path + error case por cada regla + edge cases (mín 7 scenarios)
- Constraints: performance, security, compatibility, scalability cuantificados
- Archivos: lista exacta de crear/modificar/no-tocar (no ambigüedades)

**NO empezar implementación si:**
- Hay inputs sin tipo concreto ← Iterar
- Una regla dice "según corresponda" ← Iterar
- Un scenario describe con 1 palabra ("crear paciente") ← Iterar
- Un constraint dice "eficiente" o "seguro" sin números ← Iterar
- Hay 2+ archivos con ruta incompleta ← Iterar

---

*Template versión 2.0 — SDD Skill para {Workspace Name}*
*Basado en Clean Architecture .NET 8 + CQRS + MediatR + SDD Best Practices*
