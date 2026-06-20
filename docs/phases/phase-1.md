# Phase 1 — ES + MX Vertical Slice

> **Parent:** `docs/master-plan.md` · **Source of truth for requirements:** `docs/requirements.md`
> **Status:** Planning artifact only. No code written.
> **Goal:** One complete, correct, observable end-to-end flow for **Spain (ES)** and **Mexico (MX)** that exercises every functional and non-functional requirement and proves the global architecture. After Phase 1, anyone should be able to explain the whole system from this slice.

---

## 1. Phase Goal & Boundaries

**Entry condition:** Phase 0 foundation gate green (`make setup && make test` passes on an empty-but-wired skeleton).

**In scope:** create / validate / enrich / query / list / status-update applications for ES + MX; async backbone (triggers → outbox → workers); one inbound webhook + one outbound simulated notification; near-real-time LiveView UI; JWT auth + roles; structured logs + PII redaction; ETS country cache; reproducible local run; k8s manifests; README with data-model + scale analysis.

**Out of scope (deferred):** real providers; PT/IT/CO/BR; PII encryption at rest; metrics/dashboards; circuit breakers; DLQ; rate limiting; app-level detail cache; real k8s deploy; load testing. (See Phase 2–4.)

---

## 2. Product Perspective

### 2.1 Personas
- **Applicant data entry / API consumer** — creates applications (read + create role).
- **Operations reviewer** — lists, inspects, and updates application status (update role).
- **External provider system** — sends webhook confirmations.
- **Evaluator** — runs the system locally and verifies the flow.

### 2.2 User Stories & Acceptance Criteria

**US-1 — Create an application (API + UI)**
> As an API consumer / operator, I can create a credit application for ES or MX so it enters risk processing.
- **AC1.1** Required fields accepted: country, full name, identity document, requested amount, monthly income; `application_date` and initial `status` are server-set.
- **AC1.2** Invalid country, non-positive amounts/income, or bad document format return `422` with field-level messages.
- **AC1.3** On success, status = `submitted`, `provider_summary` is populated (normalized), and the response redacts the document to last-4.
- **AC1.4** Creation generates durable async work (an `application_events` row appears).

**US-2 — Country rules enforced**
> As the business, country-specific rules are applied at creation.
- **AC2.1 (ES)** Document must match DNI format + checksum (simplification documented if used).
- **AC2.2 (ES)** `requested_amount > 15000.00` → `additional_review_required = true`.
- **AC2.3 (ES)** `requested_amount > 12 × monthly_income` → `additional_review_required = true` (flagged, **not** rejected — decision D7).
- **AC2.4 (MX)** Document must match CURP format (uppercase alphanumeric, expected length).
- **AC2.5 (MX)** `requested_amount > 10 × monthly_income` → `additional_review_required = true`.
- **AC2.6 (MX)** `provider_debt + requested_amount > 18 × monthly_income` → `additional_review_required = true`.

**US-3 — Provider enrichment**
> As the system, I fetch and normalize banking data per country.
- **AC3.1** Each country has a simulated adapter implementing a shared behaviour; responses are deterministic.
- **AC3.2** Only normalized fields are stored in `provider_summary`; raw payloads never persisted or returned.
- **AC3.3** Provider failure moves the application into a recoverable `provider_error` state (no silent success).

**US-4 — Query an application**
- **AC4.1** Authenticated `GET /api/applications/:id` and a LiveView detail page return full safe (redacted) data.
- **AC4.2** Unknown id returns `404`.

**US-5 — List & filter applications**
- **AC5.1** `GET /api/applications` and the LiveView list support filters: country, status, `application_date` range.
- **AC5.2** Results use **cursor pagination** (no unbounded OFFSET).
- **AC5.3** The UI allows filtering by country and status.

**US-6 — Update status (audited + realtime)**
- **AC6.1** Status changes go through one validated transition function; invalid transitions are rejected.
- **AC6.2** Every transition writes an `application_status_transitions` row and an `audit_logs` entry.
- **AC6.3** Transitions emit a PubSub event; the UI updates **without manual refresh**.
- **AC6.4** Update requires the update role (`403` otherwise).

