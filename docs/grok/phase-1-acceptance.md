# Debt Stalker — Phase 1 Acceptance Criteria (Definition of Done)

**Status:** Definition only. No implementation begins until this document (and the Global Architecture) is reviewed and agreed.

**Purpose**  
This document is the authoritative **Definition of Done** for Phase 1.  
Phase 1 is complete only when every item below is verifiably true.

**Scope**  
- Countries: Spain (ES) and Mexico (MX) only.
- Architecture: Must fully exercise and respect the Global Architecture defined in `global-architecture.md` (see the Mermaid diagrams section).
- Master reference: `plan.md`.

Everything in this document derives directly from:
- `docs/spec.md` (the original challenge)
- `docs/v1/spec.md` (detailed v1 requirements)
- The Global Architecture and decisions in the grok/ documents

---

## 1. Global Architecture Invariants (Must Hold in Phase 1)

The following must be demonstrably true in the implemented code and design:

- Country-specific logic lives **only** inside `DebtStalker.Countries` modules (behind a `Behaviour` or equivalent contract) + `Registry`.
- Provider logic lives **only** inside `DebtStalker.Providers` (behind a `Behaviour`).
- No controller, LiveView, or web layer contains business rules, document validation, financial rules, or status transition logic.
- Raw provider responses are **never** stored in a way that bypasses normalization and **never** appear in public API responses or logs.
- Every status change goes through a single, auditable transition function that:
  - Validates the transition (per country module)
  - Records the change in `application_status_transitions`
  - Writes to `audit_logs`
  - Emits a PubSub event for realtime
- All list queries are cursor-paginated (no unbounded `OFFSET` pagination).
- Application date is always set server-side.
- PII (especially full `identity_document`) is never logged in full.
- Database changes that must produce async work do so via **PostgreSQL triggers** writing to `application_events`.

If any invariant is violated, Phase 1 is not complete.

---

## 2. Required Functionality (from docs/spec.md) — All Must Work for ES + MX

### 2.1 Application Creation
- A credit application can be created containing:
  - Country (ES or MX)
  - Full name
  - Identity document (appropriate for country)
  - Requested amount
  - Monthly income
  - Application date (server-set)
  - Initial status
  - Normalized banking information from the country provider
- Creation is available via:
  - Authenticated JSON API
  - Frontend form (LiveView)
- Creation synchronously validates:
  - Input shape and positive monetary values
  - Supported country
  - Country-specific document format
  - Country financial rules
- Creation triggers asynchronous work (see section 4).

### 2.2 Rule Validation by Country (Phase 1 specific rules from v1/spec.md)

**Spain (ES) — DNI**
- Document format validation (DNI-like, with checksum documented if simplified).
- Reject if `requested_amount > 12 × monthly_income`.
- Mark `additional_review_required = true` if `requested_amount > 15000.00`.

**Mexico (MX) — CURP**
- Document format validation (CURP uppercase alphanumeric pattern, expected length).
- Reject if `requested_amount > 10 × monthly_income`.
- Mark `additional_review_required = true` when `provider_debt + requested_amount > 18 × monthly_income`.

Validation errors are returned with clear field-level messages (422 on API).

### 2.3 Integration with Banking Provider
- Simulated provider adapters exist for ES and MX implementing a common behaviour.
- Provider responses are **normalized** before persistence.
- Provider failures during creation put the application into a recoverable `provider_error` state (not silent success).
- Raw provider data is never exposed.

### 2.4 Application Statuses
Supported statuses (shared):
- `submitted`
- `pending_risk`
- `additional_review`
- `approved`
- `rejected`
- `provider_error`
- `cancelled`

- All transitions are validated by the country module.
- Every transition is recorded.
- Status changes emit realtime updates.
- Transitions can be triggered from:
  - API (authorized)
  - Frontend UI (authorized)
  - Background workers (via context)

### 2.5 Querying an Application
- Authenticated API and frontend detail view exist to retrieve a single application by ID.
- Response includes safe, redacted data (last-4 of document at minimum; no raw provider payloads).

### 2.6 Listing Applications
- Authenticated API and frontend list view support filtering by:
  - Country
  - Status
  - Date range (application_date)
- Results use cursor pagination.
- Frontend allows filtering by country and status.

