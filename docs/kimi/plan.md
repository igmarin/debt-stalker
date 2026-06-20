# Debt Stalker v1 — Refined Implementation Plan

> Source documents: `docs/spec.md` (challenge brief), `docs/v1/spec.md` (v1 domain spec).  
> Outcome of this plan: a single Phoenix application that implements Spain (`ES`) and Mexico (`MX`) credit applications end-to-end, with an architecture that makes additional countries, providers, rules, status flows, and frontend views additive.

---

## 1. Goal & Scope

**Goal**  
Build a working, reproducible, test-covered MVP for multi-country credit applications. The MVP must satisfy all functional and non-functional requirements in the challenge brief while remaining simple enough to run locally in under five minutes.

**Scope for v1 / first phase**  
- Implement exactly two countries: **Spain (ES)** and **Mexico (MX)**.
- Expose an authenticated JSON API plus a Phoenix LiveView frontend.
- Simulate banking providers per country behind a normalized adapter boundary.
- Use PostgreSQL-backed Oban jobs plus a PostgreSQL trigger-driven `application_events` outbox for asynchronous work.
- Provide Kubernetes manifests, a `Makefile`, and a `README` with install/run instructions, data model, decisions, security, and scalability notes.

**Out of scope for v1 / first phase**  
- Real banking provider integrations.
- Remaining four countries (PT, IT, CO, BR).
- Production multi-tenant authorization or full KYC/AML compliance.
- Real Kubernetes deployment and load testing at millions of rows.
- Advanced metrics/dashboards beyond structured logs and health checks.
- Complete PII encryption at rest (document hash + redaction only).
- Dead-letter queues, circuit breakers, and rate limiting.

---

## 2. Global Architecture

A single Phoenix umbrella-free application with clear domain boundaries:

| Boundary | Responsibility |
|----------|----------------|
| `DebtStalker.Countries` | Country registry, behaviour contracts, and `ES` / `MX` implementations. Document validation, income/amount rules, status-transition rules. |
| `DebtStalker.Providers` | Provider behaviour and simulated adapters. Normalizes every provider response before persistence or API exposure. |
| `DebtStalker.Applications` | Application creation, retrieval, listing, pagination, and controlled status transitions. |
| `DebtStalker.Risk` | Async risk-evaluation orchestration (worker + business logic). |
| `DebtStalker.Audit` | Append-only audit-log records for every status change and sensitive event. |
| `DebtStalker.Notifications` | Simulated external notifications and webhook processing. |
| `DebtStalkerWeb` | API controllers, auth plugs, webhook controller, and LiveView frontend. |
| `DebtStalker.Workers` | Oban workers: `EventDispatcherWorker`, `RiskEvaluationWorker`, `AuditWorker`, `ExternalNotificationWorker`, `ProviderWebhookWorker`. |

**Runtime components**  
- Phoenix web server (API + LiveView).
- Oban job runner inside the same release (configurable worker count).
- PostgreSQL database with triggers on `credit_applications` that write to `application_events`.
- Phoenix PubSub for real-time frontend updates.

**Key data stores**  
- PostgreSQL for applications, status transitions, audit logs, events, webhook events, notification attempts, and Oban jobs.
- ETS cache for country configuration / validation metadata (static, loaded on boot).

---

## 3. Requirements Traceability

The original challenge (`docs/spec.md`) contains more requirements than v1 can reasonably implement. This section maps each high-level requirement to its treatment in v1.

| Requirement source | Treatment in v1 | Notes |
|--------------------|-----------------|-------|
| Create credit applications | **Implement** | API + LiveView form. |
| Validate country-specific rules | **Implement** | ES and MX only. |
| Integrate banking providers by country | **Implement** | Simulated adapters. |
| Query one application | **Implement** | By UUID. |
| List applications filtered by country | **Implement** | Also by status and date range. |
| Update application status | **Implement** | With controlled transitions. |
| Background/parallel processing | **Implement** | Oban + PostgreSQL triggers. |
| Real-time frontend | **Implement** | LiveView + PubSub. |
| All six countries | **Defer** | ES + MX in v1; architecture supports the rest. |
| JWT auth + basic authorization | **Implement** | Read vs. status-update roles. |
| Observability (logs, errors) | **Implement** | Structured logs; metrics deferred. |
| Caching | **Implement** | Country config only; app-level caching considered but optional. |
| Kubernetes manifests | **Implement** | Documented, not deployed. |
| Scalability analysis in README | **Implement** | Indexes, partitioning, pagination, archiving. |

