# Phase 1 Code Review & Analysis

> **Reviewers:** Senior Tech Lead / Product Manager + Senior Elixir Engineer
> **Scope:** Full Phase 1 (ES + MX vertical slice) — PR #69
> **Date:** 2026-06-20
>
> **Note:** This is the **initial** (Round 1) review, capturing the state at 133 tests.
> All findings (GAP-1 through GAP-5, ISSUE-1 through ISSUE-7) were resolved in
> Round 1 and Round 2. See `docs/phases/phase-1-report.md` §"Post-Implementation
> Review Notes" and §"Round 2 Review" for resolution details. Final state: 220
> tests, 0 credo warnings, 0 dialyzer errors.

---

## Part A: Tech Lead & Product Manager Review

### 1. Test Report vs Phase 1 Definition of Done

| DoD Item | Status | Notes |
|----------|--------|-------|
| ES + MX apps CRUD via API + LiveView | PASS | All endpoints and LiveViews operational |
| Document validation + financial rules | PASS | DNI checksum, CURP format, threshold flags work |
| Provider simulated + normalized | PASS | No raw payloads exposed |
| Postgres triggers → outbox → workers | PASS | Integration test + concurrency test confirm |
| Status transitions validated + audited + broadcast | PASS | Multi transaction + PubSub verified |
| Webhook signature + idempotency | PARTIAL | Signature bypass in dev/test; no E2E signature test |
| Notification on approved/rejected | PASS | Simulated result stored |
| LiveView realtime updates | PASS | PubSub subscribe in mount, handle_info refreshes |
| JWT auth + roles | PASS | 401/403 enforced correctly |
| Cloak encryption at rest | PASS | Raw SQL confirms ciphertext ≠ plaintext |
| PII redaction | PASS | `****XXXX` format in API + LiveView |
| Cursor pagination | PASS | (date, id) tuple cursor, no OFFSET |
| `make test` + credo + dialyzer green | PASS | CI green, 133 tests |
| k8s manifests + dry-run | PASS | Manifests present |
| Seeds + demo tokens | PASS | 10 apps seeded, tokens printed |
| README + CHANGELOG + ADRs + Report | PASS | All documentation present |
| Postman collection | PASS | All endpoints documented |
| **Global Architecture invariants hold** | **PARTIAL** | See findings below |

### 2. Spec Compliance Gaps (Priority Order)

#### GAP-1: Country-Specific Transitions Not Consulted (Invariant Violation)

**Master Plan §4.1 Invariant #4** + **Phase 1 §3.3**: "Country modules return their allowed transitions from `allowed_status_transitions/0`. The `update_status/3` function validates against the country module's set."

**Actual:** `Applications.update_status/3` only validates against `@global_transitions` (a hardcoded module attribute). The country module's `allowed_status_transitions/0` is never called.

**Impact:** Today both ES and MX return the same transitions as the global set, so behavior is correct. But the contract is violated — when Phase 3 adds countries that *narrow* transitions, this code path will silently ignore their restrictions.

**Recommendation:** Consult `country_module.allowed_status_transitions()` and intersect with global set.

---

#### GAP-2: MX Debt Rule (AC2.6) Not Evaluated in Risk Worker

**Phase 1 AC2.6:** `provider_debt + requested_amount > 18× monthly_income → additional_review_required`

**Actual:** `RiskEvaluationWorker.evaluate_risk/1` calls:
```elixir
financials_params = %{
  requested_amount: app.requested_amount,
  monthly_income: app.monthly_income
}
# Missing: provider_debt from provider_summary
```

The MX module's `validate_financials/1` does check `provider_debt`, but the worker never passes it. The field defaults to `Decimal.new("0")`, so **the 18× debt rule is never triggered at risk evaluation time**.

**Impact:** MX applications that should be flagged for `additional_review` due to high existing debt will instead be `approved`. This is a functional correctness bug.

**Recommendation:** Extract `existing_debt` from `app.provider_summary["risk_indicators"]["existing_debt"]` and pass as `:provider_debt`.

---

#### GAP-3: No AuditWorker Dispatch

**Master Plan §4.4** lists 5 specialized workers: Dispatcher, Risk, Audit, Notification, Webhook.