### 2.7 Asynchronous Processing and Events (Critical Challenge Requirement)
- Creating an application generates durable asynchronous work.
- **PostgreSQL triggers** on `credit_applications` (INSERT and status UPDATE) insert rows into an `application_events` outbox table.
- Events include at minimum: `application.created` and `application.status_changed`.
- An `EventDispatcherWorker` (or equivalent) claims unprocessed events using row-level locking (`FOR UPDATE SKIP LOCKED`).
- Specialized workers exist and process work:
  - Risk evaluation
  - Audit enrichment
  - External notifications
  - Provider webhook handling
- Workers are idempotent where possible.
- Multiple workers can run in parallel safely (demonstrable via Oban concurrency).
- Job failures are logged with application id and are retryable.

### 2.8 Webhooks and External Processes
- System exposes a webhook endpoint (`POST /api/webhooks/...` or equivalent).
- Webhook payloads are authenticated (shared secret or signature).
- Receipt of a valid webhook writes a `webhook_events` record.
- Webhook processing can update application state **only** through validated transitions.
- A simulated external notification flow exists:
  - When an application reaches `approved` or `rejected`, a notification job is enqueued.
  - The job either calls a configurable external endpoint or records a local simulated result.

### 2.9 Concurrency and Parallel Processing
- The design (Oban + DB locking + idempotency) demonstrably allows multiple processes/workers to execute concurrent business logic safely.
- No obvious data inconsistencies under parallel execution (documented + basic concurrency test coverage).

### 2.10 Real-time Updates on the Frontend
- The UI (LiveView) shows list and/or detail views that update **without manual refresh** when relevant changes occur.
- Implemented with Phoenix PubSub.
- UI clearly shows validation errors and async processing states (e.g., "pending risk evaluation").

---

## 3. Non-Functional Requirements — Must Be Satisfied

### 3.1 Architecture & Modularity
- Clear separation of concerns matching the Global Architecture (Countries, Providers, Applications, Workers, Web).
- Country and provider additions are additive (no changes required to core persistence, API, or UI layers).

### 3.2 API Security
- All API endpoints except health and token issuance require valid JWT.
- JWT secret comes from environment variable (fail-fast in prod).
- Basic authorization distinguishes read vs. status-update actions.
- PII is handled securely (redacted in responses and logs).

### 3.3 Observability
Structured logs are emitted for (at minimum):
- Application creation
- Validation failures
- Provider calls (success/failure)
- Queued jobs
- Job completion and failure
- Webhook receipt
- Status transitions

Logs include `application_id` when available. Full identity documents and raw provider payloads are never logged.

### 3.4 Reproducibility
- A new developer with Elixir + Docker can run the full system locally in **under 5 minutes**.
- Clear `README.md` instructions exist.
- `make` (or equivalent) commands exist for common tasks (`setup`, `db`, `migrate`, `run`, `test`, etc.).
- Docker Compose provides the database.
- Seeds provide usable demo ES + MX data.

### 3.5 Scalability & Large Volume Thinking
- The `README.md` contains a dedicated section with analysis covering:
  - Recommended indexes
  - Partitioning strategy (by `application_date`)
  - Cursor pagination rationale
  - Critical queries and bottleneck avoidance
  - Archiving / retention strategy
- The actual code uses cursor pagination and appropriate indexes even for Phase 1.

### 3.6 Queues and Job Queueing
- Oban (PostgreSQL-backed) is used.
- `README.md` explains the queue technology and strategy.
- At least one full job production + consumption flow is working and documented.

### 3.7 Caching
- Country configuration and validation metadata is cached (ETS recommended, loaded at boot, static invalidation for v1).
- Invalidation strategy is documented (even if trivial).

### 3.8 Deployment (Kubernetes)
- A `k8s/` directory (or equivalent) contains basic manifests for:
  - Web process
  - Worker process
  - Database configuration (or external)
  - Services, config, secrets placeholders
  - Migration job (if separate)
- Manifests document required environment variables.
- `kubectl apply --dry-run=client` succeeds.

### 3.9 Required Frontend
The LiveView interface allows:
- Creating applications (with country-driven validation hints and inline errors)
- Viewing the list of applications (with filters)
- Viewing details
- Updating status (for authorized actions)
- Seeing relevant changes (status, async results) update in near real-time
- Clear error handling and feedback