---

## 4. First Phase: Foundation — Implementation Roadmap

This section is the immediate work package. It is intentionally sequential in headline order, but many tasks can run in parallel once the project skeleton and contracts exist.

### 4.1 Project Bootstrap
- Generate a new Phoenix application (`debt_stalker`) with PostgreSQL, LiveView, and Ecto.
- Add dependencies: `oban`, `joken`.
- Configure `dev.exs`, `test.exs`, `runtime.exs`, Docker Compose for Postgres, and a root `Makefile` with `setup`, `db`, `test`, `run`, `format`, `lint`.
- Add a basic CI GitHub Actions workflow (format, compile warnings, tests).

**Acceptance**  
`make setup && make test` passes with a green suite.

### 4.2 Domain Contracts & Country Implementations
- Define `DebtStalker.Countries.Behaviour` with callbacks for `validate_document/1`, `validate_financials/1`, `interpret_provider_summary/1`, `additional_review_required?/1`, and `allowed_status_transitions/0`.
- Implement `DebtStalker.Countries.ES`:
  - DNI format and checksum validation.
  - If requested amount > 12 × monthly income, mark `additional_review_required` (do **not** hard-reject at creation; see §5 decision on "manual review").
  - If requested amount > 15,000 EUR, mark `additional_review_required`.
- Implement `DebtStalker.Countries.MX`:
  - CURP format validation (uppercase alphanumeric, expected length).
  - If requested amount > 10 × monthly income, mark `additional_review_required`.
  - If provider debt + requested amount > 18 × monthly income, mark `additional_review_required`.
- Build `DebtStalker.Countries.Registry` to resolve a country code to its module.

**Acceptance**  
Unit tests cover valid/invalid DNI, valid/invalid CURP, and all financial rule edge cases.

### 4.3 Provider Abstraction & Simulated Adapters
- Define `DebtStalker.Providers.Behaviour` with a contract of:
  - Input: country, identity document, application fields needed for lookup.
  - Output: normalized provider summary, provider status, optional risk indicators.
  - Errors: `timeout`, `unavailable`, `invalid_document`, provider-specific rejection.
- Build simulated adapters `DebtStalker.Providers.ESAdapter` and `DebtStalker.Providers.MXAdapter`:
  - Deterministic responses based on document hash or configured fixtures.
  - Return normalized fields: `existing_debt`, `score_bucket`, `delinquency_flag`, `account_age_months`.
  - Simulate error cases via module attributes or env config.
- Ensure raw provider payloads are never stored in `provider_summary`; only normalized, safe fields.

**Acceptance**  
Provider tests verify normalization and error paths; no raw payload appears in `credit_applications.provider_summary`.

### 4.4 Database Schema, Triggers, and Outbox
Create Ecto migrations for:
- `credit_applications`:
  - `id` UUID PK.
  - `country` string, not null, constrained to supported countries.
  - `full_name` string.
  - `identity_document` string (plain for local MVP; encryption deferred).
  - `identity_document_hash` string for audit-safe lookup.
  - `requested_amount` decimal.
  - `monthly_income` decimal.
  - `application_date` utc_datetime.
  - `status` string, not null.
  - `additional_review_required` boolean, default false.
  - `provider_summary` jsonb, default `%{}`.
  - `risk_result` jsonb.
  - timestamps.
- `application_status_transitions` (audit status changes):
  - `id` UUID PK, `application_id` FK, `from_status`, `to_status`, `reason`, `actor_type`, `actor_id` nullable, `inserted_at`.
- `application_events` (outbox table for DB-generated async work):
  - `id` UUID PK, `application_id` FK, `event_type`, `payload` jsonb, `processed_at`, `attempt_count`, timestamps.
- `audit_logs` (append-only redacted records).
- `webhook_events` (received webhooks, signature verification, payload hash, processing result).
- `notification_attempts` (external notification attempts).
- Add PostgreSQL functions/triggers on `credit_applications` INSERT and UPDATE of `status` to insert `application.created` and `application.status_changed` events into `application_events`.

**Acceptance**  
A migration/integration test proves that inserting an application creates an `application.created` event, and updating status creates an `application.status_changed` event.

