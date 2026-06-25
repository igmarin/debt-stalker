# 08 — Gaps & Recommendations

This document consolidates every significant gap, risk, or inconsistency found across the codebase and provides a prioritized backlog of recommended fixes. Gaps are grouped by area and ranked by severity.

---

## 1. How to Read This Register

| Severity | Meaning |
|----------|---------|
| 🔴 **Critical** | Blocks production, violates a hard invariant, or risks data loss/PII leakage. Must fix before real traffic. |
| 🟠 **High** | Production-impacting bug or contract violation. Should be fixed in the next sprint. |
| 🟡 **Medium** | Real issue, but mitigable or limited blast radius. Plan for near-term fix. |
| 🟢 **Low** | Code quality, maintainability, or polish item. Fix opportunistically. |

---

## 2. Security & PII

### 🔴 GAP-001 — Full name is exposed in API responses and UI

| | |
|---|---|
| **Severity** | Critical |
| **Contract** | `AGENTS.md` §3.3 and logging spec require full names to be scrubbed from logs and redacted to first + last initial in responses. |
| **Evidence** | `ApplicationController.serialize_application/1` returns `full_name: app.full_name` (`lib/debt_stalker_web/controllers/api/application_controller.ex:155`). `ApplicationConfirmationLive` (`lib/debt_stalker_web/live/apply/application_confirmation_live.ex:120`), `ApplicationsLive` (`lib/debt_stalker_web/live/admin/applications_live.ex:179`), and `ApplicationDetailLive` (`lib/debt_stalker_web/live/admin/application_detail_live.ex:118`) render `app.full_name` directly. The `CreditApplication.redact_full_name/1` helper exists but is unused. |
| **Recommended fix** | Use `CreditApplication.redact_full_name/1` in `serialize_application/1` and in all LiveView render functions. Add tests asserting redaction. |
| **Effort** | Small |

---

### 🟠 GAP-002 — Webhook idempotency hash is order-sensitive

| | |
|---|---|
| **Severity** | High |
| **Contract** | Webhook deduplication should be stable for the same logical payload. |
| **Evidence** | `WebhookController.hash_payload/1` uses `Jason.encode!(params)` (`lib/debt_stalker_web/controllers/api/webhook_controller.ex:139`). JSON key order affects the hash. |
| **Recommended fix** | Canonicalize the payload before hashing, e.g., `Jason.encode!(Map.new(params) |> Enum.sort())`, or hash only stable fields (`application_id`, `status`, `source`). Add a test with reordered keys. |
| **Effort** | Small |

---

### 🟡 GAP-003 — Rate limit trusts `X-Forwarded-For` without proxy validation

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | Rate limiting should be hard to bypass. |
| **Evidence** | `RateLimit.get_client_ip/1` takes the leftmost value of `X-Forwarded-For` without validating a trusted proxy chain (`lib/debt_stalker_web/plugs/rate_limit.ex:66-73`). |
| **Recommended fix** | Configure a list of trusted proxies and take the first untrusted IP, or perform rate limiting at the Ingress/LB layer. |
| **Effort** | Medium |

---

## 3. Domain Logic

### 🟠 GAP-004 — Provider-error transition records non-existent `from_status`

| | |
|---|---|
| **Severity** | High |
| **Contract** | All `from_status` values must be valid statuses. |
| **Evidence** | `Applications.create_application/1` records a transition `from_status: "created"` on provider failure (`lib/debt_stalker/applications.ex:111`), but `"created"` is not in `CreditApplication.valid_statuses/0` (`lib/debt_stalker/applications/credit_application.ex:17`). |
| **Recommended fix** | Use `"submitted"` or the initial status value, or skip the transition record and rely on audit log only. Add a test validating transition statuses. |
| **Effort** | Small |

---

### 🟡 GAP-005 — No top-level `DebtStalker.Providers` facade

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | `DebtStalker.Providers` should own fetch + normalize. |
| **Evidence** | `Applications` calls `Providers.Registry.lookup/1`, `Providers.CircuitBreakers.lookup/1`, and `Providers.CircuitBreaker.call/2` directly. |
| **Recommended fix** | Add `DebtStalker.Providers.fetch/2` that wraps registry + breaker + adapter. Update `Applications.fetch_provider/1` to call it. |
| **Effort** | Small |

