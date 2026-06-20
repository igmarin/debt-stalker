# Debt Stalker v1 Spec

## What

Build v1 of Debt Stalker: an Elixir/Phoenix fintech MVP for creating, validating, processing, tracking, and displaying credit applications across multiple countries. v1 will implement Spain (`ES`) and Mexico (`MX`) end-to-end, with an architecture that makes additional countries, banking providers, validation rules, status flows, background jobs, and frontend views additive instead of disruptive.

## Context

The source challenge in `docs/spec.md` asks for a scalable multi-country credit application system using Elixir and Phoenix. The project currently has no application code, so v1 defines the initial implementation boundary, domain model, runtime architecture, async flow, real-time UI behavior, and deployment shape.

The required system must support:

- Creating credit applications with PII, financial fields, country, status, and banking-provider-derived information.
- Country-specific document and affordability validation.
- Country-specific banking provider integrations.
- Querying one application and listing applications with filters.
- Updating application status with controlled transitions.
- Background processing and parallel workers.
- At least one database-generated asynchronous work flow.
- At least one webhook or simulated external notification flow.
- Near-real-time frontend updates.
- Basic API security, observability, caching, reproducible local setup, and Kubernetes manifests.

## Requirements

### Countries

- The system must implement Spain (`ES`) and Mexico (`MX`) in v1.
- The country abstraction must allow additional countries to be added without changing controller or persistence code.
- Country-specific logic must be isolated behind country modules or behaviours.

### Credit application creation

- The system must expose an authenticated API endpoint to create a credit application.
- The system must expose a frontend form to create a credit application.
- A credit application must include:
  - Country.
  - Full name.
  - Identity document.
  - Requested amount.
  - Monthly income.
  - Application date.
  - Current status.
  - Normalized banking information from the selected country provider.
- The application date must be set by the server.
- The initial status must be `submitted` unless synchronous validation rejects the request.
- Creation must synchronously validate basic input shape, supported country, positive monetary values, and country document format.
- Creation must create an asynchronous event for risk evaluation and audit logging.

### Spain validation

- Spain applications must require a DNI-like document format.
- Spain applications must run a DNI checksum validation in v1 if feasible during implementation; otherwise the implementation must clearly document the simplified validation rule.
- Spain applications with requested amount greater than `15000.00` must be marked `additional_review_required`.
- Spain applications must reject requested amounts greater than `12` times monthly income unless manually reviewed.

### Mexico validation

- Mexico applications must require a CURP-like document format.
- Mexico applications must validate CURP format using an uppercase alphanumeric pattern with expected length.
- Mexico applications must reject requested amounts greater than `10` times monthly income unless manually reviewed.
- Mexico applications must be marked `additional_review_required` when provider debt plus requested amount is greater than `18` times monthly income.

### Banking providers

- v1 must use simulated banking providers, not real external banking APIs.
- Each country must have its own provider adapter implementing a common behaviour.
- Provider responses must be normalized before storage.
- Raw provider payloads must not be exposed through public API responses.
- Provider failures during creation must move the application into a recoverable provider error path rather than silently succeeding.

### Status flow

- The system must support the following shared statuses in v1:
  - `submitted`.
  - `pending_risk`.
  - `additional_review`.
  - `approved`.
  - `rejected`.
  - `provider_error`.
  - `cancelled`.
- The system must validate all status transitions.
- The system must record every status transition in an audit log.
- Status transitions must emit real-time frontend updates.
- Status transition rules must be configurable per country module.

### Querying and listing

- The system must expose an authenticated API endpoint to fetch a credit application by id.
- The system must expose an authenticated API endpoint to list credit applications.
- The list endpoint must support filters for country, status, and application date range.
- The frontend must display the application list and allow filtering by country and status.
- The frontend must display a detail view for one application.

### Asynchronous processing

- The system must use PostgreSQL-backed job processing.
- Creating an application must generate durable asynchronous work.
- At least one database operation must generate asynchronous work through a PostgreSQL-native mechanism.
- Background jobs must be safe to run with multiple worker processes in parallel.
- Jobs must be idempotent where possible.
- Job failures must be logged and retryable.

### Webhooks and external notifications

