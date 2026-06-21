# Closed Issues Code Review — 2026-06-21

> **Scope:** All 53 closed GitHub issues (Phase 0–2)  
> **Reviewer:** AI-assisted audit + PR follow-up  
> **Coverage gate:** Active on `main` via PR #93; latest local verification is above the 85% threshold.

---

## Executive summary

The codebase is in strong shape for Phase 1 and partial Phase 2. Phase 1 review gaps (GAP-1, GAP-3–5) are resolved in `main`. The highest-priority follow-up PRs are now merged except for this documentation sync PR:

| PR | Issue | Status | Fix |
|----|-------|--------|-----|
| [#89](https://github.com/igmarin/debt-stalker/pull/89) | GAP-2 E2E | Merged | MX `existing_debt` simulation + deterministic worker test |
| [#90](https://github.com/igmarin/debt-stalker/pull/90) | #53 | Merged | Oban exhaustion → `DeadLetter.capture/1` |
| [#91](https://github.com/igmarin/debt-stalker/pull/91) | #52 | Merged | Circuit breaker wired into `fetch_provider/1` |
| [#93](https://github.com/igmarin/debt-stalker/pull/93) | Coverage | Merged | 85% coverage gate (Option A) |
| [#95](https://github.com/igmarin/debt-stalker/pull/95) | #78 | Merged | Custom Credo checks for architecture contracts |
| [#94](https://github.com/igmarin/debt-stalker/pull/94) | Docs | This PR | README, CHANGELOG, Postman, this report |

---

## 1. Code quality

**Strengths**

- Clean `Ecto.Multi` for status transitions + audit (`applications.ex`)
- Country/provider registry + behaviour patterns
- 294+ tests on the current merged baseline, including property-style DNI/CURP, PII redaction, concurrency (SKIP LOCKED), AuthController, telemetry, MX debt, and circuit-breaker wiring coverage
- CI: format, compile warnings-as-errors, credo strict, dialyzer, coverage-gated tests

**Findings (deferred / open PRs)**

| Severity | Finding | Status |
|----------|---------|--------|
| Critical | MX debt rule not E2E-testable (adapter capped debt ~98) | Resolved in #89 |
| Critical | DLQ not hooked to Oban exhaustion | Resolved in #90 |
| Critical | Circuit breaker orphaned from fetch path | Resolved in #91 |
| Important | Risk score thresholds in `Risk`, not `Countries` | Resolved in #95 |
| Important | `WebhookProcessingWorker` permanent errors return `:ok` | Branch `77-fix-webhook-processing-worker-permanent-errors` exists |
| Suggestion | `emit_status_transition/5` `@spec` mismatch | Deferred |

---

## 2. Context boundaries (AGENTS.md §3.1)

| Context | Verdict |
|---------|---------|
| `Countries` | Strong |
| `Providers` | Strong after #91 wiring |
| `Applications` | Good (inline audit per ADR-0004) |
| `Risk` | Improved by #95 threshold delegation |
| `Workers` | Good (delegate to contexts) |
| `DeadLetter` | Complete after #90 Oban wiring |
| `Audit` / `Notifications` | Not extracted (acceptable for current phase) |

---

## 3. Tests

| Area | Coverage |
|------|----------|
| Unit | Strong for domain, API edge cases, workers |
| Integration | Trigger/outbox, concurrency, webhook HMAC |
| Gaps closed by PRs | MX E2E (#89), DLQ exhaustion (#90), circuit breaker (#91), AuthController + telemetry (#93), custom Credo checks (#95) |

---

## 4. Documentation

| Artifact | Before | This PR |
|----------|--------|---------|
| README | Missing health, observability, coverage command | Updated |
| CHANGELOG | Wrong webhook path, missing Phase 2 partials | Fixed + Phase 2 partial |
| Postman | No health endpoint | Health folder added |
| `phase-2.md` | Says "no code written" | Still stale — update after remaining Phase 2 planning is finalized |
| `phase-1-code-review.md` | Stale GAP-4/5 | Superseded by this report |

---

## 5. Postman vs router

| Route | Router | Postman (after #94) |
|-------|--------|---------------------|
| `GET /api/health` | Yes | Yes |
| `POST /api/auth/token` | Yes | Yes |
| `/api/applications` CRUD | Yes | Yes |
| `PATCH .../status` | Yes | Yes |
| `POST .../provider-confirmations` | Yes | Yes |

---

## 6. Coverage (Option A — approved)

- **Tool:** built-in `test_coverage` in `mix.exs` (no excoveralls)
- **Threshold:** 85%
- **Command:** `make coverage` (wraps `mix test --cover`)
- **CI:** Quality Checks run the coverage-gated test command
- **Ignored:** CoreComponents, Layouts, PageHTML, ErrorHTML, Mailer, Gettext, Endpoint
- **Status:** active on `main` after #93; latest local verification remains above threshold

---

## 7. Closed issue checklist (summary)

| Phase | Issues | Verdict |
|-------|--------|---------|
| Phase 0 (#1–#18) | Scaffold, CI, rs-guard, docs | Complete |
| Phase 1 (#19–#47) | ES+MX slice | Complete after #89 |
| Phase 2 (#48–#53) | Telemetry, metrics, breaker, DLQ | Partial on `main`; DLQ and breaker wiring are complete after #90/#91 |
| Phase 1 refinement (#78, #80) | Credo checks + country docs | Complete after #95 and #96 |
| #63 | PII backfill | Correctly closed wontfix |

---

## Recommended merge order

1. #94 (final docs sync) after fresh CI remains green.

Run `make coverage` and rs-guard before merge. **Do not merge without your review.**