### 3.10 Deliverables
- Working backend + frontend + async/queue/cache code.
- Comprehensive `README.md` (see exact required sections in `docs/spec.md`).
- Kubernetes configuration files.
- Makefile / equivalent.

---

## 4. Data Model & Async Flow Expectations (from v1/spec.md)

See the dedicated definition: [data-model.md](data-model.md)

The implementation must realize the tables and trigger-based outbox behavior described there (and in `v1/spec.md`).

The trigger → event → dispatcher → specialized worker flow must be working and observable.

---

## 5. Specific Verifiable Flows (Must Be Demonstrable)

See the detailed flows in `global-architecture.md` (diagrams 2 and 3).

A reviewer must be able to perform these and observe correct behavior:

1. Create an ES application via UI → see it appear in list → background risk processing occurs → status moves (e.g. to `approved` or `additional_review`) → UI updates live.
2. Create an MX application via API (with JWT) that triggers the debt+income additional review rule.
3. Attempt invalid document or financial rule violation → clear error returned.
4. Trigger a provider error path → application lands in `provider_error`.
5. Perform a status transition via authorized API → audit log written + realtime update.
6. Send a signed webhook → application state changes through validated transition.
7. Reach `approved`/`rejected` → notification attempt is recorded (simulated or external).
8. View full list with country + status filters using cursor pagination.
9. Restart the application / workers — in-flight or unprocessed events are eventually handled (durability).

---

## 6. Documentation Requirements

The `README.md` (and grok/ docs) must allow a reader to understand:

- How to run everything locally
- The data model (diagram or clear table)
- Technical decisions and trade-offs
- Security & PII handling
- Full scalability / large volume analysis
- Concurrency, queues, cache, and webhooks strategy
- How to add a new country (pointing to the behaviour contracts)

---

## 7. Phase 1 Acceptance Checklist

Use this checklist to verify completion.

**Global Invariants**
- [ ] Country logic isolated behind contract + registry
- [ ] Provider normalization boundary respected
- [ ] No domain rules in web layer
- [ ] Raw provider data never leaks
- [ ] All status changes audited + broadcast
- [ ] Lists use cursor pagination
- [ ] Triggers generate `application_events`

**Functionality**
- [ ] Create (API + UI) for ES and MX with all required fields
- [ ] Country document + financial rules enforced for both countries
- [ ] Normalized provider data included on creation
- [ ] Full status set and validated transitions working
- [ ] Get + filtered cursor-paginated list (API + UI)
- [ ] PostgreSQL trigger → outbox → worker pipeline operational
- [ ] Risk evaluation, audit, notification, and webhook workers exist and function
- [ ] Authenticated webhook endpoint with signature verification
- [ ] Simulated external notification on terminal statuses
- [ ] Live realtime updates in UI (PubSub)
- [ ] Concurrency safety demonstrable

**Security & Observability**
- [ ] JWT required on protected endpoints
- [ ] PII redacted in logs and API responses
- [ ] Structured logs for all key events with application ids
- [ ] Basic authorization for status updates

**Reproducibility & Deployment**
- [ ] Full local run in < 5 minutes via documented commands
- [ ] Seeds with demo data
- [ ] Makefile covers common operations
- [ ] k8s manifests present and dry-run valid
- [ ] README contains all required sections + scale analysis

**Frontend**
- [ ] Create form with validation feedback
- [ ] List with filters + realtime
- [ ] Detail view + status update action
- [ ] Clear display of async states and errors

**Documentation & Extensibility**
- [ ] Global contracts make adding countries additive (provable from code + docs)
- [ ] All decisions and scale strategy documented

---

## 8. Verification Approach (Definition Time)

- Automated tests must cover happy paths, validation errors, transition rules, async flows, and security boundaries.
- Manual demo of the 9 flows in section 5 must succeed.
- A new person following only the README must have a working system in <5 minutes.
- Code review must confirm that global architecture invariants hold.

---

**This document is the gate for Phase 1.**

Once this (plus `global-architecture.md`, `plan.md`, and related definition docs) is finalized and agreed, implementation work can begin — strictly following the definitions.

No code changes should be made until the definitions are considered complete by the team.