**Actual:** `EventDispatcherWorker.dispatch_event/1` only dispatches:
- `application.created` → `RiskEvaluationWorker`
- `application.status_changed` (to terminal) → `ExternalNotificationWorker`

No `AuditWorker` is ever enqueued. Audit logs *are* created inside `update_status/3` via `Ecto.Multi`, so the functional requirement is met. But the architecture diverges from the documented design.

**Impact:** Low — audit records are written synchronously. But if audit enrichment needs to become async (e.g., Phase 2 adds external audit trail), the dispatch path doesn't exist.

**Recommendation:** Either add the AuditWorker dispatch or document this as an explicit simplification in an ADR.

---

#### GAP-4: API Webhook Endpoint Path Mismatch

**Master Plan §4.6:** `POST /api/webhooks/provider-confirmations`
**Router:** `post "/webhooks/provider", WebhookController, :receive_webhook`

**Impact:** Low (internal naming), but Postman collection and any external integrator documentation should match.

---

#### GAP-5: Missing `/api/health` Endpoint

**Master Plan §4.6** specifies `GET /api/health` as a public endpoint. Not implemented in the router.

**Impact:** Low for MVP, but k8s manifests likely reference it for readiness/liveness probes.

---

### 3. Phase 2 Readiness Assessment

Based on `docs/phases/phase-2.md` scope, the following are ready vs need prep:

| Phase 2 Concern | Readiness | Action Needed |
|-----------------|-----------|---------------|
| Telemetry hooks | Low | No `:telemetry.execute` calls in hot paths |
| Circuit breakers | Ready | Provider behaviour supports error returns cleanly |
| DLQ for exhausted jobs | Ready | Oban `max_attempts: 3` + `:cancel` pattern in place |
| Rate limiting | Not started | Needs plug-level implementation |
| App-level cache | Ready | PubSub invalidation pattern already proven |
| Real k8s deploy | Manifests exist | Need real ingress + HPA + probes |

---

## Part B: Senior Elixir Engineer Code Review

### 4. Architecture (Positive Findings)

1. **Clean context boundaries** — Web layer never contains domain logic; workers delegate to contexts.
2. **Behaviour + Registry pattern** — Extensibility proven; adding a country is truly additive.
3. **Ecto.Multi for transactional writes** — Status update atomically writes application + transition + audit.
4. **Struct-based domain model** — `ProviderSummary`, `CreditApplication` with proper typespecs.
5. **Property-based testing** — StreamData for DNI/CURP validation is excellent.
6. **Integration test for trigger→outbox→worker** — De-risked the most novel requirement early (per plan).
7. **SKIP LOCKED concurrency test** — Proves parallel safety with `Task.async`.

### 5. Code Quality Issues

#### ISSUE-1: `Decimal.new/1` Crash in API Controller (Severity: Medium)

```elixir
# lib/debt_stalker_web/controllers/api/application_controller.ex:119
defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
```

`Decimal.new("abc")` raises `Decimal.Error`. The LiveView correctly uses `Decimal.parse/1`. The API controller should too:

```elixir
defp to_decimal(value) when is_binary(value) do
  case Decimal.parse(value) do
    {decimal, ""} -> decimal
    {decimal, _remainder} -> decimal
    :error -> nil  # Let changeset validation catch it
  end
end
```

---

#### ISSUE-2: `import Ecto.Query` Repeated in Private Functions (Severity: Low)

`maybe_filter_country/2`, `maybe_filter_status/2`, `maybe_filter_date_range/2`, and `maybe_apply_cursor/2` each import `Ecto.Query` in their body. Idiomatic Elixir imports at module level:

```elixir
defmodule DebtStalker.Applications do
  import Ecto.Query
  # ...
end
```

---

#### ISSUE-3: Provider Adapter Map Hardcoded (Severity: Medium)

```elixir
@provider_adapters %{
  "ES" => DebtStalker.Providers.ESAdapter,
  "MX" => DebtStalker.Providers.MXAdapter
}
```

This bypasses the Registry pattern. If Phase 3 adds PT, a developer must remember to update *both* the country registry *and* this map. Consider a `DebtStalker.Providers.Registry` or storing the adapter reference in the country config.

---