### 4.5 Core Application Context
- Implement `DebtStalker.Applications` context:
  - `create_application/1` — validate country, document, financial rules, call provider adapter, persist application, status defaults to `submitted` (or `provider_error` if provider fails), set `application_date` server-side.
  - `get_application/1` — retrieve by UUID.
  - `list_applications/1` — filter by country, status, and date range; use cursor pagination.
  - `update_status/3` — validate transition via country module, write audit log, broadcast PubSub event.
- Implement serializers that redact `identity_document` to last-4 and never expose `risk_result` internals beyond high-level outcome.

**Acceptance**  
Context tests cover creation success/failure, provider error path, listing filters, and status transitions.

### 4.6 Authentication & Authorization
- Implement JWT-based auth with `Joken`:
  - `POST /api/auth/token` issues a demo token for a fixed local user (no real user management in v1).
  - API plug requires valid JWT except for health and token endpoints.
  - Distinguish read role from status-update role in token claims; `PATCH /api/applications/:id/status` requires update role.
- Keep JWT secret in env var; fail fast on startup if missing.

**Acceptance**  
API tests verify 401/403 responses and successful authenticated calls.

### 4.7 Asynchronous Processing with Oban
- Add Oban configuration and migration.
- Implement workers:
  - `EventDispatcherWorker`: polls `application_events` with `FOR UPDATE SKIP LOCKED`, marks processed, enqueues specialized workers.
  - `RiskEvaluationWorker`: runs country rules against provider summary, moves application to `pending_risk` / `additional_review` / `approved` / `rejected` through the context.
  - `AuditWorker`: writes non-blocking audit enrichment.
  - `ExternalNotificationWorker`: sends/simulates notification when status reaches `approved` or `rejected`.
  - `ProviderWebhookWorker`: processes verified webhook events.
- All workers include structured logs with application id and event id; never log full documents or raw payloads.
- Workers are idempotent: check current state / attempt uniqueness before writing side effects.

**Acceptance**  
Worker tests verify dispatch, risk evaluation outcomes, notification idempotency, and retry behavior.

### 4.8 Webhooks
- `POST /api/webhooks/provider-confirmations` receives signed webhook events.
- Verify signature with shared secret from env var.
- Store webhook event record.
- If valid, enqueue `ProviderWebhookWorker` to update application status through the context.

**Acceptance**  
Controller tests verify signature rejection, valid event processing, and duplicate idempotency.

### 4.9 Frontend with Phoenix LiveView
- Application list page:
  - Filters by country and status.
  - Cursor pagination.
  - Subscribes to PubSub and updates on status changes.
- Application detail page:
  - Full safe application data.
  - Status update action for authorized users.
  - Subscribes to PubSub for live updates.
- Application creation form:
  - Country selector drives document validation hints.
  - Displays validation errors inline.
- Handle errors gracefully with flash messages.

**Acceptance**  
LiveView tests cover list updates, detail view, status update flow, and creation form errors.

### 4.10 Caching
- ETS cache for country modules and validation metadata, populated on application startup.
- Cache key: country code; invalidation: static for v1 (redeploy to refresh).
- Application-level detail caching is **deferred** in v1 to avoid invalidation complexity; revisit if list/detail reads become slow.

**Acceptance**  
Cache is observable in logs and does not require external infrastructure.

### 4.11 Kubernetes Manifests
- Provide `k8s/` manifests:
  - `namespace.yaml`
  - `configmap.yaml` (non-secret env)
  - `secret.yaml` placeholders
  - `postgres.yaml` (optional in-cluster DB or external DB config)
  - `web-deployment.yaml`, `web-service.yaml`, `ingress.yaml`
  - `worker-deployment.yaml`
  - `migration-job.yaml`
- Document environment variables in `README.md`.

**Acceptance**  
Manifests are syntactically valid (`kubectl apply --dry-run=client` passes) and documented.

### 4.12 README, Makefile & Documentation
- `README.md` with:
  - Assumptions.
  - Data model diagram or table.
  - Technical decisions and trade-offs.
  - Security considerations.
  - Scalability and large-volume analysis (indexes, partitioning, cursor pagination, archiving).
  - Concurrency, queues, cache, and webhooks strategy.
- `Makefile` commands: `setup`, `db`, `migrate`, `seed`, `run`, `test`, `format`, `lint`, `k8s-apply`.

**Acceptance**  
A new developer with Elixir/Docker installed can run the system in under five minutes.

---

