# Code vs. Documentation Gap Analysis

This document records mismatches between the documented architecture/behaviour and the implemented Elixir code. Findings are framed as documented-claim vs. actual-implementation, not as a list of missing features.

## Summary

| Severity | Count | Meaning |
| -------- | ----- | ------- |
| Critical | 1 | Documented product scope is not implemented; breaks the requirements contract. |
| High | 2 | Public API/architectural description is materially different from the code. |
| Medium | 5 | Implementation diverges from docs in ways that require doc updates or small API adjustments. |
| Low | 3 | Naming, history, or cosmetic drift. |

## Gaps

### 1. Country coverage: six documented, two implemented

- **Severity:** Critical
- **Priority:** P1
- **Documented:** `docs/requirements.md`, `docs/master-plan.md`, `docs/optional-real-providers.md`
  - The system must support Spain, Portugal, Italy, Mexico, Colombia, and Brazil.
- **Implemented:** `lib/debt_stalker/countries/` contains only `es.ex` and `mx.ex`.
  - `DebtStalker.Countries.Registry` hardcodes `@default_countries ["ES", "MX"]` and fails to load any others.
  - `DebtStalker.Countries.Behaviour` is country-agnostic, but no modules implement it for PT, IT, CO, or BR.
- **Impact:** The API and UI only allow applicants and admins to select ES and MX. The documented six-country requirement is not met.
- **Recommended action:** Either update the docs to reflect the current ES+MX scope and schedule PT/IT/CO/BR for a future phase, or implement the remaining four countries. This is a product/roadmap decision, not a code-only fix.

### 2. Async pipeline: docs show five workers, code has four

- **Severity:** High
- **Priority:** P1
- **Documented:** `docs/master-plan.md`, `README.md`
  - The async pipeline includes a Dispatcher plus five workers: Risk, Audit, Notification, Webhook, and an explicit AuditWorker.
- **Implemented:** `lib/debt_stalker/workers/`
  - Only four workers exist: `RiskEvaluationWorker`, `ExternalNotificationWorker`, `WebhookProcessingWorker`, and the dispatcher `EventDispatcherWorker`.
  - Audit records are written synchronously inside `Applications.update_status/3` via `Ecto.Multi` (see `ADR-0004` and `lib/debt_stalker/applications.ex`).
- **Impact:** The pipeline diagram and architecture description are wrong. Engineers reading the docs will look for an `AuditWorker` that does not exist.
- **Recommended action:** Update the README and master-plan diagrams to show the four-worker pipeline and add a note that audit is synchronous per ADR-0004.

### 3. DLQ context exists, but no admin API surface is documented

- **Severity:** High
- **Priority:** P2
- **Documented:** `docs/postman/debt-stalker.json` (suspected), `docs/handoff/phase-2-continuation.md`
  - The handoff mentions DLQ admin endpoints in the Postman collection that should be removed or clearly marked as non-existent.
- **Implemented:** `lib/debt_stalker/dead_letter.ex`
  - The `DeadLetter` context provides `list_jobs/1`, `get_job/1`, `count_jobs/0`, and `reenqueue_job/1`.
  - No router entry, controller, or LiveView exposes these functions over HTTP or the UI.
  - The supervisor starts `ObanTelemetryHandler` (which captures exhausted jobs), but there is no admin interface to inspect them.
- **Impact:** The public API surface is smaller than the collection implies, and operations cannot view/replay dead-letter jobs without opening `iex`.
- **Recommended action:** Remove DLQ admin endpoints from the Postman collection and add a short note in `README.md` or `docs/master-plan.md` that DLQ operations are currently internal-only (via `iex` / `DeadLetter` context).

### 4. Provider error atoms documented as `:provider_timeout`/`:provider_unavailable`, code exposes `:provider_error`

- **Severity:** Medium
- **Priority:** P2
- **Documented:** `docs/master-plan.md` §5 lists domain error atoms including `:provider_timeout` and `:provider_unavailable`.
- **Implemented:**
  - `lib/debt_stalker/providers/behaviour.ex` defines provider errors as `{:error, :timeout | :unavailable | :invalid_document | :rejection}`.
  - `lib/debt_stalker/providers/circuit_breaker.ex` returns `{:error, :timeout}` or `{:error, :unavailable}`.
  - `lib/debt_stalker/applications.ex` maps all provider errors to the public atom `:provider_error`.
  - No caller ever receives `:provider_timeout` or `:provider_unavailable`.
- **Impact:** The public error contract in `master-plan.md` is incorrect. API clients or pattern matches in tests written against the docs will fail.
- **Recommended action:** Update `master-plan.md` §5 to remove `:provider_timeout` and `:provider_unavailable` from the public domain error list, and document `:provider_error` plus the internal provider error atoms.

### 5. Full-name policy is implemented differently than some docs imply

