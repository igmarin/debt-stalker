# ADR-0005: Circuit Breaker Choice (Custom GenServer)

## Status

Accepted

## Context

The `DebtStalker.Providers` context calls external credit-bureau providers per country (ES, PT, IT, MX, CO, BR). These calls are network-bound and can fail, time out, or degrade. A circuit breaker is required so that repeated provider failures fail fast instead of queuing requests, protecting both the application and the downstream provider.

The circuit breaker must:

- Track consecutive failures per circuit instance and open after a configurable threshold
- Support a half-open state that allows a single probe call before re-closing
- Emit observability signals on state transitions (for dashboards and alerting)
- Classify errors as transient (retryable) vs permanent (fail immediately)
- Integrate with the existing provider adapter pattern (`DebtStalker.Providers.Behaviour`)
- Remain a critical resilience component with no opaque third-party logic that the team cannot inspect or patch

## Decision

Implement a **custom GenServer-based circuit breaker** (`DebtStalker.Providers.CircuitBreaker`) instead of adopting the `:fuse` library.

The implementation lives at `lib/debt_stalker/providers/circuit_breaker.ex` and provides:

1. **Fine-grained half-open concurrency control** — In the half-open state, only a single probe call is allowed in-flight. Concurrent callers are rejected with `{:error, :circuit_open}` until the probe reports back. A `trial_in_flight` flag plus a `Process.monitor` on the trial caller guarantees the slot is released even if the caller crashes before reporting (see `handle_info({:DOWN, ...})`).

2. **Telemetry integration** — Every state transition emits a `:telemetry` event:
   - `[:debt_stalker, :circuit_breaker, :open]`
   - `[:debt_stalker, :circuit_breaker, :close]`
   
   Events carry `country`, `from_state`, and `to_state` metadata, enabling per-country dashboards without additional instrumentation.

3. **No external dependency** — The circuit breaker is a critical resilience component. Owning the implementation means the team can audit, patch, and extend it without waiting for upstream releases or carrying an opaque dependency in the hot path of every provider call.

4. **Custom error classification** — Transient errors (`:timeout`, `:unavailable`) are retried up to a configurable `retry_budget` with exponential backoff before counting as a failure. Permanent errors fail immediately. The retry loop runs in the **caller's process**, not the GenServer, so backoff sleeps never block the GenServer.

### Alternatives considered

| Option | Rejected because |
|--------|------------------|
| `:fuse` library | Erlang-native and fast, but offers no built-in half-open single-probe guarantee, no telemetry hooks, and opaque internals that are hard to extend with custom error classification |
| `circuit_breaker` (hex) | Less maintained; API does not expose half-open concurrency control or transition events |
| No circuit breaker | Provider failures would propagate unbounded, risking thread pool exhaustion and cascading failures during outages |

## Consequences

### Positive

- Full control over half-open semantics: exactly one probe in-flight, with crash-safe slot reclamation via `Process.monitor`
- Native `:telemetry` events on every transition — no adapter or wrapper needed for observability
- Custom error classification (transient vs permanent) baked into the retry loop, matching the provider error atoms (`:timeout`, `:unavailable`)
- No external dependency for a critical resilience path; the team can patch and extend immediately
- Retry loop runs in the caller's process, so the GenServer is never blocked by long-running calls or backoff sleeps
- Configurable per-instance thresholds (`failure_threshold`, `cooldown_ms`, `retry_budget`, `base_backoff_ms`)

### Negative

- The team owns the maintenance burden — bugs in the circuit breaker are ours to fix
- More code to test and reason about than dropping in a library
- No battle-tested community validation; correctness depends on the project's own test suite

### Neutral

- Circuit state is in-memory and per-node; it resets on restart (acceptable for provider-call resilience; provider availability is relearned within one cooldown window)
- The GenServer is contacted only for a quick state check (`:check_access`) and result reporting (`:report_result`), keeping the hot path cheap