## 5. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Countries in v1 | ES + MX | Distinct document types, cover Europe + Latin America, and exercise both amount-to-income and debt-to-income rules. |
| "Manual review" income rules | Flag `additional_review_required` instead of hard-rejecting | Matches v1 spec wording "unless manually reviewed" and keeps the application inside the system for human decision. |
| Frontend | Phoenix LiveView | Near-real-time updates via PubSub with fewer moving parts than a separate SPA. |
| Jobs | Oban on PostgreSQL | Durable, retryable, simple local setup, fits a Postgres-centric MVP. |
| DB-generated async work | PostgreSQL trigger → `application_events` outbox → Oban | Explicitly satisfies the challenge requirement and decouples triggers from Oban internals. |
| Providers | Simulated adapters | Repeatable tests and sub-five-minute local setup. |
| Auth | JWT bearer tokens | Satisfies challenge requirement; simple local demo token endpoint. |
| PII storage | Plain document + hash + redaction in v1 | Keeps MVP simple; encryption can be added later without changing the API contract. |
| App-level caching | Deferred | Country config is cached; application detail caching adds invalidation complexity not justified in v1. |

---

## 6. Status Flow

Shared v1 statuses and allowed transitions:

```
submitted         -> pending_risk
submitted         -> provider_error
submitted         -> cancelled
pending_risk      -> additional_review
pending_risk      -> approved
pending_risk      -> rejected
pending_risk      -> cancelled
additional_review -> approved
additional_review -> rejected
```

Default flow for a healthy application:
1. `create_application/1` sets status to `submitted`.
2. `RiskEvaluationWorker` moves it to `pending_risk`.
3. Based on rules + provider data, it moves to `additional_review`, `approved`, or `rejected`.
4. On `approved` or `rejected`, `ExternalNotificationWorker` enqueues a simulated notification.

Country modules may narrow the allowed transition set; they cannot bypass audit logging.

---

## 7. API Surface

