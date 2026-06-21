# Closed Issues Code Review — 2026-06-21

> **Scope:** All 53 closed GitHub issues (Phase 0–2)  
> **Reviewer:** AI-assisted audit + open PRs for critical fixes  
> **Baseline coverage:** 77.00% on `main` (before PR #93)

---

## Executive summary

The codebase is in strong shape for Phase 1 and partial Phase 2. Phase 1 review gaps (GAP-1, GAP-3–5) are resolved in `main`. Remaining critical gaps were addressed in **open PRs** (not merged — awaiting your review + rs-guard):

| PR | Issue | Fix |
|----|-------|-----|
| [#89](https://github.com/igmarin/debt-stalker/pull/89) | GAP-2 E2E | MX `existing_debt` simulation + deterministic worker test |
| [#90](https://github.com/igmarin/debt-stalker/pull/90) | #53 | Oban exhaustion → `DeadLetter.capture/1` |
| [#91](https://github.com/igmarin/debt-stalker/pull/91) | #52 | Circuit breaker wired into `fetch_provider/1` |
| [#93](https://github.com/igmarin/debt-stalker/pull/93) | Coverage | 85% gate (Option A), baseline now **87.34%** |
| [#94](https://github.com/igmarin/debt-stalker/pull/94) | Docs | README, CHANGELOG, Postman, this report |

---

## 1. Code quality

**Strengths**

- Clean `Ecto.Multi` for status transitions + audit (`applications.ex`)
- Country/provider registry + behaviour patterns
- ~275 tests, property-style DNI/CURP, PII redaction, concurrency (SKIP LOCKED)
- CI: format, credo strict, dialyzer, tests

**Findings (deferred / open PRs)**

| Severity | Finding | Status |
|----------|---------|--------|
| Critical | MX debt rule not E2E-testable (adapter capped debt ~98) | PR #89 |
| Critical | DLQ not hooked to Oban exhaustion | PR #90 |
| Critical | Circuit breaker orphaned from fetch path | PR #91 |
| Important | Risk score thresholds in `Risk`, not `Countries` | Deferred |
| Important | `WebhookProcessingWorker` permanent errors return `:ok` | Branch `77-fix-webhook-processing-worker-permanent-errors` exists |
| Suggestion | `emit_status_transition/5` `@spec` mismatch | Deferred |

---

## 2. Context boundaries (AGENTS.md §3.1)

| Context | Verdict |
|---------|---------|
| `Countries` | Strong |
| `Providers` | Good (registry on `main`; breaker wiring in #91) |
| `Applications` | Good (inline audit per ADR-0004) |
| `Risk` | Partial (thresholds not in country modules) |
| `Workers` | Good (delegate to contexts) |
| `DeadLetter` | Good module; wiring in #90 |
| `Audit` / `Notifications` | Not extracted (acceptable for current phase) |

---

## 3. Tests

| Area | Coverage |
|------|----------|
| Unit | Strong for domain, API edge cases, workers |
| Integration | Trigger/outbox, concurrency, webhook HMAC |
| Gaps closed by PRs | MX E2E (#89), DLQ exhaustion (#90), circuit breaker (#91), AuthController + telemetry (#93) |

---

## 4. Documentation

| Artifact | Before | This PR |
|----------|--------|---------|
| README | Missing health, observability | Updated |
| CHANGELOG | Wrong webhook path | Fixed + Phase 2 partial |
| Postman | No health endpoint | Health folder added |
| `phase-2.md` | Says "no code written" | Still stale — update when Phase 2 PRs merge |
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
- **Ignored:** CoreComponents, Layouts, PageHTML, ErrorHTML, Mailer, Gettext, Endpoint
- **PR:** #93

---

## 7. Closed issue checklist (summary)

| Phase | Issues | Verdict |
|-------|--------|---------|
| Phase 0 (#1–#18) | Scaffold, CI, rs-guard, docs | Complete |
| Phase 1 (#19–#47) | ES+MX slice | Complete (GAP-2 E2E in #89) |
| Phase 2 (#48–#53) | Telemetry, metrics, breaker, DLQ | Partial on `main`; #90–#91 complete wiring |
| #63 | PII backfill | Correctly closed wontfix |

---

## Recommended merge order

1. #93 (coverage gate — independent)
2. #89 (MX debt)
3. #90 (DLQ)
4. #91 (circuit breaker — may conflict with #90; rebase if needed)
5. #94 (docs)

Run `make coverage` and rs-guard on each PR before merge. **Do not merge without your review.**