#### ISSUE-4: `fetch_provider/1` Raises on Unknown Country (Severity: Medium)

```elixir
defp fetch_provider(%{country: country, identity_document: document}) do
  adapter = Map.fetch!(@provider_adapters, country)
```

If `resolve_country/1` succeeds but `@provider_adapters` doesn't have the key (e.g., future misconfiguration), this will raise `KeyError` instead of returning a clean `{:error, _}`.

---

#### ISSUE-5: PubSub Broadcast Only From LiveView Create (Severity: Medium)

`ApplicationCreateLive` manually broadcasts `:application_created` to `"applications:list"`. But applications created via API do *not* trigger this broadcast. The list page's PubSub subscription only catches events broadcast to `"applications:list"`.

The Postgres trigger does fire and creates an outbox event, but the EventDispatcher only enqueues `RiskEvaluationWorker` — it doesn't broadcast to the list topic. So **API-created applications don't appear in the LiveView list in real-time**.

**Fix:** Broadcast from the domain layer (`Applications.create_application/1` success path) or have the EventDispatcher emit a list-refresh broadcast.

---

#### ISSUE-6: `WebhookProcessingWorker` Silently Swallows Errors (Severity: Low)

```elixir
def perform(%Oban.Job{...}) do
  case Applications.update_status(app_id, status, triggered_by) do
    {:ok, _app} -> :ok
    {:error, :not_found} -> :ok
    {:error, :invalid_transition} -> :ok
  end
end
```

All error paths return `:ok`, meaning Oban considers them successful. An invalid transition or missing app is a legitimate concern that should at minimum be logged. Consider `:cancel` for `:not_found` and logging for `:invalid_transition`.

---

#### ISSUE-7: `to_decimal/1` Float Precision (Severity: Low)

```elixir
defp to_decimal(value) when is_number(value), do: Decimal.from_float(value * 1.0)
```

Multiplying by `1.0` is a no-op for floats and unnecessary for integers. For integers, `Decimal.new(value)` is more appropriate (no float precision loss). `Decimal.from_float/1` introduces IEEE 754 representation artifacts.

---

### 6. Proposed Test Additions (Edge Cases)

#### 6.1 Critical (Address GAP-2)

```elixir
# test/debt_stalker/workers/risk_evaluation_worker_test.exs
test "MX app with high provider_debt moves to additional_review" do
  # Create MX app where debt+amount > 18× income
  attrs = %{
    country: "MX",
    full_name: "High Debt User",
    identity_document: "GARC850101HDFRRL09",
    requested_amount: Decimal.new("15000"),
    monthly_income: Decimal.new("2000")
    # provider_summary will show existing_debt of ~X from the simulated adapter
  }
  {:ok, app} = Applications.create_application(attrs)
  # This test will FAIL currently because provider_debt is not passed
  perform_job(RiskEvaluationWorker, %{application_id: app.id})
  {:ok, updated} = Applications.get_application(app.id)
  # Should be additional_review if debt+amount > 36000
  # Assert based on simulated adapter's debt value
end
```

#### 6.2 Status Transition Edge Cases

```elixir
# Terminal states cannot transition
test "cannot transition from approved" do
  # ... create + move to approved
  assert {:error, :invalid_transition} =
    Applications.update_status(app.id, "pending_risk", "system")
end

test "cannot transition from rejected" do
  # ...
end

test "cannot transition from cancelled" do
  # ...
end

# Cancellation paths
test "can cancel from submitted" do
  # ...
  assert {:ok, updated} = Applications.update_status(app.id, "cancelled", "user")
  assert updated.status == "cancelled"
end
```

#### 6.3 API Controller Robustness

```elixir
test "handles non-numeric requested_amount gracefully", %{conn: conn} do
  conn
  |> auth_conn("update")
  |> post("/api/applications", %{@valid_es_params | "requested_amount" => "abc"})
  |> json_response(422)
end

test "handles very large amounts", %{conn: conn} do
  conn
  |> auth_conn("update")
  |> post("/api/applications", %{@valid_es_params | "requested_amount" => "99999999999999"})
  |> json_response(201)  # Should succeed (no upper limit in spec)
end
```

#### 6.4 Auth Edge Cases

