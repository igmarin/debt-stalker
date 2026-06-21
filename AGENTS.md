# AGENTS.md — Debt Stalker Development Guidelines

> Canonical source of conventions for developers and AI agents working on this project.
> For architecture, roadmap, and decisions, see `docs/master-plan.md`.
> For phase-specific details, see `docs/phases/phase-N.md`.

---

## 1. Project Overview

**Debt Stalker** is a multi-country credit-application core for a fintech operating in 6 countries (ES, PT, IT, MX, CO, BR). Built with Elixir + Phoenix + PostgreSQL + Oban + LiveView.

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.18.x / Erlang/OTP 27.x |
| Web | Phoenix 1.8, LiveView, Bandit |
| Database | PostgreSQL 16, Ecto |
| Background Jobs | Oban (Postgres-backed) |
| Auth | JWT (Joken) |
| PII Protection | Cloak Ecto (encryption at rest) |
| Logging | logger_json (structured JSON) |
| Code Quality | Credo (strict), Dialyxir, ExDoc |
| Testing | ExUnit, Mox, StreamData |
| CI/CD | GitHub Actions |
| Code Review | rs-guard (DeepSeek Pro), CodeRabbit |

---

## 2. TDD Policy (Hard Gate)

**Test-first is mandatory** for these task types:
- `[DOMAIN]` — Domain logic, business rules, validation
- `[ASYNC]` — Workers, background jobs, event processing
- `[API]` — API endpoints, controllers, serialization
- `[WEB]` — LiveView, components, frontend interaction

**TDD-exempt** (tests still required where applicable, but no test-first gate):
- `[CHORE]` — Dependency updates, reformatting
- `[INFRA]` — CI/CD, Docker, tooling configuration
- `[DB]` — Migrations (Ecto handles reversibility)
- `[OPS]` — Deployment, k8s manifests
- `[DOCS]` — Documentation-only changes

### TDD Workflow

```
1. Write failing test for the acceptance criteria
2. Run test → verify it FAILS for the right reason
3. Implement minimal code to pass
4. Run test → verify PASSES
5. Run full quality suite (see §7)
6. rs-guard review (pre-commit hook)
7. Iterate (max 3 rounds)
8. Commit when rs-guard returns APPROVE or COMMENT
```

---

## 3. Code Organization Contract

### 3.1 Context Boundaries

| Module | Owns | Must NOT |
|--------|------|----------|
| `DebtStalker.Countries` | Document/financial validation, rule interpretation, allowed transitions | Access DB, web |
| `DebtStalker.Providers` | Fetch + normalize provider data | Make decisions, persist raw payloads |
| `DebtStalker.Applications` | Lifecycle: create, get, list, update_status | Contain country rules |
| `DebtStalker.Risk` | Async risk evaluation logic | Access web/transport |
| `DebtStalker.Audit` | Append-only audit records | Make business decisions |
| `DebtStalker.Notifications` | Outbound notifications + inbound webhooks | Contain country rules |
| `DebtStalker.Workers` | Oban workers (delegate to contexts) | Contain business rules |
| `DebtStalkerWeb` | Transport, auth, serialization, LiveView | Contain domain logic |

### 3.2 Rules

1. **No country/provider branching** (`if country == "ES"`) outside `DebtStalker.Countries` and `DebtStalker.Providers`.
2. **Workers delegate** — they call context functions, never implement business logic.
3. **Web layer calls contexts only** — never reaches into internal modules.
4. **Raw provider payloads are never persisted or exposed** — only normalized `provider_summary`.

### 3.3 Code Style

- Every public module has `@moduledoc`.
- Every public function has `@doc` and `@spec`.
- All `@type`/`@opaque` declarations have `@typedoc`.
- Prefer pattern matching over `if/cond` for control flow.
- Use `with` for multi-step happy paths.
- Keep function arity low; use keyword lists for optional params.
- Use `Decimal` for financial calculations, never floats.
- `application_date` is always server-set.
- Full `identity_document` is never logged; responses redact to last-4.

---

## 4. Review Loop

Every task goes through the rs-guard review loop:

