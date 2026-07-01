# Documentation Consistency Audit

This document records contradictions, drift, and outdated references between the project docs, excluding code-level gaps (see `code-vs-docs.md`).

## Summary

| Severity | Count | Meaning |
| -------- | ----- | ------- |
| Critical | 1 | Roadmap/product scope contradiction that can mislead new engineers. |
| High | 1 | Architectural description disagrees with accepted ADR. |
| Medium | 4 | Outdated references or inconsistent policy wording that need doc updates. |
| Low | 2 | Cosmetic drift, diagrams, or Postman accuracy. |

## Gaps

### 1. Country scope across master-plan, requirements, and phase docs

- **Severity:** Critical
- **Priority:** P1
- **Location:** `docs/master-plan.md`, `docs/requirements.md`, `docs/phases/phase-1.md`, `docs/how-to-add-country.md`, `docs/optional-real-providers.md`
- **Finding:**
  - `requirements.md` states the app must support **Spain, Portugal, Italy, Mexico, Colombia, and Brazil** (six countries).
  - `master-plan.md` repeats the same six-country list and treats them as in-scope.
  - `phase-1.md` is titled "ES + MX Vertical Slice" and only implements Spain and Mexico.
  - No phase doc explicitly owns Portugal, Italy, Colombia, or Brazil. The roadmap jumps from Phase 1 (ES+MX) to Phase 2 (resilience/hardening) without scheduling the remaining four countries.
- **Impact:** New engineers and interviewers assume all six countries are implemented or planned. The gap is only discoverable by reading the code.
- **Recommended action:** Add a roadmap note to `master-plan.md` and `requirements.md` clarifying that Phase 1 only delivers ES and MX, and that PT/IT/CO/BR are Phase 3+ or future expansion.

### 2. Async pipeline diagram still shows five workers including AuditWorker

- **Severity:** High
- **Priority:** P1
- **Location:** `docs/master-plan.md` §4.4, `README.md` architecture section, `docs/adr/0004-synchronous-audit-logging.md`
- **Finding:**
  - `master-plan.md` and `README.md` describe the async pipeline as: Dispatcher → Risk, Audit, Notification, Webhook workers.
  - `ADR-0004` explicitly decided to keep audit logging synchronous inside `Applications.update_status/3` and **not** dispatch an `AuditWorker`.
  - The README/master-plan text has not been updated to reflect the accepted ADR, so the docs contradict the ADR.
- **Impact:** Architectural diagrams and descriptions describe a worker that does not exist, leading to confusion about the audit flow.
- **Recommended action:** Update `README.md` and `master-plan.md` to show four async workers (Dispatcher, Risk, Notification, Webhook) and note that audit is synchronous per ADR-0004.

### 3. Full-name redaction policy is inconsistent across docs

- **Severity:** Medium
- **Priority:** P2
- **Location:** `docs/handoff/phase-2-continuation.md`, `docs/adr/0008-notifications-context-and-webhook-payloads.md`, `README.md`, `docs/master-plan.md`
- **Finding:**
  - `phase-2-continuation.md` contains a superseded note stating: "authorized API/UI surfaces show full names consistently; identity documents remain redacted and logs remain scrubbed."
  - `master-plan.md` and `README.md` still describe redaction in general terms without explicitly distinguishing full-name visibility on authorized surfaces from public/log visibility.
  - `ADR-0008` focuses on webhook payload redaction but does not address the full-name policy.
- **Impact:** Engineers may implement or test the wrong redaction behaviour, and security reviewers may flag the UI/API as leaking PII.
- **Recommended action:** Add a short "PII visibility policy" section to `README.md` and `master-plan.md` that mirrors the handoff's accepted rule: full name is visible on authorized UI/API, identity document is redacted to last-4, logs are scrubbed.

### 4. Postman collection references non-existent DLQ admin endpoints

