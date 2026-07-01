# Countries Context (`lib/debt_stalker/countries/`)

This folder isolates every country-specific rule in the system: document validation, financial thresholds, provider-summary interpretation, allowed status transitions, and risk-score thresholds. It is the only place in the codebase allowed to contain country-specific logic.

## Responsibilities

- Define the behaviour contract for country modules.
- Implement country modules (currently `ES` and `MX`).
- Register country modules in an ETS-backed registry for O(1) lookup.
- Provide UI helpers (document hints, currency symbols) without exposing internal modules.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `behaviour.ex` | Defines `DebtStalker.Countries.Behaviour` callbacks. |
| `es.ex` | Spain implementation: DNI validation, € thresholds, transitions. |
| `mx.ex` | Mexico implementation: CURP validation, $ thresholds, transitions. |
| `registry.ex` | ETS-backed GenServer that loads supported countries at boot. |

## Public API

### `DebtStalker.Countries`

This is the facade used by the web layer and seeds. It does not expose the registry directly; it resolves optional callbacks safely.

#### `get_document_hint(country_code :: String.t() | nil) :: String.t()`

Returns a UI placeholder for the identity document field (e.g. `"12345678A"` for Spain). Returns `""` for unknown countries.

#### `currency_symbol(country_code :: String.t() | nil) :: String.t()`

Returns the currency symbol for the country (e.g. `"€"`, `"$"`). Returns `""` for unknown countries.

#### `random_identity_document(country_code :: String.t()) :: String.t() | nil`

Generates a demo identity document suitable for seeds and tests. Returns `nil` for unknown countries.

### `DebtStalker.Countries.Registry`

#### `lookup(country_code :: String.t()) :: {:ok, module()} | {:error, :unsupported_country}`

Looks up the country module in ETS. Returns `{:error, :unsupported_country}` when the country is not configured.

#### `supported_countries() :: [String.t()]`

Returns the list of configured country codes (currently `["ES", "MX"]`).

## Behaviour contract (`DebtStalker.Countries.Behaviour`)

Required callbacks:

- `validate_document(identity_document :: String.t()) :: :ok | {:error, atom()}`
- `validate_financials(requested_amount :: Decimal.t(), monthly_income :: Decimal.t()) :: :ok | {:error, atom()}`
- `interpret_provider_summary(provider_summary :: map()) :: map()`
- `allowed_transitions(status :: String.t()) :: [String.t()]`
- `risk_score_threshold() :: integer()`
- `additional_review_required?(provider_summary :: map()) :: boolean()`

Optional callbacks:

- `document_hint/0`
- `currency_symbol/0`
- `random_identity_document/0`
- `format_document/1`
- `debt_to_income_threshold/0`

## Implementation notes

- **Spain (`es.ex`)**:
  - DNI format: 8 digits + 1 letter, with a checksum letter validation.
  - Financial rule: requested amount must not exceed 24× monthly income.
  - Risk threshold: 60.
  - Allowed transitions: `submitted` → `pending_risk` → `approved`/`rejected`/`additional_review`, plus `cancelled` from several states.
- **Mexico (`mx.ex`)**:
  - CURP format: 18-character alphanumeric with structural validation.
  - Financial rule: requested amount must not exceed 18× monthly income.
  - Risk threshold: 65.
  - Similar transition graph with `additional_review` as a terminal flag state.

## Important notes

- **No branching outside this folder**: `if country == "ES"` is forbidden outside country modules and their tests. Use `Registry.lookup/1` and the behaviour callbacks.
- **ETS is private to the registry**: callers should use `DebtStalker.Countries.Registry.lookup/1`, not read the ETS table directly.
- **Optional callbacks are optional**: the facade (`DebtStalker.Countries`) uses `function_exported?/3` to avoid runtime errors when a country does not implement a hint or currency symbol.

## Where to look next

- `lib/debt_stalker/providers/` — how provider summaries are produced and normalized.
- `lib/debt_stalker/risk.ex` — how risk scores are evaluated using the behaviour.
- `lib/debt_stalker_web/components/ui.ex` — UI formatting that uses country hints and currency symbols.
- `docs/how-to-add-country.md` — step-by-step guide for adding Portugal, Italy, Colombia, or Brazil.