```
implement → rs-guard (pre-commit) → evaluate findings → iterate
```

- **Max 3 iterations** per task.
- `[Critical]` / `[Security]` findings → must fix before commit.
- `[Important]` findings → fix if ≤ 2, document if deferred.
- `[Suggestion]` findings → optional (fix or acknowledge).
- **Bypass** (emergency only): `git commit --no-verify`

### CI Review

PRs are automatically reviewed by:
1. **rs-guard** (`.github/workflows/rs-guard-review.yml`) — posts structured review.
2. **CodeRabbit** (`.coderabbit.yaml`) — posts inline suggestions.

### PR Strategy

**One PR per issue, NOT one PR per phase.**

- Each issue gets its own branch from `main` and its own PR.
- Tag every PR with the appropriate `phase-N` label so it can be traced back to the roadmap.
- Keep PRs small and focused — a 7,000-line PR is unreviewable and defeats the purpose of code review.
- If an issue depends on another issue's code, wait for the dependency PR to merge first.
- Phase-level reports and ADRs are written after all issues in the phase are merged.

---

## 5. Error Handling Strategy

| Layer | Success | Error |
|-------|---------|-------|
| Domain contexts | `{:ok, struct}` | `{:error, %Ecto.Changeset{}}` or `{:error, atom}` |
| Oban workers | `:ok` | `{:cancel, reason}` (permanent) or `{:error, reason}` (transient/retry) |
| API controllers | `200` with data | `422` validation, `401`/`403` auth, `404` not found |
| Webhook controller | `200` with `{"received": true}` | `401`/`404`/`422` |
| LiveView | `{:ok, socket}` | `{:error, changeset}` or redirect with flash |

**Domain error atoms:** `:not_found`, `:invalid_transition`, `:provider_timeout`, `:provider_unavailable`, `:invalid_document`, `:unsupported_country`, `:already_processed`.

---

## 6. Logging Specification

| Aspect | Decision |
|--------|----------|
| Backend | `logger_json` (all environments) |
| Format | JSON: timestamp, level, message, metadata |
| Required metadata | `application_id`, `event_id`, `country`, `status`, `worker` |
| Log levels | dev: `debug`, test: `warning`, prod: `info` |
| PII redaction | `identity_document` → last-4, `full_name` → first + last initial |
| No raw provider payloads in logs | Only normalized fields |

---

## 7. Makefile Commands

| Command | Purpose |
|---------|---------|
| `make setup` | Install deps, create DB, run migrations |
| `make db` | Create + migrate database |
| `make migrate` | Run migrations |
| `make seed` | Run seeds |
| `make run` | Start Phoenix server |
| `make test` | Run full test suite |
| `make format` | Format code |
| `make lint` | Run `mix credo --strict` |
| `make dialyzer` | Run dialyzer |
| `make docs` | Generate ExDoc |

### Full Quality Suite (run before every commit)

```bash
mix format --check-formatted && \
mix compile --warnings-as-errors && \
mix credo --strict && \
mix dialyzer && \
mix test
```

---

## 8. Testing Strategy

| Concern | Tool | Pattern |
|---------|------|---------|
| Provider mocking | Mox | `Mox.expect/3` + `Mox.verify_on_exit!` |
| Worker testing | Oban.Testing | `assert_enqueued/1`, `perform_job/2` |
| PubSub | Phoenix.PubSub | `subscribe/2` + `assert_received` |
| LiveView | `live_isolated` / `live/2` | Full lifecycle assertions |
| Time | Injected `now` argument | No `Time.now` stubbing |
| Document validation | StreamData | Property tests for format + checksum |
| Database | Ecto sandbox | Async mode, `DataCase` / `ConnCase` |
| Integration | Trigger→outbox→worker | INSERT → assert event → perform_job → assert status |

---

## 9. References

- **Master Plan:** `docs/master-plan.md`
- **Phase Docs:** `docs/phases/phase-N.md`
- **ADRs:** `docs/adr/`
- **Changelog:** `CHANGELOG.md`
- **Postman Collection:** `docs/postman/debt-stalker.json`
- **Handoff Prompts:** `docs/handoff/`