- v1 must include a simulated external notification flow.
- When an application reaches `approved` or `rejected`, the system must enqueue a notification job.
- The notification job must call a configurable simulated external endpoint when configured.
- If no external endpoint is configured, the notification job must store a simulated successful notification result locally.
- The system must expose a webhook endpoint that can receive a provider confirmation event for an application.
- Webhook payloads must be authenticated with a shared secret or signed header.
- Webhook processing must write an event record and update application state only through validated transitions.

### Real-time frontend

- The frontend must show application list changes or status changes without manual refresh.
- Real-time updates must be implemented using Phoenix PubSub and either Phoenix LiveView or Phoenix Channels.
- The UI must show validation errors and async processing states clearly.

### Security

- API endpoints must require JWT authentication except health checks and auth token issuance.
- JWT secrets must come from environment variables.
- PII must not be logged in full.
- API responses must avoid exposing raw provider payloads or sensitive internal fields.
- Basic authorization must distinguish at least read access from status update access.

### Observability

- The system must emit structured logs for application creation, validation failures, provider calls, queued jobs, job completion, job failure, webhook receipt, and status transitions.
- Logs must include application id when available.
- Logs must not include full identity documents or raw provider payloads.

### Caching

- v1 must cache country configuration and validation metadata.
- Cache invalidation can be static-on-boot for v1 because country configuration is code-defined.
- If application detail caching is added, status updates must invalidate the cached detail.

### Reproducibility

- The project must include local setup instructions in `README.md`.
- The project must include a `Makefile` or `Justfile` with common commands.
- The evaluator must be able to run the system locally in under five minutes when Elixir, Docker, and standard tools are already installed.

### Deployment

- The project must include Kubernetes manifests for the Phoenix web process, worker process, PostgreSQL dependency or external database configuration, services, config, and secrets placeholders.
- Manifests must document required environment variables.

## Design

### Application shape

Use a Phoenix application with clear domain boundaries:

- `DebtStalker.Applications`: core application creation, retrieval, listing, and status transitions.
- `DebtStalker.Countries`: country registry, validation behaviour, status flow behaviour, country configuration.
- `DebtStalker.Providers`: provider behaviour plus simulated country provider adapters.
- `DebtStalker.Risk`: asynchronous risk evaluation orchestration.
- `DebtStalker.Notifications`: external notification and webhook processing.
- `DebtStalker.Audit`: audit log creation and retrieval helpers.
- `DebtStalkerWeb`: API controllers, auth plugs, LiveView or channel frontend, webhook controller.

v1 should be a single Phoenix app, not an umbrella app, unless implementation discovers a strong reason to split web and worker supervision trees into separate release applications.

### Data model

Use PostgreSQL as the primary datastore.

Core tables:

- `credit_applications`.
  - `id` UUID primary key.
  - `country` string or enum-like constrained field.
  - `full_name` encrypted or plain text for MVP with restricted logging.
  - `identity_document_hash` for lookup/audit-safe references.
  - `identity_document_encrypted` or `identity_document` depending on encryption scope selected during implementation.
  - `requested_amount` decimal.
  - `monthly_income` decimal.
  - `application_date` UTC datetime.
  - `status` string.
  - `additional_review_required` boolean.
  - `provider_summary` JSONB normalized safe fields.
  - `risk_result` JSONB.
  - `inserted_at` and `updated_at`.
- `application_status_transitions`.
  - `id` UUID primary key.
  - `application_id` foreign key.
  - `from_status`.
  - `to_status`.
  - `reason`.
  - `actor_type`.
  - `actor_id` nullable.
  - `inserted_at`.
- `application_events`.
  - Durable outbox/event table generated by application writes and PostgreSQL triggers.
  - Fields: `id`, `application_id`, `event_type`, `payload`, `processed_at`, `attempt_count`, timestamps.
- `audit_logs`.
  - Append-only audit records with redacted metadata.
- `webhook_events`.
  - Stores received webhook metadata, signature verification result, payload hash, processing result.
- `notification_attempts`.
  - Stores external notification attempts and outcomes.

### PostgreSQL-native async flow

Use a PostgreSQL trigger on `credit_applications` insert and status update to insert rows into `application_events`.

Example generated events:

- `application.created` after insert.
- `application.status_changed` after status update.