**US-7 — Async processing visible**
- **AC7.1** Creating an application triggers (via Postgres trigger) `application.created`; a status update triggers `application.status_changed`.
- **AC7.2** `EventDispatcherWorker` claims events with `FOR UPDATE SKIP LOCKED` and enqueues specialized workers.
- **AC7.3** Risk evaluation moves the application through `pending_risk` → `approved`/`rejected`/`additional_review`.
- **AC7.4** Job failures are logged with `application_id` and are retryable; reruns do not duplicate side effects.

**US-8 — Webhook + notification**
- **AC8.1** `POST /api/webhooks/provider-confirmations` verifies a shared-secret/signature; invalid → `401/403`.
- **AC8.2** A valid webhook writes a `webhook_events` row and updates state only through a validated transition.
- **AC8.3** When an application reaches `approved` or `rejected`, a notification job runs; with no configured endpoint it stores a simulated successful result locally.

**US-9 — Realtime UI**
- **AC9.1** List and/or detail update live on status changes via PubSub.
- **AC9.2** UI clearly shows validation errors and async states (e.g., "pending risk evaluation").

### 2.3 Demo Script (what "done" looks like)
1. `make run` → app + Postgres up in < 5 min.
2. Get a JWT from `/api/auth/token`.
3. Create an ES application over the threshold → it is flagged `additional_review_required`; create a valid MX application.
4. Watch the LiveView list update live as workers move applications to `pending_risk` then to a final status.
5. POST a webhook confirmation → see a status transition + audit entry appear live.
6. Show structured logs (no full document/PII) and the `application_events` outbox rows.

---

## 3. Technical Scope

### 3.1 Modules
- `DebtStalker.Countries` — `Behaviour` (`validate_document/1`, `validate_financials/1`, `interpret_provider_summary/1`, `additional_review_required?/1`, `allowed_status_transitions/0`), `ES`, `MX`, `Registry` (ETS-cached).
- `DebtStalker.Providers` — `Behaviour` (input: country + document + lookup fields; output: normalized summary + provider status + risk indicators; errors: `timeout`/`unavailable`/`invalid_document`/rejection), `ESAdapter`, `MXAdapter`.
- `DebtStalker.Applications` — `create_application/1`, `get_application/1`, `list_applications/1`, `update_status/3`; serializers with redaction.
- `DebtStalker.Risk`, `DebtStalker.Audit`, `DebtStalker.Notifications`.
- `DebtStalker.Workers` — `EventDispatcherWorker`, `RiskEvaluationWorker`, `AuditWorker`, `ExternalNotificationWorker`, `ProviderWebhookWorker`.
- `DebtStalkerWeb` — auth plugs, API controllers, webhook controller, LiveViews.

### 3.2 Data Model (migrations)
`credit_applications` (`id uuid`, `country`, `full_name`, `identity_document`, `identity_document_hash`, `requested_amount decimal`, `monthly_income decimal`, `application_date utc_datetime`, `status`, `additional_review_required boolean`, `provider_summary jsonb`, `risk_result jsonb`, timestamps) · `application_status_transitions` · `application_events` (outbox) · `audit_logs` · `webhook_events` · `notification_attempts`.

**Triggers:** AFTER INSERT → `application.created`; AFTER UPDATE OF `status` → `application.status_changed`, both inserting into `application_events`.

**Indexes:** `(country, status, application_date)`, `(application_date)`, `application_events(processed_at, inserted_at)`, FK indexes, `identity_document_hash`.

### 3.3 Status Flow
```
submitted         -> pending_risk | provider_error | cancelled
pending_risk      -> additional_review | approved | rejected | cancelled
additional_review -> approved | rejected
```
Country modules may **narrow** allowed transitions; they cannot bypass audit logging.

