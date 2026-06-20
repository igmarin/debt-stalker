# Debt Stalker — Global Architecture

This is the single source of truth for the entire system design (all phases).

Extracted and refined from the master plan (docs/grok/plan.md).

## Core Domain Concepts (Glossary)

- Credit Application
- Country Module
- Provider Adapter (always normalized)
- Database-Generated Work (PostgreSQL triggers → application_events outbox)
- Async Boundary + Realtime Surface

## Modular Structure + Invariants

See the **Architecture Diagrams** section below for visual overviews of components, responsibilities, and data flows.

**Invariants (never violate):**
- No web code contains country or provider rules.
- Raw provider payloads never persist or leak.
- All status changes go through one audited transition path + broadcast.
- Lists are always cursor-paginated.

## Responsibility Matrix
| Layer      | Owns                                      | Must NOT |
|------------|-------------------------------------------|----------|
| Countries  | Validation, rules, transitions            | DB, web  |
| Providers  | Fetch + normalize only                    | Decisions|
| Applications | Lifecycle + coordination                | Rules    |
| Workers    | Reliable processing of events             | Rules    |
| Web        | Transport, auth, presentation, realtime   | Domain   |

## Country Behaviour (The Key Contract)
Callbacks defined in the master plan.

**Phase 1 rules (ES + MX)** — exact as in docs/spec.md + v1/spec.md.

Adding a country = implement behaviour + register. Zero other changes.

## Provider Behaviour
Normalization contract only. Simulated in Phase 1.

## Data Model + Async Flow (Critical)
Tables: credit_applications, application_events (outbox via trigger), transitions, audit, etc.

The required pattern:
Write → trigger → event row → worker claims (SKIP LOCKED) → Oban job(s) → context update + broadcast.

## Other Global Aspects
- API surface (JWT, cursor lists, webhooks)
- LiveView realtime
- Security & redaction
- Caching (ETS for registry)
- Observability
- Deployment (k8s manifests, Makefile)

Full details + rationale are in the master `plan.md`, `decisions.md`, and `risks.md`.

**Phase 1 must implement this architecture for ES + MX** while satisfying every criterion in `phase-1-acceptance.md`.

This architecture makes the other 4 countries and future evolution additive.

---

## Architecture Diagrams

### 1. High-Level Component Architecture & Responsibility Boundaries

This diagram shows the major layers and how the **Responsibility Matrix** is enforced in the system.

```mermaid
flowchart TD
    subgraph Client["🌐 Client Layer"]
        direction TB
        UI[LiveView UI<br/>List • Create • Detail<br/>Real-time updates]
        Browser[Browser / API Client]
    end

    subgraph Web["🖥️ DebtStalkerWeb<br/>(Delivery Layer)"]
        direction TB
        Auth[JWT Authentication<br/>+ Authorization Plugs]
        API[API Controllers<br/>JSON responses with redaction]
        LV[LiveViews]
        WebhookC[Webhook Controller<br/>Signature verification]
    end

    subgraph Domain["📦 DebtStalker Domain"]
        direction TB
        Apps["Applications Context<br/>• create/1<br/>• get/1 • list/1<br/>• update_status/3<br/>(orchestrates everything)"]
        Countries["Countries<br/>Behaviour + Registry<br/>ES • MX (Phase 1)"]
        Providers["Providers<br/>Behaviour + Adapters<br/>(Simulated + Normalized)"]
        Risk["Risk Logic"]
        Audit["Audit Log"]
        Notifs["Notifications"]
    end

    subgraph Async["⚙️ Async Workers (Oban)"]
        direction TB
        Dispatcher["EventDispatcherWorker<br/>(FOR UPDATE SKIP LOCKED)"]
        RiskW["RiskEvaluationWorker"]
        AuditW["AuditWorker"]
        NotifW["ExternalNotificationWorker"]
        WebhookW["ProviderWebhookWorker"]
    end

    subgraph DB["🗄️ PostgreSQL"]
        direction TB
        AppTable[("credit_applications")]
        Events[("application_events<br/>OUTBOX")]
        Transitions[("application_status_transitions")]
        AuditT[("audit_logs")]
        WebhookT[("webhook_events")]
        NotifT[("notification_attempts")]
    end

    subgraph Infra["📡 Infrastructure"]
        PubSub[("Phoenix PubSub")]
        ETS[ETS Cache<br/>Country Registry]
    end

    %% Flows
    Browser --> Auth
    UI --> Auth
    Auth --> Apps
    Auth --> WebhookC

    Apps --> Countries
    Apps --> Providers
    Apps --> DB

    Providers --> DB
    Countries -.-> Apps

    DB -- "INSERT / UPDATE status" --> Trigger["PostgreSQL Triggers"]
    Trigger --> Events

    Events --> Dispatcher
    Dispatcher --> RiskW & AuditW & NotifW & WebhookW

    RiskW --> Apps
    AuditW --> Audit
    NotifW --> Notifs
    WebhookW --> Apps

    Apps --> Audit
    Apps --> Notifs
    Apps --> PubSub
    PubSub --> UI

    Apps -. "Cache lookup / write" .-> ETS

    classDef domain fill:#e0f2fe,stroke:#0369a1
    classDef web fill:#fef3c7,stroke:#b45309
    classDef async fill:#f3e8ff,stroke:#7c3aed
    classDef db fill:#dcfce7,stroke:#166534
    classDef infra fill:#f1f5f9,stroke:#475569

    class Domain domain
    class Web,Auth,API,LV,WebhookC web
    class Async,Dispatcher,RiskW,AuditW,NotifW,WebhookW async
    class DB,AppTable,Events,Transitions,AuditT,WebhookT,NotifT db
    class Infra,PubSub,ETS infra
```