An Oban worker or supervised poller processes unprocessed `application_events` using row-level locking with `FOR UPDATE SKIP LOCKED`, then enqueues specialized Oban jobs:

- Risk evaluation job.
- Audit enrichment job.
- Notification job.

This keeps the challenge requirement explicit: a database operation generates durable asynchronous work, and worker concurrency is controlled through database locks and idempotent processing.

### Job processing

Use Oban with PostgreSQL for durable background jobs.

Primary workers:

- `EventDispatcherWorker`: drains `application_events` and routes work.
- `RiskEvaluationWorker`: evaluates provider data, income ratio, and country rules that do not need to block creation.
- `AuditWorker`: writes non-blocking audit enrichment entries.
- `ExternalNotificationWorker`: sends or simulates status notifications.
- `ProviderWebhookWorker`: processes verified webhook events asynchronously if webhook handling should return quickly.

Workers must include application id and event id in logs. Workers must avoid duplicate side effects by checking event processing state, notification attempt uniqueness, or current application status before writing.

### Provider abstraction

Define a provider behaviour with a contract equivalent to:

- Input: country, identity document, application fields needed for lookup.
- Output: normalized provider summary, provider status, and optional risk indicators.
- Errors: timeout, unavailable, invalid document, provider-specific rejection.

Adapters for v1:

- Spain provider adapter returns normalized fields such as existing debt, internal score bucket, account age months.
- Mexico provider adapter returns normalized fields such as existing debt, bureau score bucket, delinquency flag.

Adapters must be simulated in code and deterministic enough for tests.

### Country abstraction

Define a country behaviour with responsibilities equivalent to:

- Validate document format.
- Validate amount and income rules.
- Interpret normalized provider summary.
- Determine whether additional review is required.
- Validate allowed status transitions.

Country modules for v1:

- `ES`: DNI validation, amount threshold, amount-to-income rule.
- `MX`: CURP validation, amount-to-income rule, debt-to-income rule.

The rest of the system must call the behaviour through a registry rather than branching on country in controllers.

### API surface

Authenticated JSON API:

- `POST /api/auth/token` for local/demo token issuance.
- `POST /api/applications` to create an application.
- `GET /api/applications/:id` to retrieve one application.
- `GET /api/applications` to list applications with filters.
- `PATCH /api/applications/:id/status` to update status.
- `POST /api/webhooks/provider-confirmations` to receive signed provider events.
- `GET /api/health` for health checks.

Public responses must use serializers that redact sensitive fields.

### Frontend surface

Use Phoenix LiveView unless implementation chooses Phoenix Channels plus a separate frontend. LiveView is the default for v1 because it satisfies near-real-time updates with fewer moving parts.

Required views:

- Application creation form.
- Application list with country and status filters.
- Application detail page.
- Status update action for authorized users.
- Real-time status/list updates via PubSub subscriptions.

### Status transitions

Default v1 transition model:

- `submitted` -> `pending_risk`.
- `submitted` -> `provider_error`.
- `pending_risk` -> `additional_review`.
- `pending_risk` -> `approved`.
- `pending_risk` -> `rejected`.
- `additional_review` -> `approved`.
- `additional_review` -> `rejected`.
- `submitted` -> `cancelled`.
- `pending_risk` -> `cancelled`.

Country modules may narrow this flow, but they must not bypass audit logging.

### Large-volume strategy

v1 must include README documentation for scaling beyond MVP:

- Indexes on `credit_applications(country, status, application_date)`, `credit_applications(application_date)`, `application_events(processed_at, inserted_at)`, and foreign keys.
- Consider range partitioning `credit_applications` by application date for millions of rows.
- Consider country/date composite partitioning only if query distribution proves country-heavy.
- Use cursor pagination rather than unbounded offset pagination for high-volume list endpoints.
- Archive old audit logs and notification attempts to cheaper storage if retention requirements allow.

## Decisions

### Decision: Implement Spain and Mexico first

- Choice: v1 supports `ES` and `MX`.
- Alternatives: Spain and Portugal, or all six countries.
- Reason: Spain and Mexico cover Europe and Latin America, have distinct document types, and exercise both amount-to-income and provider debt-to-income rules.
- Reversible: Yes. Additional countries can be added through the country and provider behaviours.