### 3.4 API & Auth
Endpoints per master plan §4.6. JWT secret from env (fail-fast in prod). Roles: `read` and `update`; `PATCH /status` requires `update`. Public: health + token issuance. All responses redacted.

### 3.5 Frontend (LiveView)
List page (filters + cursor pagination + PubSub live updates) · Detail page (safe data + status update action for authorized users + live updates) · Create form (country-driven document hints + inline validation errors) · graceful error flashes.

### 3.6 Observability & Caching
Structured logs for: creation, validation failures, provider calls (success/failure), queued jobs, job completion/failure, webhook receipt, status transitions — each with `application_id` when available; never full document or raw payload. ETS cache for country config (static, boot-loaded).

### 3.7 Reproducibility & Deployment
`Makefile` (`setup`, `db`, `migrate`, `seed`, `run`, `test`, `format`, `lint`, `k8s-apply`) · Docker Compose for Postgres · seeds for ES + MX demo data · `k8s/` manifests (namespace, configmap, secret placeholders, postgres, web deploy/service, ingress, worker deploy, migration job) validated with `kubectl apply --dry-run=client` · README (assumptions, data model, decisions, security, scalability analysis, concurrency/queues/cache/webhooks strategy).

---

## 4. Definition of Done

- [ ] ES + MX applications can be created, retrieved, listed, and status-updated via API **and** LiveView.
- [ ] Document validation + financial rules enforced with tests (incl. ES threshold/income flag and MX income/debt rules).
- [ ] Provider responses simulated, normalized, never exposed raw; provider failure → recoverable `provider_error`.
- [ ] Postgres triggers create `application_events`; `EventDispatcherWorker` drains with `SKIP LOCKED`; specialized workers process safely and idempotently.
- [ ] Status transitions validated, recorded in `application_status_transitions` + `audit_logs`, and broadcast via PubSub.
- [ ] JWT protects all endpoints except health + token; read vs update roles enforced.
- [ ] Webhook signature verified; valid webhook → `webhook_events` + validated transition.
- [ ] `approved`/`rejected` enqueues a notification job (simulated result stored if no endpoint).
- [ ] LiveView list/detail update without manual refresh; validation + async states shown.
- [ ] PII never logged in full; responses redact to last-4.
- [ ] Cursor pagination + the Phase 1 indexes are in place.
- [ ] `make test` green; `make run` brings up the full stack locally in < 5 min.
- [ ] k8s manifests included + `--dry-run=client` valid + documented env vars.
- [ ] README covers architecture, decisions, security, scalability strategy.
- [ ] **All Global Architecture invariants (master plan §4.1) hold.**

---

## 5. Phase 1 Risks (delta from master register)

| Risk | Mitigation |
|------|------------|
| Trigger→outbox→worker chain hard to verify | Build the integration test first (insert/update → event row → worker enqueue) as the earliest spike. |
| DNI/CURP rules subtly wrong | Property-based + table tests; document any simplification in README. |
| Realtime UI test flakiness | Subscribe in `mount`; assert on `handle_info`; test PubSub directly. |
| Provider error orphans | Persist with enough data + `provider_error`; enqueue retry. |

---

## 6. Task Seeds (TDD-ordered, ticket-ready)

> Area-prefixed, each with acceptance criteria, ordered by dependency. `T0.0` always creates the feature branch. Each implementation task implies the TDD quadruplet: (a) write failing test, (b) run → fail, (c) implement, (d) run → pass. Import via the `github-issue` skill under a "Phase 1" milestone.