- **Severity:** Medium
- **Priority:** P2
- **Location:** `docs/postman/debt-stalker.json`, `docs/handoff/phase-2-continuation.md` Issue #2
- **Finding:**
  - The handoff explicitly lists an acceptance criterion to "Remove or clearly mark the non-existent DLQ admin endpoints" from the Postman collection.
  - The collection has not been audited yet; it is likely still carrying placeholder admin endpoints for dead-letter replay/list that have no matching router/controller.
- **Impact:** API consumers import a collection with endpoints that return 404.
- **Recommended action:** Open the Postman collection, remove DLQ admin endpoints unless a controller is added, and add a note in the collection description about the current API surface.

### 5. Health endpoint wording drift

- **Severity:** Low
- **Priority:** P3
- **Location:** `README.md`, `docs/handoff/phase-2-continuation.md` Issue #1, `lib/debt_stalker_web/controllers/api/health_controller.ex`
- **Finding:**
  - The handoff says the README used to describe `/api/health` as returning `"ok"` but the controller returns `"healthy"`.
  - The live/live/ready endpoints (`/api/health/live`, `/api/health/ready`) were added in Phase 2 and may not be consistently linked from the README quick-start or deployment sections.
- **Impact:** Minor documentation inaccuracy; the code is correct.
- **Recommended action:** Verify the README health endpoint examples and add a one-line note about the three health endpoints.

### 6. README scalability section lacks concrete migration/index references

- **Severity:** Low
- **Priority:** P3
- **Location:** `README.md` scalability section, `docs/master-plan.md` §9, `priv/repo/migrations/`
- **Finding:**
  - `master-plan.md` describes recommended indexes, partitioning by `application_date`, read replicas, and archiving.
  - The README scalability section is high-level and does not cite the existing indexes (`credit_applications [country, status, application_date]`, `[application_date]`, `[identity_document_hash]`) or the unprocessed-events index.
- **Impact:** New engineers cannot connect the scalability advice to the current schema.
- **Recommended action:** Add a short "Current schema support" paragraph to the README scalability section listing the existing indexes and the planned partitioning strategy.

### 7. Error atom naming mismatch between master-plan and provider behaviour

- **Severity:** Medium
- **Priority:** P2
- **Location:** `docs/master-plan.md` §5, `lib/debt_stalker/providers/behaviour.ex`, `docs/adr/0005-circuit-breaker-choice.md`
- **Finding:**
  - `master-plan.md` lists domain error atoms including `:provider_timeout` and `:provider_unavailable`.
  - The provider behaviour type and circuit-breaker logic use `:timeout` and `:unavailable`.
  - The `Applications` context maps any provider error to `:provider_error` in its public API, so `:provider_timeout` / `:provider_unavailable` never reach callers.
- **Impact:** The documented error contract is wrong; callers cannot match on the documented atoms.
- **Recommended action:** Update `master-plan.md` §5 to list the actual public error atoms (`:provider_error`, `:timeout`, `:unavailable` internal, `:not_found`, `:invalid_transition`, etc.) and cross-reference the behaviour type.

### 8. `raw_payload` column lifecycle is split across migrations without a single doc anchor

- **Severity:** Medium
- **Priority:** P2
- **Location:** `priv/repo/migrations/20260620220833_create_supporting_tables.exs`, `priv/repo/migrations/20260622050000_remove_raw_payload_from_webhook_events.exs`, `docs/adr/0008-notifications-context-and-webhook-payloads.md`
- **Finding:**
  - The supporting-tables migration creates `raw_payload` on `webhook_events`.
  - A later migration removes it.
  - `ADR-0008` documents the decision but does not point to the migration files, so a reader cannot trace the schema evolution from the ADR alone.
- **Impact:** Schema archaeology is harder than necessary.
- **Recommended action:** Add migration file references to `ADR-0008` and a short note in the migration comments explaining why the column was removed.

## Cross-Reference

- For the code-side view of these same issues, see `docs/audits/code-vs-docs.md`.