---

### 🟢 GAP-006 — Optional callback inconsistency in `Countries.Behaviour`

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Optional callbacks should be declared in `@optional_callbacks`. |
| **Evidence** | `random_identity_document/0` is called conditionally but not declared optional (`lib/debt_stalker/countries/behaviour.ex:45`). |
| **Recommended fix** | Add `:random_identity_document` to `@optional_callbacks`. |
| **Effort** | Trivial |

---

### 🟢 GAP-007 — Duplicated transition-allowed logic

| | |
|---|---|
| **Severity** | Low |
| **Contract** | DRY. |
| **Evidence** | `allowed_transitions/1` and `transition_allowed?/2` repeat the same global/country intersection (`lib/debt_stalker/applications.ex:207-235`). |
| **Recommended fix** | Extract a private helper that returns the intersected list. |
| **Effort** | Trivial |

---

### 🟢 GAP-008 — Mexico CURP validation has no checksum

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Document validation should be as authoritative as possible. |
| **Evidence** | `DebtStalker.Countries.MX.validate_document/1` checks format only (`lib/debt_stalker/countries/mx.ex:17-31`). |
| **Recommended fix** | Document the simplification (already done in README/master-plan) or implement the CURP checksum. |
| **Effort** | Medium |

---

## 4. Async & Resilience

### 🟠 GAP-009 — Audit writes are synchronous in status-update transaction

| | |
|---|---|
| **Severity** | High |
| **Contract** | Master-plan architecture shows an `AuditWorker`; audit should not block transitions. |
| **Evidence** | `Applications.perform_status_update/3` inserts the audit log in the same `Ecto.Multi` as the status update (`lib/debt_stalker/applications.ex:251-261`). |
| **Recommended fix** | Either document the intentional synchronous design (consistency over latency) or move audit to an outbox-driven `AuditWorker`. If synchronous is intentional, update the master-plan diagram. |
| **Effort** | Medium |

---

### 🟠 GAP-010 — Webhook flow bypasses the outbox