Authenticated JSON API:

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/auth/token` | Public | Issues a local demo JWT. |
| GET | `/api/health` | Public | Health check. |
| POST | `/api/applications` | Read | Create an application. |
| GET | `/api/applications/:id` | Read | Retrieve one application. |
| GET | `/api/applications` | Read | List applications with filters. |
| PATCH | `/api/applications/:id/status` | Update | Update status. |
| POST | `/api/webhooks/provider-confirmations` | Webhook secret | Receive provider events. |

Public responses must use serializers that redact sensitive fields.

---

## 8. Invariants

These rules must hold across the codebase:

1. Controllers and LiveViews must not contain country-specific business rules.
2. Provider adapters must return normalized data before persistence or API serialization.
3. Status changes must go through the application status transition function.
4. Every status change must create an audit record.
5. Raw provider payloads must not appear in public API responses.
6. Logs must not include full identity documents.
7. Background jobs must be safe under at-least-once execution.
8. Application list endpoints must never return unbounded result sets.
9. Webhook events must be authenticated before state changes.

---

## 9. Error Behavior

### Validation errors
- Return `422 Unprocessable Entity` for invalid country, invalid document format, invalid amount, invalid income, and failed country rule validation.
- Response body must identify fields and human-readable error messages.

### Authentication and authorization errors
- Return `401 Unauthorized` when JWT is missing or invalid.
- Return `403 Forbidden` when the user lacks permission for status updates or sensitive reads.

### Provider errors
- If provider lookup fails before application persistence, create the application only when enough information exists to track recovery, then set status to `provider_error`.
- If provider lookup fails after application persistence, record the error, enqueue retryable work when appropriate, and expose a safe provider error state.

### Job errors
- Jobs must use retry policies.
- Exhausted retries must be logged with application id and job type.
- Re-running a job must not duplicate audit logs, notifications, or invalid status transitions.

### Webhook errors
- Invalid signatures return `401 Unauthorized` or `403 Forbidden`.
- Unknown application ids return `404 Not Found` or store a rejected webhook event, depending on implementation simplicity.
- Duplicate webhook events must be idempotent.

---

## 10. Testing Strategy

| Layer | What to test |
|-------|--------------|
| Unit | ES document validation and rules; MX document validation and rules; status transition validation; provider normalization. |
| Context | Application creation success/failure; listing filters and cursor pagination; status updates creating audit logs and PubSub events. |
| Workers | Event dispatch; risk evaluation outcomes; notification idempotency; retry behavior. |
| Webhooks | Signature validation; valid event processing; duplicate idempotency. |
| API | Authentication; authorization; validation errors; redacted responses. |
| LiveView | Creation form; list updates; detail view; status update flow. |
| Migrations/Integration | PostgreSQL trigger creates `application_events` rows on insert and status update. |

---

## 11. Caching & Large-Volume Strategy

### Caching
- Cache country modules and validation metadata in ETS on boot.
- Static invalidation is acceptable because country config is code-defined.

### Indexes (v1)
- `credit_applications(country, status, application_date)`
- `credit_applications(application_date)`
- `application_events(processed_at, inserted_at)`
- Foreign-key indexes on all FK columns.

### Scaling considerations (documented in README)
- Use cursor pagination rather than unbounded offset pagination for list endpoints.
- Consider range partitioning `credit_applications` by `application_date` once volume reaches millions of rows.
- Consider country/date composite partitioning only if query distribution proves country-heavy.
- Archive old audit logs and notification attempts to cheaper storage if retention requirements allow.

---

## 12. Assumptions

1. **PII encryption scope**: v1 will avoid logging PII and will store identity documents in plain text for local MVP use only, plus a hash for audit-safe lookup. Full encryption at rest is deferred.
2. **External notification endpoint**: v1 will support a configurable external notification URL but will not require one to run locally. Missing configuration results in a simulated successful notification result stored locally.
3. **Demo JWT tokens**: v1 uses a hardcoded demo user/role model for token issuance. Real user management is deferred.
4. **Simulated providers**: v1 providers are deterministic code simulations, not real banking APIs.
5. **Single-node Postgres**: v1 runs a single Postgres container locally; high-availability Postgres is deferred.

---

## 13. Versions

The implementation must document exact versions in `README.md`, `mix.exs`, `docker-compose.yml`, and Kubernetes manifests. Initial intended stack:

- Elixir 1.20.x (compatible with Phoenix 1.8.x).
- Phoenix 1.8.x with LiveView.
- PostgreSQL 16 (Docker image).
- Oban 2.23.x.
- Joken 2.6.x.

---

## 14. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| DNI/CURP validation algorithms are tricky to get exactly right. | Start with documented format + checksum rules; add property-based tests; document any simplifications. |
| Async flows are hard to debug. | Structured logs with application id/event id; idempotent workers; integration tests for trigger → event → worker chain. |
| LiveView real-time updates can be flaky in tests. | Use PubSub directly in tests; subscribe in LiveView `mount`/`handle_info`. |
| Provider errors during creation could leave orphan records. | Always create the application with enough data to track recovery, then move to `provider_error` and enqueue retry. |
| Kubernetes manifests become stale. | Validate with `kubectl --dry-run=client`; keep env vars documented in README. |

---

## 15. Definition of Done for First Phase

- [ ] Spain and Mexico applications can be created, retrieved, listed, and status-updated through the API and frontend.
- [ ] Document validation and country financial rules are enforced with tests.
- [ ] Provider responses are simulated, normalized, and never exposed raw.
- [ ] PostgreSQL triggers create `application_events` rows; Oban workers process them safely.
- [ ] Status transitions create audit logs and broadcast real-time frontend updates.
- [ ] JWT auth protects API endpoints; webhook signatures are verified.
- [ ] PII is not logged in full; API responses redact sensitive fields.
- [ ] `make test` passes; `make run` brings up the full stack locally.
- [ ] Kubernetes manifests are included and documented.
- [ ] README explains architecture, decisions, security, and scalability strategy.

---

## 16. Later Phases (High Level)

**Phase 2 — Resilience & Observability**
- Add structured telemetry and metrics (`:telemetry` + Prometheus/StatsD).
- Add provider circuit breakers and retry budgets.
- Add dead-letter handling for exhausted Oban jobs.
- Add rate limiting on webhooks and auth endpoints.
- Add application-level detail caching with PubSub invalidation.

**Phase 3 — Scale & Expansion**
- Add PT, IT, CO, BR through the existing country/provider behaviours.
- Implement range partitioning for `credit_applications` by `application_date`.
- Add read replicas for list/detail queries.
- Add archive jobs for old audit logs and notification attempts.
- Evaluate full PII encryption at rest.

---

## 17. Immediate Next Task

Generate the Phoenix application skeleton, add Oban and Joken, configure Docker Compose for PostgreSQL, and create the `Makefile` so that the remaining domain work has a runnable base.