### Decision: Use Phoenix LiveView for the frontend

- Choice: Build the frontend with Phoenix LiveView.
- Alternatives: Separate React frontend with Phoenix Channels, or server-rendered pages with polling.
- Reason: LiveView gives near-real-time updates through Phoenix PubSub with less infrastructure and faster MVP delivery.
- Reversible: Yes. The API and PubSub boundaries can later support a separate SPA.

### Decision: Use Oban for background jobs

- Choice: Use Oban backed by PostgreSQL.
- Alternatives: Broadway, GenServer-only queue, RabbitMQ, or external cloud queue.
- Reason: Oban keeps local setup simple, is durable, supports retries, and fits a PostgreSQL-centric MVP.
- Reversible: Partially. Worker contracts can move to another queue later, but job storage and retry semantics would change.

### Decision: Use PostgreSQL trigger plus outbox table for database-generated work

- Choice: Application inserts and status updates trigger rows in `application_events`.
- Alternatives: Only enqueue jobs in application code, or insert directly into Oban internals from triggers.
- Reason: The outbox table explicitly satisfies database-generated async work without coupling triggers to Oban internals.
- Reversible: Yes. The event dispatcher boundary can be replaced with logical replication, LISTEN/NOTIFY, or direct app-level enqueueing later.

### Decision: Simulate banking providers

- Choice: Use deterministic simulated providers for v1.
- Alternatives: Integrate real banking APIs or use random fake responses.
- Reason: The challenge evaluates architecture and flow; deterministic simulation enables repeatable tests and a sub-five-minute setup.
- Reversible: Yes. Real providers can implement the same behaviour.

### Decision: JWT for API authentication

- Choice: Use JWT bearer tokens for API endpoints.
- Alternatives: Session-only auth, API keys, OAuth/OIDC.
- Reason: JWT satisfies the challenge requirement and is simple for local testing.
- Reversible: Yes. Authorization plugs can later validate OIDC-issued JWTs.

### Assumption: PII encryption scope

Assumption: v1 will avoid logging PII and may store identity documents encrypted if the selected library and setup remain simple. If encryption would significantly slow delivery, v1 must store a document hash plus a clearly documented simplified PII storage approach for local MVP use only.

### Assumption: External notification endpoint

Assumption: v1 will support a configurable external notification URL but will not require one to run locally. Missing configuration results in a local simulated notification result.

## Versions

Version choices must be finalized during implementation against current stable/LTS documentation. Initial intended stack:

- Elixir stable release compatible with the selected Phoenix release.
- Phoenix stable release with LiveView support.
- PostgreSQL stable release available through Docker.
- Oban version compatible with the selected Elixir/Phoenix stack.

The implementation must document exact versions in `README.md`, `mix.exs`, Docker configuration, and Kubernetes manifests once the project is generated.

## Invariants

- Controllers and LiveViews must not contain country-specific business rules.
- Provider adapters must return normalized data before persistence or API serialization.
- Status changes must go through the application status transition function.
- Every status change must create an audit record.
- Raw provider payloads must not appear in public API responses.
- Logs must not include full identity documents.
- Background jobs must be safe under at-least-once execution.
- Application list endpoints must never return unbounded result sets.
- Webhook events must be authenticated before state changes.

## Error Behavior

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

## Testing Strategy

- Unit tests for Spain document validation and rules.
- Unit tests for Mexico document validation and rules.
- Unit tests for status transition validation.
- Unit tests for provider normalization.
- Context tests for application creation.
- Context tests for listing filters and pagination.
- Context tests for status updates creating audit logs and PubSub events.
- Worker tests for event dispatch, risk evaluation, notification, retries, and idempotency.
- Webhook controller tests for signature validation and state changes.
- API tests for authentication, authorization, validation errors, and redacted responses.
- LiveView tests for creation form, list updates, detail view, and status update flow.
- Migration tests or integration tests proving the PostgreSQL trigger creates `application_events` rows.

## Out of Scope

- Real banking provider integrations.
- Production-grade KYC or AML checks.
- Full multi-tenant authorization model.
- All six countries.
- Advanced dashboards and metrics beyond structured logs and basic health checks.
- Real Kubernetes deployment to a cluster.
- Load testing with millions of records.
- Complete PII compliance certification.
