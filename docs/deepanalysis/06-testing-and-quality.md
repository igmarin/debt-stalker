# 06 — Testing & Quality

This document describes the test harness, code-quality tooling, CI/CD pipeline, review bots, and the gaps in the current quality posture.

---

## 1. Test Harness

### `test/test_helper.exs`

Minimal bootstrap:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(DebtStalker.Repo, :manual)
```

Manual sandbox mode means tests must explicitly check out the connection via `DataCase`/`ConnCase`.

### `DebtStalker.DataCase`

**File:** `test/support/data_case.ex`

- Sets up the Ecto SQL sandbox owner based on `async` tags.
- Resets all circuit breakers before each test.
- Provides `errors_on/1` for changeset assertions.

```elixir
setup tags do
  DebtStalker.DataCase.setup_sandbox(tags)
  DebtStalker.Providers.CircuitBreakers.reset_all()
  :ok
end
```

### `DebtStalkerWeb.ConnCase`

**File:** `test/support/conn_case.ex`

- Extends `DataCase` for HTTP/LiveView tests.
- Sets Gettext locale to `"es"`.
- Builds a test connection.
- Provides `with_role/2` for testing LiveViews with session personas (`applicant`, `admin`).

### Oban test mode

`config/test.exs` configures Oban in `:manual` testing mode:

```elixir
config :debt_stalker, Oban, testing: :manual
```

This lets tests assert that jobs are enqueued and then run them synchronously with `Oban.Testing.perform_job/2` without a running queue.

---

## 2. Test Coverage by Area

The suite contains roughly 500 tests across the following areas:

| Area | Test files | Patterns |
|------|------------|----------|
| Domain applications | `test/debt_stalker/applications/*` | Create, status update, pagination, PII redaction, query, cursor pagination, status edge cases |
| Country rules | `test/debt_stalker/countries_test.exs`, `es_test.exs`, `mx_test.exs` | Document validation, financial thresholds, property-based format + checksum tests |
| Providers | `test/debt_stalker/providers/*` | Adapter behavior, circuit breaker, registry, provider summary |
| Workers | `test/debt_stalker/workers/*` | Oban job perform, idempotency, dispatcher, notification, webhook |
| Web / API | `test/debt_stalker_web/**/*` | Controllers, LiveViews, auth plugs, rate limit, components, telemetry |
| Integration | `test/debt_stalker/integration/trigger_outbox_worker_test.exs` | End-to-end trigger → outbox → worker flow |
| Concurrency | `test/debt_stalker/concurrency_test.exs` | SKIP LOCKED parallel safety |
| PII / Security | `test/debt_stalker/applications/pii_*_test.exs`, `log_scrubbing_audit_test.exs` | Encryption at rest, redaction, log scrubbing |
| Quality checks | `test/debt_stalker/credo_checks/*` | Unit tests for custom Credo checks |

### Notable tests

- **SKIP LOCKED concurrency test** (`test/debt_stalker/concurrency_test.exs`) verifies that multiple dispatcher instances can claim disjoint event batches safely.
- **PII encryption at rest** (`test/debt_stalker/applications/pii_encryption_at_rest_test.exs`) asserts that the database stores ciphertext, not plaintext.
- **Outbox integration** (`test/debt_stalker/integration/trigger_outbox_worker_test.exs`) inserts an application, asserts an `application_events` row exists, runs the dispatcher and worker, and asserts the status changed.
- **Auth edge cases** (`test/debt_stalker_web/auth/auth_edge_cases_test.exs`) covers expired, malformed, and tampered JWTs.
- **Webhook edge cases** (`test/debt_stalker_web/controllers/api/webhook_edge_test.exs`) covers signature validation, idempotency, and invalid payloads.

---

## 3. Custom Credo Checks

The project loads three custom checks in `.credo.exs:21-24`:

### `NoCountryBranching`

**File:** `test/support/credo_checks/no_country_branching.ex`

Prevents country/provider-specific branching outside `DebtStalker.Countries` and `DebtStalker.Providers`. It detects patterns like `if country == "ES"`, `"ES" ->` case arms, and `when` clauses.

Known limitation: it does **not** flag function-head branching such as `def fetch("ES", ...)`. Provider adapters use this pattern legitimately inside `DebtStalker.Providers`, but the check would miss it elsewhere.

### `RequireSpec`

**File:** `test/support/credo_checks/require_spec.ex`

Requires `@spec` on every public function. It excludes OTP/Phoenix callbacks (`handle_call`, `mount`, `render`, `perform`, etc.), test files, and generated components.

Known limitation: it enforces `@spec` but **not** `@doc`. The project convention requires both, but only `@spec` is automated.

### `NoIOInspect`

**File:** `test/support/credo_checks/no_io_inspect.ex`

Forbids `IO.inspect` in committed code.

---

## 4. Dialyzer

`mix.exs:17-20` configures Dialyzer:

```elixir
dialyzer: [
  plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
  plt_add_apps: [:mix, :ex_unit, :credo]
]
```

The PLT is cached in CI to avoid rebuilding. `.dialyzer_ignore.exs` exists as a documented baseline but is currently empty.

CI runs `mix dialyzer --halt-exit-status` (`.github/workflows/ci.yml:83`).

---

## 5. Coverage Gate

`mix.exs:25-28` sets the threshold to **85%**:

```elixir
test_coverage: [
  summary: [threshold: 85],
  ignore_modules: coverage_ignore_modules()
]
```

Ignored modules are boilerplate: `Mailer`, `CoreComponents`, `Endpoint`, `ErrorHTML`, `Gettext`, `Layouts`, `PageHTML`.

The Makefile `ci` target runs `check test` but **not** `test --cover`; the 85% gate is enforced only in CI (`make coverage`).

---

## 6. CI/CD Pipeline

### `.github/workflows/ci.yml`

Three jobs run on every PR/push:

1. **Quality Checks** (`ubuntu-latest`, Postgres 16 service):
   - `mix format --check-formatted`
   - `mix compile --warnings-as-errors`
   - `mix credo --strict`
   - `mix dialyzer --halt-exit-status`
   - `mix test --cover`

2. **k8s Manifest Dry-Run**:
   - Validates YAML structure and required fields with PyYAML.
   - Does **not** run `kubectl apply --dry-run=client`.

3. **Secret Scan**:
   - Runs `gitleaks` with `.gitleaks.toml`.

### `.github/workflows/cd.yml`

Builds and pushes a container image to GHCR on merges to `main`. Deploy requires a manual `workflow_dispatch` approval. There is a bug in the approval condition:

```yaml
if: github.event_name == 'workflow_dispatch' && github.event.inputs.approve_deploy == 'true'
```

For a `type: boolean` input, the value is a boolean, not a string, so the comparison may never be true.

### `.github/workflows/rs-guard-review.yml`

Triggers the `rs-guard` LLM review on PRs using `.github/review-prompt.md`.

---

## 7. Review Infrastructure

### rs-guard

- Local pre-commit hook (`scripts/rs-guard-install.sh`, `scripts/rs-guard-smoke.sh`).
- CI review runner.
- Uses `.reviewer.toml` for provider/model config.
- Output must include severity tags and an `[RS_GUARD_VERDICT_METADATA]` block.

### CodeRabbit

Configured via `.coderabbit.yaml` to post inline suggestions in PRs.

### GitLeaks

Configured via `.gitleaks.toml` to allow dev/test placeholder secrets while flagging real ones.

---

## 8. Testing Gaps

| # | Issue | Severity | Evidence |
|---|-------|----------|----------|
| 1 | **Mox is declared but unused** | Medium | `AGENTS.md §8` mandates Mox for provider mocking, but no test uses `Mox.defmock`/`Mox.expect`. Provider tests rely on deterministic simulated adapters. |
| 2 | **No `@doc` enforcement** | Low | `RequireSpec` checks `@spec`, but there is no counterpart check for `@doc`. |
| 3 | **Dispatcher failure test is a placeholder** | Low | `test/debt_stalker/workers/event_dispatcher_worker_test.exs:128-163` does not actually force `Oban.insert/1` to fail; it only asserts pre-dispatch state. |
| 4 | **Provider-error transition is not validated** | Medium | No test asserts that the recorded `from_status` is valid. |
| 5 | **Many controller/LiveView tests run `async: false`** | Low | Shared Hammer/PubSub/global config state forces serialization, slowing the suite. |
| 6 | **Makefile `ci` omits `--cover`** | Low | The 85% coverage gate is only enforced in CI, not locally via `make ci`. |
| 7 | **No load/performance tests** | Low | The project documents scale plans but has no load-test harness yet. |

---

## 9. Running the Quality Suite Locally

```bash
# Full local quality suite
make check && make coverage

# Or step-by-step
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test --cover
```

The `rs-guard` pre-commit hook can be installed with:

```bash
make install-hooks  # or scripts/rs-guard-install.sh
```