- **Severity:** Medium
- **Priority:** P2
- **Documented:** `docs/master-plan.md` and `README.md` discuss PII redaction in general terms, without clearly distinguishing full-name visibility on authorized surfaces.
- **Implemented:**
  - `lib/debt_stalker/applications/credit_application.ex` only redacts the `identity_document` to last-4.
  - `lib/debt_stalker_web/live/admin/application_detail_live.ex` and `application_confirmation_live.ex` render `app.full_name` in plain text.
  - The API controller returns `full_name` in `serialize_application/1` without redaction.
  - Logs scrub only identity documents; full names are not scrubbed in the code paths reviewed.
- **Impact:** The handoff (issue #5) already accepted this as the intended policy, but the master-plan/README wording can still be read as requiring broader redaction.
- **Recommended action:** Add an explicit PII visibility policy to the README and master-plan: identity document is redacted everywhere, full name is visible on authorized UI/API, logs never contain full identity documents.

### 6. Provider integration is simulated, not real

- **Severity:** Medium
- **Priority:** P3
- **Documented:** `docs/master-plan.md`, `README.md`, and `docs/optional-real-providers.md` describe provider integrations and research into real services.
- **Implemented:** `lib/debt_stalker/providers/es_adapter.ex`, `mx_adapter.ex`
  - Both adapters are deterministic simulators keyed by `identity_document` prefixes.
  - They return hardcoded `provider_summary` maps and simulate errors with prefixes like `"TIME"` and `"ERR"`.
  - No real HTTP calls, sandbox APIs, or bank integrations are present.
- **Impact:** The docs describe a provider integration pattern that is fully exercised only by simulation. Performance and resilience testing against real providers is not possible today.
- **Recommended action:** Clarify in `README.md` and `master-plan.md` that providers are simulated for the challenge and that real integrations would implement the same `DebtStalker.Providers.Behaviour` contract.

### 7. README scalability section does not cite the current indexes

- **Severity:** Low
- **Priority:** P3
- **Documented:** `README.md` and `docs/master-plan.md` describe future scalability tactics (partitioning, read replicas, archiving) in abstract terms.
- **Implemented:** `priv/repo/migrations/`
  - `credit_applications` has indexes on `[country, status, application_date]`, `[application_date]`, and `[identity_document_hash]`.
  - `application_events` has an index on `[processed_at, inserted_at]` and an unprocessed-depth index.
  - No partitioning, replicas, or archiving is implemented yet.
- **Impact:** Engineers cannot see how the current schema supports the documented scalability strategy.
- **Recommended action:** Add a short paragraph to the README scalability section listing the existing indexes and the planned next steps (partitioning by `application_date`, archiving old records).

### 8. Webhook `raw_payload` column was removed, but the migration history still contains it

- **Severity:** Low
- **Priority:** P3
- **Documented:** `docs/adr/0008-notifications-context-and-webhook-payloads.md` says raw payloads are not persisted.
- **Implemented:**
  - `priv/repo/migrations/20260620220833_create_supporting_tables.exs` creates `webhook_events.raw_payload`.
  - `priv/repo/migrations/20260622050000_remove_raw_payload_from_webhook_events.exs` removes it.
  - The current schema matches the ADR.
- **Impact:** The migration history is correct but can surprise someone reading only the first migration. The ADR does not reference the migration files.
- **Recommended action:** Reference both migration files in `ADR-0008` so readers can follow the schema evolution.

### 9. Health endpoint status values

- **Severity:** Low
- **Priority:** P3
- **Documented:** `README.md` historically described `/api/health` returning `"ok"` (per handoff note).
- **Implemented:** `lib/debt_stalker_web/controllers/api/health_controller.ex` returns `"healthy"` / `"unhealthy"` for the legacy endpoint, and `"alive"` / `"ready"` for the liveness/readiness probes.
- **Impact:** Minor documentation inaccuracy; the code is internally consistent.
- **Recommended action:** Ensure the README examples match the current controller output.

### 10. Phase-2 UI/UX polish is partially implemented

- **Severity:** Medium
- **Priority:** P2
- **Documented:** `docs/handoff/phase-2-continuation.md` lists remaining UI/UX improvements: debounce, skeletons, interactive charts, page pagination, confirmation copy-to-clipboard, and error states.
- **Implemented:**
  - `filter_bar` inputs use `phx-debounce="300"`.
  - `Components.UI.skeleton/1` exists.
  - Charts use `ChartHook` and Chart.js (`phx-hook="ChartHook"`).
  - Page pagination is present in `ApplicationsLive` (`lib/debt_stalker_web/live/admin/applications_live.ex`).
  - Copy-to-clipboard is present in `ApplicationConfirmationLive` (`JS.dispatch("phx:copy")`).
  - Empty states exist (`empty_state/1`).
  - Some advanced polish (e.g. chart skeletons, pagination ellipses beyond seven pages, dashboard date-range presets) may still be open.
- **Impact:** The handoff reads like a list of unresolved work, but much of it is already done. New contributors may duplicate effort.
- **Recommended action:** Close or update the handoff issues to reflect the current implementation, and update the README dashboard section to list the implemented features.

## Cross-Reference

- For contradictions between the docs themselves, see `docs/audits/doc-consistency.md`.
