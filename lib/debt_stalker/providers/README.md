# Providers Context (`lib/debt_stalker/providers/`)

This folder owns the **fetch and normalize** boundary for external credit-data providers. It defines a behaviour contract, provides simulated adapters for Spain, Mexico, and Poland, normalizes raw provider data into a common shape, and protects provider calls with a custom circuit breaker.

## Responsibilities

- Fetch provider data for a country without leaking HTTP or provider details into the rest of the app.
- Normalize every provider response into a `ProviderSummary` struct/map.
- Guard provider calls with per-country circuit breakers.
- Classify provider errors as transient or permanent.
- **Never** make business decisions or persist raw payloads.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `behaviour.ex` | Defines the provider adapter contract. |
| `provider_summary.ex` | Normalized provider summary struct and serialization. |
| `es_adapter.ex` | Simulated Spain provider adapter. |
| `mx_adapter.ex` | Simulated Mexico provider adapter. |
| `pl_adapter.ex` | Simulated Poland provider adapter. |
| `registry.ex` | ETS-backed registry mapping country codes to adapter modules. |
| `circuit_breaker.ex` | Custom GenServer circuit breaker with closed/open/half-open states. |
| `circuit_breakers.ex` | Supervisor that boots one breaker per supported provider. |

## Public API

### `DebtStalker.Providers.Behaviour`

#### `fetch(identity_document :: String.t(), opts :: keyword()) :: {:ok, ProviderSummary.t()} | {:error, atom()}`

The single adapter callback. Implementations must return a normalized summary or a provider error atom (`:timeout`, `:unavailable`, `:invalid_document`, `:rejection`).

### `DebtStalker.Providers.Registry`

#### `lookup(country_code :: String.t()) :: {:ok, module()} | {:error, :unsupported_country}`

Returns the adapter module for a country from ETS.

#### `supported_providers() :: [String.t()]`

Returns the list of configured provider countries (currently `["ES", "MX", "PL"]`).

### `DebtStalker.Providers.CircuitBreaker`

#### `call(name :: atom(), fun :: (-> result), opts :: keyword()) :: result`

Executes `fun` through the breaker named `name`. If the breaker is open, it returns `{:error, :unavailable}`; if it is half-open, concurrency is limited to one probe at a time. Successful calls with the retry budget close the breaker; failures increment the failure counter and may open it.

#### `reset(name :: atom()) :: :ok`

Resets the named breaker to the closed state. Used mainly in tests.

### `DebtStalker.Providers.CircuitBreakers`

Supervisor that starts a `CircuitBreaker` for each supported provider at boot. It also stores the breaker PIDs in a private ETS table for lookup.

### `DebtStalker.Providers.ProviderSummary`

Struct representing a normalized provider response:

- `provider_status` (string, e.g. `"active"`, `"inactive"`, `"blocked"`)
- `normalized_data` (map, e.g. `bank_name`, `monthly_payment`)
- `risk_indicators` (map, e.g. `credit_score`, `active_loans`, `existing_debt`)
- `country_code` (string)
- `fetched_at` (utc datetime)

Functions:

- `new/2` — creates a summary from a map.
- `to_map/1` — serializes a summary to a plain map.

## Important notes

- **Simulated adapters**: `es_adapter.ex` and `mx_adapter.ex` return deterministic data based on the identity document prefix and a test-only override map for Mexico. They do not perform real HTTP calls.
- **Circuit breaker states**:
  - `closed` — normal operation; failures increment a counter.
  - `open` — calls fail fast with `{:error, :unavailable}`; a cooldown timer allows periodic half-open probes.
  - `half-open` — only one probe at a time; success closes the breaker, failure reopens it.
- **Retry budget**: breakers allow a limited number of retry attempts while half-open. The budget is configurable.
- **Telemetry**: every state transition and call emits `:telemetry` events (`[:debt_stalker, :provider, ...]`).
- **Error classification**: `circuit_breaker.ex` classifies errors as `transient` or `permanent`; only transient errors open the breaker.

## Where to look next

- `lib/debt_stalker/applications.ex` — orchestrates provider calls during application creation.
- `lib/debt_stalker/countries/` — country modules interpret the normalized provider summary.
- `lib/debt_stalker/risk.ex` — consumes provider summaries to make risk decisions.
- `docs/adr/0005-circuit-breaker-choice.md` — why a custom breaker was chosen over an external library.
