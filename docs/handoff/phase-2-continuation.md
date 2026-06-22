# Phase 2 Continuation — README, API Docs, Security, UI/UX Improvements

This handoff captures four follow-up improvement issues after the core Phase 2
resilience work is complete. Each issue is written as a self-contained PR and
traces back to the observations from the pre-implementation review.

> **Goal:** Polish the evaluator-facing surface, fix production safety gaps, and
> improve the admin UI/UX without changing domain architecture.

---

## Issue #1 — README + Mermaid Architecture Diagrams

**Type:** `[DOCS]` (TDD-exempt, but README examples must be verified manually)

**Scope:**
- Replace the ASCII architecture diagram in `README.md` with a Mermaid diagram.
- Add a second Mermaid sequence diagram for the async outbox flow.
- Add a Phase 2 architecture view that includes Cachex, circuit breaker, DLQ,
  rate limiter, Prometheus metrics, and web/worker split.
- Fix health endpoint descriptions (`/api/health` returns `"healthy"`, not `"ok"`).
- Document `/api/health/live` and `/api/health/ready`.
- Link to generated ExDoc, master-plan, ADRs, and Postman collection.
- Expand the scalability section with concrete indexes, partitioning strategy,
  cursor pagination, and archiving notes.

**Acceptance criteria:**
- [ ] `README.md` renders correctly on GitHub (Mermaid is natively supported).
- [ ] All endpoints described in README match the router.
- [ ] Scalability section mentions recommended indexes, partitioning by
      `application_date`, read replicas, and audit/notification archiving.

**Files to change:**
- `README.md`

---

## Issue #2 — Postman Collection + API Docs Accuracy

**Type:** `[DOCS]` (TDD-exempt, but collection must run against a live server)

**Scope:**
- Fix the health-check test assertion (`"healthy"`, not `"ok"`).
- Add requests for `/api/health/live` and `/api/health/ready`.
- Add a cursor-pagination flow: first request captures `cursor`, second uses it.
- Add `x-webhook-signature` header example to the webhook request.
- Fix token variables in "Provider Failures" folder (`{{token}}`, role `update`).
- Remove or clearly mark the non-existent DLQ admin endpoints.
- Add status-transition examples for `additional_review`, `rejected`, `cancelled`, and
  `provider_error`.
- Ensure every request matches the current router and controller behavior.

**Acceptance criteria:**
- [ ] Postman collection imports without errors.
- [ ] Health test passes against `make run`.
- [ ] Create application → list with cursor → get → update status flow works end-to-end.
- [ ] Webhook request includes a valid signature header when
      `require_webhook_signature` is enabled.

**Files to change:**
- `docs/postman/debt-stalker.json`

---

## Issue #3 — Production/Security Hardening

**Type:** `[SEC]` + `[API]` (TDD hard gate)

**Scope:**
1. **Webhook signature fix:** Capture the raw request body in the endpoint so
   HMAC verification computes over the actual payload.
2. **Production webhook secret:** Require `WEBHOOK_SECRET` in `runtime.exs` and
   default `require_webhook_signature` to `true` in production.
3. **Env-driven LiveView salt:** Move `live_view` signing salt out of
   `config.exs` into `runtime.exs` (required in prod, dev default in test/dev).
4. **`full_name` redaction:** Apply first-name + last-initial redaction in API
   responses and UI (or document the intentional admin exception clearly).
5. **`Notifications` context:** Extract webhook event storage and outbound
   notification recording from controller/worker into a new
   `DebtStalker.Notifications` context.
6. **Stop persisting raw webhook payloads** or document a clear exception.
7. **Handle unexpected DB errors** in `ApplicationController.update_status/2`.

**Acceptance criteria:**
- [ ] Webhook signature verification succeeds in production mode.
- [ ] Missing `WEBHOOK_SECRET` raises at boot in production.
- [ ] API responses redact `full_name` consistently (or policy is documented).
- [ ] `DebtStalker.Notifications` context exists and is called by controller/worker.
- [ ] `mix test`, `mix credo --strict`, and `mix dialyzer` are green.

**Files to change:**
- `lib/debt_stalker_web/endpoint.ex`
- `lib/debt_stalker_web/controllers/api/webhook_controller.ex`
- `lib/debt_stalker_web/controllers/api/application_controller.ex`
- `config/config.exs`
- `config/runtime.exs`
- `lib/debt_stalker/notifications.ex` (new)
- `lib/debt_stalker/notifications/webhook_event.ex` (new)
- `lib/debt_stalker/notifications/notification_attempt.ex` (new, if moving schema)
- `lib/debt_stalker/workers/external_notification_worker.ex`
- Tests for all of the above.

---

## Issue #4 — UI/UX Polish

**Type:** `[WEB]` (TDD hard gate)

**Scope:**
1. **Filter debounce:** Add `phx-debounce="300"` to filter inputs in the admin
   dashboard and applications list.
2. **Loading skeletons:** Add skeleton placeholders for dashboard stats, charts,
   and recent-applications table while data loads.
3. **Interactive charts:** Replace static Contex SVG charts with a client-side
   chart library (Chart.js or ApexCharts) accessible via a small JS hook, with
   tooltips, legends, and labels.
4. **Timeline respects filters:** Make the dashboard timeline use the selected
   date range instead of always showing the last 7 days.
5. **Audit timeline icons:** Use status-specific icons for different audit actions.
6. **Human-readable provider summary:** Show a short summary card before the
   collapsible raw JSON on the detail page.
7. **Admin list cursor pagination:** Switch from OFFSET to cursor pagination so
   the admin UI matches the API scale contract.
8. **Applicant form step validation:** Enforce validation per step before
   allowing the user to proceed.
9. **Theme toggle accessibility:** Add `aria-label`s to theme buttons.

**Acceptance criteria:**
- [ ] Typing in filter inputs does not trigger a DB query on every keystroke.
- [ ] Dashboard shows skeleton states during initial load.
- [ ] Charts are interactive and have legends/tooltips.
- [ ] Admin applications list uses cursor pagination.
- [ ] LiveView tests still pass; new tests added for debounce and pagination.

**Files to change:**
- `lib/debt_stalker_web/live/admin/dashboard_live.ex`
- `lib/debt_stalker_web/live/admin/applications_live.ex`
- `lib/debt_stalker_web/live/admin/application_detail_live.ex`
- `lib/debt_stalker_web/live/apply/application_form_live.ex`
- `lib/debt_stalker_web/components/charts.ex`
- `lib/debt_stalker_web/components/ui.ex`
- `lib/debt_stalker_web/components/admin_filters.ex`
- `assets/js/app.js` (add chart hook)
- `assets/css/app.css` (skeleton animations)
- Related LiveView tests.

---

## Workflow

1. Implement Issue #1, then #2, then #3, then #4.
2. For `[SEC]` and `[WEB]` issues, follow TDD: failing test first.
3. After each issue, run:
   ```bash
   mix format --check-formatted && \
   mix compile --warnings-as-errors && \
   mix credo --strict && \
   mix dialyzer && \
   mix test
   ```
4. Update `CHANGELOG.md` under an unreleased `[Unreleased]` section.
5. Add ADRs for any new architectural decisions (e.g., chart library choice).
6. Regenerate ExDoc with `mix docs` after Issue #2.

## Dependencies

- Issue #2 depends on Issue #1 (README links to Postman).
- Issue #3 depends on Issue #2 (webhook signature example in Postman must match
  the fixed implementation).
- Issue #4 is mostly independent but should come after #1 so README screenshots
  match the polished UI.