```elixir
test "expired token returns 401", %{conn: conn} do
  # Generate token with past expiry
  claims = %{"role" => "read", "exp" => DateTime.to_unix(DateTime.utc_now()) - 3600}
  {:ok, token, _} = Joken.generate_and_sign(claims, Token.signer())
  conn
  |> put_req_header("authorization", "Bearer #{token}")
  |> get("/api/applications")
  |> json_response(401)
end

test "malformed Bearer header returns 401", %{conn: conn} do
  conn
  |> put_req_header("authorization", "Token xyz")
  |> get("/api/applications")
  |> json_response(401)
end
```

#### 6.5 Webhook Signature Verification

```elixir
test "valid HMAC signature is accepted", %{conn: conn} do
  payload = Jason.encode!(%{"application_id" => "...", "status" => "approved"})
  secret = Application.get_env(:debt_stalker, :webhook_secret, "dev-webhook-secret")
  signature = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)

  conn
  |> put_req_header("x-webhook-signature", signature)
  |> put_req_header("content-type", "application/json")
  |> post("/api/webhooks/provider", payload)
  |> json_response(200)
end

test "invalid HMAC signature returns 401 when signature required", %{conn: conn} do
  Application.put_env(:debt_stalker, :require_webhook_signature, true)
  on_exit(fn -> Application.delete_env(:debt_stalker, :require_webhook_signature) end)

  conn
  |> put_req_header("x-webhook-signature", "invalid")
  |> post("/api/webhooks/provider", %{"application_id" => "x"})
  |> json_response(401)
end
```

#### 6.6 Cursor Pagination

```elixir
test "invalid cursor is gracefully ignored" do
  result = Applications.list_applications(%{cursor: "not-valid-base64!!!"})
  assert is_list(result.entries)
end

test "cursor with tampered data is gracefully ignored" do
  result = Applications.list_applications(%{cursor: Base.url_encode64("not json")})
  assert is_list(result.entries)
end
```

#### 6.7 PII Boundary Cases

```elixir
test "redact_document handles nil" do
  assert CreditApplication.redact_document(nil) == "****"
end

test "redact_document handles very short document" do
  assert CreditApplication.redact_document("AB") == "****"
end

test "redact_document shows exactly last 4" do
  assert CreditApplication.redact_document("12345678Z") == "****678Z"
end
```

---

### 7. Improvement Proposals (Prioritized)

| # | Priority | Description | Effort |
|---|----------|-------------|--------|
| P1 | HIGH | Fix MX debt rule in RiskEvaluationWorker (GAP-2) | S |
| P2 | HIGH | Use country transitions in `update_status/3` (GAP-1) | S |
| P3 | MEDIUM | Fix `Decimal.new` crash in API controller (ISSUE-1) | XS |
| P4 | MEDIUM | Broadcast application creation from domain layer (ISSUE-5) | S |
| P5 | MEDIUM | Add `/api/health` endpoint (GAP-5) | XS |
| P6 | MEDIUM | Provider registry (decouple from hardcoded map) (ISSUE-3) | M |
| P7 | LOW | Move `import Ecto.Query` to module level (ISSUE-2) | XS |
| P8 | LOW | Add Telemetry events in hot paths (Phase 2 prep) | M |
| P9 | LOW | Add webhook signature E2E test | S |
| P10 | LOW | Document AuditWorker simplification in ADR (GAP-3) | XS |

---

### 8. Summary

**Overall Assessment: Strong foundation with targeted fixes needed.**

The Phase 1 implementation correctly delivers the vertical slice. Architecture is clean, extensible, and well-tested (133 tests including property-based and integration tests). The most critical issue is **GAP-2** (MX debt rule silently not applied at risk evaluation) — this is a functional correctness bug that should be fixed before considering Phase 1 complete.

**GAP-1** (country transitions not consulted) is an architectural contract violation that's benign today but will bite in Phase 3. Fix it now while it's cheap.

**ISSUE-1** (`Decimal.new` crash) is a production stability concern — any malformed numeric input will crash the controller with a 500 instead of returning a proper 422.

The remaining items are code quality improvements and Phase 2 preparation.

---

*Review complete. Recommend addressing P1–P3 immediately, P4–P5 before merge, and P6–P10 as follow-up.*