- **[CHORE] T0.0 — Create feature branch** · *AC:* branch `phase-1-es-mx` created from `main`.
- **[INFRA] T1.1 — Spike: trigger→outbox→worker integration test** · *AC:* a failing integration test asserts INSERT creates an `application.created` event row and an UPDATE of status creates `application.status_changed`; documents the SKIP LOCKED claim. *(De-risks earliest.)*
- **[DB] T1.2 — Migrations: `credit_applications` + indexes** · *AC:* table + constraints + composite/hash indexes; migrate/rollback clean.
- **[DB] T1.3 — Migrations: transitions, events (outbox), audit, webhook, notification tables** · *AC:* all five tables + FK indexes; rollback clean.
- **[DB] T1.4 — Postgres trigger functions for outbox** · *AC:* AFTER INSERT + AFTER UPDATE OF status insert correct event rows; covered by T1.1.
- **[DOMAIN] T2.1 — `Countries.Behaviour` + `Registry` (ETS cache)** · *AC:* registry resolves `"ES"`/`"MX"` to modules; unknown country → error; config cached on boot.
- **[DOMAIN] T2.2 — `Countries.ES` (DNI + amount threshold + 12× income flag)** · *AC:* valid/invalid DNI; `>15000` flags review; `>12× income` flags review (not reject).
- **[DOMAIN] T2.3 — `Countries.MX` (CURP + 10× income + 18× debt rule)** · *AC:* valid/invalid CURP; `>10× income` flags review; `debt+amount > 18× income` flags review.
- **[DOMAIN] T3.1 — `Providers.Behaviour` + normalization contract** · *AC:* contract defined; normalization helper; error variants.
- **[DOMAIN] T3.2 — `ESAdapter` + `MXAdapter` (simulated, deterministic)** · *AC:* deterministic normalized fields; error path; no raw payload stored.
- **[DOMAIN] T4.1 — `Applications.create_application/1`** · *AC:* validates country/document/financials, calls provider, persists with server-set date + `submitted` (or `provider_error`), redacts document.
- **[DOMAIN] T4.2 — `get_application/1` + `list_applications/1` (cursor + filters)** · *AC:* get by uuid; list filters country/status/date range; cursor pagination.
- **[DOMAIN] T4.3 — `update_status/3` (validate + transition row + audit + broadcast)** · *AC:* invalid transition rejected; transition + audit rows written; PubSub event emitted.
- **[ASYNC] T5.1 — Oban config + `EventDispatcherWorker` (SKIP LOCKED)** · *AC:* drains unprocessed events, marks processed, enqueues specialized workers; parallel-safe.
- **[ASYNC] T5.2 — `RiskEvaluationWorker`** · *AC:* re-evaluates via country + provider summary; moves status through context; idempotent.
- **[ASYNC] T5.3 — `AuditWorker` + `ExternalNotificationWorker`** · *AC:* audit enrichment non-blocking; notification on `approved`/`rejected`; simulated result when no endpoint; idempotent.
- **[API] T6.1 — JWT auth (`/api/auth/token`) + auth/authz plugs** · *AC:* 401 without/invalid token; 403 for update without role; env secret fail-fast.
- **[API] T6.2 — Applications API controllers (create/get/list/status)** · *AC:* endpoints + redacted serializers + 422 on validation errors.
- **[API] T6.3 — Webhook controller + `ProviderWebhookWorker`** · *AC:* signature verified; `webhook_events` written; state change only via validated transition; duplicate idempotent.
- **[WEB] T7.1 — LiveView list (filters + cursor + PubSub)** · *AC:* filters work; live updates on status change; no refresh.
- **[WEB] T7.2 — LiveView detail + status update action** · *AC:* safe data; authorized status update; live updates.
- **[WEB] T7.3 — LiveView create form** · *AC:* country-driven hints; inline validation errors; success flash.
- **[OPS] T8.1 — Makefile + Docker Compose + seeds** · *AC:* `make run` brings up full stack in < 5 min; seeds create ES + MX demo data.
- **[OPS] T8.2 — k8s manifests + dry-run validation** · *AC:* manifests for web/worker/postgres/config/secret/ingress/migration-job; `kubectl --dry-run=client` passes.
- **[DOCS] T8.3 — README (architecture, decisions, security, scalability analysis)** · *AC:* covers all Deliverables §6 items incl. indexes/partitioning/cursor/archiving.
- **[QA] T9.1 — Concurrency note + basic parallel-processing test** · *AC:* documents how to scale workers; test shows no double-processing under parallel dispatch.