| | |
|---|---|
| **Severity** | High |
| **Contract** | "Async work driven by data changes originates from Postgres triggers → application_events" (master-plan invariant #8). |
| **Evidence** | `WebhookController` enqueues `WebhookProcessingWorker` directly (`lib/debt_stalker_web/controllers/api/webhook_controller.ex:128-134`). |
| **Recommended fix** | Record the webhook event and let a trigger or explicit insert create an outbox event, then dispatch the worker from the dispatcher. Alternatively, document the exception. |
| **Effort** | Medium |

---

### 🟠 GAP-011 — Webhook worker marks all unprocessed events for an app as processed

| | |
|---|---|
| **Severity** | High |
| **Contract** | Each webhook event should be processed independently. |
| **Evidence** | `WebhookProcessingWorker.mark_webhook_processed/1` runs `UPDATE webhook_events SET processed = true WHERE application_id = $1 AND processed = false` (`lib/debt_stalker/workers/webhook_processing_worker.ex:61-69`). |
| **Recommended fix** | Pass the specific `webhook_event_id` in the job args and update only that row. |
| **Effort** | Small |

---

### 🟡 GAP-012 — DLQ reenqueue uses `String.to_atom/1` on stored queue name

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | Avoid atom-table exhaustion. |
| **Evidence** | `DeadLetter.insert_reenqueued_job/2` calls `String.to_atom(entry.queue || "events")` (`lib/debt_stalker/dead_letter.ex:340`). |
| **Recommended fix** | Validate queue name against the configured Oban queue list before converting, or store the queue as an atom only after validation. |
| **Effort** | Small |

---

### 🟡 GAP-013 — Risk worker silently swallows `:unsupported_country`

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | Data integrity issues should be visible. |
| **Evidence** | `RiskEvaluationWorker.evaluate_risk/1` returns `:ok` and logs a warning for `:unsupported_country` (`lib/debt_stalker/workers/risk_evaluation_worker.ex:63-70`). |
| **Recommended fix** | Keep returning `:ok` to avoid retries, but emit a metric/alert for unsupported countries in `pending_risk`. |
| **Effort** | Small |

---

### 🟢 GAP-014 — Cache invalidator logs `inspect(payload)`

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Logs should not leak PII. |
| **Evidence** | `CacheInvalidator.handle_info/2` fallback logs `inspect(payload)` (`lib/debt_stalker/cache_invalidator.ex:53-55`). Current payload is safe, but shape could change. |
| **Recommended fix** | Log only that an unexpected payload was received, without inspecting it. |
| **Effort** | Trivial |

---

### 🟢 GAP-015 — Dispatcher config read from global env every run

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Prefer compile-time or init-time config for stable values. |
| **Evidence** | `EventDispatcherWorker.dispatcher_config/0` calls `Application.get_env/2` every run (`lib/debt_stalker/workers/event_dispatcher_worker.ex:217-230`). |
| **Recommended fix** | Read config at worker init or use `Application.compile_env/3` if static. This also simplifies tests. |
| **Effort** | Small |

---

## 5. Web Layer

### 🟡 GAP-016 — Web layer reaches into internal modules

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | Web layer should call context public APIs only. |
| **Evidence** | LiveViews call `CountryRegistry.supported_countries/0` directly (`application_form_live.ex:28`, `applications_live.ex:15`, `dashboard_live.ex:11`). Controllers call `CreditApplication.redact_document/1` directly. |
| **Recommended fix** | Expose `Countries.supported_countries/0` and `Applications.redact_document/1` (or redact in serialization context) and route calls through them. |
| **Effort** | Small |

---

### 🟡 GAP-017 — Missing `@spec` on LiveView callbacks

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | Public functions have `@spec`. |
| **Evidence** | `ApplicationFormLive.handle_event("save", ...)` (`lib/debt_stalker_web/live/apply/application_form_live.ex:61`), `ApplicationsLive` handlers (`:88, :99, :106, :110, :114, :118`), `DashboardLive` handlers. |
| **Recommended fix** | Add `@spec` annotations or extend `RequireSpec` exclusions for LiveView callbacks and document the exception. |
| **Effort** | Small |

---

### 🟢 GAP-018 — LiveView form constructs `CreditApplication.changeset` directly

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Web layer should not reach into schema changesets. |
| **Evidence** | `ApplicationFormLive.handle_event("validate", ...)` builds `%CreditApplication{} |> CreditApplication.changeset(attrs)` (`lib/debt_stalker_web/live/apply/application_form_live.ex:47-50`). |
| **Recommended fix** | Provide `Applications.change_application/1` for client-side validation. |
| **Effort** | Small |

---

### 🟢 GAP-019 — `SetLocale` hardcodes Spanish

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Internationalization should respect client preference if multi-locale is a goal. |
| **Evidence** | `lib/debt_stalker_web/plugs/set_locale.ex:10` sets locale to `"es"`. |
| **Recommended fix** | Either respect `Accept-Language` or document the intentional single-locale product choice. |
| **Effort** | Small |

---

### 🟢 GAP-020 — Generic `ErrorJSON`/`ErrorHTML`

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Consistent, helpful error payloads. |
| **Evidence** | `lib/debt_stalker_web/controllers/error_json.ex` and `error_html.ex` are minimal. |
| **Recommended fix** | Enrich error shapes with codes or links to docs if API consumers need them. |
| **Effort** | Low |

---

## 6. Testing & Quality

### 🟡 GAP-021 — Mox is declared but unused

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | `AGENTS.md §8` mandates Mox for provider mocking. |
| **Evidence** | `mix.exs:116` includes `{:mox, ...}`, but no test uses `Mox.defmock`/`Mox.expect`. Provider tests use deterministic simulated adapters. |
| **Recommended fix** | Define a mock for `DebtStalker.Providers.Behaviour` and use it in provider-dependent tests, or remove Mox and update the testing strategy. |
| **Effort** | Medium |

---

### 🟢 GAP-022 — No automated `@doc` enforcement

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Every public function has `@doc` and `@spec`. |
| **Evidence** | `RequireSpec` only checks `@spec` (`test/support/credo_checks/require_spec.ex`). |
| **Recommended fix** | Add a `RequireDoc` Credo check or remove the `@doc` requirement from the contract. |
| **Effort** | Small |

---

### 🟢 GAP-023 — `NoCountryBranching` misses function-head branching

| | |
|---|---|
| **Severity** | Low |
| **Contract** | No country branching outside Countries/Providers. |
| **Evidence** | The check flags `if/case/cond/when` but not direct function-head matching like `def fetch("ES", ...)`. Provider adapters use this legitimately, but the check would miss it elsewhere. |
| **Recommended fix** | Extend the check to inspect function heads, or document the known limitation. |
| **Effort** | Medium |

---

### 🟢 GAP-024 — Dispatcher failure test is a placeholder

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Tests should verify retry/failure behavior. |
| **Evidence** | `test/debt_stalker/workers/event_dispatcher_worker_test.exs:128-163` does not force `Oban.insert/1` to fail. |
| **Recommended fix** | Inject a failing mock or temporarily override `Oban.insert/1` to assert the event remains unprocessed. |
| **Effort** | Small |

---

### 🟢 GAP-025 — Makefile `ci` omits coverage

| | |
|---|---|
| **Severity** | Low |
| **Contract** | `AGENTS.md §7` full quality suite includes `mix test --cover`. |
| **Evidence** | `Makefile` defines `ci: check test` without `--cover`. |
| **Recommended fix** | Change `ci` target to `check coverage` or add a separate `ci-with-coverage` target. |
| **Effort** | Trivial |

---

## 7. Deployment & Operations

### 🔴 GAP-026 — k8s migration Job has a fixed name

| | |
|---|---|
| **Severity** | Critical |
| **Contract** | Deploys must be repeatable. |
| **Evidence** | `k8s/migration-job.yaml:4` uses `name: debt-stalker-migrate` with no `ttlSecondsAfterFinished` or `generateName`. Re-applying a completed Job fails. |
| **Recommended fix** | Use `generateName: debt-stalker-migrate-` and `ttlSecondsAfterFinished: 86400`, or delete the Job before re-applying in CD. |
| **Effort** | Small |

---

### 🔴 GAP-027 — CD approval condition never matches

| | |
|---|---|
| **Severity** | Critical |
| **Contract** | Manual deploy gate must work. |
| **Evidence** | `.github/workflows/cd.yml:69` checks `github.event.inputs.approve_deploy == 'true'`, but the input is `type: boolean`. |
| **Recommended fix** | Use `github.event.inputs.approve_deploy == true` (boolean comparison). |
| **Effort** | Trivial |

---

### 🔴 GAP-028 — k8s Secret manifest is incomplete

| | |
|---|---|
| **Severity** | Critical |
| **Contract** | Production pods must have all required secrets. |
| **Evidence** | `k8s/secret.yaml` provides `DATABASE_URL`, `SECRET_KEY_BASE`, `CLOAK_KEY`, `JWT_SECRET`, `WEBHOOK_SECRET`, but `runtime.exs` also requires `SESSION_SIGNING_SALT`, `ADMIN_PASSWORD`, `LIVE_VIEW_SIGNING_SALT`. |
| **Recommended fix** | Add the missing keys. Prefer Sealed Secrets or External Secrets Operator for real clusters. |
| **Effort** | Small |

---

### 🟠 GAP-029 — Deployments use mutable `:latest` image tag

| | |
|---|---|
| **Severity** | High |
| **Contract** | Immutable deployments. |
| **Evidence** | `k8s/deployment-web.yaml:23` and `k8s/deployment-worker.yaml:23` use `ghcr.io/igmarin/debt-stalker:latest`. With `IfNotPresent`, rolling updates may not pull the new image. |
| **Recommended fix** | Patch manifests in CD to use the SHA digest output by the build step, or use a semver tag. |
| **Effort** | Medium |

---

### 🟠 GAP-030 — Placeholder secrets committed

| | |
|---|---|
| **Severity** | High |
| **Contract** | No secrets committed to the repository. |
| **Evidence** | `k8s/secret.yaml:9-13` contains placeholder secret values. |
| **Recommended fix** | Replace with empty values and require Sealed Secrets / External Secrets Operator, or move to a separate secrets repo. |
| **Effort** | Small |

---

### 🟡 GAP-031 — No Ingress / TLS manifest

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | Production needs external access and TLS. |
| **Evidence** | Only a `ClusterIP` service is provided (`k8s/service.yaml:10`). |
| **Recommended fix** | Add an Ingress manifest with TLS (e.g., cert-manager). |
| **Effort** | Medium |

---

### 🟡 GAP-032 — k8s dry-run is structural, not schema-validated

| | |
|---|---|
| **Severity** | Medium |
| **Contract** | CI should catch k8s schema errors. |
| **Evidence** | `.github/workflows/ci.yml:104-141` uses PyYAML to check required fields, not `kubectl apply --dry-run=client`. |
| **Recommended fix** | Add a step that runs `kubectl apply --dry-run=client -f k8s/` against a kind cluster or use `kubeconform`. |
| **Effort** | Medium |

---

### 🟢 GAP-033 — Dockerfile runtime package mismatch

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Container should build and run. |
| **Evidence** | `Dockerfile:47` installs `libncurses5`; Debian Bookworm typically provides `libncurses6`. |
| **Recommended fix** | Install `libncurses6` or both packages. |
| **Effort** | Trivial |

---

### 🟢 GAP-034 — Worker liveness probe uses temporary node

| | |
|---|---|
| **Severity** | Low |
| **Contract** | Conventional, reliable probe. |
| **Evidence** | `k8s/deployment-worker.yaml:42-43` uses `bin/debt_stalker rpc DebtStalker.Release.version()`. |
| **Recommended fix** | Use a dedicated health check module or a simpler exec check that does not start a temporary node. |
| **Effort** | Small |

---

## 8. Prioritized Backlog

### Quick wins (do this week)

1. **GAP-027** — Fix CD boolean approval condition.
2. **GAP-006** — Add `random_identity_document` to `@optional_callbacks`.
3. **GAP-025** — Add `--cover` to `make ci`.
4. **GAP-007** — Extract shared transition-intersection helper.
5. **GAP-014** — Remove `inspect(payload)` from cache invalidator fallback log.

### High-value fixes (next sprint)

1. **GAP-001** — Redact full names in API and LiveViews.
2. **GAP-004** — Fix provider-error `from_status`.
3. **GAP-002** — Canonicalize webhook idempotency hash.
4. **GAP-026** — Make migration Job re-runnable.
5. **GAP-028** — Add missing k8s secrets.
6. **GAP-029** — Pin deployment image tags to SHA digest.
7. **GAP-011** — Process webhook events individually.

### Medium-term improvements (next phase)

1. **GAP-009** — Decide on async audit worker vs. documented synchronous design.
2. **GAP-010** — Route webhooks through the outbox.
3. **GAP-005** — Add `DebtStalker.Providers.fetch/2` facade.
4. **GAP-003** — Validate proxy headers for rate limiting.
5. **GAP-021** — Adopt Mox for provider mocking or remove it.
6. **GAP-031** — Add Ingress + TLS manifest.
7. **GAP-032** — Use `kubectl --dry-run=client` in CI.

### Architectural polish

1. **GAP-012** — Remove `String.to_atom/1` from DLQ reenqueue.
2. **GAP-013** — Alert on unsupported-country risk evaluations.
3. **GAP-015** — Read dispatcher config at init time.
4. **GAP-016** — Route all web calls through context public APIs.
5. **GAP-017** — Add `@spec` to LiveView callbacks or document exemption.
6. **GAP-023** — Extend `NoCountryBranching` to function heads.
7. **GAP-024** — Strengthen dispatcher failure test.

---

## 9. What Not to Fix

Some observations are intentional design choices, not gaps:

- **Simulated provider adapters** are deliberate for reproducibility and zero external secrets (master-plan Decision D11).
- **Synchronous audit writes** may be intentional for consistency; only fix if latency or coupling becomes a problem.
- **CURP checksum absence** is a documented simplification for the MVP.
- **Admin page pagination uses OFFSET** is a documented trade-off for sortable operational tables; replace only at high volume.
- **Spanish-only locale** may be a deliberate product choice.