### 2. End-to-End Application Lifecycle Data Flow

This shows the main happy path for creating an application and how async processing + realtime updates occur.

```mermaid
flowchart TD
    Start([Create Request<br/>API or LiveView Form]) --> ValidateInput[Validate basic input]

    ValidateInput --> CountryVal[Country Validation<br/>Document + Financial Rules<br/>via Countries.ES / .MX]
    CountryVal -->|Invalid| Error1[Return 422 + errors]
    CountryVal -->|Valid| ProviderCall[Call Provider Adapter<br/>ESAdapter / MXAdapter]

    ProviderCall --> Normalize[Normalize Response<br/>into ProviderSummary]
    Normalize --> Persist[Persist credit_application<br/>with status=submitted<br/>+ provider_summary JSONB]

    Persist --> Trigger1[PostgreSQL Trigger<br/>INSERT → application.created]
    Trigger1 --> Outbox[(application_events)]

    Persist --> ReturnSuccess[Return success<br/>with application ID]

    Outbox --> Dispatcher[EventDispatcherWorker<br/>claims with SKIP LOCKED]

    Dispatcher --> RiskWorker[RiskEvaluationWorker]
    RiskWorker --> ReEval[Re-evaluate using<br/>Countries + ProviderSummary]
    ReEval --> Decide[Decide next status<br/>pending_risk → approved / rejected / additional_review]

    Decide --> UpdateStatus[Applications.update_status<br/>Validate transition<br/>Record transition<br/>Write audit_log]

    UpdateStatus --> Trigger2[PostgreSQL Trigger<br/>status change → application.status_changed]
    Trigger2 --> Outbox

    UpdateStatus --> Broadcast[PubSub broadcast<br/>applications:{id}]

    Broadcast --> UIUpdate[LiveView updates in real-time<br/>No page refresh]

    %% Side effects
    UpdateStatus --> NotifJob[Enqueue ExternalNotificationWorker]
    NotifJob --> Simulate[Simulate external notification<br/>or call configured endpoint]

    UpdateStatus --> AuditLog[Append to audit_logs]

    classDef start fill:#22c55e,stroke:#166534,color:#fff
    classDef error fill:#ef4444,stroke:#991b1b,color:#fff
    classDef process fill:#3b82f6,stroke:#1e40af,color:#fff
    classDef dbop fill:#8b5cf6,stroke:#4c1d95,color:#fff
    classDef ui fill:#f59e0b,stroke:#92400e,color:#fff

    class Start start
    class Error1 error
    class ValidateInput,CountryVal,ProviderCall,Normalize,Persist,RiskWorker,ReEval,Decide,UpdateStatus,NotifJob,Simulate process
    class Trigger1,Trigger2,Outbox,Broadcast,AuditLog dbop
    class UIUpdate ui
```

### 3. Async Outbox + Worker Processing Detail

Focus on the database-generated async requirement.

```mermaid
sequenceDiagram
    participant App as Applications Context
    participant DB as PostgreSQL
    participant Trigger as DB Trigger
    participant Events as application_events
    participant Disp as EventDispatcherWorker
    participant Worker as Risk / Audit / Notif Worker
    participant Ctx as Applications Context (again)
    participant Pub as PubSub

    App->>DB: INSERT credit_application OR<br/>UPDATE status
    DB->>Trigger: Fire trigger
    Trigger->>Events: INSERT event row<br/>(created / status_changed)
    Note over Events: durable outbox

    Disp->>Events: SELECT ... FOR UPDATE SKIP LOCKED<br/>(claim unprocessed)
    Disp->>Events: Mark processing / increment attempts
    Disp->>Worker: enqueue or directly perform

    Worker->>Ctx: Risk evaluation / side effects<br/>(only through public context)
    Ctx->>DB: Update application (may fire new trigger)
    Ctx->>Pub: broadcast change
    Worker->>Events: Mark processed

    Pub->>LiveView: Real-time update to UI
```

### How to Use These Diagrams

- Use the **Component Architecture** diagram when explaining boundaries and the Responsibility Matrix to new team members.
- Use the **Lifecycle Flow** to walk through a complete application journey (including async and realtime).
- Use the **Sequence Diagram** to discuss the critical "database operation generates async work" requirement from the original challenge.

These diagrams are intended to be living documentation — update them as the design evolves.

**Next steps before implementation:** Review these diagrams against the Responsibility Matrix, Data Model, and `phase-1-acceptance.md`.
